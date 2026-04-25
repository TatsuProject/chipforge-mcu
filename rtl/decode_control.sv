module decode_control (
    input  logic [6:0] opcode,
    input  logic [6:0] funct7,
    input  logic [2:0] funct3,
    input  logic [4:0] rs2_field,   // inst[24:20], used as sub-op in FP encodings

    // ---- integer-side decode (original) -------------------------------
    output logic       reg_write,
    output logic       mem_write,
    output logic       mem_to_reg,
    output logic       branch,
    output logic       alu_src,
    output logic       jump,
    output logic [1:0] alu_op,
    output logic       lui,
    output logic       auipc,
    output logic       jal,
    output logic       r_type,
    output logic       sys_inst,
    output logic       is_atomic,
    output logic       illegal_inst,

    // ---- F extension decode (Challenge 0013) --------------------------
    output logic       is_fp,
    output logic       fp_reg_write,   // writes to f-reg
    output logic       fp_wb_to_int,   // writes to GPR instead (FCVT.W.S, FCVT.WU.S, FMV.X.W)
    output logic       fp_uses_rs1,    // rs1 operand is read from f-reg (else GPR)
    output logic       fp_uses_rs2,    // rs2 operand is read from f-reg (else GPR)
    output logic [4:0] fpu_op,         // fpu_op_e enum code
    output logic [2:0] fp_rm           // rounding mode (funct3 field)
);

