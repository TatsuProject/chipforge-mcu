module decode_control (
    input  logic [6:0] opcode,
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
    output logic       illegal_inst
);

always_comb begin
    // Set defaults: if not explicitly enabled, signals are low.
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
    
    case (opcode)
      7'b0110011: begin // R-type
        reg_write = 1'b1;
        alu_src   = 1'b0;
        alu_op    = 2'b11;
        r_type    = 1'b1;
      end

      7'b0010011: begin // I-type ALU instructions
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

      7'b1100011: begin // Branch (B-type)
        branch = 1'b1;
        alu_src = 1'b0;
        alu_op  = 2'b10;
      end

      7'b1101111: begin // JAL
        jump      = 1'b1;
        reg_write = 1'b1;  // Write return address
        jal       = 1'b1;
      end

      7'b1100111: begin // JALR
        jump      = 1'b1;
        reg_write = 1'b1;  // Write return address
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

      // gen illegal instruction exception if instruction is csr, atomic, or pqc
      // 7'b1110011: begin // CSR instructions
      //   sys_inst  = 1'b1;
      //   reg_write = 1'b1;
      // end

      // 7'b0101111: begin // atomic instructions
      //   is_atomic = 1'b1;
      //   reg_write = 1'b1;
      // end

      7'b0000000: begin // flushed instruction 
      end
      default: begin
        illegal_inst = 1'b1;
      end
    endcase
  end

endmodule
