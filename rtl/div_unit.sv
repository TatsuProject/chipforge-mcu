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
  logic [31:0]       pc_q;
  logic [XLEN-1:0]  rs1_q, rs2_q;
  logic             op_in_progress;
  logic             is_signed, is_rem;
  logic             a_neg, b_neg, res_neg;
  logic [XLEN-1:0]  a_abs, b_abs;
  logic [XLEN  :0]  a_abs_tmp, b_abs_tmp;
  logic [XLEN-1:0]  quotient, remainder;
  logic             start_div;

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

  always @(posedge clk, negedge reset_n) begin
    if(~reset_n) start_ff <= 0;
    else start_ff <= start_i & ~busy_o;
  end
  
  assign rd_o = rd_q;
  assign pc_o = pc_q;

  //=======================
  // Sign + ABS conversion
  //=======================
  assign is_signed = (funct3_q == 3'b100 || funct3_q == 3'b110); // DIV, REM
  assign is_rem    = (funct3_q == 3'b110 || funct3_q == 3'b111); // REM, REMU
  assign a_neg     = is_signed && rs1_q[XLEN-1];
  assign b_neg     = is_signed && rs2_q[XLEN-1];
  assign res_neg   = is_rem ? a_neg : (a_neg ^ b_neg);

  assign a_abs_tmp = a_neg ? -rs1_q : {1'b0,rs1_q};
  assign b_abs_tmp = b_neg ? -rs2_q : {1'b0,rs2_q};

  assign a_abs = a_abs_tmp[XLEN-1:0];
  assign b_abs = b_abs_tmp[XLEN-1:0];


  assign div_start = (!div_busy & start_ff);

  divu_int #(.WIDTH(XLEN)) u_divu (
    .clk    (clk),
    .rst    (~reset_n), // logic on the reset? is fine? 
    .clear  (flush_i),
    .start  (div_start),
    .busy   (div_busy),
    .done   (div_done),
    .dbz    (div_dbz),
    .a      (a_abs),
    .b      (b_abs),
    .val    (div_quotient),
    .rem_    (div_remainder)
  );

  //=======================
  // Sign Fix on Output
  //=======================

  assign quotient_tmp  = res_neg ? -div_quotient :  {1'b0,div_quotient };
  assign reminder_tmp  = a_neg   ? -div_remainder : {1'b0,div_remainder};
  assign quotient      = quotient_tmp[31:0];
  assign remainder     = reminder_tmp[31:0];

  assign result_o  = div_dbz ? (is_rem ? rs1_q : 32'hFFFFFFFF) :
                     (is_rem ? remainder : quotient);

//   assign ready_o   = div_done;

  assign busy_o    = div_busy | div_start;
  logic div_busy_ff;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) div_busy_ff <= 1'b0;
    else div_busy_ff <= busy_o;
  end

  assign ready_o = div_busy_ff & ~div_busy;
endmodule

module divu_int #(parameter WIDTH = 32) ( // width of numbers in bits
    input  wire logic             clk,      // clock
    input  wire logic             rst,      // async reset (active high)
    input  wire logic             clear,    // synchronous clear
    input  wire logic             start,    // start calculation (pulse)
    output      logic             busy,     // calculation in progress
    output      logic             done,     // calculation is complete (high for one tick)
    output      logic             dbz,      // divide by zero
    input  wire logic [WIDTH-1:0] a,        // dividend (numerator)
    input  wire logic [WIDTH-1:0] b,        // divisor (denominator)
    output      logic [WIDTH-1:0] val,      // quotient
    output      logic [WIDTH-1:0] rem_      // remainder
);

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam int STEPS     = WIDTH / 2;          // radix-4 → 2 bits/step
    localparam int STEP_BITS = $clog2(STEPS);

    // ----------------------------------------------------------------
    // State registers
    // ----------------------------------------------------------------
    logic                  busy_q,   busy_d;
    logic                  done_q,   done_d;
    logic                  dbz_q,    dbz_d;

    logic [WIDTH-1:0]      dividend_q, dividend_d; // shifting dividend
    logic [WIDTH-1:0]      divisor_q,  divisor_d;  // latched divisor
    logic [WIDTH-1:0]      quotient_q, quotient_d; // building quotient
    logic [WIDTH+1:0]      rem_q,      rem_d;      // remainder (WIDTH+2 bits)
    logic [STEP_BITS-1:0]  iter_q,     iter_d;     // step counter

    // Outputs from regs
    assign busy = busy_q;
    assign done = done_q;
    assign dbz  = dbz_q;
    assign val  = quotient_q;
    assign rem_ = rem_q[WIDTH-1:0];

    // ----------------------------------------------------------------
    // Combinational next-state (one radix-4 step when busy_q=1)
    // ----------------------------------------------------------------
    always_comb begin
        // Default: hold state
        busy_d     = busy_q;
        done_d     = 1'b0;         // "done" is a pulse
        dbz_d      = dbz_q;
        dividend_d = dividend_q;
        divisor_d  = divisor_q;
        quotient_d = quotient_q;
        rem_d      = rem_q;
        iter_d     = iter_q;

        // -------- Highest priority: clear (flush) --------
        if (clear) begin
            busy_d     = 1'b0;
            done_d     = 1'b0;
            dbz_d      = 1'b0;
            dividend_d = '0;
            divisor_d  = '0;
            quotient_d = '0;
            rem_d      = '0;
            iter_d     = '0;

        // -------- Start new division (only when idle) --------
        end else if (start && !busy_q) begin
            done_d <= 1'b0;

            if (b == '0) begin
                // divide-by-zero
                busy_d     = 1'b0;
                dbz_d      = 1'b1;
                quotient_d = '0;
                rem_d      = {2'b00, a};  // remainder = dividend (wrapper just looks at dbz)
            end else if (a == '0) begin
                // 0 / b = 0
                busy_d     = 1'b0;
                dbz_d      = 1'b0;
                quotient_d = '0;
                rem_d      = '0;
            end else begin
                // normal start
                busy_d     = 1'b1;
                dbz_d      = 1'b0;
                dividend_d = a;
                divisor_d  = b;
                quotient_d = '0;
                rem_d      = '0;
                iter_d     = '0;
            end

        // -------- Radix-4 restoring step while busy --------
        end else if (busy_q) begin
            // Local step signals (no extra flops)
            logic [WIDTH+1:0] rem_shift;
            logic [WIDTH+1:0] d1, d2, d3;
            logic [WIDTH+1:0] rem_next;
            logic [WIDTH-1:0] quotient_next;
            logic [WIDTH-1:0] dividend_next;
            logic [1:0]       q_digit;

            // Shift remainder by 2 and bring in next 2 MSBs of dividend
            rem_shift = {rem_q[WIDTH-1:0], dividend_q[WIDTH-1:WIDTH-2]};

            d1 = {2'b00, divisor_q};    // 1*b
            d2 = d1 << 1;               // 2*b
            d3 = d2 + d1;               // 3*b

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

            quotient_next = (quotient_q << 2) | q_digit;
            dividend_next = (dividend_q << 2);

            // Last step?
            if (iter_q == STEPS-1) begin
                busy_d     = 1'b0;
                done_d     = 1'b1;
                quotient_d = quotient_next;
                rem_d      = rem_next;
                // iter_d can stay; unused when !busy
            end else begin
                iter_d     = iter_q + 1'b1;
                quotient_d = quotient_next;
                rem_d      = rem_next;
                dividend_d = dividend_next;
                done_d     = 1'b0;
            end
        end
        // else: idle, keep state; done_d already 0
    end

    // ----------------------------------------------------------------
    // Sequential state update
    // ----------------------------------------------------------------
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
        end else begin
            busy_q     <= busy_d;
            done_q     <= done_d;
            dbz_q      <= dbz_d;
            dividend_q <= dividend_d;
            divisor_q  <= divisor_d;
            quotient_q <= quotient_d;
            rem_q      <= rem_d;
            iter_q     <= iter_d;
        end
    end

endmodule
