module div_unit #(parameter XLEN = 32)(
    input  logic             clk,
    input  logic             reset_n,
    input  logic             start_i,
    input  logic             flush_i,
    input  logic [2:0]       funct3_i,
    input  logic [XLEN-1:0]  rs1_i,
    input  logic [XLEN-1:0]  rs2_i,
    input  logic [4:0]       rd_i,
    input  logic [31:0]      pc_i,

    output logic             ready_o,
    output logic             busy_o,
    output logic [4:0]       rd_o,
    output logic [XLEN-1:0]  result_o,
    output logic [31:0]      pc_o
);

  //=======================
  // Internal State
  //=======================
  logic [2:0]       funct3_q;
  logic [4:0]       rd_q;
  logic [31:0]      pc_q;
  logic [XLEN-1:0]  rs1_q, rs2_q;
  logic             is_signed, is_rem;
  logic             a_neg, b_neg, res_neg;
  logic [XLEN-1:0]  a_abs, b_abs;
  logic [XLEN  :0]  a_abs_tmp, b_abs_tmp;
  logic [XLEN-1:0]  quotient, remainder;

  //=======================
  // Divider instantiation (unsigned)
  //=======================
  logic            div_start, div_busy, div_done, div_dbz;
  logic [XLEN-1:0] div_quotient, div_remainder;
  logic [XLEN:0]   quotient_tmp, reminder_tmp;

  //=======================
  // Latch Inputs (only when idle)
  //=======================
  logic start_ff;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      funct3_q <= 3'b000;
      rd_q     <= 5'b0;
      pc_q     <= 'b0;
      rs1_q    <= 0;
      rs2_q    <= 0;
    end else if (~div_busy & ~start_ff & start_i) begin
      funct3_q <= funct3_i;
      rd_q     <= rd_i;
      pc_q     <= pc_i;
      rs1_q    <= rs1_i;
      rs2_q    <= rs2_i;
   end
  end

  always_ff @(posedge clk, negedge reset_n) begin
    if(~reset_n) start_ff <= 0;
    else start_ff <= start_i & ~busy_o;
  end

  assign rd_o = rd_q;
  assign pc_o = pc_q;

  //=======================
  // Sign + ABS conversion
  //=======================
  assign is_signed = (funct3_q == 3'b100) | (funct3_q == 3'b110); // DIV, REM
  assign is_rem    = (funct3_q == 3'b110) | (funct3_q == 3'b111); // REM, REMU
  assign a_neg     = is_signed & rs1_q[XLEN-1];
  assign b_neg     = is_signed & rs2_q[XLEN-1];
  assign res_neg   = is_rem ? a_neg : (a_neg ^ b_neg);

  assign a_abs_tmp = a_neg ? -rs1_q : {1'b0, rs1_q};
  assign b_abs_tmp = b_neg ? -rs2_q : {1'b0, rs2_q};

  assign a_abs = a_abs_tmp[XLEN-1:0];
  assign b_abs = b_abs_tmp[XLEN-1:0];

  assign div_start = ~div_busy & start_ff;

  divu_radix4 #(.WIDTH(XLEN)) u_divu (
    .clk    (clk),
    .rst    (~reset_n),
    .clear  (flush_i),
    .start  (div_start),
    .busy   (div_busy),
    .done   (div_done),
    .dbz    (div_dbz),
    .a      (a_abs),
    .b      (b_abs),
    .val    (div_quotient),
    .rem_   (div_remainder)
  );

  //=======================
  // Sign Fix on Output
  //=======================
  assign quotient_tmp  = res_neg ? -div_quotient  : {1'b0, div_quotient};
  assign reminder_tmp  = a_neg   ? -div_remainder : {1'b0, div_remainder};
  assign quotient      = quotient_tmp[31:0];
  assign remainder     = reminder_tmp[31:0];

  assign result_o = div_dbz ? (is_rem ? rs1_q : 32'hFFFFFFFF) :
                    (is_rem ? remainder : quotient);

  assign busy_o = div_busy | div_start;

  // Edge detection for ready_o - cleaner timing
  logic div_busy_ff;
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) div_busy_ff <= 1'b0;
    else div_busy_ff <= busy_o;
  end
  assign ready_o = div_busy_ff & ~div_busy;

endmodule

// Radix-4 unsigned divider - 2 bits per cycle with cleaner logic
module divu_radix4 #(parameter WIDTH = 32) (
    input  wire logic             clk,
    input  wire logic             rst,
    input  wire logic             clear,
    input  wire logic             start,
    output      logic             busy,
    output      logic             done,
    output      logic             dbz,
    input  wire logic [WIDTH-1:0] a,
    input  wire logic [WIDTH-1:0] b,
    output      logic [WIDTH-1:0] val,
    output      logic [WIDTH-1:0] rem_
);

    localparam STEPS     = WIDTH / 2;
    localparam STEP_BITS = $clog2(STEPS);

    // State registers
    logic                  busy_q, done_q, dbz_q;
    logic [WIDTH-1:0]      dividend_q, divisor_q, quotient_q;
    logic [WIDTH+1:0]      rem_q;
    logic [STEP_BITS-1:0]  iter_q;

    // Outputs
    assign busy = busy_q;
    assign done = done_q;
    assign dbz  = dbz_q;
    assign val  = quotient_q;
    assign rem_ = rem_q[WIDTH-1:0];

    // Radix-4 step computation
    logic [WIDTH+1:0] rem_shift, d1, d2, d3, rem_next;
    logic [WIDTH-1:0] quotient_next, dividend_next;
    logic [1:0]       q_digit;

    always_comb begin
        // Shift remainder and bring in 2 MSBs of dividend
        rem_shift = {rem_q[WIDTH-1:0], dividend_q[WIDTH-1:WIDTH-2]};

        // Multiples of divisor
        d1 = {2'b00, divisor_q};
        d2 = d1 << 1;
        d3 = d1 + d2;

        // Quotient digit selection
        if (rem_shift >= d3) begin
            q_digit  = 2'b11;
            rem_next = rem_shift - d3;
        end else if (rem_shift >= d2) begin
            q_digit  = 2'b10;
            rem_next = rem_shift - d2;
        end else if (rem_shift >= d1) begin
            q_digit  = 2'b01;
            rem_next = rem_shift - d1;
        end else begin
            q_digit  = 2'b00;
            rem_next = rem_shift;
        end

        quotient_next = {quotient_q[WIDTH-3:0], q_digit};
        dividend_next = {dividend_q[WIDTH-3:0], 2'b00};
    end

    // State machine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_q     <= 1'b0;
            done_q     <= 1'b0;
            dbz_q      <= 1'b0;
            dividend_q <= '0;
            divisor_q  <= '0;
            quotient_q <= '0;
            rem_q      <= '0;
            iter_q     <= '0;
        end else if (clear) begin
            busy_q     <= 1'b0;
            done_q     <= 1'b0;
            dbz_q      <= 1'b0;
            dividend_q <= '0;
            divisor_q  <= '0;
            quotient_q <= '0;
            rem_q      <= '0;
            iter_q     <= '0;
        end else if (start && !busy_q) begin
            done_q <= 1'b0;
            if (b == '0) begin
                dbz_q  <= 1'b1;
                busy_q <= 1'b0;
            end else if (a == '0) begin
                dbz_q      <= 1'b0;
                busy_q     <= 1'b0;
                quotient_q <= '0;
                rem_q      <= '0;
            end else begin
                busy_q     <= 1'b1;
                dbz_q      <= 1'b0;
                dividend_q <= a;
                divisor_q  <= b;
                quotient_q <= '0;
                rem_q      <= '0;
                iter_q     <= '0;
            end
        end else if (busy_q) begin
            if (iter_q == STEPS-1) begin
                busy_q     <= 1'b0;
                done_q     <= 1'b1;
                quotient_q <= quotient_next;
                rem_q      <= rem_next;
            end else begin
                iter_q     <= iter_q + 1'b1;
                quotient_q <= quotient_next;
                rem_q      <= rem_next;
                dividend_q <= dividend_next;
            end
        end else begin
            done_q <= 1'b0;
        end
    end

endmodule
