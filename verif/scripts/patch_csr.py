#!/usr/bin/env python3
import sys

# Base NOP encoding (addi x0,x0,0)
NOP_INSTRUCTION = 0x00000013

# CSR SYSTEM opcode
SYSTEM_OPCODE = 0x73

# CSRs we always NOP on writes (rd==x0 or write semantics), plus MRET
TARGET_CSRS = {0x300, 0x301, 0x305, 0x341}  # mstatus, misa, mtvec, mepc
MRET_IMM     = 0x302                        # imm[11:0] for mret

def is_mret(instr_word: int) -> bool:
    opcode = instr_word & 0x7F
    if opcode != SYSTEM_OPCODE:
        return False
    funct3 = (instr_word >> 12) & 0x7
    csr_imm = (instr_word >> 20) & 0xFFF
    return funct3 == 0 and csr_imm == MRET_IMM

def is_csr_op(instr_word: int) -> bool:
    opcode = instr_word & 0x7F
    if opcode != SYSTEM_OPCODE:
        return False
    funct3 = (instr_word >> 12) & 0x7
    return funct3 in (0b001, 0b010, 0b011, 0b101, 0b110, 0b111)

def get_rd(instr_word: int) -> int:
    return (instr_word >> 7) & 0x1F

def get_rs1(instr_word: int) -> int:
    return (instr_word >> 15) & 0x1F

def get_funct3(instr_word: int) -> int:
    return (instr_word >> 12) & 0x7

def get_csr_addr(instr_word: int) -> int:
    return (instr_word >> 20) & 0xFFF

def is_csr_read(instr_word: int) -> bool:
    """
    Treat any CSR* with rd != x0 as a 'read' (the old CSR value would be written to rd).
    We rewrite these to `li rd, 0`.
    """
    return is_csr_op(instr_word) and get_rd(instr_word) != 0

def writes_csr(instr_word: int) -> bool:
    """
    Determine if the CSR op *modifies* the CSR:
      - CSRRW/CSRRWI (funct3 001 / 101): always writes.
      - CSRRS/CSRRC (010 / 011): writes only if rs1 != x0.
      - CSRRSI/CSRRCI (110 / 111): writes only if zimm != 0 (encoded in rs1 field).
    """
    if not is_csr_op(instr_word):
        return False
    f3 = get_funct3(instr_word)
    rs1 = get_rs1(instr_word)
    if f3 in (0b001, 0b101):  # CSRRW / CSRRWI
        return True
    if f3 in (0b010, 0b011):  # CSRRS / CSRRC
        return rs1 != 0
    if f3 in (0b110, 0b111):  # CSRRSI / CSRRCI
        zimm = rs1  # rs1 field holds the 5-bit immediate
        return zimm != 0
    return False

def encode_addi_rd_x0_0(rd: int) -> int:
    opcode = 0x13
    funct3 = 0
    rs1    = 0
    imm    = 0
    return ((imm & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | ((funct3 & 0x7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

def patch_specific_instructions(filename: str):
    with open(filename, 'r') as f:
        lines = [l.strip() for l in f if l.strip()]

    patched = []
    for line in lines:
        hex_str = line.lower()
        if hex_str.startswith('0x'):
            hex_str = hex_str[2:]
        try:
            instr = int(hex_str, 16)
        except ValueError:
            patched.append(line)
            continue

        if is_csr_read(instr):
            rd = get_rd(instr)
            new_instr = encode_addi_rd_x0_0(rd)
            print(f"CSR-read -> li x{rd},0 : 0x{instr:08x} -> 0x{new_instr:08x}")
            patched.append(f"{new_instr:08x}")
        elif is_mret(instr):
            print(f"MRET -> NOP          : 0x{instr:08x} -> 0x{NOP_INSTRUCTION:08x}")
            patched.append(f"{NOP_INSTRUCTION:08x}")
        elif is_csr_op(instr) and writes_csr(instr) and get_csr_addr(instr) in TARGET_CSRS:
            print(f"CSR write@target -> NOP: 0x{instr:08x} (csr=0x{get_csr_addr(instr):03x}) -> 0x{NOP_INSTRUCTION:08x}")
            patched.append(f"{NOP_INSTRUCTION:08x}")
        else:
            patched.append(f"{instr:08x}")

    with open(filename, 'w') as f:
        for w in patched:
            f.write(w + '\n')

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 patch_specific_csrs_to_nop.py <hex_file>")
        sys.exit(1)
    patch_specific_instructions(sys.argv[1])

if __name__ == "__main__":
    main()