// fpu_cvt_f2i.sv — FCVT.W.S / FCVT.WU.S
// Convert IEEE-754 single-precision float to signed/unsigned 32-bit integer
// with rounding mode rm_i and saturation per the RISC-V F v2.2 spec:
//
//   Source operand    signed result      unsigned result
//   ---------------   ----------------   -----------------
//   NaN               0x7FFFFFFF (max)   0xFFFFFFFF (max)
//   +∞                0x7FFFFFFF (max)   0xFFFFFFFF (max)
//   -∞                0x80000000 (min)   0x00000000
//   > INT_MAX (rnd)   0x7FFFFFFF         saturate
//   < INT_MIN (rnd)   0x80000000         0x00000000 (negative clamps to 0)
//
// Rounding modes (rm_i from funct3):
//   000 RNE, 001 RTZ, 010 RDN, 011 RUP, 100 RMM
//   111 DYN → treat as RNE (FCSR out of scope for Challenge 0013)
//
// Implementation: align the 24-bit effective mantissa (implicit bit + 23)
// into a 96-bit fixed-point reg with the LSB of the integer at bit 47,
// then left-shift by eff_exp. Upper 49 bits are integer, lower 47 bits are
// fraction (guard/round/sticky collapsed from those 47 bits).

module fpu_cvt_f2i (
    input  logic        is_unsigned_i,   // 0 = FCVT.W.S, 1 = FCVT.WU.S
    input  logic [2:0]  rm_i,
    input  logic [31:0] rs1_i,
    output logic [31:0] result_o
);

    // ----- unpack ---------------------------------------------------------
    logic        sign_a;
    logic [7:0]  exp_a;
    logic [22:0] mant_a;
    logic        is_zero, is_subnormal, is_normal, is_inf, is_nan;
    logic [23:0] mant_full;

    assign sign_a       = rs1_i[31];
    assign exp_a        = rs1_i[30:23];
    assign mant_a       = rs1_i[22:0];
    assign is_zero      = (exp_a == 8'd0)   & (mant_a == 23'd0);
    assign is_subnormal = (exp_a == 8'd0)   & (mant_a != 23'd0);
    assign is_inf       = (exp_a == 8'hFF)  & (mant_a == 23'd0);
    assign is_nan       = (exp_a == 8'hFF)  & (mant_a != 23'd0);
    assign is_normal    = ~(is_zero | is_subnormal | is_inf | is_nan);
    assign mant_full    = is_subnormal ? {1'b0, mant_a} : {1'b1, mant_a};

    // Effective exponent (unbiased). Subnormals: use -126 (not -127 + LZ shift)
    // — we don't bother to pre-normalise subnormals; their contribution after
    // shifting will underflow to 0 / ±1 anyway. For true subnormals rounding
    // to a non-zero int is only possible for rm = RUP/RDN, which we handle
    // conservatively.
    logic signed [10:0] eff_exp;
    assign eff_exp = is_subnormal ? -11'sd126 :
                                    $signed({3'b000, exp_a}) - 11'sd127;

    // ----- fixed-point alignment -----------------------------------------
    // Place mant_full at bits [47:24] of a 96-bit register. bit 47 represents
    // 2^0 of the float magnitude when eff_exp = 0. Left-shift by eff_exp to
    // put the integer MSB at the right position.
    logic [95:0] m96_base;
    assign m96_base = {48'd0, mant_full, 24'd0};

    logic [95:0] m96_shifted;
    logic        sticky_far;       // OR of bits shifted past bit 0 on a right shift
    logic [6:0]  abs_sh;           // 7-bit magnitude of shift amount
    logic [95:0] lo_mask;          // low-abs_sh-bits mask, used for sticky capture

    always_comb begin
        sticky_far  = 1'b0;
        m96_shifted = 96'd0;
        abs_sh      = 7'd0;
        lo_mask     = 96'd0;
        if (eff_exp >= 0) begin
            // Left shift — integer grows. Cap at 48 to stay safe in a 96-bit reg.
            // eff_exp > 31 is an overflow; saturation logic below handles it.
            if (eff_exp <= 11'sd48) begin
                m96_shifted = m96_base << eff_exp[5:0];
            end else begin
                m96_shifted = 96'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            end
        end else begin
            abs_sh = ((-eff_exp) > 11'sd96) ? 7'd96 : (-eff_exp[6:0]);
            m96_shifted = m96_base >> abs_sh;
            // Sticky: build mask (1 << abs_sh) - 1, AND with m96_base.
            if (abs_sh >= 7'd96) begin
                lo_mask = {96{1'b1}};
            end else begin
                lo_mask = (96'd1 << abs_sh) - 96'd1;
            end
            sticky_far = |(m96_base & lo_mask);
        end
    end

    // ----- extract integer and rounding bits -----------------------------
    logic [48:0] integer_part;     // bits [95:47]
    logic        g_bit, r_bit;
    logic        s_bit;
    logic [44:0] sticky_bits;

    assign integer_part = m96_shifted[95:47];
    assign g_bit        = m96_shifted[46];
    assign r_bit        = m96_shifted[45];
    assign sticky_bits  = m96_shifted[44:0];
    assign s_bit        = (|sticky_bits) | sticky_far;

    // ----- round decision -------------------------------------------------
    logic round_up;
    logic lsb;
    assign lsb = integer_part[0];

    always_comb begin
        unique case (rm_i)
            3'b000, 3'b111: // RNE (DYN treated as RNE)
                round_up = g_bit & (r_bit | s_bit | lsb);
            3'b001:         // RTZ
                round_up = 1'b0;
            3'b010:         // RDN (toward -inf)
                round_up = sign_a & (g_bit | r_bit | s_bit);
            3'b011:         // RUP (toward +inf)
                round_up = ~sign_a & (g_bit | r_bit | s_bit);
            3'b100:         // RMM (round to nearest, ties to max magnitude)
                round_up = g_bit;
            default:
                round_up = g_bit & (r_bit | s_bit | lsb);  // fallback RNE
        endcase
    end

    logic [49:0] integer_rounded; // 50 bits to catch rounding carry
    assign integer_rounded = {1'b0, integer_part} + {49'd0, round_up};

    // ----- overflow / saturation checks ----------------------------------
    // For signed int32:
    //   Positive: magnitude must fit in 31 bits (0 .. 2^31-1).
    //   Negative: magnitude must fit in 31 bits, OR be exactly 2^31 with no fraction (→ -2^31).
    // For unsigned int32:
    //   Any negative non-zero rounded value → 0.
    //   Magnitude must fit in 32 bits (0 .. 2^32-1).
    logic mag_gt_2to31;         // integer_rounded >= 2^31
    logic mag_eq_2to31;         // integer_rounded == 2^31  (exact, no fraction, implies round_up==0)
    logic mag_gt_2to32;         // integer_rounded >= 2^32

    assign mag_gt_2to31 = (integer_rounded[49:31] != 19'd0);
    assign mag_eq_2to31 = (integer_rounded == 50'h0_0000_8000_0000);
    assign mag_gt_2to32 = (integer_rounded[49:32] != 18'd0);

    // ----- assemble result -----------------------------------------------
    logic [31:0] signed_result;
    logic [31:0] unsigned_result;
    logic [31:0] magnitude_32;

    assign magnitude_32 = integer_rounded[31:0];

    // SIGNED
    always_comb begin
        if (is_nan | (is_inf & ~sign_a)) begin
            signed_result = 32'h7FFF_FFFF;
        end else if (is_inf & sign_a) begin
            signed_result = 32'h8000_0000;
        end else if (is_zero) begin
            signed_result = 32'h0000_0000;
        end else if (~sign_a) begin
            // positive
            if (mag_gt_2to31) signed_result = 32'h7FFF_FFFF;
            else              signed_result = magnitude_32;
        end else begin
            // negative: need two's complement of magnitude; saturate.
            if (mag_eq_2to31) signed_result = 32'h8000_0000; // exactly -2^31 representable
            else if (mag_gt_2to31) signed_result = 32'h8000_0000;
            else signed_result = -magnitude_32;
        end
    end

    // UNSIGNED
    always_comb begin
        if (is_nan | (is_inf & ~sign_a)) begin
            unsigned_result = 32'hFFFF_FFFF;
        end else if (is_inf & sign_a) begin
            unsigned_result = 32'h0000_0000;
        end else if (is_zero) begin
            unsigned_result = 32'h0000_0000;
        end else if (sign_a) begin
            // any negative finite rounds to 0 for unsigned (saturate)
            unsigned_result = 32'h0000_0000;
        end else begin
            // positive
            if (mag_gt_2to32) unsigned_result = 32'hFFFF_FFFF;
            else              unsigned_result = magnitude_32;
        end
    end

    assign result_o = is_unsigned_i ? unsigned_result : signed_result;

endmodule