always_comb begin
    // -- integer-side defaults
    reg_write     = 1'b0;
    mem_write     = 1'b0;
    mem_to_reg    = 1'b0;
    branch        = 1'b0;
    alu_src       = 1'b0;
    jump          = 1'b0;
    alu_op        = 2'b00;
    lui           = 1'b0;
    auipc         = 1'b0;
    jal           = 1'b0;
    r_type        = 1'b0;
    sys_inst      = 1'b0;
    is_atomic     = 1'b0;
    illegal_inst  = 1'b0;

    // -- F-extension defaults
    is_fp         = 1'b0;
    fp_reg_write  = 1'b0;
    fp_wb_to_int  = 1'b0;
    fp_uses_rs1   = 1'b0;
    fp_uses_rs2   = 1'b0;
    fpu_op        = 5'd0;
    fp_rm         = funct3;   // funct3 carries rm for most FP ops

    case (opcode)
      7'b0110011: begin // R-type
        reg_write = 1'b1;
        alu_src   = 1'b0;
        alu_op    = 2'b11;
        r_type    = 1'b1;
      end

      7'b0010011: begin // I-type ALU
        reg_write = 1'b1;
        alu_src   = 1'b1;
        alu_op    = 2'b01;
      end

      7'b0000011: begin // LOAD
        reg_write  = 1'b1;
        mem_to_reg = 1'b1;
        alu_src    = 1'b1;
        alu_op     = 2'b00;
      end

      7'b0100011: begin // STORE
        mem_write = 1'b1;
        alu_src   = 1'b1;
        alu_op    = 2'b00;
      end

      7'b1100011: begin // Branch
        branch  = 1'b1;
        alu_src = 1'b0;
        alu_op  = 2'b10;
      end

      7'b1101111: begin // JAL
        jump      = 1'b1;
        reg_write = 1'b1;
        jal       = 1'b1;
      end

      7'b1100111: begin // JALR
        jump      = 1'b1;
        reg_write = 1'b1;
      end

      7'b0110111: begin // LUI
        reg_write = 1'b1;
        lui       = 1'b1;
        alu_src   = 1'b1;
      end

      7'b0010111: begin // AUIPC
        reg_write = 1'b1;
        auipc     = 1'b1;
        alu_src   = 1'b1;
      end

      // SYSTEM / CSR (opcode 0x73). Full CSR support already exists in
      // csr_file.sv / data_path.sv (mret_inst_id, trap_ret → mepc path).
      // We need:
      //   funct3 != 000 → CSR{R,W,S,C}{,I}: sys_inst=1, reg_write=1 (control_unit
      //                   rewrites via csr_inst = sys_inst & |funct3).
      //   funct3 == 000:
      //     MRET (funct7=0011000, rs2=00010) → sys_inst=1 so mret_inst_id fires
      //                   and the core restores PC from mepc. Required by the
      //                   F-test's kernel_setup → init → kernel_end → mret flow.
      //     ECALL/EBREAK/WFI → illegal_inst=1 so tb_top's wait(illegal_inst)
      //                   terminates the sim (the F-test ends with ecall at
      //                   `test_done:` — this is the intended program end).
      7'b1110011: begin
        case (funct3)
          3'b000: begin
            if (funct7 == 7'b0011000 && rs2_field == 5'b00010) begin
              sys_inst = 1'b1;          // MRET
            end else begin
              illegal_inst = 1'b1;      // ECALL/EBREAK/WFI → end sim
            end
          end
          default: begin
            sys_inst  = 1'b1;
            reg_write = 1'b1;
          end
        endcase
      end

      // ==================================================================
      // OP-FP (opcode 0x53) — basic RV32F subset for Challenge 0013.
      // ==================================================================
      7'b1010011: begin
        is_fp = 1'b1;
        case (funct7)
          7'b0000000: begin // FADD.S
            fp_reg_write = 1'b1;
            fp_uses_rs1  = 1'b1;
            fp_uses_rs2  = 1'b1;
            fpu_op       = 5'd1;
          end
          7'b0000100: begin // FSUB.S
            fp_reg_write = 1'b1;
            fp_uses_rs1  = 1'b1;
            fp_uses_rs2  = 1'b1;
            fpu_op       = 5'd2;
          end
          7'b0001000: begin // FMUL.S
            fp_reg_write = 1'b1;
            fp_uses_rs1  = 1'b1;
            fp_uses_rs2  = 1'b1;
            fpu_op       = 5'd3;
          end
          7'b0010000: begin // FSGNJ.S / FSGNJN.S / FSGNJX.S
            fp_reg_write = 1'b1;
            fp_uses_rs1  = 1'b1;
            fp_uses_rs2  = 1'b1;
            case (funct3)
              3'b000:  fpu_op = 5'd6;   // FSGNJ
              3'b001:  fpu_op = 5'd7;   // FSGNJN
              3'b010:  fpu_op = 5'd8;   // FSGNJX
              default: illegal_inst = 1'b1;
            endcase
          end
          7'b0010100: begin // FMIN.S / FMAX.S
            fp_reg_write = 1'b1;
            fp_uses_rs1  = 1'b1;
            fp_uses_rs2  = 1'b1;
            case (funct3)
              3'b000:  fpu_op = 5'd4;   // FMIN
              3'b001:  fpu_op = 5'd5;   // FMAX
              default: illegal_inst = 1'b1;
            endcase
          end
          7'b1100000: begin // FCVT.W.S / FCVT.WU.S (float → int)
            reg_write    = 1'b1;
            fp_wb_to_int = 1'b1;
            fp_uses_rs1  = 1'b1;
            case (rs2_field)
              5'd0:    fpu_op = 5'd9;   // FCVT.W.S
              5'd1:    fpu_op = 5'd10;  // FCVT.WU.S
              default: illegal_inst = 1'b1;
            endcase
          end
          7'b1101000: begin // FCVT.S.W / FCVT.S.WU (int → float)
            fp_reg_write = 1'b1;
            fp_uses_rs1  = 1'b0;       // rs1 is GPR
            case (rs2_field)
              5'd0:    fpu_op = 5'd11;  // FCVT.S.W
              5'd1:    fpu_op = 5'd12;  // FCVT.S.WU
              default: illegal_inst = 1'b1;
            endcase
          end
          7'b1110000: begin // FMV.X.W (funct3=000, rs2=00000) — FCLASS is 001/00000 (out of scope)
            if (funct3 == 3'b000 && rs2_field == 5'd0) begin
              reg_write    = 1'b1;
              fp_wb_to_int = 1'b1;
              fp_uses_rs1  = 1'b1;
              fpu_op       = 5'd13;
            end else begin
              illegal_inst = 1'b1;
            end
          end
          7'b1111000: begin // FMV.W.X (funct3=000, rs2=00000)
            if (funct3 == 3'b000 && rs2_field == 5'd0) begin
              fp_reg_write = 1'b1;
              fp_uses_rs1  = 1'b0;
              fpu_op       = 5'd14;
            end else begin
              illegal_inst = 1'b1;
            end
          end
          // FDIV (0001100), FSQRT (0101100), FCMP (1010000), FCLASS (1110000/fun3=001),
          // FMADD (opcode 43/47/4B/4F), FLW (0000111), FSW (0100111) — all OUT of scope.
          default: illegal_inst = 1'b1;
        endcase
      end

      7'b0000000: begin // flushed instruction
      end

      default: illegal_inst = 1'b1;
    endcase
  end

endmodule
