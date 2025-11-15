module core_dbg_fsm (
    input logic clk_i, 
    input logic reset_i,
    input logic ebreak_inst_mem,
    input logic dbg_resumereq_i, 
    input logic dbg_haltreq_i,
    input logic trap,
    input logic trap_ret,
    input logic inst_valid_wb,

    output logic core_resumeack_o,
    output logic core_running_o,
    output logic core_halted_o,
    output logic dbg_ret,
    output logic dont_trap,

    input logic [31:0] cinst_pc,
    input logic [31:0] next_pc_if1,
 
    output logic [31:0] dcsr_o, 
    output logic [31:0] dpc_o,

    // abstract register access interface 
    input  logic        dbg_ar_en,
    input  logic        dbg_ar_wr,
    input  logic [15:0] dbg_ar_ad,
    input  logic [31:0] dbg_ar_do
);

    logic [31:0] dpc, dcsr;
    dcause_e debug_cause;
    logic debug_step;
    logic stepie;

    enum logic [1:0] {RUNNING, HALTED, RESUME} pstate, nstate;
    always_ff@(posedge clk_i or posedge reset_i)
    begin
        if(reset_i)
            pstate <= RUNNING;
        else
            pstate <= nstate;
    end
    always_comb
    begin
        case(pstate)
            RUNNING: nstate = ((ebreak_inst_mem && dcsr[15]) || ((debug_step) && (trap | trap_ret | inst_valid_wb)) || dbg_haltreq_i)? HALTED : RUNNING;
            HALTED:	nstate = dbg_resumereq_i? RESUME : HALTED;
            RESUME: nstate = dbg_resumereq_i? RESUME : RUNNING;
            default: nstate = RUNNING;
        endcase
    end
    assign core_resumeack_o = (pstate == RESUME);
    assign core_running_o = (pstate == RUNNING);
    assign core_halted_o = ((pstate == HALTED) || (pstate == RESUME));

    //dcsr
    always_ff@(posedge clk_i or posedge reset_i)
    begin
        if(reset_i)
            debug_cause <= NO_DBG_CAUSE;
        else if(core_running_o && ebreak_inst_mem && dcsr[15])
            debug_cause <= DBG_EBREAK;
        else if(core_running_o && dbg_haltreq_i)
            debug_cause <= DBG_HALTREQ;
        else if(core_running_o && debug_step)
            debug_cause <= DBG_STEP;
    end
    assign debug_step = (dcsr[2]);
    assign stepie     = (dcsr[9]);

    always_ff@(posedge clk_i or posedge reset_i)
    begin
            if(reset_i)
                dcsr <= 0;
            else if(dbg_ar_en && dbg_ar_wr && (dbg_ar_ad == 16'h07b0))
                dcsr <= dbg_ar_do;//add dcsr
    end
    //dpc
    always_ff@(posedge clk_i or posedge reset_i)
    begin
        if(reset_i)
            dpc <= 0;
        else if(dbg_ar_en & dbg_ar_wr & (dbg_ar_ad == 16'h07b1)) 
            dpc <= dbg_ar_do;
        else if(core_running_o & ebreak_inst_mem & dcsr[15])
            dpc <= cinst_pc;
        else if(core_running_o & ((debug_step & inst_valid_wb) | dbg_haltreq_i))
            dpc <= cinst_pc;
        else if(core_running_o & (debug_step) & (trap | trap_ret) )
            dpc <= next_pc_if1; // TODO the earliest valid insturction won't always be in wb, *bcz of flush*
    end

    assign dcsr_o = {4'd4, 12'd0, dcsr[15], 1'b0, dcsr[13:9], debug_cause, 1'b0, dcsr[4], 1'b0, dcsr[2], 2'd3}; // no warning on variable read but set?
    assign dpc_o  = dpc;

    logic core_running_o_ff;
    always @(posedge clk_i, posedge reset_i ) begin
        if(reset_i)
            core_running_o_ff <= 'b1;
        else 
            core_running_o_ff <= core_running_o;
    end
    
    
    assign dbg_ret = ~core_running_o_ff & core_running_o;


    assign dont_trap =  (~core_running_o | dbg_ret | (((debug_step | dbg_haltreq_i) & inst_valid_wb) 
                        | (ebreak_inst_mem & dcsr[15])))
                        | (debug_step & ~stepie);




endmodule : core_dbg_fsm



/* 

import debug_pkg::*;

module core_dbg_fsm (
    input  logic         clk_i,
    input  logic         reset_i,

    // Debug requests and controls
    input  logic         ebreak_inst_mem,
    input  logic         dbg_resumereq_i,
    input  logic         dbg_haltreq_i,

    // Pipeline and trap signals
    input  logic         trap,
    input  logic         trap_ret,
    input  logic         inst_valid_wb,

    // Core status outputs
    output logic         core_resumeack_o,
    output logic         core_running_o,
    output logic         core_halted_o,
    output logic         dbg_ret,
    output logic         dont_trap,

    // PC interfaces
    input  logic [31:0]  current_pc_id,
    input  logic [31:0]  cinst_pc,
    input  logic [31:0]  next_pc_if1,
    input  logic         fetch_busy_i,

    output logic [31:0]  dcsr_o,
    output logic [31:0]  dpc_o,

    // Abstract register access interface
    input  logic         dbg_ar_en,
    input  logic         dbg_ar_wr,
    input  logic [15:0]  dbg_ar_ad,
    input  logic [31:0]  dbg_ar_do
);

    //------------------------------------------------------------------------
    // Local types & signals
    //------------------------------------------------------------------------
    typedef enum logic [1:0] {RUNNING, HALTED, RESUME} state_e;

    state_e        pstate, nstate;
    dcause_e       debug_cause;
    logic [31:0]   dcsr, dpc;

    // Single-step request bit from DCSR
    wire           debug_step = dcsr[2];

    // Composite signals
    wire           ebreak_en  = ebreak_inst_mem && dcsr[15];
    wire           step_req   = debug_step || dbg_haltreq_i;
    wire           step_event = step_req && (trap || trap_ret || inst_valid_wb);

    //------------------------------------------------------------------------
    // State Machine: core debug FSM
    //------------------------------------------------------------------------
    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i)
            pstate <= RUNNING;
        else
            pstate <= nstate;
    end

    always_comb begin
        unique case (pstate)
            RUNNING: nstate = (ebreak_en || step_event) ? HALTED : RUNNING;
            HALTED:  nstate = dbg_resumereq_i        ? RESUME : HALTED;
            RESUME:  nstate = dbg_resumereq_i        ? RESUME : RUNNING;
            default: nstate = RUNNING;
        endcase
    end

    assign core_resumeack_o = (pstate == RESUME);
    assign core_running_o   = (pstate == RUNNING);
    assign core_halted_o    = (pstate == HALTED) || (pstate == RESUME);

    //------------------------------------------------------------------------
    // Debug cause recorder
    //------------------------------------------------------------------------
    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i)
            debug_cause <= NO_DBG_CAUSE;
        else if (core_running_o && ebreak_en)
            debug_cause <= DBG_EBREAK;
        else if (core_running_o && dbg_haltreq_i)
            debug_cause <= DBG_HALTREQ;
        else if (core_running_o && debug_step)
            debug_cause <= DBG_STEP;
    end

    //------------------------------------------------------------------------
    // DCSR register write
    //------------------------------------------------------------------------
    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i)
            dcsr <= '0;
        else if (dbg_ar_en && dbg_ar_wr && dbg_ar_ad == 16'h07B0)
            dcsr <= dbg_ar_do;
    end

    //------------------------------------------------------------------------
    // DPC register write and update
    //------------------------------------------------------------------------
    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i)
            dpc <= '0;
        else if (dbg_ar_en && dbg_ar_wr && dbg_ar_ad == 16'h07B1)
            dpc <= dbg_ar_do;
        else if (core_running_o && ebreak_en)
            dpc <= cinst_pc;
        else if (core_running_o && step_req && inst_valid_wb)
            dpc <= cinst_pc;
        else if (core_running_o && step_req && (trap || trap_ret))
            dpc <= next_pc_if1; // earliest valid PC after flush
    end

    //------------------------------------------------------------------------
    // DCSR output formatting
    //------------------------------------------------------------------------
    // Format: {version[3:0], zeros[11:0], ebreak_m, rsrv1, prvm, stepie, rsrv2, ss, sb, explanation, union[1:0]}
    wire [3:0]  version = 4;
    wire [4:0]  cause   = debug_cause;
    wire [15:0] flags   = {
        dcsr[15],       // ebreak_m
        1'b0,           // reserved
        dcsr[13:9],     // mprven, etc.
        1'b0,           // reserved
        dcsr[4],        // stepie
        1'b0,           // reserved
        debug_step      // ss
    };

    assign dcsr_o = {version, 12'd0, flags, cause, 2'b11};
    assign dpc_o  = dpc;

    //------------------------------------------------------------------------
    // dbg_ret pulse generation
    //------------------------------------------------------------------------
    logic core_running_ff;
    always_ff @(posedge clk_i or posedge reset_i) begin
        if (reset_i)
            core_running_ff <= 1'b0;
        else
            core_running_ff <= core_running_o;
    end

    assign dbg_ret = core_running_o && ~core_running_ff;

    //------------------------------------------------------------------------
    // Trap suppression during debug
    //------------------------------------------------------------------------
    assign dont_trap = core_running_o && (
        (step_req && inst_valid_wb) ||
        ebreak_en
    );

endmodule : core_dbg_fsm


*/