// fpu_mul.sv — FMUL.S (4-stage pipelined).
//
// Stage 1  (EX)   : unpack, sign_r, exp_eff, specials                  -> ff
// Stage 2a (MEM)  : LZC + left-shift normalise + exp_r_signed          -> ff2
// Stage 2b (WB)   : shift+mask+sticky, mant_rounded, bit extract       -> ff3
// Stage 2c (WB+1) : sub_round_up, sub_mant_r adder, final pack mux     -> result_o
//
// Splitting 2b/2c cuts the v11 subnormal critical cone
// (ss_clamp_ff2 → 48-bit shift → sticky → sub_mant_r adder → final mux)
// roughly in half. FMUL result timing moves from WB to WB+1 — the surrounding
// pipe carries a small {rd, fp_reg_write, fp_wb_to_int} tail register so both
// reg_files can absorb the delayed write, and hazard_controller's fp_hazard
// now also fires when an FP producer is at WB.
//
// Mantissa product `full_product_i` comes from the shared mul_unit (MULHU
// of {8'b0,mant}*{8'b0,mant}, flopped at end of EX inside mul_unit).
//
// All inter-stage flops are clock-enabled by ~stall_i so a MEM-stage stall
// freezes the whole pipe (same handshake as v6).

module fpu_mul (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        stall_i,
    input  logic [2:0]  rm_i,
    input  logic [31:0] rs1_i,
    input  logic [31:0] rs2_i,
    input  logic [47:0] full_product_i,   // valid at MEM-stage timing
    output logic [31:0] result_o          // valid at WB-stage timing
);

    localparam logic [31:0] CANONICAL_QNAN = 32'h7FC00000;

    // ================================================================
    // Stage 1 (EX) — unpack, specials, sign_r, exp_eff
    // ================================================================
    logic        sign_a_s1, sign_b_s1, sign_r_s1;
    logic [7:0]  exp_a_raw_s1, exp_b_raw_s1;
    logic [22:0] mant_a_raw_s1, mant_b_raw_s1;
    logic        a_zero_s1, a_sub_s1, a_inf_s1, a_nan_s1;
    logic        b_zero_s1, b_sub_s1, b_inf_s1, b_nan_s1;
    logic [23:0] ma_full_s1, mb_full_s1;
    logic [7:0]  exp_a_eff_s1, exp_b_eff_s1;

    assign sign_a_s1     = rs1_i[31];
    assign sign_b_s1     = rs2_i[31];
    assign sign_r_s1     = sign_a_s1 ^ sign_b_s1;
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

    assign ma_full_s1   = a_sub_s1 ? {1'b0, mant_a_raw_s1} : {1'b1, mant_a_raw_s1};
    assign mb_full_s1   = b_sub_s1 ? {1'b0, mant_b_raw_s1} : {1'b1, mant_b_raw_s1};
    assign exp_a_eff_s1 = a_sub_s1 ? 8'd1 : exp_a_raw_s1;
    assign exp_b_eff_s1 = b_sub_s1 ? 8'd1 : exp_b_raw_s1;

    wire _mul_unused = &{1'b0, ma_full_s1, mb_full_s1, 1'b0};

    logic is_nan_result_s1, is_inf_result_s1, is_zero_result_s1;
    always_comb begin
        is_nan_result_s1  = 1'b0;
        is_inf_result_s1  = 1'b0;
        is_zero_result_s1 = 1'b0;
        if (a_nan_s1 | b_nan_s1) begin
            is_nan_result_s1 = 1'b1;
        end else if ((a_inf_s1 & b_zero_s1) | (a_zero_s1 & b_inf_s1)) begin
            is_nan_result_s1 = 1'b1;
        end else if (a_inf_s1 | b_inf_s1) begin
            is_inf_result_s1 = 1'b1;
        end else if (a_zero_s1 | b_zero_s1) begin
            is_zero_result_s1 = 1'b1;
        end
    end

    // --- Stage 1 → Stage 2a register (existing v6 flops) -------------
    logic        sign_r_ff, is_nan_ff, is_inf_ff, is_zero_ff;
    logic [7:0]  exp_a_eff_ff, exp_b_eff_ff;
    logic [2:0]  rm_ff;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            sign_r_ff    <= 1'b0;
            exp_a_eff_ff <= 8'd0;
            exp_b_eff_ff <= 8'd0;
            is_nan_ff    <= 1'b0;
            is_inf_ff    <= 1'b0;
            is_zero_ff   <= 1'b0;
            rm_ff        <= 3'd0;
        end else if (!stall_i) begin
            sign_r_ff    <= sign_r_s1;
            exp_a_eff_ff <= exp_a_eff_s1;
            exp_b_eff_ff <= exp_b_eff_s1;
            is_nan_ff    <= is_nan_result_s1;
            is_inf_ff    <= is_inf_result_s1;
            is_zero_ff   <= is_zero_result_s1;
            rm_ff        <= rm_i;
        end
    end

    // ================================================================
    // Stage 2a (MEM) — LZC, left-shift normalise, exp_r_signed
    // ================================================================
    wire [47:0] prod_ff = full_product_i;   // flopped in mul_unit

    logic [5:0] prod_lzc_s2a;
    always_comb begin
        casez (prod_ff)
            48'b1???????????????????????????????????????????????: prod_lzc_s2a = 6'd0;
            48'b01??????????????????????????????????????????????: prod_lzc_s2a = 6'd1;
            48'b001?????????????????????????????????????????????: prod_lzc_s2a = 6'd2;
            48'b0001????????????????????????????????????????????: prod_lzc_s2a = 6'd3;
            48'b00001???????????????????????????????????????????: prod_lzc_s2a = 6'd4;
            48'b000001??????????????????????????????????????????: prod_lzc_s2a = 6'd5;
            48'b0000001?????????????????????????????????????????: prod_lzc_s2a = 6'd6;
            48'b00000001????????????????????????????????????????: prod_lzc_s2a = 6'd7;
            48'b000000001???????????????????????????????????????: prod_lzc_s2a = 6'd8;
            48'b0000000001??????????????????????????????????????: prod_lzc_s2a = 6'd9;
            48'b00000000001?????????????????????????????????????: prod_lzc_s2a = 6'd10;
            48'b000000000001????????????????????????????????????: prod_lzc_s2a = 6'd11;
            48'b0000000000001???????????????????????????????????: prod_lzc_s2a = 6'd12;
            48'b00000000000001??????????????????????????????????: prod_lzc_s2a = 6'd13;
            48'b000000000000001?????????????????????????????????: prod_lzc_s2a = 6'd14;
            48'b0000000000000001????????????????????????????????: prod_lzc_s2a = 6'd15;
            48'b00000000000000001???????????????????????????????: prod_lzc_s2a = 6'd16;
            48'b000000000000000001??????????????????????????????: prod_lzc_s2a = 6'd17;
            48'b0000000000000000001?????????????????????????????: prod_lzc_s2a = 6'd18;
            48'b00000000000000000001????????????????????????????: prod_lzc_s2a = 6'd19;
            48'b000000000000000000001???????????????????????????: prod_lzc_s2a = 6'd20;
            48'b0000000000000000000001??????????????????????????: prod_lzc_s2a = 6'd21;
            48'b00000000000000000000001?????????????????????????: prod_lzc_s2a = 6'd22;
            48'b000000000000000000000001????????????????????????: prod_lzc_s2a = 6'd23;
            48'b0000000000000000000000001???????????????????????: prod_lzc_s2a = 6'd24;
            48'b00000000000000000000000001??????????????????????: prod_lzc_s2a = 6'd25;
            48'b000000000000000000000000001?????????????????????: prod_lzc_s2a = 6'd26;
            48'b0000000000000000000000000001????????????????????: prod_lzc_s2a = 6'd27;
            48'b00000000000000000000000000001???????????????????: prod_lzc_s2a = 6'd28;
            48'b000000000000000000000000000001??????????????????: prod_lzc_s2a = 6'd29;
            48'b0000000000000000000000000000001?????????????????: prod_lzc_s2a = 6'd30;
            48'b00000000000000000000000000000001????????????????: prod_lzc_s2a = 6'd31;
            48'b000000000000000000000000000000001???????????????: prod_lzc_s2a = 6'd32;
            48'b0000000000000000000000000000000001??????????????: prod_lzc_s2a = 6'd33;
            48'b00000000000000000000000000000000001?????????????: prod_lzc_s2a = 6'd34;
            48'b000000000000000000000000000000000001????????????: prod_lzc_s2a = 6'd35;
            48'b0000000000000000000000000000000000001???????????: prod_lzc_s2a = 6'd36;
            48'b00000000000000000000000000000000000001??????????: prod_lzc_s2a = 6'd37;
            48'b000000000000000000000000000000000000001?????????: prod_lzc_s2a = 6'd38;
            48'b0000000000000000000000000000000000000001????????: prod_lzc_s2a = 6'd39;
            48'b00000000000000000000000000000000000000001???????: prod_lzc_s2a = 6'd40;
            48'b000000000000000000000000000000000000000001??????: prod_lzc_s2a = 6'd41;
            48'b0000000000000000000000000000000000000000001?????: prod_lzc_s2a = 6'd42;
            48'b00000000000000000000000000000000000000000001????: prod_lzc_s2a = 6'd43;
            48'b000000000000000000000000000000000000000000001???: prod_lzc_s2a = 6'd44;
            48'b0000000000000000000000000000000000000000000001??: prod_lzc_s2a = 6'd45;
            48'b00000000000000000000000000000000000000000000001?: prod_lzc_s2a = 6'd46;
            48'b000000000000000000000000000000000000000000000001: prod_lzc_s2a = 6'd47;
            default:                                              prod_lzc_s2a = 6'd48;
        endcase
    end

    logic [47:0] prod_norm_s2a;
    assign prod_norm_s2a = prod_ff << prod_lzc_s2a;

    logic signed [10:0] exp_r_signed_s2a;
    assign exp_r_signed_s2a = $signed({3'd0, exp_a_eff_ff}) + $signed({3'd0, exp_b_eff_ff})
                              - 11'sd126 - $signed({5'd0, prod_lzc_s2a});

    // Precompute ss_clamp in stage 2a. Depends on exp_r_signed_s2a (itself
    // post-LZC), so this extends stage 2a's LZC-chain by +5 gate levels —
    // but shortens stage 2b by the same amount, which is our critical cone.
    logic signed [10:0] subshift_s2a;
    assign subshift_s2a = 11'sd1 - exp_r_signed_s2a;

    logic [5:0] ss_clamp_s2a;
    assign ss_clamp_s2a = (subshift_s2a > 11'sd48) ? 6'd48 :
                          (subshift_s2a < 11'sd0)  ? 6'd0  : subshift_s2a[5:0];

    // Precompute NORMAL-path round_up in stage 2a (mirrors the fpu_addsub
    // precompute). G/R/S/LSB come from prod_norm_s2a; rm_ff and sign_r_ff
    // are flopped from stage 1. Saves ~4-5 gate levels from stage 2b's
    // normal-path critical cone.
    logic g_s2a, r_s2a, s_s2a, lsb_s2a;
    assign g_s2a   = prod_norm_s2a[23];
    assign r_s2a   = prod_norm_s2a[22];
    assign s_s2a   = |prod_norm_s2a[21:0];
    assign lsb_s2a = prod_norm_s2a[24];

    logic round_up_s2a;
    always_comb begin
        unique case (rm_ff)
            3'b000, 3'b111: round_up_s2a = g_s2a & (r_s2a | s_s2a | lsb_s2a);
            3'b001:         round_up_s2a = 1'b0;
            3'b010:         round_up_s2a = sign_r_ff  & (g_s2a | r_s2a | s_s2a);
            3'b011:         round_up_s2a = ~sign_r_ff & (g_s2a | r_s2a | s_s2a);
            3'b100:         round_up_s2a = g_s2a;
            default:        round_up_s2a = g_s2a & (r_s2a | s_s2a | lsb_s2a);
        endcase
    end

    // --- Stage 2a → Stage 2b register --------------------------------
    logic [47:0]         prod_norm_ff2;
    logic signed [10:0]  exp_r_signed_ff2;
    logic [5:0]          ss_clamp_ff2;
    logic                round_up_ff2;
    logic                sign_r_ff2;
    logic [2:0]          rm_ff2;
    logic                is_nan_ff2, is_inf_ff2, is_zero_ff2;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            prod_norm_ff2    <= 48'd0;
            exp_r_signed_ff2 <= 11'sd0;
            ss_clamp_ff2     <= 6'd0;
            round_up_ff2     <= 1'b0;
            sign_r_ff2       <= 1'b0;
            rm_ff2           <= 3'd0;
            is_nan_ff2       <= 1'b0;
            is_inf_ff2       <= 1'b0;
            is_zero_ff2      <= 1'b0;
        end else if (!stall_i) begin
            prod_norm_ff2    <= prod_norm_s2a;
            exp_r_signed_ff2 <= exp_r_signed_s2a;
            ss_clamp_ff2     <= ss_clamp_s2a;
            round_up_ff2     <= round_up_s2a;
            sign_r_ff2       <= sign_r_ff;
            rm_ff2           <= rm_ff;
            is_nan_ff2       <= is_nan_ff;
            is_inf_ff2       <= is_inf_ff;
            is_zero_ff2      <= is_zero_ff;
        end
    end

    // ================================================================
    // Stage 2b (WB) — subnormal shift+mask+sticky, normal mant round,
    //                 bit extract for stage 2c.
    // ================================================================
    //
    // 2b's job is to produce all values that depend on the wide combinational
    // shift/mask of `prod_norm_ff2` / `ss_clamp_ff2`. The remaining rounding
    // adder and the final pack mux run in 2c, where their inputs are flopped.
    // This cuts the v11 critical cone roughly in half.

    // Normal-path rounded mantissa (round_up was precomputed in 2a).
    logic [24:0] mant_rounded_s2b;
    assign mant_rounded_s2b = {1'b0, prod_norm_ff2[47:24]} + {24'd0, round_up_ff2};

    // Subnormal path: 48-bit variable right shift, sticky mask, bit extract.
    logic [47:0] sub_mask_s2b;
    always_comb begin
        if (ss_clamp_ff2 == 6'd0)       sub_mask_s2b = 48'd0;
        else if (ss_clamp_ff2 >= 6'd48) sub_mask_s2b = {48{1'b1}};
        else                            sub_mask_s2b = (48'd1 << ss_clamp_ff2) - 48'd1;
    end

    logic [47:0] prod_sub_shifted_s2b;
    logic        sub_shift_sticky_s2b;
    assign prod_sub_shifted_s2b = prod_norm_ff2 >> ss_clamp_ff2;
    assign sub_shift_sticky_s2b = |(prod_norm_ff2 & sub_mask_s2b);

    // Pre-extract the only prod_sub_shifted bits stage 2c needs — keeps the
    // 2b→2c flop count small (27 bits instead of the full 48).
    logic [23:0] sub_mant24_s2b;
    logic        sub_g_s2b, sub_r_s2b, sub_s_s2b;
    assign sub_mant24_s2b = prod_sub_shifted_s2b[47:24];
    assign sub_g_s2b      = prod_sub_shifted_s2b[23];
    assign sub_r_s2b      = prod_sub_shifted_s2b[22];
    assign sub_s_s2b      = (|prod_sub_shifted_s2b[21:0]) | sub_shift_sticky_s2b;

    // overflow_post depends on mant_rounded[24]; compute here so 2c only
    // has to OR two flopped booleans.
    logic overflow_pre_s2b, overflow_post_s2b;
    assign overflow_pre_s2b  = (exp_r_signed_ff2 >= 11'sd255);
    assign overflow_post_s2b = (exp_r_signed_ff2 == 11'sd254) & mant_rounded_s2b[24];

    // ================================================================
    // Stage 2b → Stage 2c register
    // ================================================================
    logic [24:0]         mant_rounded_ff3;
    logic [23:0]         sub_mant24_ff3;
    logic                sub_g_ff3, sub_r_ff3, sub_s_ff3;
    logic signed [10:0]  exp_r_signed_ff3;
    logic                sign_r_ff3;
    logic [2:0]          rm_ff3;
    logic                is_nan_ff3, is_inf_ff3, is_zero_ff3;
    logic                overflow_pre_ff3, overflow_post_ff3;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mant_rounded_ff3  <= 25'd0;
            sub_mant24_ff3    <= 24'd0;
            sub_g_ff3         <= 1'b0;
            sub_r_ff3         <= 1'b0;
            sub_s_ff3         <= 1'b0;
            exp_r_signed_ff3  <= 11'sd0;
            sign_r_ff3        <= 1'b0;
            rm_ff3            <= 3'd0;
            is_nan_ff3        <= 1'b0;
            is_inf_ff3        <= 1'b0;
            is_zero_ff3       <= 1'b0;
            overflow_pre_ff3  <= 1'b0;
            overflow_post_ff3 <= 1'b0;
        end else if (!stall_i) begin
            mant_rounded_ff3  <= mant_rounded_s2b;
            sub_mant24_ff3    <= sub_mant24_s2b;
            sub_g_ff3         <= sub_g_s2b;
            sub_r_ff3         <= sub_r_s2b;
            sub_s_ff3         <= sub_s_s2b;
            exp_r_signed_ff3  <= exp_r_signed_ff2;
            sign_r_ff3        <= sign_r_ff2;
            rm_ff3            <= rm_ff2;
            is_nan_ff3        <= is_nan_ff2;
            is_inf_ff3        <= is_inf_ff2;
            is_zero_ff3       <= is_zero_ff2;
            overflow_pre_ff3  <= overflow_pre_s2b;
            overflow_post_ff3 <= overflow_post_s2b;
        end
    end

    // ================================================================
    // Stage 2c (WB+1) — subnormal round, exp/mant select, final pack
    // ================================================================
    logic sub_round_up;
    always_comb begin
        unique case (rm_ff3)
            3'b000, 3'b111: sub_round_up = sub_g_ff3 & (sub_r_ff3 | sub_s_ff3 | sub_mant24_ff3[0]);
            3'b001:         sub_round_up = 1'b0;
            3'b010:         sub_round_up = sign_r_ff3  & (sub_g_ff3 | sub_r_ff3 | sub_s_ff3);
            3'b011:         sub_round_up = ~sign_r_ff3 & (sub_g_ff3 | sub_r_ff3 | sub_s_ff3);
            3'b100:         sub_round_up = sub_g_ff3;
            default:        sub_round_up = sub_g_ff3 & (sub_r_ff3 | sub_s_ff3 | sub_mant24_ff3[0]);
        endcase
    end

    logic [24:0] sub_mant_r;
    assign sub_mant_r = {1'b0, sub_mant24_ff3} + {24'd0, sub_round_up};

    logic [7:0]  sub_exp_result;
    logic [22:0] sub_mant_result;
    always_comb begin
        if (sub_mant_r[24] | sub_mant_r[23]) begin
            sub_exp_result  = 8'd1;
            sub_mant_result = 23'd0;
        end else begin
            sub_exp_result  = 8'd0;
            sub_mant_result = sub_mant_r[22:0];
        end
    end

    logic [7:0]  exp_final;
    logic [22:0] mant_final;

    always_comb begin
        if (exp_r_signed_ff3 >= 11'sd255) begin
            exp_final  = 8'hFF;
            mant_final = 23'd0;
        end else if (exp_r_signed_ff3 <= 11'sd0) begin
            exp_final  = sub_exp_result;
            mant_final = sub_mant_result;
        end else begin
            if (mant_rounded_ff3[24]) begin
                exp_final  = exp_r_signed_ff3[7:0] + 8'd1;
                mant_final = 23'd0;
            end else begin
                exp_final  = exp_r_signed_ff3[7:0];
                mant_final = mant_rounded_ff3[22:0];
            end
        end
    end

    logic overflow_any;
    assign overflow_any = (overflow_pre_ff3 | overflow_post_ff3)
                          & ~is_nan_ff3 & ~is_inf_ff3 & ~is_zero_ff3;

    always_comb begin
        if (is_nan_ff3) begin
            result_o = CANONICAL_QNAN;
        end else if (is_inf_ff3) begin
            result_o = {sign_r_ff3, 8'hFF, 23'd0};
        end else if (is_zero_ff3) begin
            result_o = {sign_r_ff3, 8'd0, 23'd0};
        end else if (overflow_any) begin
            unique case (rm_ff3)
                3'b001: result_o = {sign_r_ff3, 8'hFE, 23'h7FFFFF};
                3'b010: result_o = sign_r_ff3 ? {1'b1, 8'hFF, 23'd0}
                                              : {1'b0, 8'hFE, 23'h7FFFFF};
                3'b011: result_o = sign_r_ff3 ? {1'b1, 8'hFE, 23'h7FFFFF}
                                              : {1'b0, 8'hFF, 23'd0};
                default: result_o = {sign_r_ff3, 8'hFF, 23'd0};
            endcase
        end else begin
            result_o = {sign_r_ff3, exp_final, mant_final};
        end
    end

endmodule
