// fpu_minmax.sv — FMIN.S / FMAX.S
// IEEE 754-2008 minNum/maxNum as mandated by RISC-V F spec v2.2:
//   * If both operands are NaN → canonical qNaN (0x7FC00000).
//   * If exactly one operand is NaN → return the other (non-NaN) operand.
//   * sNaN input still returns the non-NaN operand (sets fflags NV, which
//     we don't track — FCSR is out of scope for Challenge 0013).
//   * Signed zero: -0.0 < +0.0 (explicit tie-break — IEEE bit-compare
//     would say they are equal).
//
// op_i: 0 = FMIN, 1 = FMAX

module fpu_minmax (
    input  logic        op_i,      // 0=min, 1=max
    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    output logic [31:0] result_o
);

    localparam logic [31:0] CANONICAL_QNAN = 32'h7FC00000;

    // Decomposition
    logic        sign_a, sign_b;
    logic [7:0]  exp_a,  exp_b;
    logic [22:0] mant_a, mant_b;
    logic        is_nan_a, is_nan_b;
    logic        is_zero_a, is_zero_b;

    assign sign_a = rs1_i[31];
    assign sign_b = rs2_i[31];
    assign exp_a  = rs1_i[30:23];
    assign exp_b  = rs2_i[30:23];
    assign mant_a = rs1_i[22:0];
    assign mant_b = rs2_i[22:0];

    assign is_nan_a  = (exp_a == 8'hFF) & (mant_a != 23'd0);
    assign is_nan_b  = (exp_b == 8'hFF) & (mant_b != 23'd0);
    assign is_zero_a = (exp_a == 8'd0)  & (mant_a == 23'd0);
    assign is_zero_b = (exp_b == 8'd0)  & (mant_b == 23'd0);

    // Numeric "less than" excluding NaN cases.
    // Float compare via sign + magnitude:
    //  * If signs differ: negative < positive (unless both zero — handled below).
    //  * If both positive: compare magnitude (bit-compare of exp+mant).
    //  * If both negative: reverse magnitude compare.
    logic [30:0] mag_a, mag_b;
    logic        a_lt_b;

    assign mag_a = rs1_i[30:0];
    assign mag_b = rs2_i[30:0];

    always_comb begin
        if (is_zero_a & is_zero_b) begin
            // -0 < +0 explicit tie-break
            a_lt_b =  sign_a & ~sign_b;
        end else if (sign_a != sign_b) begin
            a_lt_b = sign_a; // a negative, b positive → a < b
        end else if (~sign_a) begin
            // both non-negative → smaller magnitude is smaller
            a_lt_b = (mag_a < mag_b);
        end else begin
            // both negative → larger magnitude is smaller
            a_lt_b = (mag_a > mag_b);
        end
    end

    // Operand selection
    always_comb begin
        if (is_nan_a & is_nan_b) begin
            result_o = CANONICAL_QNAN;
        end else if (is_nan_a) begin
            result_o = rs2_i;
        end else if (is_nan_b) begin
            result_o = rs1_i;
        end else begin
            // 0 = min → pick smaller; 1 = max → pick larger
            if (op_i == 1'b0) begin
                result_o = a_lt_b ? rs1_i : rs2_i;
            end else begin
                result_o = a_lt_b ? rs2_i : rs1_i;
            end
        end
    end

endmodule
