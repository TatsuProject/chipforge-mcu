// fpu_unit.sv — Top-level FPU (uniform 4-stage pipelined).
//
// All FP ops have uniform EX→MEM→WB→WB+1 latency; `result_o` is flopped at
// WB+1 timing.
//   - FADD/FSUB: 3-stage compute (split across 2a/2b) + 1 output flop at the
//     end of fpu_addsub. 4 stages total.
//   - FMUL: 4-stage compute — stage 2b (shift+mask+sticky) and stage 2c
//     (round+pack+mux) are now flopped separately inside fpu_mul.
//   - MIN/MAX, SGNJ*, CVT, FMV: resolve combinationally in EX, then ride
//     three passthrough flops (ff/ff2/ff3) so they land at WB+1.
//
// `stall_i` follows the `mul_unit` handshake (~exe_mem_reg_en); freezing
// every stage together keeps results stable during a downstream stall.

module fpu_unit (
    input  logic         clk,
    input  logic         reset_n,
    input  logic         stall_i,
    input  logic [4:0]   op_i,
    input  logic [2:0]   rm_i,
    input  logic [31:0]  fp_rs1_i,
    input  logic [31:0]  fp_rs2_i,
    input  logic [31:0]  int_rs1_i,
    input  logic [47:0]  fmul_product_i,
    output logic [31:0]  result_o,          // valid at WB stage
    output logic         busy_o
);

    // ------------------------------------------------------------------
    // Stage 1 (EX) — combinational submodule results
    // ------------------------------------------------------------------
    logic [31:0] res_minmax_s1;
    logic [31:0] res_sgnj_s1;
    logic [31:0] res_cvt_f2i_s1;
    logic [31:0] res_cvt_i2f_s1;

    fpu_minmax u_minmax (
        .op_i    (op_i == 5'd5),
        .rs1_i   (fp_rs1_i),
        .rs2_i   (fp_rs2_i),
        .result_o(res_minmax_s1)
    );

    logic [1:0] sgnj_sel;
    always_comb begin
        unique case (op_i)
            5'd6:    sgnj_sel = 2'd0;
            5'd7:    sgnj_sel = 2'd1;
            5'd8:    sgnj_sel = 2'd2;
            default: sgnj_sel = 2'd0;
        endcase
    end

    fpu_sgnj u_sgnj (
        .op_i    (sgnj_sel),
        .rs1_i   (fp_rs1_i),
        .rs2_i   (fp_rs2_i),
        .result_o(res_sgnj_s1)
    );

    fpu_cvt_f2i u_cvt_f2i (
        .is_unsigned_i(op_i == 5'd10),
        .rm_i         (rm_i),
        .rs1_i        (fp_rs1_i),
        .result_o     (res_cvt_f2i_s1)
    );

    fpu_cvt_i2f u_cvt_i2f (
        .is_unsigned_i(op_i == 5'd12),
        .rm_i         (rm_i),
        .rs1_i        (int_rs1_i),
        .result_o     (res_cvt_i2f_s1)
    );

    // Pre-mux the non-multicycle result at stage 1 — one 32-bit flop pair
    // carries them through the two pipeline stages.
    logic [31:0] non_mc_result_s1;
    always_comb begin
        unique case (op_i)
            5'd4, 5'd5:       non_mc_result_s1 = res_minmax_s1;
            5'd6, 5'd7, 5'd8: non_mc_result_s1 = res_sgnj_s1;
            5'd9, 5'd10:      non_mc_result_s1 = res_cvt_f2i_s1;
            5'd11, 5'd12:     non_mc_result_s1 = res_cvt_i2f_s1;
            5'd13:            non_mc_result_s1 = fp_rs1_i;   // FMV.X.W
            5'd14:            non_mc_result_s1 = int_rs1_i;  // FMV.W.X
            default:          non_mc_result_s1 = 32'd0;
        endcase
    end

    // ------------------------------------------------------------------
    // Stage 1→2 flops (non-MC path + op tracking)
    // ------------------------------------------------------------------
    logic [31:0] non_mc_result_ff;
    logic [4:0]  op_ff;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            non_mc_result_ff <= 32'd0;
            op_ff            <= 5'd0;
        end else if (!stall_i) begin
            non_mc_result_ff <= non_mc_result_s1;
            op_ff            <= op_i;
        end
    end

    // ------------------------------------------------------------------
    // Stage 2→3 flops (non-MC passthrough + op double-flop)
    // ------------------------------------------------------------------
    logic [31:0] non_mc_result_ff2;
    logic [4:0]  op_ff2;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            non_mc_result_ff2 <= 32'd0;
            op_ff2            <= 5'd0;
        end else if (!stall_i) begin
            non_mc_result_ff2 <= non_mc_result_ff;
            op_ff2            <= op_ff;
        end
    end

    // ------------------------------------------------------------------
    // Stage 3→4 flops (non-MC passthrough + op triple-flop) — aligns the
    // combinational non-MC result with the addsub/mul WB+1-flopped output.
    // ------------------------------------------------------------------
    logic [31:0] non_mc_result_ff3;
    logic [4:0]  op_ff3;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            non_mc_result_ff3 <= 32'd0;
            op_ff3            <= 5'd0;
        end else if (!stall_i) begin
            non_mc_result_ff3 <= non_mc_result_ff2;
            op_ff3            <= op_ff2;
        end
    end

    // ------------------------------------------------------------------
    // Pipelined addsub / mul (4-stage internally; result_o at WB+1)
    // ------------------------------------------------------------------
    logic [31:0] res_addsub_wb1;
    logic [31:0] res_mul_wb1;

    fpu_addsub u_addsub (
        .clk     (clk),
        .reset_n (reset_n),
        .stall_i (stall_i),
        .sub_i   (op_i == 5'd2),
        .rm_i    (rm_i),
        .rs1_i   (fp_rs1_i),
        .rs2_i   (fp_rs2_i),
        .result_o(res_addsub_wb1)
    );

    fpu_mul u_mul (
        .clk            (clk),
        .reset_n        (reset_n),
        .stall_i        (stall_i),
        .rm_i           (rm_i),
        .rs1_i          (fp_rs1_i),
        .rs2_i          (fp_rs2_i),
        .full_product_i (fmul_product_i),
        .result_o       (res_mul_wb1)
    );

    // ------------------------------------------------------------------
    // WB+1 output mux — driven by triple-flopped op.
    // All three inputs are flop outputs, so the mux combinational is tiny.
    // ------------------------------------------------------------------
    always_comb begin
        unique case (op_ff3)
            5'd1, 5'd2: result_o = res_addsub_wb1;
            5'd3:       result_o = res_mul_wb1;
            default:    result_o = non_mc_result_ff3;
        endcase
    end

    assign busy_o = 1'b0;

endmodule
