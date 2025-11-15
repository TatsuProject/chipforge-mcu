// =============================================================================
//  File        : pqc_top.sv
//  Description : Top‐level PQC ALU: Montgomery/Barrett reductions and Butterfly
// =============================================================================

module pqc_top #(
  // width parameters
  localparam int FULL_WIDTH = 32,
  localparam int HALF_WIDTH = FULL_WIDTH/2,
  localparam int CTRL_WIDTH = 3
) (

  input  logic                  clk ,
  input  logic                  reset_n,
  input  logic                  en,
  input  logic [FULL_WIDTH-1:0] operand1_i,
  input  logic [FULL_WIDTH-1:0] operand2_i,
  input  logic [CTRL_WIDTH-1:0] inst_28_27_26,
  output logic [FULL_WIDTH-1:0] result_o
);

  // Enumerated PQC operation type
  typedef enum logic [CTRL_WIDTH-1:0] {
    ALU_MULRED,         // Montgomery multiply+reduce (lower & upper)
    ALU_BARRET,         // Barrett reduction      (lower & upper)
    ALU_BUTTERFLY,      // Butterfly on lower half
    ALU_BUTTERFLY_LOWER // Butterfly on upper half
  } pqc_op_t;

  pqc_op_t pqc_op, pqc_op_ff;

  // 1) Decode inst[28:26] → pqc_op
  always_comb begin
    case (inst_28_27_26)
      3'b111, 3'b110:   pqc_op = ALU_MULRED;         // fqmul_k, fqmul_upper
      3'b011, 3'b101:   pqc_op = ALU_BARRET;         // barret_red, barret_red_k_upper
      3'b000:           pqc_op = ALU_BUTTERFLY;      // butterfly_k (lower)
      3'b100:           pqc_op = ALU_BUTTERFLY_LOWER;// butterfly_k_upper
      default:          pqc_op = ALU_MULRED;
    endcase
  end

  // 2) Is this an “upper-half” variant?
  logic is_upper;
  always_comb begin
    is_upper = (inst_28_27_26 == 3'b110) ||   // fqmul_upper
               (inst_28_27_26 == 3'b101) ||   // barret_red_k_upper
               (inst_28_27_26 == 3'b100);     // butterfly_k_upper
  end

  // 3) Slice operands and set reduction vs butterfly flags
  logic mont_or_barret;
  logic butterfly;
  logic [HALF_WIDTH-1:0] op1, op2;

  always_comb begin
    mont_or_barret = (pqc_op == ALU_MULRED);
    butterfly      = (pqc_op == ALU_BUTTERFLY) || (pqc_op == ALU_BUTTERFLY_LOWER);

    if (is_upper) begin
      // take bits [31:16]
      op1 = operand1_i[FULL_WIDTH-1:HALF_WIDTH];
      op2 = operand2_i[FULL_WIDTH-1:HALF_WIDTH];
    end else begin
      // take bits [15:0]
      op1 = operand1_i[HALF_WIDTH-1:0];
      op2 = operand2_i[HALF_WIDTH-1:0];
    end
  end

  // 4) Instantiate the Montgomery/Barrett/Butterfly core
  logic [FULL_WIDTH-1:0] reduced_o;
  montgomery mon (
    .clk, 
    .reset_n,
    .en,
    .op1_i(op1),
    .op2_i(op2),
    .func7_3    (mont_or_barret),
    .butterfly  (butterfly),
    .reduced_o  (reduced_o)
  );

  // pipelining 
  always_ff @(posedge clk or negedge reset_n) begin 
    if (!reset_n) begin 
      pqc_op_ff     <= ALU_MULRED;
    end else if (en) begin 
      pqc_op_ff     <= pqc_op;
    end
  end


  always_comb begin
    unique case (pqc_op_ff)
      ALU_MULRED,
      ALU_BARRET:
        result_o = {{HALF_WIDTH{reduced_o[HALF_WIDTH-1]}}, reduced_o[HALF_WIDTH-1:0]};

      ALU_BUTTERFLY,
      ALU_BUTTERFLY_LOWER:
        result_o = reduced_o;

      default:
        result_o = '0;
    endcase
  end

endmodule
