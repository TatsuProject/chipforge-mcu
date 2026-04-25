// fpu_addsub.sv — FADD.S / FSUB.S (4-stage pipelined).
//
// Stage 1  (EX)   : unpack, swap, align, add/subtract, specials -> ff
// Stage 2a (MEM)  : LZC + normalise shift, pre-round select     -> ff2
// Stage 2b (WB)   : round + pack + final assembly (combinational,
//                   short after v11's round_up precompute)       -> ff3
// Stage 2c (WB+1) : nothing to do — result_o just flops out.
//
// Kept in lockstep with fpu_mul's 4-stage split so fpu_unit can present a
// uniform WB+1 result. Stage 2b didn't need further logic splitting, so the
// ff3 boundary is just a pipeline register on the packed 32-bit result.

module fpu_addsub (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        stall_i,
    input  logic        sub_i,
    input  logic [2:0]  rm_i,
    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    output logic [31:0] result_o        // valid at WB+1 timing
);

    localparam logic [31:0] CANONICAL_QNAN = 32'h7FC00000;

    // ================================================================
    // Stage 1 (EX) — unpack, align, add/subtract
    // ================================================================
    logic        sign_a_s1, sign_b_s1;
    logic [7:0]  exp_a_raw_s1, exp_b_raw_s1;
    logic [22:0] mant_a_raw_s1, mant_b_raw_s1;
    logic        a_zero_s1, a_sub_s1, a_inf_s1, a_nan_s1;
    logic        b_zero_s1, b_sub_s1, b_inf_s1, b_nan_s1;
    logic [23:0] ma_full_s1, mb_full_s1;
    logic [7:0]  exp_a_s1, exp_b_s1;

    assign sign_a_s1     = rs1_i[31];
    assign sign_b_s1     = rs2_i[31] ^ sub_i;
    assign exp_a_raw_s1  = rs1_i[30:23];
    assign exp_b_raw_s1  = rs2_i[30:23];
    assign mant_a_raw_s1 = rs1_i[22:0];
    assign mant_b_raw_s1 = rs2_i[22:0];

    assign a_zero_s1 = (exp_a_raw_s1 == 8'd0)  & (mant_a_raw_s1 == 23'd0);
    assign a_sub_s1  = (exp_a_raw_s1 == 8'd0)  & (mant_a_raw_s1 != 23'd0);
    assign a_inf_s1  = (exp_a_raw_s1 == 8'hFF) & (mant_a_raw_s1 == 23'd0);
    assign a_nan_s1  = (exp_a_raw_s1 == 8'hFF) & (mant_a_raw_s1 != 23'd0);

    assign b_zero_s1 = (exp_b_raw_s1 == 8'd0)  & (mant_b_raw_s1 == 23'd0);
    assign b_sub_s1  = (exp_b_raw_s1 == 8'd0)  & (mant_b_raw_s1 != 23'd0);
    assign b_inf_s1  = (exp_b_raw_s1 == 8'hFF) & (mant_b_raw_s1 == 23'd0);
    assign b_nan_s1  = (exp_b_raw_s1 == 8'hFF) & (mant_b_raw_s1 != 23'd0);

    assign ma_full_s1 = a_sub_s1 ? {1'b0, mant_a_raw_s1} : {1'b1, mant_a_raw_s1};
    assign mb_full_s1 = b_sub_s1 ? {1'b0, mant_b_raw_s1} : {1'b1, mant_b_raw_s1};
    assign exp_a_s1   = a_sub_s1 ? 8'd1 : exp_a_raw_s1;
    assign exp_b_s1   = b_sub_s1 ? 8'd1 : exp_b_raw_s1;

    logic is_nan_result_s1;
    logic is_inf_result_s1;
    logic inf_result_sign_s1;

    always_comb begin
        is_nan_result_s1   = 1'b0;
        is_inf_result_s1   = 1'b0;
        inf_result_sign_s1 = 1'b0;
        if (a_nan_s1 | b_nan_s1) begin
            is_nan_result_s1 = 1'b1;
        end else if (a_inf_s1 & b_inf_s1) begin
            if (sign_a_s1 == sign_b_s1) begin
                is_inf_result_s1   = 1'b1;
                inf_result_sign_s1 = sign_a_s1;
            end else begin
                is_nan_result_s1 = 1'b1;
            end
        end else if (a_inf_s1) begin
            is_inf_result_s1   = 1'b1;
            inf_result_sign_s1 = sign_a_s1;
        end else if (b_inf_s1) begin
            is_inf_result_s1   = 1'b1;
            inf_result_sign_s1 = sign_b_s1;
        end
    end

    logic swap_s1;
    assign swap_s1 = (exp_a_s1 < exp_b_s1) | ((exp_a_s1 == exp_b_s1) & (ma_full_s1 < mb_full_s1));

    logic        sign_big_s1, sign_small_s1;
    logic [7:0]  exp_big_s1;
    logic [23:0] mant_big_s1, mant_small_s1;
    logic [7:0]  exp_diff_s1;

    assign sign_big_s1   = swap_s1 ? sign_b_s1 : sign_a_s1;
    assign sign_small_s1 = swap_s1 ? sign_a_s1 : sign_b_s1;
    assign exp_big_s1    = swap_s1 ? exp_b_s1  : exp_a_s1;
    assign mant_big_s1   = swap_s1 ? mb_full_s1 : ma_full_s1;
    assign mant_small_s1 = swap_s1 ? ma_full_s1 : mb_full_s1;
    assign exp_diff_s1   = exp_big_s1 - (swap_s1 ? exp_a_s1 : exp_b_s1);

    logic [26:0] mant_big_ext_s1;
    logic [26:0] mant_small_ext_s1;
    logic        sticky_align_s1;

    assign mant_big_ext_s1 = {mant_big_s1, 3'b000};

    always_comb begin
        if (exp_diff_s1 >= 8'd27) begin
            mant_small_ext_s1 = 27'd0;
            sticky_align_s1   = |mant_small_s1;
        end else if (exp_diff_s1 == 8'd0) begin
            mant_small_ext_s1 = {mant_small_s1, 3'b000};
            sticky_align_s1   = 1'b0;
        end else begin
            mant_small_ext_s1 = {mant_small_s1, 3'b000} >> exp_diff_s1[4:0];
            sticky_align_s1   = |({mant_small_s1, 3'b000} & ((27'd1 << exp_diff_s1[4:0]) - 27'd1));
        end
    end

    logic [26:0] mb_final_s1;
    assign mb_final_s1 = {mant_small_ext_s1[26:1], mant_small_ext_s1[0] | sticky_align_s1};

    logic        effective_sub_s1;
    logic [27:0] sum_ext_s1;

    assign effective_sub_s1 = (sign_big_s1 != sign_small_s1);

    always_comb begin
        if (effective_sub_s1)
            sum_ext_s1 = {1'b0, mant_big_ext_s1} - {1'b0, mb_final_s1};
        else
            sum_ext_s1 = {1'b0, mant_big_ext_s1} + {1'b0, mb_final_s1};
    end

    logic sign_zero_s1;
    always_comb begin
        if (a_zero_s1 & b_zero_s1) begin
            if (sign_a_s1 == sign_b_s1) sign_zero_s1 = sign_a_s1;
            else                        sign_zero_s1 = (rm_i == 3'b010);
        end else begin
            sign_zero_s1 = (rm_i == 3'b010);
        end
    end

    // ================================================================
    // Stage 1 → Stage 2a register (same roster as v6)
    // ================================================================
    logic [27:0] sum_ext_ff;
    logic        effective_sub_ff;
    logic [7:0]  exp_big_ff;
    logic        sign_big_ff;
    logic [2:0]  rm_ff;
    logic        is_nan_ff, is_inf_ff, inf_sign_ff;
    logic        a_zero_ff, b_zero_ff;
    logic        sign_zero_ff;
    logic [31:0] a_zero_out_ff;
    logic [31:0] b_zero_out_ff;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sum_ext_ff       <= 28'd0;
            effective_sub_ff <= 1'b0;
            exp_big_ff       <= 8'd0;
            sign_big_ff      <= 1'b0;
            rm_ff            <= 3'd0;
            is_nan_ff        <= 1'b0;
            is_inf_ff        <= 1'b0;
            inf_sign_ff      <= 1'b0;
            a_zero_ff        <= 1'b0;
            b_zero_ff        <= 1'b0;
            sign_zero_ff     <= 1'b0;
            a_zero_out_ff    <= 32'd0;
            b_zero_out_ff    <= 32'd0;
        end else if (!stall_i) begin
            sum_ext_ff       <= sum_ext_s1;
            effective_sub_ff <= effective_sub_s1;
            exp_big_ff       <= exp_big_s1;
            sign_big_ff      <= sign_big_s1;
            rm_ff            <= rm_i;
            is_nan_ff        <= is_nan_result_s1;
            is_inf_ff        <= is_inf_result_s1;
            inf_sign_ff      <= inf_result_sign_s1;
            a_zero_ff        <= a_zero_s1;
            b_zero_ff        <= b_zero_s1;
            sign_zero_ff     <= sign_zero_s1;
            a_zero_out_ff    <= {sign_b_s1, exp_b_raw_s1, mant_b_raw_s1};
            b_zero_out_ff    <= rs1_i;
        end
    end

    // ================================================================
    // Stage 2a (MEM) — LZC + normalise shift + pre-round select
    // ================================================================

    // --- add-path normalisation ---
    logic        add_overflow_s2a;
    logic [26:0] sum_add_norm_s2a;
    logic        sticky_add_shift_s2a;

    assign add_overflow_s2a     = ~effective_sub_ff & sum_ext_ff[27];
    assign sum_add_norm_s2a     = add_overflow_s2a ? sum_ext_ff[27:1] : sum_ext_ff[26:0];
    assign sticky_add_shift_s2a = add_overflow_s2a & sum_ext_ff[0];

    logic [7:0] exp_after_add_s2a;
    assign exp_after_add_s2a = add_overflow_s2a ? (exp_big_ff + 8'd1) : exp_big_ff;

    // --- sub-path normalisation (LZC + shift left) ---
    logic [26:0] sum_sub_raw_s2a;
    assign sum_sub_raw_s2a = sum_ext_ff[26:0];

    logic [4:0] lzc_sub_s2a;
    always_comb begin
        casez (sum_sub_raw_s2a)
            27'b1??????????????????????????: lzc_sub_s2a = 5'd0;
            27'b01?????????????????????????: lzc_sub_s2a = 5'd1;
            27'b001????????????????????????: lzc_sub_s2a = 5'd2;
            27'b0001???????????????????????: lzc_sub_s2a = 5'd3;
            27'b00001??????????????????????: lzc_sub_s2a = 5'd4;
            27'b000001?????????????????????: lzc_sub_s2a = 5'd5;
            27'b0000001????????????????????: lzc_sub_s2a = 5'd6;
            27'b00000001???????????????????: lzc_sub_s2a = 5'd7;
            27'b000000001??????????????????: lzc_sub_s2a = 5'd8;
            27'b0000000001?????????????????: lzc_sub_s2a = 5'd9;
            27'b00000000001????????????????: lzc_sub_s2a = 5'd10;
            27'b000000000001???????????????: lzc_sub_s2a = 5'd11;
            27'b0000000000001??????????????: lzc_sub_s2a = 5'd12;
            27'b00000000000001?????????????: lzc_sub_s2a = 5'd13;
            27'b000000000000001????????????: lzc_sub_s2a = 5'd14;
            27'b0000000000000001???????????: lzc_sub_s2a = 5'd15;
            27'b00000000000000001??????????: lzc_sub_s2a = 5'd16;
            27'b000000000000000001?????????: lzc_sub_s2a = 5'd17;
            27'b0000000000000000001????????: lzc_sub_s2a = 5'd18;
            27'b00000000000000000001???????: lzc_sub_s2a = 5'd19;
            27'b000000000000000000001??????: lzc_sub_s2a = 5'd20;
            27'b0000000000000000000001?????: lzc_sub_s2a = 5'd21;
            27'b00000000000000000000001????: lzc_sub_s2a = 5'd22;
            27'b000000000000000000000001???: lzc_sub_s2a = 5'd23;
            27'b0000000000000000000000001??: lzc_sub_s2a = 5'd24;
            27'b00000000000000000000000001?: lzc_sub_s2a = 5'd25;
            27'b000000000000000000000000001: lzc_sub_s2a = 5'd26;
            default:                          lzc_sub_s2a = 5'd27;
        endcase
    end

    logic [4:0]  sub_shift_s2a;
    logic [7:0]  exp_after_sub_s2a;
    logic [26:0] sum_sub_norm_s2a;
    logic        is_result_zero_s2a;

    always_comb begin
        is_result_zero_s2a = 1'b0;
        if (lzc_sub_s2a == 5'd27) begin
            sub_shift_s2a      = 5'd0;
            exp_after_sub_s2a  = 8'd0;
            sum_sub_norm_s2a   = 27'd0;
            is_result_zero_s2a = effective_sub_ff;
        end else if (exp_big_ff <= {3'd0, lzc_sub_s2a}) begin
            sub_shift_s2a     = exp_big_ff == 8'd0 ? 5'd0 : (exp_big_ff[4:0] - 5'd1);
            exp_after_sub_s2a = 8'd0;
            sum_sub_norm_s2a  = sum_sub_raw_s2a << sub_shift_s2a;
        end else begin
            sub_shift_s2a     = lzc_sub_s2a;
            exp_after_sub_s2a = exp_big_ff - {3'd0, lzc_sub_s2a};
            sum_sub_norm_s2a  = sum_sub_raw_s2a << sub_shift_s2a;
        end
    end

    logic [26:0] sum_pre_round_s2a;
    logic [7:0]  exp_pre_round_s2a;
    logic        sticky_extra_s2a;

    assign sum_pre_round_s2a = effective_sub_ff ? sum_sub_norm_s2a : sum_add_norm_s2a;
    assign exp_pre_round_s2a = effective_sub_ff ? exp_after_sub_s2a : exp_after_add_s2a;
    assign sticky_extra_s2a  = ~effective_sub_ff & sticky_add_shift_s2a;

    // Precompute round_up in stage 2a — analogous to v8a's ss_clamp precompute.
    // g/r/s/lsb come from bits [2:0] + [3] of sum_pre_round_s2a; rm_ff and
    // sign_big_ff are already flopped from stage 1. Moving this ~4-5 gate level
    // mux out of stage 2b's critical cone (v10 STA showed the critical path
    // starting at rm_ff2 going through this very case).
    logic g_s2a, r_s2a, s_s2a, lsb_s2a;
    assign g_s2a   = sum_pre_round_s2a[2];
    assign r_s2a   = sum_pre_round_s2a[1];
    assign s_s2a   = sum_pre_round_s2a[0] | sticky_extra_s2a;
    assign lsb_s2a = sum_pre_round_s2a[3];

    logic round_up_s2a;
    always_comb begin
        unique case (rm_ff)
            3'b000, 3'b111: round_up_s2a = g_s2a & (r_s2a | s_s2a | lsb_s2a);
            3'b001:         round_up_s2a = 1'b0;
            3'b010:         round_up_s2a = sign_big_ff  & (g_s2a | r_s2a | s_s2a);
            3'b011:         round_up_s2a = ~sign_big_ff & (g_s2a | r_s2a | s_s2a);
            3'b100:         round_up_s2a = g_s2a;
            default:        round_up_s2a = g_s2a & (r_s2a | s_s2a | lsb_s2a);
        endcase
    end

    // ================================================================
    // Stage 2a → Stage 2b register (NEW)
    // ================================================================
    logic [26:0] sum_pre_round_ff2;
    logic [7:0]  exp_pre_round_ff2;
    logic        round_up_ff2;
    logic        sign_big_ff2;
    logic [2:0]  rm_ff2;
    logic        is_nan_ff2, is_inf_ff2, inf_sign_ff2;
    logic        a_zero_ff2, b_zero_ff2;
    logic        sign_zero_ff2;
    logic [31:0] a_zero_out_ff2, b_zero_out_ff2;
    logic        is_result_zero_ff2;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sum_pre_round_ff2  <= 27'd0;
            exp_pre_round_ff2  <= 8'd0;
            round_up_ff2       <= 1'b0;
            sign_big_ff2       <= 1'b0;
            rm_ff2             <= 3'd0;
            is_nan_ff2         <= 1'b0;
            is_inf_ff2         <= 1'b0;
            inf_sign_ff2       <= 1'b0;
            a_zero_ff2         <= 1'b0;
            b_zero_ff2         <= 1'b0;
            sign_zero_ff2      <= 1'b0;
            a_zero_out_ff2     <= 32'd0;
            b_zero_out_ff2     <= 32'd0;
            is_result_zero_ff2 <= 1'b0;
        end else if (!stall_i) begin
            sum_pre_round_ff2  <= sum_pre_round_s2a;
            exp_pre_round_ff2  <= exp_pre_round_s2a;
            round_up_ff2       <= round_up_s2a;
            sign_big_ff2       <= sign_big_ff;
            rm_ff2             <= rm_ff;
            is_nan_ff2         <= is_nan_ff;
            is_inf_ff2         <= is_inf_ff;
            inf_sign_ff2       <= inf_sign_ff;
            a_zero_ff2         <= a_zero_ff;
            b_zero_ff2         <= b_zero_ff;
            sign_zero_ff2      <= sign_zero_ff;
            a_zero_out_ff2     <= a_zero_out_ff;
            b_zero_out_ff2     <= b_zero_out_ff;
            is_result_zero_ff2 <= is_result_zero_s2a;
        end
    end

    // ================================================================
    // Stage 2b (WB) — round + pack + final assembly (round_up precomputed)
    // ================================================================
    logic [24:0] mant_rounded25;
    assign mant_rounded25 = {1'b0, sum_pre_round_ff2[26:3]} + {24'd0, round_up_ff2};

    logic [7:0]  exp_post;
    logic [22:0] mant_post;
    logic        implicit_bit;

    always_comb begin
        if (mant_rounded25[24]) begin
            exp_post     = exp_pre_round_ff2 + 8'd1;
            mant_post    = 23'd0;
            implicit_bit = 1'b1;
        end else begin
            exp_post     = exp_pre_round_ff2;
            mant_post    = mant_rounded25[22:0];
            implicit_bit = mant_rounded25[23];
        end
    end

    logic [31:0] result_s2b;
    always_comb begin
        if (is_nan_ff2) begin
            result_s2b = CANONICAL_QNAN;
        end else if (is_inf_ff2) begin
            result_s2b = {inf_sign_ff2, 8'hFF, 23'd0};
        end else if (a_zero_ff2 & b_zero_ff2) begin
            result_s2b = {sign_zero_ff2, 8'd0, 23'd0};
        end else if (a_zero_ff2) begin
            result_s2b = a_zero_out_ff2;
        end else if (b_zero_ff2) begin
            result_s2b = b_zero_out_ff2;
        end else if (is_result_zero_ff2) begin
            result_s2b = {sign_zero_ff2, 8'd0, 23'd0};
        end else if (exp_post >= 8'hFF) begin
            unique case (rm_ff2)
                3'b001:
                    result_s2b = {sign_big_ff2, 8'hFE, 23'h7FFFFF};
                3'b010:
                    result_s2b = sign_big_ff2 ? {1'b1, 8'hFF, 23'd0}
                                              : {1'b0, 8'hFE, 23'h7FFFFF};
                3'b011:
                    result_s2b = sign_big_ff2 ? {1'b1, 8'hFE, 23'h7FFFFF}
                                              : {1'b0, 8'hFF, 23'd0};
                default:
                    result_s2b = {sign_big_ff2, 8'hFF, 23'd0};
            endcase
        end else if (~implicit_bit) begin
            result_s2b = {sign_big_ff2, 8'd0, mant_post};
        end else begin
            result_s2b = {sign_big_ff2, exp_post, mant_post};
        end
    end

    // Stage 2b → Stage 2c (WB+1) output register
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            result_o <= 32'd0;
        end else if (!stall_i) begin
            result_o <= result_s2b;
        end
    end

endmodule
