module montgomery(

  // signals for pipelining
  input logic clk, 
  input logic reset_n,
  input logic en,

  // operands and control signals 
  input  wire [15:0] op1_i,   
  input  wire [15:0] op2_i,   
  input  wire        func7_3,      // Control bit: 0 = Barrett, 1 = Montgomery
  input  wire        butterfly,    // Butterfly mode control signal
  output wire [31:0] reduced_o    
);

  // Precomputed Barrett constant
  reg signed [15:0] V = 20159;   // Barrett constant: floor(2^k / q)

  // Intermediate signals
  wire [31:0] product;  // op1 * op2
  wire [15:0] adder_o;  // op1 + op2
  wire [31:0] sub_o;    // (op1 - op2) or (product - m)

  // pipelined versions
  logic [15:0] op1_ff, op2_ff;
  logic        func7_3_ff, butterfly_ff;
  logic [31:0] product_ff;

  // ============================================
  //                16x16 Multiplication 
  // ============================================

  logic [15:0] mul_op2;
  assign mul_op2 = func7_3 ? op2_i : V;

  multiplier_16x16 mul1(
    .op1_i     (op1_i  ),
    .op2_i     (mul_op2),
    .result    (product)
  );

  // Stage 1 registers
  always_ff @(posedge clk or negedge reset_n) begin 
    if (!reset_n) begin 
      product_ff     <= '0;
      op1_ff         <= '0;
      op2_ff         <= '0;
      func7_3_ff     <= 1'b0;
      butterfly_ff   <= 1'b0;
    end else if (en) begin 
      product_ff     <= product;
      op1_ff         <= op1_i;
      op2_ff         <= op2_i;
      func7_3_ff     <= func7_3;
      butterfly_ff   <= butterfly;
    end
  end

  // ============================================
  //                Product x Qinv 
  // ============================================

  logic [15:0] t0;
  logic [31:0] product_x_qinv;

  assign t0 = func7_3_ff ? product_ff[15:0] : op1_ff;

  assign product_x_qinv = (t0 << 15) + (t0 << 14) +
                          (t0 << 13) + (t0 << 12) +
                          (t0 << 9)  + (t0 << 8 ) +
                           t0;

  // ============================================
  //           Product x Qinv x KYBER_Q 
  // ============================================

  logic [15:0] m;
  logic [31:0] barret_temp, mq;

  assign barret_temp = product_ff + 32'd33554432;

  assign m = func7_3_ff ? product_x_qinv[15:0] : {{10{barret_temp[31]}}, barret_temp[31:26]};

  assign mq = (m << 11) + (m << 10) + (m << 8) + m;

  // ============================================
  //                  Subtraction  
  // ============================================

  logic [31:0] sub_op1, sub_op2;
  assign sub_op1 = func7_3_ff ? product_ff : op1_ff; 
  assign sub_op2 = butterfly_ff ? op2_ff   : mq; 

  assign sub_o = sub_op1 - sub_op2;

  // ============================================
  //                     Addition  
  // ============================================

  assign adder_o = op1_ff + op2_ff;

  // ============================================
  //                 Final Output 
  // ============================================

  assign reduced_o = butterfly_ff ? {sub_o, adder_o} :
                     func7_3_ff   ?  sub_o[31:16]     : sub_o[15:0];

endmodule
