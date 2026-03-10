#!/usr/bin/env python3
import sys
import subprocess
import os

def run_objcopy(input_elf, temp_hex):
    """Runs objcopy to dump full ELF memory in Verilog format"""
    cmd = [
        "riscv32-unknown-elf-objcopy",
        "-O", "verilog",
        input_elf,
        temp_hex
    ]
    subprocess.run(cmd, check=True)
    print(f"✅ objcopy done → generated {temp_hex}")

def parse_verilog_hex(input_filename, base_addr, total_size):
    """Parses Verilog-style hex file and returns a bytearray of total_size starting at base_addr"""
    memory = {}
    current_addr = 0

    with open(input_filename, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("@"):
                current_addr = int(line[1:], 16)
                continue
            for b in line.split():
                memory[current_addr] = int(b, 16)
                current_addr += 1

    # Fill gaps with zeroes
    result = bytearray()
    for addr in range(base_addr, base_addr + total_size):
        result.append(memory.get(addr, 0x00))
    return result

def write_hex_file(data_bytes, output_filename):
    with open(output_filename, "w") as f:
        for i in range(0, len(data_bytes), 4):
            chunk = data_bytes[i:i+4]
            while len(chunk) < 4:
                chunk += b'\x00'
            word = int.from_bytes(chunk, 'little')
            f.write(f"{word:08X}\n")

def main():
    if len(sys.argv) != 5:
        print("Usage: {} <input.elf> <rom.hex> <inst.hex> <data.hex>".format(sys.argv[0]))
        sys.exit(1)

    input_file = sys.argv[1]
    rom_output = sys.argv[2]
    inst_output = sys.argv[3]
    data_output = sys.argv[4]
    temp_file = "temp_mem_dump.hex"

    # Step 1: Dump full memory as verilog hex
    run_objcopy(input_file, temp_file)

    # Step 2: Extract specific regions
    rom_data   = parse_verilog_hex(temp_file, 0x00000000, 8 * 1024)
    inst_data  = parse_verilog_hex(temp_file, 0x80000000, 32 * 1024)
    data_data  = parse_verilog_hex(temp_file, 0x80008000, 16 * 1024)

    # Step 3: Write output hex files
    write_hex_file(rom_data,  rom_output)
    write_hex_file(inst_data, inst_output)
    write_hex_file(data_data, data_output)

    print(f"✅ Wrote: {rom_output}  (8KB from 0x00000000)")
    print(f"✅ Wrote: {inst_output} (32KB from 0x80000000)")
    print(f"✅ Wrote: {data_output} (16KB from 0x80008000)")

    os.remove(temp_file)

if __name__ == "__main__":
    main()
