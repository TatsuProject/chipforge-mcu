// ============================================================================
//  ROB-for-Trace (Software-style, no div decoding, Verilator-safe) + Logging
// ----------------------------------------------------------------------------
//  PURPOSE:
//    Pure procedural ROB for tracer ordering with robust DIV flush handling.
//    - WB → enqueue completed
//    - DIV busy → ensure placeholder exists (once), refresh operands
//    - DIV flush → software-complete (and if not found, create+complete)
//    - Retire head in order
//  LOGGING:
//    Writes step-by-step events to 'rob.log' (file name configurable).
// ----------------------------------------------------------------------------
//  Notes:
//    - Testbench/simulation helper (not synthesizable)
//    - Uses blocking assignments and tasks; runs after each posedge clk
// ============================================================================

`ifdef tracer 
module rob #(
    parameter int    ROB_SIZE  = 128,
    parameter string LOG_FILE  = "rob.log",
    parameter bit    LOG_EN    = 1
)(
    input  logic        clk,
    input  logic        reset_n,

    // Writeback → enqueue (ready)
    input  logic        reg_write_wb,
    input  logic [4:0]  rd_wb,
    input  logic [31:0] result_wb,
    input  logic [31:0] pc_wb,
    input  logic [31:0] inst_wb,
    input  logic [4:0]  rs1_wb, rs2_wb,
    input  logic [31:0] rs1_data_wb, rs2_data_wb,
    input  logic        inst_valid_wb,

    input logic         illegal_inst_id,

    // Divider interface
    input  logic        div_flush,
    input  logic        div_busy,
    input  logic [31:0] div_rs1, div_rs2,
    input  logic [31:0] div_inst_pc,
    input  logic [31:0] div_inst,

    // Tracer outputs
    output logic [31:0] rvfi_insn,
    output logic [4:0]  rvfi_rs1_addr, rvfi_rs2_addr, rvfi_rd_addr,
    output logic [31:0] rvfi_rs1_rdata, rvfi_rs2_rdata, rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic        rvfi_valid,


    output logic        illegal_inst_o
);

    // ---------------- Entry structure ----------------
    typedef struct {
        bit   valid;
        bit   completed;
        bit   is_div;
        int   rd, rs1, rs2;
        int   pc;
        int   inst;
        int   rs1_data, rs2_data;
        int   result;
    } entry_t;

    entry_t rob[ROB_SIZE];
    int head, tail, count;

    // Logging
    int                logfd;
    longint unsigned   cyc;
    bit program_finished;

    // =========================================================================
    //  UTILITY FUNCTIONS / TASKS
    // =========================================================================

    function automatic int div_swmodel(input int rs1, input int rs2, input int inst);
        int f3 = (inst >> 12) & 3'h7;
        int res;
        int signed s1, s2;  // properly declared signed 32-bit vars

        s1 = rs1;
        s2 = rs2;

        case (f3)
            3'b100: begin
                // Signed DIV
                if (s2 != 0)
                    if(s1 == 32'h8000_0000 && s2 == 32'hffffffff)
                        res = 32'h8000_0000; // overflow case
                    else
                    res = s1 / s2;
                else
                    res = 'hFFFF_FFFF;
                    log_line($sformatf("[SWMODEL] DIV  rs1=%08x (%0d) rs2=%08x (%0d) -> res=%08x (%0d)",
                                rs1, s1, rs2, s2, res, res));
            end

            3'b101: begin
                // Unsigned DIVU
                if (rs2 != 0)
                    res = (rs1 & 32'hFFFF_FFFF) / (rs2 & 32'hFFFF_FFFF);
                else
                    res = 'hFFFF_FFFF;
                log_line($sformatf("[SWMODEL] DIVU rs1=%08x rs2=%08x -> res=%08x", rs1, rs2, res));
            end

            3'b110: begin
                // Signed REM
                if (s2 != 0)
                    res = s1 % s2;
                else
                    res = s1;
                log_line($sformatf("[SWMODEL] REM  rs1=%08x (%0d) rs2=%08x (%0d) -> res=%08x (%0d)",
                                rs1, s1, rs2, s2, res, res));
            end

            3'b111: begin
                // Unsigned REMU
                if (rs2 != 0)
                    res = (rs1 & 32'hFFFF_FFFF) % (rs2 & 32'hFFFF_FFFF);
                else
                    res = rs1;
                log_line($sformatf("[SWMODEL] REMU rs1=%08x rs2=%08x -> res=%08x", rs1, rs2, res));
            end

            default: begin
                res = 0;
                log_line($sformatf("[SWMODEL] UNKNOWN f3=%03b inst=%08x", f3, inst));
            end
        endcase

        return res;
    endfunction



    task automatic reset_rob();
        head = 0;
        tail = 0;
        count = 0;
        rvfi_valid = 0;
        for (int i = 0; i < ROB_SIZE; i++)
            rob[i] = '{default:0};
        cyc = 0;
        if (LOG_EN) begin
            if (logfd) $fclose(logfd);
            logfd = $fopen(LOG_FILE, "w");
            if (logfd)
                $fdisplay(logfd, "[init] ROB reset, size=%0d", ROB_SIZE);
        end
    endtask

    // Logging helpers
    task automatic log_line(input string s);
        if (LOG_EN && logfd)
            $fdisplay(logfd, "[%0t|%0d] %s", $time, cyc, s);
    endtask

    task automatic log_enq(input entry_t e, input string src);
        log_line($sformatf("%s ENQ pc=%08x inst=%08x rd=%0d rs1=%0d rs2=%0d rs1d=%08x rs2d=%08x is_div=%0d tail=%0d cnt=%0d",
            src, e.pc, e.inst, e.rd, e.rs1, e.rs2, e.rs1_data, e.rs2_data, e.is_div, tail, count));
    endtask

    task automatic log_retire(input entry_t e);
        log_line($sformatf("RET  pc=%08x inst=%08x rd=%0d res=%08x head=%0d cnt=%0d",
            e.pc, e.inst, e.rd, e.result, head, count));
    endtask

    task automatic log_flush_hit(input int idx, input int res);
        log_line($sformatf("FLUSH pc=%08x inst=%08x -> SWRES=%08x (idx=%0d)",
            div_inst_pc, div_inst, res, idx));
    endtask

    task automatic log_flush_miss_create(input int res);
        log_line($sformatf("FLUSH-MISS pc=%08x inst=%08x -> create+complete SWRES=%08x",
            div_inst_pc, div_inst, res));
    endtask

    // Circular range iterator: walk youngest→oldest within current window
    // Returns the index of the *youngest* matching DIV entry by PC if found.
    function automatic bit find_youngest_div_by_pc(
        input int pc,
        output int idx_out
    );
        bit found = 0;
        int idx;
        // start from (tail-1) and walk backward until we pass head-1
        int scan = (tail == 0) ? (ROB_SIZE-1) : (tail-1);
        int stop = (head == 0) ? (ROB_SIZE-1) : (head-1);
        for (;;) begin
            if (rob[scan].valid && rob[scan].is_div && (rob[scan].pc == pc)) begin
                found   = 1;
                idx_out = scan;
                break;
            end
            if (scan == head) break;
            if (scan == 0) scan = ROB_SIZE-1; else scan--;
            if (scan == stop) break;
        end
        return found;
    endfunction

    // Enqueue helper
    task automatic enqueue(input entry_t e, input string src);
        if (count < ROB_SIZE) begin
            rob[tail] = e;
            tail = (tail + 1) % ROB_SIZE;
            count++;
            log_enq(e, src);
        end else begin
            log_line($sformatf("WARN: ENQ DROPPED (ROB full) src=%s pc=%08x inst=%08x", src, e.pc, e.inst));
        end
    endtask

    // -------------------------------------------------------------------------
    // Handle normal and DIV writeback
    // -------------------------------------------------------------------------
    task automatic write_back();
        if (inst_valid_wb && reg_write_wb) begin
            int idx;
            bit found = find_youngest_div_by_pc(pc_wb, idx);

            if (found && rob[idx].is_div && !rob[idx].completed) begin
                // ✅ Update existing DIV placeholder instead of enqueueing a new one
                rob[idx].completed  = 1;
                rob[idx].result     = result_wb;
                rob[idx].rs1_data   = rs1_data_wb;
                rob[idx].rs2_data   = rs2_data_wb;
                rob[idx].rd         = rd_wb;
                log_line($sformatf("DIV WB-UPDATE pc=%08x idx=%0d result=%08x", pc_wb, idx, result_wb));
            end else begin
                // Normal instruction → just enqueue
                entry_t e;
                e.valid      = 1;
                e.completed  = 1;
                e.is_div     = 0;
                e.pc         = pc_wb;
                e.inst       = inst_wb;
                e.rd         = rd_wb;
                e.rs1        = rs1_wb;
                e.rs2        = rs2_wb;
                e.rs1_data   = rs1_data_wb;
                e.rs2_data   = rs2_data_wb;
                e.result     = result_wb;
                enqueue(e, "WB ");
            end
        end
    endtask


    // -------------------------------------------------------------------------
    // Add/refresh DIV placeholder while divider is busy
    // -------------------------------------------------------------------------
    task automatic write_div();
        if (div_busy) begin
            // youngest match?
            int idx;
            bit found = find_youngest_div_by_pc(div_inst_pc, idx);
            if (!found || rob[idx].completed) begin
                entry_t e;
                e.valid      = 1;
                e.completed  = 0;
                e.is_div     = 1;
                e.pc         = div_inst_pc;
                e.inst       = div_inst;
                e.rd         = (div_inst >> 7)  & 31;
                e.rs1        = (div_inst >> 15) & 31;
                e.rs2        = (div_inst >> 20) & 31;
                e.rs1_data   = div_rs1;
                e.rs2_data   = div_rs2;
                e.result     = 0;
                enqueue(e, "DIV");
            end else begin
                // refresh live operands in case they changed
                rob[idx].rs1_data = div_rs1;
                rob[idx].rs2_data = div_rs2;
                log_line($sformatf("DIV REFRESH pc=%08x idx=%0d rs1d=%08x rs2d=%08x", div_inst_pc, idx, div_rs1, div_rs2));
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // When divider flushes, software-complete the entry (robust)
    //  • If found → compute & mark complete
    //  • If not found (timing/path issue) → create placeholder and complete
    // -------------------------------------------------------------------------
    task automatic complete_flushed_div();
        if (div_flush) begin
            int idx;
            bit found = find_youngest_div_by_pc(div_inst_pc, idx);
            int swres = div_swmodel(div_rs1, div_rs2, div_inst);
            if (found) begin
                rob[idx].result    = swres;
                rob[idx].completed = 1;
                log_flush_hit(idx, swres);
            end else begin
                // Create a synthetic completed entry so tracer stays in-order
                entry_t e;
                e.valid      = 1;
                e.completed  = 1;   // immediately complete
                e.is_div     = 1;
                e.pc         = div_inst_pc;
                e.inst       = div_inst;
                e.rd         = (div_inst >> 7)  & 31;
                e.rs1        = (div_inst >> 15) & 31;
                e.rs2        = (div_inst >> 20) & 31;
                e.rs1_data   = div_rs1;
                e.rs2_data   = div_rs2;
                e.result     = swres;
                log_flush_miss_create(swres);
                enqueue(e, "DFL");  // “DIV FLUSH create”
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Retire instructions in order (head-first)
    // -------------------------------------------------------------------------
    task automatic retire();
        rvfi_valid = 0;
        if (count > 0 && rob[head].valid && rob[head].completed) begin
            entry_t e = rob[head];

            if(e.pc == 32'h00000000) begin
                program_finished = 1'b1;
            end 
            rvfi_valid     = ~program_finished;
            rvfi_insn      = e.inst;
            rvfi_pc_rdata  = e.pc;
            rvfi_rd_addr   = e.rd;
            rvfi_rd_wdata  = e.result;
            rvfi_rs1_addr  = e.rs1;
            rvfi_rs2_addr  = e.rs2;
            rvfi_rs1_rdata = e.rs1_data;
            rvfi_rs2_rdata = e.rs2_data;

            log_retire(e);

            // pop head
            rob[head].valid = 0;
            head  = (head + 1) % ROB_SIZE;
            count = count - 1;
        end
    endtask

    // =========================================================================
    //  MAIN EXECUTION LOOP (software-style)
    // =========================================================================
    initial begin
        logfd = 0;
        reset_rob();
        wait (reset_n === 1);

        forever begin
            @(posedge clk);
            cyc++;
            #1; // software tick order

            if (!reset_n) begin
                reset_rob();
            end else begin
                write_back();
                write_div();
                complete_flushed_div();
                retire();
                if (LOG_EN && logfd) $fflush(logfd);
            end
        end
    end

    bit illegal_caught;
    initial begin 
        forever begin 
            @(posedge clk);
            if(illegal_inst_id) begin 
                illegal_caught = 1'b1;
                break;
            end
        end 
    end

    assign illegal_inst_o = illegal_caught & program_finished;
    // Optional close on finish
    final begin
        if (LOG_EN && logfd) begin
            $fdisplay(logfd, "[final] cycles=%0d head=%0d tail=%0d count=%0d", cyc, head, tail, count);
            $fclose(logfd);
        end
    end

endmodule
`endif