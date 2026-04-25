// fpu_cvt_i2f.sv — FCVT.S.W / FCVT.S.WU
// Convert 32-bit signed/unsigned integer to IEEE-754 single-precision float.
// Combinational. Handles RNE/RTZ/RDN/RUP/RMM; DYN (111) → RNE.
//
// Notes:
//   * Signed -2^31 (0x80000000): magnitude is exactly 2^31 — converts to
//     0xCF000000 without rounding loss.
//   * Unsigned 0xFFFFFFFF: nearest float is 2^32 = 0x4F800000 (carry from
//     rounding pushes exp from 158 to 159).

module fpu_cvt_i2f (
    input  logic        is_unsigned_i,   // 0 = FCVT.S.W, 1 = FCVT.S.WU
    input  logic [2:0]  rm_i,
    input  logic [31:0] rs1_i,
    output logic [31:0] result_o
);

    // ----- sign + magnitude ----------------------------------------------
    logic        sign_out;
    logic [31:0] mag32;

    assign sign_out = is_unsigned_i ? 1'b0 : rs1_i[31];
    // Magnitude: for unsigned or non-negative signed, use rs1 directly.
    // For negative signed, two's-complement negate.
    assign mag32    = (is_unsigned_i | ~rs1_i[31]) ? rs1_i : (~rs1_i + 32'd1);

    logic is_zero_mag;
    assign is_zero_mag = (mag32 == 32'd0);

    // ----- leading-zero count / MSB position -----------------------------
    // Priority encoder: highest set bit, 0..31.
    logic [4:0] msb_pos;
    always_comb begin
        msb_pos = 5'd0;
        if      (mag32[31]) msb_pos = 5'd31;
        else if (mag32[30]) msb_pos = 5'd30;
        else if (mag32[29]) msb_pos = 5'd29;
        else if (mag32[28]) msb_pos = 5'd28;
        else if (mag32[27]) msb_pos = 5'd27;
        else if (mag32[26]) msb_pos = 5'd26;
        else if (mag32[25]) msb_pos = 5'd25;
        else if (mag32[24]) msb_pos = 5'd24;
        else if (mag32[23]) msb_pos = 5'd23;
        else if (mag32[22]) msb_pos = 5'd22;
        else if (mag32[21]) msb_pos = 5'd21;
        else if (mag32[20]) msb_pos = 5'd20;
        else if (mag32[19]) msb_pos = 5'd19;
        else if (mag32[18]) msb_pos = 5'd18;
        else if (mag32[17]) msb_pos = 5'd17;
        else if (mag32[16]) msb_pos = 5'd16;
        else if (mag32[15]) msb_pos = 5'd15;
        else if (mag32[14]) msb_pos = 5'd14;
        else if (mag32[13]) msb_pos = 5'd13;
        else if (mag32[12]) msb_pos = 5'd12;
        else if (mag32[11]) msb_pos = 5'd11;
        else if (mag32[10]) msb_pos = 5'd10;
        else if (mag32[9])  msb_pos = 5'd9;
        else if (mag32[8])  msb_pos = 5'd8;
        else if (mag32[7])  msb_pos = 5'd7;
        else if (mag32[6])  msb_pos = 5'd6;
        else if (mag32[5])  msb_pos = 5'd5;
        else if (mag32[4])  msb_pos = 5'd4;
        else if (mag32[3])  msb_pos = 5'd3;
        else if (mag32[2])  msb_pos = 5'd2;
        else if (mag32[1])  msb_pos = 5'd1;
        else if (mag32[0])  msb_pos = 5'd0;
        else                msb_pos = 5'd0; // mag==0, caught separately
    end

    // ----- normalise: shift MSB to bit 31 --------------------------------
    logic [4:0]  shift_lo;
    logic [31:0] mag_norm;
    assign shift_lo = 5'd31 - msb_pos;
    assign mag_norm = mag32 << shift_lo;

    // ----- extract mantissa + G/R/S --------------------------------------
    // mag_norm[31]    = implicit 1
    // mag_norm[30:8]  = mantissa[22:0]       (23 bits)
    // mag_norm[7]     = guard
    // mag_norm[6]     = round
    // mag_norm[5:0]   = sticky source
    logic        g_bit, r_bit, s_bit, lsb;
    assign g_bit = mag_norm[7];
    assign r_bit = mag_norm[6];
    assign s_bit = |mag_norm[5:0];
    assign lsb   = mag_norm[8];

    logic round_up;
    always_comb begin
        unique case (rm_i)
            3'b000, 3'b111: round_up = g_bit & (r_bit | s_bit | lsb);
            3'b001:         round_up = 1'b0;
            3'b010:         round_up = sign_out  & (g_bit | r_bit | s_bit);
            3'b011:         round_up = ~sign_out & (g_bit | r_bit | s_bit);
            3'b100:         round_up = g_bit;
            default:        round_up = g_bit & (r_bit | s_bit | lsb);
        endcase
    end

    // ----- apply rounding — watch for carry out of the mantissa ----------
    // {1'b0, mag_norm[31:8]} is 25 bits; adding round_up yields up to 25 bits.
    logic [24:0] mant_r25;
    assign mant_r25 = {1'b0, mag_norm[31:8]} + {24'd0, round_up};

    // ----- pack -----------------------------------------------------------
    logic [7:0]  biased_exp;
    logic [22:0] mant_out;

    always_comb begin
        if (mant_r25[24]) begin
            // Rounding carried into a new integer bit — bump exponent.
            biased_exp = {3'b000, msb_pos} + 8'd128;  // = msb_pos + 127 + 1
            mant_out   = 23'd0;
        end else begin
            biased_exp = {3'b000, msb_pos} + 8'd127;
            mant_out   = mant_r25[22:0];
        end
    end

    assign result_o = is_zero_mag ? 32'h0000_0000
                                  : {sign_out, biased_exp, mant_out};

endmodule
