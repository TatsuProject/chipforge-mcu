// fpu_sgnj.sv — FSGNJ.S / FSGNJN.S / FSGNJX.S
// Sign injection: magnitude from rs1, sign derived from rs2 per variant.
// Purely combinational, single-cycle.
//
// op_i:  0 = FSGNJ  (sign = rs2[31])
//        1 = FSGNJN (sign = ~rs2[31])
//        2 = FSGNJX (sign = rs1[31] ^ rs2[31])
//
// Note: FSGNJ is NOT a no-op even when rs1 == rs2 — it has canonicalising
// effects on NaN operands per the architecture, but for sign injection we
// simply copy the low 31 bits of rs1 and compute the sign bit. NaN payload
// is preserved as-is (RISC-V spec does not require canonicalisation here).

module fpu_sgnj (
    input  logic [1:0]  op_i,
    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    output logic [31:0] result_o
);

    logic sign_bit;

    always_comb begin
        unique case (op_i)
            2'd0:    sign_bit =  rs2_i[31];              // FSGNJ
            2'd1:    sign_bit = ~rs2_i[31];              // FSGNJN
            2'd2:    sign_bit =  rs1_i[31] ^ rs2_i[31];  // FSGNJX
            default: sign_bit =  rs2_i[31];
        endcase
    end

    assign result_o = {sign_bit, rs1_i[30:0]};

endmodule
