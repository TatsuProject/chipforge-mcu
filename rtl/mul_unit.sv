module mul_unit #(parameter XLEN = 32)(
    input  logic             clk,
    input  logic             reset_n,
    input  logic             stall_i,
    input  logic [2:0]       funct3_i,    // 000: MUL, 001: MULH, 010: MULHSU, 011: MULHU
    input  logic [XLEN-1:0]  rs1_i,
    input  logic [XLEN-1:0]  rs2_i,
    output logic [XLEN-1:0]  result_o
);

  localparam HALF = XLEN / 2;

  logic [HALF-1:0] a_lo, b_lo;
  logic [HALF-1:0] a_hi, b_hi;

  logic [HALF:0] a_lo_ext, b_lo_ext;
  logic [HALF:0] a_hi_ext, b_hi_ext;

  logic signed [XLEN+1:0] p0, p1, p2, p3;

  logic a_sign, b_sign;

  assign a_lo   = rs1_i[HALF-1:0   ];
  assign a_hi   = rs1_i[XLEN-1:HALF];
  assign b_lo   = rs2_i[HALF-1:0   ];
  assign b_hi   = rs2_i[XLEN-1:HALF];
  assign a_sign = rs1_i[XLEN-1];
  assign b_sign = rs2_i[XLEN-1];


  // Stage 1: partial multiplications with sign handling
  always_comb begin
    a_lo_ext = {1'b0  , a_lo};
    b_lo_ext = {1'b0  , b_lo};
    a_hi_ext = {1'b0  , a_hi};
    b_hi_ext = {1'b0  , b_hi};
    unique case (funct3_i)
      3'b000, 3'b001: begin // signed × signed (MUL, MULH)
        a_hi_ext = {a_sign, a_hi};
        b_hi_ext = {b_sign, b_hi};
      end
      3'b010: begin // signed × unsigned (MULHSU)
        a_hi_ext = {a_sign, a_hi};
        b_hi_ext = {1'b0  , b_hi};
      end
      3'b011: begin // unsigned × unsigned (MULHU)
        a_hi_ext = {1'b0  , a_hi};
        b_hi_ext = {1'b0  , b_hi};
      end
      default: begin
        a_hi_ext = {1'b0  , a_hi};
        b_hi_ext = {1'b0  , b_hi};
      end
    endcase
  end

  // 4x 16-bit multipliers (this is the fast part)
  assign p0 = $signed(a_lo_ext) * $signed(b_lo_ext);
  assign p1 = $signed(a_lo_ext) * $signed(b_hi_ext);
  assign p2 = $signed(a_hi_ext) * $signed(b_lo_ext);
  assign p3 = $signed(a_hi_ext) * $signed(b_hi_ext);

  // =========================================================================
  // REGISTER: Stage 1 output
  // =========================================================================
  logic signed [2:0] funct3_ff;
  logic signed [XLEN+1:0] p0_ff, p1_ff, p2_ff, p3_ff;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      funct3_ff <= 3'b000;
      p0_ff <= 0;
      p1_ff <= 0;
      p2_ff <= 0;
      p3_ff <= 0;
    end else if (!stall_i) begin
      funct3_ff <= funct3_i;
      p0_ff <= p0;
      p1_ff <= p1;
      p2_ff <= p2;
      p3_ff <= p3;
    end
  end

  // =========================================================================
  // STAGE 2: Efficient adder tree
  // =========================================================================
  // Formula: result = p0 + (p1 << 16) + (p2 << 16) + (p3 << 32)
  // Regroup: result = [p0 + (p1 << 16)] + [(p2 << 16) + (p3 << 32)]
  //                    \_____sum1_____/    \__________sum2_________/
  //                         ^^ These two additions happen in parallel ^^
  // Then: result = sum1 + sum2  (final addition)
  // =========================================================================

  logic signed [2*XLEN-1:0] sum1, sum2;
  logic signed [2*XLEN-1:0] final_product;

  // Two parallel additions (Level 1 of adder tree)
  assign sum1 = (p2_ff + p1_ff) << HALF;
  assign sum2 = {{p0_ff[33] ? (p3_ff[31:0]- 1) : p3_ff},p0_ff[31:0]};

  // Final addition (Level 2 of adder tree)
  assign final_product = sum1 + sum2;

  // Output selection based on operation type
  assign result_o = (funct3_ff == 3'b000) ? final_product[XLEN-1:0] :  final_product[2*XLEN-1:XLEN];
endmodule
