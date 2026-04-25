// mul_unit.sv — 2-stage shared int/FP multiplier (Strategy #2 rebalanced).
//
// EX  stage: operand unpack + partial products + adder tree  -> 64-bit product
// MEM stage: flopped product, output mux (int) / full_result (FPU).
//
// The adder tree was previously in MEM with partials flopped at EX->MEM. That
// kept EX short but piled onto MEM — once FMUL started re-using this mul
// (Strategy #2), the MEM cone stretched "adder tree → LZC → shift → round →
// pack", blowing fmax. Rebalancing: do partials + adder tree all in EX,
// flop only the 64-bit product. MEM then has just the output mux for int
// MUL / the FPU back-end for FMUL — much shorter.
//
// Flop budget: previously 4x34 partials + funct3 = 139 bits. Now 64-bit
// product + funct3 = 67 bits — roughly half the pipeline-register area.

module mul_unit #(parameter XLEN = 32)(
    input  logic                clk,
    input  logic                reset_n,
    input  logic                stall_i,
    input  logic [2:0]          funct3_i,    // 000: MUL, 001: MULH, 010: MULHSU, 011: MULHU
    input  logic [XLEN-1:0]     rs1_i,
    input  logic [XLEN-1:0]     rs2_i,
    output logic [XLEN-1:0]     result_o,
    output logic [2*XLEN-1:0]   full_result_o   // for shared FMUL (Strategy #2)
);

  localparam HALF = XLEN / 2;

  logic [HALF-1:0] a_lo, b_lo;
  logic [HALF-1:0] a_hi, b_hi;
  logic [HALF:0]   a_lo_ext, b_lo_ext;
  logic [HALF:0]   a_hi_ext, b_hi_ext;
  logic            a_sign, b_sign;
  logic signed [XLEN+1:0] p0, p1, p2, p3;

  assign a_lo   = rs1_i[HALF-1:0];
  assign a_hi   = rs1_i[XLEN-1:HALF];
  assign b_lo   = rs2_i[HALF-1:0];
  assign b_hi   = rs2_i[XLEN-1:HALF];
  assign a_sign = rs1_i[XLEN-1];
  assign b_sign = rs2_i[XLEN-1];

  // Partial multiplications with sign handling.
  always_comb begin
    a_lo_ext = {1'b0, a_lo};
    b_lo_ext = {1'b0, b_lo};
    a_hi_ext = {1'b0, a_hi};
    b_hi_ext = {1'b0, b_hi};
    unique case (funct3_i)
      3'b000, 3'b001: begin // signed × signed (MUL, MULH)
        a_hi_ext = {a_sign, a_hi};
        b_hi_ext = {b_sign, b_hi};
      end
      3'b010: begin         // signed × unsigned (MULHSU)
        a_hi_ext = {a_sign, a_hi};
        b_hi_ext = {1'b0,   b_hi};
      end
      3'b011: begin         // unsigned × unsigned (MULHU; used by shared FMUL)
        a_hi_ext = {1'b0, a_hi};
        b_hi_ext = {1'b0, b_hi};
      end
      default: begin
        a_hi_ext = {1'b0, a_hi};
        b_hi_ext = {1'b0, b_hi};
      end
    endcase
  end

  assign p0 = $signed(a_lo_ext) * $signed(b_lo_ext);
  assign p1 = $signed(a_lo_ext) * $signed(b_hi_ext);
  assign p2 = $signed(a_hi_ext) * $signed(b_lo_ext);
  assign p3 = $signed(a_hi_ext) * $signed(b_hi_ext);

  // 2-level adder tree in EX (was in MEM previously).
  logic signed [2*XLEN-1:0] sum1, sum2, final_product_s1;
  assign sum1 = (p2 + p1) << HALF;
  assign sum2 = {p0[33] ? (p3[31:0] - 1'b1) : p3[31:0], p0[31:0]};
  assign final_product_s1 = sum1 + sum2;

  // Pipeline register (EX → MEM).
  logic [2:0]            funct3_ff;
  logic signed [2*XLEN-1:0] final_product_ff;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      funct3_ff        <= 3'b000;
      final_product_ff <= '0;
    end else if (!stall_i) begin
      funct3_ff        <= funct3_i;
      final_product_ff <= final_product_s1;
    end
  end

  // MEM stage: simple output mux (int) + full product (FPU).
  assign result_o      = (funct3_ff == 3'b000) ? final_product_ff[XLEN-1:0]
                                               : final_product_ff[2*XLEN-1:XLEN];
  assign full_result_o = final_product_ff;

endmodule
