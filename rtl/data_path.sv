


module data_path #(
    parameter DMEM_DEPTH = 1024, 
    parameter IMEM_DEPTH = 1024
)(
    input logic clk, 
    input logic reset_n,

    // outputs to controller
    output logic [6:0] opcode_id,
    // additional signal has been added
    output logic [6:0] fun7_exe,
    output logic [2:0] fun3_exe, fun3_mem,
    output logic [6:0] fun7_id,           // F-extension decode (Challenge 0013)
    output logic [2:0] fun3_id,
    output logic zero_mem,
    output logic [1:0] alu_op_exe,
    output logic jump_mem,
    output logic branch_mem,

    // control signals from the controller
    input logic reg_write_id,
    input logic mem_write_id,
    input logic mem_to_reg_id,
    input logic branch_id,
    input logic alu_src_id,
    input logic jump_id,
    input logic lui_id,
    input logic auipc_id,
    input logic jal_id,
    input logic r_type_id,
    input logic [1:0] alu_op_id,
    input logic sys_inst_id,
    input logic is_atomic_id,
    input logic illegal_inst_id,

    // F-extension decode inputs (Challenge 0013)
    input logic       is_fp_id,
    input logic       fp_reg_write_id,
    input logic       fp_wb_to_int_id,
    input logic       fp_uses_rs1_id,
    input logic       fp_uses_rs2_id,
    input logic [4:0] fpu_op_id,
    input logic [2:0] fp_rm_id,
    // modified
    input logic [9:0] alu_ctrl_exe,
    // additional signal has been added for AES
    input logic pc_sel_mem,


    // forwarding unit stuff
    output wire [4:0] rs1_id,
    output wire [4:0] rs2_id,
    output wire [4:0] rs1_exe,
    output wire [4:0] rs2_exe,
    output wire [4:0] rs2_mem,
    output wire [4:0] rd_mem,
    output wire [4:0] rd_wb,
    output wire reg_write_mem,
    output wire reg_write_wb,

    input  wire forward_rd1_id,
    input  wire forward_rd2_id,
    input  wire [1:0] forward_rd1_exe,
    input  wire [1:0] forward_rd2_exe,
    input  wire forward_rd2_mem,


    // hazard handler data required from the data path
    output  wire mem_to_reg_exe,
    output  wire [4:0] rd_exe,

    // signals to control the flow of the pipeline
    input logic if_id_reg_clr, 
    input logic id_exe_reg_clr,
    input logic exe_mem_reg_clr,
    input logic mem_wb_reg_clr,

    input logic if_id_reg_en, 
    input logic id_exe_reg_en,
    input logic exe_mem_reg_en,
    input logic mem_wb_reg_en,
    input logic pc_reg_en,


    // memory bus 
    output logic [31:0] mem_addr_mem, 
    output logic [31:0] mem_wdata_mem, 
    output logic [3:0] mem_wstrb_mem,
    input logic [31:0] mem_rdata_mem,
    output logic mem_write_mem,
    output logic mem_to_reg_mem,
    input logic mem_ack_mem,
    input logic mem_err_mem,

    // to pipeline controller from memory bus
    output logic atomic_unit_stall,
    output logic is_atomic_mem,
    output logic is_mul_exe,
    output logic div_busy,

    // F extension EX/MEM/WB-stage hazard exports (4-stage FP pipeline)
    output logic is_fp_multicycle_exe,
    output logic fp_reg_write_exe,
    output logic fp_wb_to_int_exe,
    output logic is_fp_multicycle_mem,
    output logic fp_reg_write_mem,
    output logic fp_wb_to_int_mem,
    output logic is_fp_multicycle_wb,
    output logic fp_reg_write_wb,
    output logic fp_wb_to_int_wb,

    // inst mem access
    output logic [31:0] current_pc_if,
    input logic [31:0] inst_if,

    // timer interrupt from the clint
    input logic timer_irq,
    input logic external_irq,

    output logic trap,
    output logic trap_ret,

    output logic [31:0] next_pc_if1,
    output logic        ebreak_inst_mem,

    input  logic        core_halted,
    input  logic        dbg_ar_en,
    input  logic        dbg_ar_wr,
    input  logic [15:0] dbg_ar_ad,
    input  logic [31:0] dbg_ar_do,

    output logic [31:0] dbg_gpr_rdata,
    output logic [31:0] dbg_csr_result,


    output logic inst_valid_wb,
    output logic [31:0] cinst_pc,
    input  logic [31:0] dpc,
    input  logic dbg_ret,
    input  logic dont_trap,
    input  logic core_running,
    input  logic inst_fetch_stall,
    output logic inst_fetch_stall_ff,
    input  logic load_hazard,
    input  logic mul_hazard,
    input  logic fp_hazard

`ifdef tracer
    ,
    output logic [31:0] rvfi_insn,
    output logic [4:0]  rvfi_rs1_addr,
    output logic [4:0]  rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0]  rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [31:0] rvfi_mem_wdata,
    output logic [31:0] rvfi_mem_rdata,
    output logic        rvfi_valid
`endif
);
    
    // 2 bits are being added for selection between SHA instructions 
    logic [4:0]  func5_exe;
    logic [4:0]  sha_sel_exe;
    logic [6:0]  opcode_exe;
    logic        no_jump;
    logic [31:0] current_pc_id;
    logic        prv_fetch_busy;
    logic [31:0] inst_id, inst_exe, inst_mem;
    logic [31:0] current_pc_exe, current_pc_mem, current_pc_mem_;
    logic [31:0] reg_rdata1_id, reg_rdata1_exe, reg_rdata1_mem;
    logic [31:0] reg_rdata2_id, reg_rdata2_exe;
    logic [31:0] reg_wdata_wb;

    // ---- F extension (Challenge 0013) signal declarations ----
    // ID stage — decode signals (is_fp_id..fp_rm_id) are module inputs now.
    logic [31:0] fp_rdata1_raw, fp_rdata2_raw;          // raw fp_reg_file outputs
    logic [31:0] fp_reg_rdata1_id, fp_reg_rdata2_id;    // after WB-forward mux
    logic        forward_fp_rd1_id, forward_fp_rd2_id;
    // EXE stage
    logic [31:0] fp_reg_rdata1_exe, fp_reg_rdata2_exe;
    logic [31:0] fp_rs1_frw_exe, fp_rs2_frw_exe;   // after EX-stage FP forwarding
    logic        is_fp_exe;
    logic        fp_uses_rs1_exe, fp_uses_rs2_exe;
    logic [4:0]  fpu_op_exe;
    logic [2:0]  fp_rm_exe;
    logic [1:0]  forward_fp_rd1_exe, forward_fp_rd2_exe;
    // MEM stage
    // is_fp_multicycle_mem, fp_reg_write_mem, fp_wb_to_int_mem are module
    // outputs (declared in port list). is_fp_mem remains a local helper.
    logic        is_fp_mem;
    // WB / WB+1 stage — fpu_unit.result_o is flopped internally at WB+1 timing
    // (4-stage FPU). fp_reg_file.wdata comes from the WB+1 tail register so the
    // write fires one cycle after the instruction is in WB. fpu_result_wb1 is
    // just a readable alias for fpu_unit.result_o.
    // fp_reg_write_wb / fp_wb_to_int_wb / is_fp_multicycle_wb are module
    // outputs declared in the port list (exported to hazard_controller).
    logic [31:0] fpu_result_wb1;
    logic [4:0]  rd_wb1;
    logic        fp_reg_write_wb1, fp_wb_to_int_wb1, is_fp_multicycle_wb1;

    logic [31:0] imm_id,imm_exe, imm_mem, imm_wb;
    logic [31:0] pc_plus_4_if1, pc_plus_4_id, pc_plus_4_exe, pc_plus_4_mem,pc_plus_4_wb;
    logic [31:0] pc_minus_2_if1;
    logic [31:0] corrected_pc_if1, corrected_pc_if2;
    logic [31:0] pc_jump_exe, pc_jump_mem;
    logic [31:0] non_mul_result_wb;
    logic [31:0] tvec, trap_base_pc, trap_pc,  trap_return_pc;
    logic [32:0] trap_pc_tmp;
    logic [5:0]  trap_cause;
    logic        trap_ret_id, trap_ret_exe, trap_ret_mem;


    logic        reg_write_id_, reg_write_exe;
    logic        alu_src_exe;
    logic        mem_write_exe;
    logic        branch_exe;
    logic        jump_exe, jump_wb;
    logic        lui_exe, lui_mem, lui_wb;
    logic        auipc_exe, auipc_mem, auipc_wb;
    logic        jal_exe, jal_mem, jal_wb;
    logic        zero_exe;
    logic        csr_en_id, csr_en_exe, csr_en_mem;
    logic        csr_inst_id, csr_inst_exe, csr_inst_mem;  
    logic        mret_inst_id; 
    logic        wfi_inst_id;  
    logic        pc_sel_wb; // used in the trap logic 
    logic        is_comp_if2;


    // atomic extension 
    logic        is_atomic_exe;
    logic [4:0]  fun5_mem;
    logic        mem_write_req_mem;
    logic        mem_to_reg_req_mem;
    logic [31:0] mem_wdata_frw_mem;
    logic [31:0] atomic_unit_wdata_mem;
    logic [31:0] mem_rdata_wb;
    logic [31:0] mem_rdata_aligned;

    /// additional signal for crypto result 
    logic [31:0] crypto_result_exe;
    logic [31:0] alu_result_exe, alu_result_mem;
    logic [31:0] result_mem;
    logic [31:0] rdata2_frw_mem;
    logic [31:0] current_pc_if1;
    logic [31:0] current_pc_if2, pc_plus_2_if2,pc_plus_4_if2, inst_if2;
    logic [11:0] csr_addr_id, csr_addr_exe, csr_addr_mem;
    logic [31:0] inst_if2_uncomp;

    logic        is_mul_id, is_mul_mem, is_mul_wb;
    logic        is_div_id, is_div_exe, div_ready;
    logic [31:0] mul_result_mem, mul_result_wb;
    logic [31:0] div_result;
    logic [4:0]  div_rd;
    logic [31:0] div_pc;
    logic        reg_write_mem_;

    // exeptions support (5 exceptions supported yet)
    logic        ecall_inst_id, ecall_exe, ecall_mem; 
    logic        inst_addr_malign_mem;
    logic        inst_access_fault_mem;
    logic        load_addr_malign_mem;
    logic        load_access_fault_mem;
    logic        illegal_inst_exe, illegal_inst_mem;
    logic        store_amo_addr_malign_mem;
    logic        store_amo_access_fault_mem;
    logic        ebreak_inst_id, ebreak_inst_exe;


    logic inst_valid_if2, inst_valid_id, inst_valid_exe, inst_valid_mem;


    `ifdef tracer 
        logic [31:0] inst_wb;
        logic [4:0]  rs1_mem;
        logic [4:0]  rs1_wb, rs2_wb;
        logic [31:0] reg_rdata1_wb, reg_rdata2_wb;
        logic [31:0] current_pc_wb;
        logic [31:0] mem_wdata_wb, mem_addr_wb;
    `endif

    // ============================================   
    //                Fetch Stage 1 
    // ============================================  
 
    // pc adder 
    logic increment_pc_by_2;
    logic hold_pc;
    logic [31:0] fetch_stall_refetch_pc;
    // logic inst_fetch_stall_ff;
    logic inst_fetch_stall_trigger;
    logic inst_fetch_stall_drop;
    logic if_id_reg_en_ff;
    logic if_id_reg_clr_ff;

    always_ff @(posedge clk, negedge reset_n) begin
        if (!reset_n)  inst_fetch_stall_ff <= 1'b0;
        else           inst_fetch_stall_ff <= inst_fetch_stall;
    end

    assign inst_fetch_stall_trigger =  inst_fetch_stall & ~inst_fetch_stall_ff;
    assign inst_fetch_stall_drop    = ~inst_fetch_stall &  inst_fetch_stall_ff;



    always_ff @(posedge clk, negedge reset_n) begin
        if (!reset_n)                     fetch_stall_refetch_pc <= 32'h0;
        else if(inst_fetch_stall_trigger) begin 
            if(load_hazard | mul_hazard | fp_hazard)                    fetch_stall_refetch_pc <= current_pc_id;
            else if((inst_valid_if2 | (|inst_if2)) & ~if_id_reg_clr_ff) fetch_stall_refetch_pc <= corrected_pc_if2;
            else                                                        fetch_stall_refetch_pc <= current_pc_if1;
        end
    end


    assign pc_plus_4_if1  = (inst_fetch_stall | inst_fetch_stall_ff) ? (fetch_stall_refetch_pc) : (hold_pc ? (corrected_pc_if1) : (corrected_pc_if1 + 4));
    assign pc_minus_2_if1 = current_pc_if1 - 2;
    assign trap_base_pc   = { tvec[31:2], 2'b00 };
    assign trap_pc_tmp    = (tvec[1:0] == 2'b01) ? (trap_base_pc + (trap_cause << 2)) : {1'b0,trap_base_pc};
    assign trap_pc        = trap_pc_tmp[31:0];

    assign no_jump = ~(trap | (trap_ret & dont_trap) | pc_sel_mem); 

    always_comb begin 
        if      (dbg_ret)    next_pc_if1 = dpc;
        else if (trap)       next_pc_if1 = trap_pc;
        else if (trap_ret)   next_pc_if1 = trap_return_pc;
        else if (pc_sel_mem) next_pc_if1 = pc_jump_mem;
        else                 next_pc_if1 = pc_plus_4_if1;
    end

    // ============================================
    //               Program Counter
    // ============================================

    n_bit_reg_wclr #( // TODO might need a register with clear
        .n(32),
		.RESET_VALUE(32'h80000000)
    ) PC_inst (
        .clk(clk),
        .reset_n(reset_n),
        .wen(pc_reg_en | ~no_jump | inst_fetch_stall_drop),
        .data_i(next_pc_if1),
        .data_o(current_pc_if1)
    );
    assign corrected_pc_if1 = increment_pc_by_2 ? (pc_minus_2_if1):(current_pc_if1); 
    assign current_pc_if    = corrected_pc_if1;

    // ============================================
    //              IF1-IF2 Pipeline Register
    // ============================================
    

    n_bit_reg_wo_en #(
        .n(1)
    ) if_id_reg_en_ff_inst (
        .*,
        .data_i(if_id_reg_en),
        .data_o(if_id_reg_en_ff)
    );

    // always_ff @(posedge clk) begin 
    //     if_id_reg_en_ff <= if_id_reg_en;
    // end


    n_bit_reg_wo_en #(
        .n(1)
    ) if_id_reg_clr_ff_inst (
        .*,
        .data_i(if_id_reg_clr),
        .data_o(if_id_reg_clr_ff)
    );


    if1_if2_reg_t if1_if2_bus_i, if1_if2_bus_o;

    assign if1_if2_bus_i = {
        corrected_pc_if1
    };

    n_bit_reg_wclr #(
    `ifdef tracer 
        .n($bits(if1_if2_reg_t)) // Automatically sets width
    `else 
        .n(32)
    `endif
    
    ) if1_if2_reg (
        .clk(clk),
        .reset_n(reset_n),
        .clear(if_id_reg_clr),
        .wen(if_id_reg_en),
        .data_i(if1_if2_bus_i),
        .data_o(if1_if2_bus_o)
    );

    assign current_pc_if2  = if1_if2_bus_o.current_pc;


    // ============================================   
    //                Fetch Stage 2 
    // ============================================   
    logic [31:0] inst_if_ff;

    n_bit_reg_wclr #(
        .n(32),
        .CLR_VALUE(32'h00000000)
    ) if2_reg (
        .*,
        .data_i(inst_if),
        .data_o(inst_if_ff),
        .wen(if_id_reg_en_ff),
        .clear(if_id_reg_clr)
    );
    assign inst_if2 = (if_id_reg_en_ff) ? inst_if : inst_if_ff;



    // ============================================
    //     Instruction Align and Decompress Unit
    // ============================================
    
    iadu iadu_inst (
        .clk(clk),
        .reset_n(reset_n),
        .i_inst(inst_if2),
        .i_pc(current_pc_if2),
        .i_pc_if1(current_pc_if1),
        .i_decode_busy(~if_id_reg_en),
        .clear(if_id_reg_clr_ff | if_id_reg_clr),
        .o_inst(inst_if2_uncomp),
        .o_is_comp(is_comp_if2),
        .o_hold(hold_pc),
        .o_pc_corrected(corrected_pc_if2),
        .o_increment_pc_by_2(increment_pc_by_2),
        .o_fetch_busy(prv_fetch_busy)
    );

    // Optimize ?
    // assign pc_plus_2_if2  = corrected_pc_if2 + 2;
    // assign pc_plus_4_if2  = corrected_pc_if2 + 4;

    wire [31:0] pc_if2;
    wire [31:0] pc_step;

    assign pc_step[0]    =  1'b0;
    assign pc_step[1]    =  is_comp_if2;
    assign pc_step[2]    = ~is_comp_if2;
    assign pc_step[31:3] = 29'b0;
    
    assign pc_if2        = corrected_pc_if2 + pc_step;


    assign inst_valid_if2 =  |inst_if2_uncomp; // valid if not zero

    // ============================================
    //              IF2-ID Pipeline Register
    // ============================================
    
    if2_id_reg_t if2_id_bus_i, if2_id_bus_o;

    // assign if2_id_bus_i = {
    //     corrected_pc_if2,
    //     is_comp_if2 ? (pc_plus_2_if2):(pc_plus_4_if2),
    //     inst_if2_uncomp,
    //     inst_valid_if2
    // };

    assign if2_id_bus_i = {
        corrected_pc_if2,
        pc_if2,
        inst_if2_uncomp,
        inst_valid_if2
    };

    n_bit_reg_wclr #(
    `ifdef tracer
        .n($bits(if2_id_reg_t)) // Automatically sets width
    `else 
        .n(97)
    `endif
    ) if_id_reg (
        .clk(clk),
        .reset_n(reset_n),
        .clear(if_id_reg_clr | if_id_reg_clr_ff),
        .wen(if_id_reg_en),
        .data_i(if2_id_bus_i),
        .data_o(if2_id_bus_o)
    );


    assign current_pc_id  = if2_id_bus_o.current_pc;
    assign pc_plus_4_id   = if2_id_bus_o.pc_plus_4;
    assign inst_id        = if2_id_bus_o.inst;
    assign inst_valid_id  = if2_id_bus_o.inst_valid;
    // ============================================
    //                Decode Stage 
    // ============================================


    // Giving descriptive names to field of instructions
    logic [4:0]  rd_id;
    // fun7_id / fun3_id are now module output ports (F extension decode).
    logic [11:0] fun12_id;

    // additional signal has been added trap_ret
    logic [4:0] func5_id;
    // sha selector has been added 
    logic [4:0] sha_sel_id;

    assign rs1_id      = inst_id[19:15];
    assign rs2_id      = inst_id[24:20];
    assign rd_id       = inst_id[11:7] ;
    assign fun3_id     = inst_id[14:12];
    assign fun7_id     = inst_id[31:25];
    assign opcode_id   = inst_id[6:0];
    assign csr_addr_id = inst_id[31:20];
    assign fun12_id    = inst_id[31:20];

    // these additional assignments are for AES 
    assign func5_id    = inst_id[29:25];
    // sha selector has been extracted 
    assign sha_sel_id  = rs2_id;

    // Optimize ?

    // assign csr_inst_id    = sys_inst_id & ~(fun3_id == 0);
    assign csr_inst_id    = sys_inst_id & |fun3_id;

    assign csr_en_id      = csr_inst_id & ~((fun3_id[1] & rs1_id == 0) | (fun3_id[2] & fun3_id[1] & imm_id==0));
    
    wire fun3_id_eq_zero;
    wire sys_inst_id_and_fun3_id_eq_zero;

    assign fun3_id_eq_zero = ~|fun3_id;
    assign sys_inst_id_and_fun3_id_eq_zero = fun3_id_eq_zero & sys_inst_id;
    
    // assign ecall_inst_id  = sys_inst_id &  (fun3_id == 0) &  (fun12_id == 12'h000);
    // assign ebreak_inst_id = sys_inst_id &  (fun3_id == 0) &  (fun12_id == 12'h001);
    // assign mret_inst_id   = sys_inst_id &  (fun3_id == 0) &  (fun12_id == 12'h302);
    // assign wfi_inst_id    = sys_inst_id &  (fun3_id == 0) &  (fun12_id == 12'h105);
    
    assign ecall_inst_id  = sys_inst_id_and_fun3_id_eq_zero &  (fun12_id == 12'h000);
    assign ebreak_inst_id = sys_inst_id_and_fun3_id_eq_zero &  (fun12_id == 12'h001);
    assign mret_inst_id   = sys_inst_id_and_fun3_id_eq_zero &  (fun12_id == 12'h302);
    assign wfi_inst_id    = sys_inst_id_and_fun3_id_eq_zero &  (fun12_id == 12'h105); 
    
    assign trap_ret_id    = mret_inst_id;
    assign is_mul_id      = r_type_id   & fun7_id[0] & ~|fun7_id[6:1]    & ~fun3_id[2];
    assign is_div_id      = r_type_id   & fun7_id[0] & ~|fun7_id[6:1]    &  fun3_id[2];

    assign reg_write_id_  = sys_inst_id ? csr_inst_id : reg_write_id; 

    logic [31:0] reg_rdata1, reg_rdata2;
    assign dbg_gpr_rdata = reg_rdata1;

    logic dbg_gpr_write;
    
    assign dbg_gpr_write = dbg_ar_en & dbg_ar_wr & 
                           (dbg_ar_ad>= 32'h1000 && dbg_ar_ad <= 32'h101f);

    // Integer register file (decode stage).
    //   Port 1 (main): the normal WB write — ALU, MUL, load, etc. For FP→int
    //     instructions (FCVT.W.S/WU, FMV.X.W, FCLASS, FEQ/FLT/FLE) we gate
    //     this port OFF because the result isn't at WB for 4-stage FPU;
    //     port 2 handles it one cycle later.
    //   Port 2 (fp-delayed): fires at WB+1 from the tail register with
    //     fpu_unit's flopped result. The reg_file has write-before-read
    //     bypass so a consumer at ID reads the new value on the same edge.
    reg_file reg_file_inst (
        .clk         (clk        ),
        .reset_n     (reset_n    ),
        // Port 1 — main WB write (gated for fp_wb_to_int so port 2 owns that path)
        .reg_write   (core_halted ? dbg_gpr_write
                                  : reg_write_wb & ~fp_wb_to_int_wb),
        .waddr       (core_halted ? dbg_ar_ad[4:0] : rd_wb),
        .wdata       (core_halted ? dbg_ar_do      : reg_wdata_wb),
        // Port 2 — FP→int WB+1 write
        .reg_write2  (fp_wb_to_int_wb1),
        .waddr2      (rd_wb1),
        .wdata2      (fpu_result_wb1),
        // Reads
        .raddr1      (core_halted ? dbg_ar_ad[4:0] : rs1_id),
        .raddr2      (rs2_id),
        .rdata1      (reg_rdata1),
        .rdata2      (reg_rdata2)
    );

    // FP register file (decode stage). The write port is driven from the
    // WB+1 tail register, since the 4-stage FPU delivers its result one cycle
    // after the instruction is in WB. Read ports use write-before-read bypass
    // inside the regfile, so a consumer at ID sees the result on the same
    // rising edge the write fires — no separate forwarding mux needed here.
    fp_reg_file fp_reg_file_inst (
        .clk       (clk),
        .reset_n   (reset_n),
        .reg_write (fp_reg_write_wb1),
        .raddr1    (rs1_id),
        .raddr2    (rs2_id),
        .waddr     (rd_wb1),
        .wdata     (fpu_result_wb1),
        .rdata1    (fp_rdata1_raw),
        .rdata2    (fp_rdata2_raw)
    );

    // WB→ID FP forwarding is replaced by fp_reg_file's write-before-read
    // bypass. Tie the old mux selects to 0; the read ports already return the
    // being-written value for same-address hits.
    assign forward_fp_rd1_id = 1'b0;
    assign forward_fp_rd2_id = 1'b0;


    // Immediate unit (decode stage_)
    imm_gen imm_gen_inst (
        .inst(inst_id[31:7]),
        .j_type(jal_id),
        .b_type(branch_id),
        .s_type(mem_write_id),
        .lui(lui_id),
        .auipc(auipc_id),
        .csr_inst(csr_inst_id),
        .imm(imm_id)
    );

   // forwarding mux for rd1 (decode stage)
    mux2x1 #(32) reg_file_rd1_mux (
        .sel(forward_rd1_id),
        .in0(reg_rdata1),
        .in1(reg_wdata_wb),
        .out_(reg_rdata1_id)
    );

    // forwarding mux for rd2 (decode stage)
    mux2x1 #(32) reg_file_rd2_mux (
        .sel(forward_rd2_id),
        .in0(reg_rdata2),
        .in1(reg_wdata_wb),
        .out_(reg_rdata2_id)
    );

    // FP ID-stage read pass-through. With 4-stage FPU the WB+1 write and the
    // ID read share a cycle; fp_reg_file's internal write-before-read bypass
    // covers that case, so these muxes just forward the raw read.
    // (Keeping the muxes to preserve the module's shape; sel is tied 0.)
    mux2x1 #(32) fp_reg_file_rd1_mux (
        .sel(forward_fp_rd1_id),
        .in0(fp_rdata1_raw),
        .in1(fpu_result_wb1),
        .out_(fp_reg_rdata1_id)
    );

    mux2x1 #(32) fp_reg_file_rd2_mux (
        .sel(forward_fp_rd2_id),
        .in0(fp_rdata2_raw),
        .in1(fpu_result_wb1),
        .out_(fp_reg_rdata2_id)
    );

    // ============================================
    //             ID-EXE Pipeline Register
    // ============================================
    
    id_exe_reg_t id_exe_bus_i, id_exe_bus_o;

    assign id_exe_bus_i = {
        // data signals 
        current_pc_id, // 32
        pc_plus_4_id,  // 32
        rs1_id,        // 32
        rs2_id,
        rd_id, 
        fun3_id,
        fun7_id, 
        func5_id,
        sha_sel_id,
        opcode_id,
        reg_rdata1_id,
        reg_rdata2_id,
        imm_id,
        csr_addr_id,
        // control signals
        reg_write_id_,
        mem_write_id,
        mem_to_reg_id, 
        branch_id,
        alu_src_id,
        jump_id,
        lui_id,
        auipc_id,
        jal_id,
        alu_op_id,
        csr_inst_id,
        csr_en_id,
        trap_ret_id,
        is_atomic_id,
        is_mul_id, 
        is_div_id,
        ecall_inst_id,
        illegal_inst_id,
        inst_valid_id,
        ebreak_inst_id,
        inst_id,
        // F extension (Challenge 0013) — order matches id_exe_reg_t field order
        fp_reg_rdata1_id,
        fp_reg_rdata2_id,
        is_fp_id,
        fp_reg_write_id,
        fp_wb_to_int_id,
        fp_uses_rs1_id,
        fp_uses_rs2_id,
        fpu_op_id,
        fp_rm_id
    };

    n_bit_reg_wclr #(
    `ifdef tracer
        .n($bits(id_exe_reg_t)) // Automatically sets width
    `else
        .n(344) // 267 + 77 F-extension bits (fp_rdata1/2 + 5 flags + fpu_op[5] + fp_rm[3])
    `endif
    ) id_exe_reg (
        .clk(clk),
        .reset_n(reset_n),
        .clear(id_exe_reg_clr),
        .wen(id_exe_reg_en),
        .data_i(id_exe_bus_i),
        .data_o(id_exe_bus_o)
    );

    // data signals 
    assign current_pc_exe  = id_exe_bus_o.current_pc; // 32
    assign pc_plus_4_exe   = id_exe_bus_o.pc_plus_4;  // 32
    assign rs1_exe         = id_exe_bus_o.rs1;     // 5
    assign rs2_exe         = id_exe_bus_o.rs2;
    assign rd_exe          = id_exe_bus_o.rd; 
    assign fun3_exe        = id_exe_bus_o.fun3;
    assign fun7_exe        = id_exe_bus_o.fun7;
    // additional signals are being added for AES 
    assign func5_exe       = id_exe_bus_o.fun5;
    assign sha_sel_exe     = id_exe_bus_o.sha_sel;
    assign opcode_exe      = id_exe_bus_o.opcode;    

    assign reg_rdata1_exe  = id_exe_bus_o.reg_rdata1;
    assign reg_rdata2_exe  = id_exe_bus_o.reg_rdata2;
    assign imm_exe         = id_exe_bus_o.imm;
    assign csr_addr_exe    = id_exe_bus_o.csr_addr;

    // control signals
    assign reg_write_exe     = id_exe_bus_o.reg_write;
    assign mem_write_exe     = id_exe_bus_o.mem_write;
    assign mem_to_reg_exe    = id_exe_bus_o.mem_to_reg;
    assign branch_exe        = id_exe_bus_o.branch;
    assign alu_src_exe       = id_exe_bus_o.alu_src;
    assign jump_exe          = id_exe_bus_o.jump;
    assign lui_exe           = id_exe_bus_o.lui; 
    assign auipc_exe         = id_exe_bus_o.auipc;
    assign jal_exe           = id_exe_bus_o.jal;
    assign alu_op_exe        = id_exe_bus_o.alu_op;
    assign csr_inst_exe      = id_exe_bus_o.csr_inst;
    assign csr_en_exe        = id_exe_bus_o.csr_en;
    assign trap_ret_exe      = id_exe_bus_o.trap_ret;
    assign is_atomic_exe     = id_exe_bus_o.is_atomic;
    assign is_mul_exe        = id_exe_bus_o.is_mul;
    assign is_div_exe        = id_exe_bus_o.is_div;
    assign ecall_exe         = id_exe_bus_o.ecall;
    assign illegal_inst_exe  = id_exe_bus_o.illegal_inst; 
    assign inst_valid_exe    = id_exe_bus_o.inst_valid;
    assign ebreak_inst_exe   = id_exe_bus_o.ebreak_inst;
    assign inst_exe          = id_exe_bus_o.inst;

    // F extension unpacks
    assign fp_reg_rdata1_exe = id_exe_bus_o.fp_reg_rdata1;
    assign fp_reg_rdata2_exe = id_exe_bus_o.fp_reg_rdata2;
    assign is_fp_exe         = id_exe_bus_o.is_fp;
    assign fp_reg_write_exe  = id_exe_bus_o.fp_reg_write;
    assign fp_wb_to_int_exe  = id_exe_bus_o.fp_wb_to_int;
    assign fp_uses_rs1_exe   = id_exe_bus_o.fp_uses_rs1;
    assign fp_uses_rs2_exe   = id_exe_bus_o.fp_uses_rs2;
    assign fpu_op_exe        = id_exe_bus_o.fpu_op;
    assign fp_rm_exe         = id_exe_bus_o.fp_rm;

    // FPU is now 2-stage pipelined (Challenge 0013, Strategy #1): every FP
    // op in EX produces its result in MEM, so all FP ops are "multicycle"
    // from the hazard controller's point of view.
    assign is_fp_multicycle_exe = is_fp_exe;

    // ============================================
    //                Execute Stage
    // ============================================

    // forwarding multiplexers
    wire [31:0] rdata1_frw_exe, rdata2_frw_exe;

    // Forwarding mux for rd1
    mux3x1 #(32) forwarding_mux_a (
        .sel(forward_rd1_exe),
        .in0(reg_rdata1_exe),
        .in1(result_mem),
        .in2(reg_wdata_wb),
        .out_(rdata1_frw_exe)
    );

    // Forwarding mux for rd2
    mux3x1 #(32) forwarding_mux_b (
        .sel(forward_rd2_exe),
        .in0(reg_rdata2_exe),
        .in1(result_mem),
        .in2(reg_wdata_wb),
        .out_(rdata2_frw_exe)
    );

    // ------- FP EX-stage forwarding (4-stage FP pipeline) ----------------
    // FP results are valid only at WB+1, and fp_hazard_{exe,mem,wb} stalls
    // every consumer until the producer reaches WB+1. By that cycle the
    // fp_reg_file's write-before-read bypass has already handled the ID-stage
    // read, so the value is correctly captured in fp_reg_rdata*_exe. No
    // EX-stage FP forwarding is required.
    assign forward_fp_rd1_exe[0] = 1'b0;
    assign forward_fp_rd1_exe[1] = 1'b0;
    assign forward_fp_rd2_exe[0] = 1'b0;
    assign forward_fp_rd2_exe[1] = 1'b0;

    mux3x1 #(32) fp_forwarding_mux_a (
        .sel(forward_fp_rd1_exe),
        .in0(fp_reg_rdata1_exe),
        .in1(32'd0),
        .in2(fpu_result_wb1),
        .out_(fp_rs1_frw_exe)
    );

    mux3x1 #(32) fp_forwarding_mux_b (
        .sel(forward_fp_rd2_exe),
        .in0(fp_reg_rdata2_exe),
        .in1(32'd0),
        .in2(fpu_result_wb1),
        .out_(fp_rs2_frw_exe)
    );

    // ------- FPU unit (combinational for Challenge 0013) -----------------
    // Resolve DYN rounding (rm == 3'b111): spec requires looking up the live
    // frm CSR — not treating DYN as RNE. frm_csr is bypass-aware so a
    // back-to-back `csrrwi frm, <mode>; fadd.s` picks up the new mode.
    logic [2:0] fp_rm_resolved;
    assign fp_rm_resolved = (fp_rm_exe == 3'b111) ? frm_csr : fp_rm_exe;

    // fpu_unit is 4-stage (split FMUL 2b/2c + uniform output flop). `result_o`
    // appears at WB+1 timing (three cycles after inputs leave EX), flopped
    // inside the unit. `stall_i = ~exe_mem_reg_en` freezes every internal
    // stage together so the result stays stable during downstream stalls.
    fpu_unit fpu_unit_inst (
        .clk           (clk),
        .reset_n       (reset_n),
        .stall_i       (~exe_mem_reg_en),
        .op_i          (fpu_op_exe),
        .rm_i          (fp_rm_resolved),
        .fp_rs1_i      (fp_rs1_frw_exe),
        .fp_rs2_i      (fp_rs2_frw_exe),
        .int_rs1_i     (rdata1_frw_exe), // for FMV.W.X, FCVT.S.W/WU
        .fmul_product_i(mul_full_result_mem[47:0]),
        .result_o      (fpu_result_wb1),
        .busy_o        ()
    );


    // jalr multiplexer
    logic jalr_exe;
    assign jalr_exe = ~jal_exe & jump_exe;
    logic [31:0] jump_base_pc_exe;
    logic [32:0] pc_jump_exe_temp;
    
    mux2x1 #(
        .n(32)
    ) jalr_pc_mux (
        .sel(jalr_exe), // jalr means jump to ([rs1] + imm)
        .in0(current_pc_exe[31:0]), // all other (pc + imm)
        .in1(rdata1_frw_exe[31:0]),
        .out_(jump_base_pc_exe[31:0])
    );
    assign pc_jump_exe_temp = jump_base_pc_exe + imm_exe;
    assign pc_jump_exe      = {pc_jump_exe_temp[31:1], 1'b0};

    // multiplxers at alu inputs (exe stage)
    logic [31:0] alu_op1_exe;
    logic [31:0] alu_op2_exe;
    mux2x1 #(
        .n(32)
    ) alu_op1_mux (
        .sel(auipc_exe),
        .in0(rdata1_frw_exe),
        .in1(current_pc_exe),
        .out_(alu_op1_exe)       
    );

    // (exe stage)
    mux2x1 #(
        .n(32)
    ) alu_op2_mux (
        .sel(alu_src_exe),
        .in0(rdata2_frw_exe),
        .in1(imm_exe),
        .out_(alu_op2_exe)       
    );

    // ============================================
    //                     ALU
    // ============================================
    alu alu_inst (
        .alu_ctrl(alu_t'(alu_ctrl_exe)),
        .op1(alu_op1_exe),
        .op2(alu_op2_exe),
        .alu_result(alu_result_exe), 
        .zero(zero_exe)
    );

    logic [31:0] result_exe;

    // ============================================
    //                 Crypto Unit 
    // ============================================

    // additional logic has been added for crypto_unit 
    // add an additional mux here to seelct between aes and sha 

    logic [31:0] crypto_alu_result_exe;
    logic crypto_valid;
    crypto_unit crypto_unit_inst(
            .rs1(rdata1_frw_exe),
            .rs2(rdata2_frw_exe),
            .sha_sel(sha_sel_exe[1:0]),
            .crypto_result(crypto_result_exe),
            .crypto_ctrl(alu_t'(alu_ctrl_exe)),
            .result_valid(crypto_valid)
            );
    
    mux2x1 #(
        .n(32)
    ) crypto_alu_mux (
        .sel(crypto_valid),
        .in0(alu_result_exe),
        .in1(crypto_result_exe),
        .out_(crypto_alu_result_exe)
    );


        assign result_exe = crypto_alu_result_exe;



    // ============================================
    //    Two Stage Multiplier — shared int/FP (Strategy #2)
    // ============================================
    // When FMUL is in EX, hijack mul_unit with the FP mantissas zero-
    // extended to 32 bits and funct3 = MULHU (3'b011). mul_unit's internal
    // partial-product flops then carry the FMUL product into MEM, where
    // fpu_mul's stage 2 picks it up via fmul_product_i. The 48-bit
    // mantissa product lives in the lower 48 bits of mul_unit.full_result_o.
    wire        is_fmul_exe = is_fp_exe & (fpu_op_exe == 5'd3);

    // Unpack FP mantissas (implicit-1 for normals, 0 for subnormals).
    wire        fp_rs1_is_sub_exe = (fp_rs1_frw_exe[30:23] == 8'd0) & (fp_rs1_frw_exe[22:0] != 23'd0);
    wire        fp_rs2_is_sub_exe = (fp_rs2_frw_exe[30:23] == 8'd0) & (fp_rs2_frw_exe[22:0] != 23'd0);
    wire [23:0] fp_rs1_mant24_exe = fp_rs1_is_sub_exe ? {1'b0, fp_rs1_frw_exe[22:0]}
                                                      : {1'b1, fp_rs1_frw_exe[22:0]};
    wire [23:0] fp_rs2_mant24_exe = fp_rs2_is_sub_exe ? {1'b0, fp_rs2_frw_exe[22:0]}
                                                      : {1'b1, fp_rs2_frw_exe[22:0]};

    wire [31:0] mul_rs1_in  = is_fmul_exe ? {8'b0, fp_rs1_mant24_exe} : rdata1_frw_exe;
    wire [31:0] mul_rs2_in  = is_fmul_exe ? {8'b0, fp_rs2_mant24_exe} : rdata2_frw_exe;
    wire [2:0]  mul_funct3_in = is_fmul_exe ? 3'b011 /*MULHU*/ : fun3_exe;

    wire [63:0] mul_full_result_mem;

    mul_unit #(32) mul_inst (
        .clk          (clk),
        .reset_n      (reset_n),
        .stall_i      (~exe_mem_reg_en),
        .funct3_i     (mul_funct3_in),
        .rs1_i        (mul_rs1_in),
        .rs2_i        (mul_rs2_in),
        .result_o     (mul_result_mem),
        .full_result_o(mul_full_result_mem)
    );

    // ============================================
    //   Multicycle Division (out_ of the Pipeline)
    // ============================================
    logic flush_div;

    assign flush_div = trap | core_halted;
    div_unit #(32) div_unit (
        .clk(clk),
        .reset_n(reset_n),
        .flush_i(flush_div),
        .start_i(is_div_exe & ~exe_mem_reg_clr & exe_mem_reg_en),
        .funct3_i(fun3_exe),
        .rs1_i(rdata1_frw_exe),
        .rs2_i(rdata2_frw_exe),
        .rd_i(rd_exe),
        .pc_i(current_pc_exe),
        .ready_o(div_ready),
        .busy_o(div_busy),
        .rd_o(div_rd),
        .result_o(div_result),
        .pc_o(div_pc)
    );   

    // ============================================
    //           EXE-MEM Pipeline Register
    // ============================================
    
    exe_mem_reg_t exe_mem_bus_i, exe_mem_bus_o;

    assign exe_mem_bus_i = {
    // data signals 
    pc_plus_4_exe,  
    pc_jump_exe,     
    rs2_exe,
    rd_exe, 
    fun3_exe,
    rdata2_frw_exe,
    imm_exe,
    result_exe,
    rdata1_frw_exe, // send the forwarded rs1 data
    csr_addr_exe,
    current_pc_exe,
    // control signals
    reg_write_exe,
    mem_write_exe,
    mem_to_reg_exe, 
    branch_exe,
    jump_exe,
    lui_exe,
    zero_exe,
    csr_inst_exe,
    csr_en_exe,
    trap_ret_exe,
    is_atomic_exe,
    is_mul_exe,
    ecall_exe,
    illegal_inst_exe,
    inst_valid_exe,
    ebreak_inst_exe,
    inst_exe,
    // F extension (Challenge 0013) — order matches exe_mem_reg_t.
    // fpu_result no longer rides this register (fpu_unit is 2-stage and
    // drives fpu_result_mem directly, same pattern as mul_result_mem).
    is_fp_exe,
    fp_reg_write_exe,
    fp_wb_to_int_exe,
    is_fp_multicycle_exe
    `ifdef tracer
        ,rs1_exe
    `endif
    };

    n_bit_reg_wclr #(
    `ifdef tracer
        .n($bits(exe_mem_reg_t)) // Automatically sets width
    `else
        .n(301) // 297 + 4 F-extension bits (fp flags); fpu_result no longer flopped here
    `endif
    ) exe_mem_reg (
        .clk(clk),
        .reset_n(reset_n),
        .clear(exe_mem_reg_clr),
        .wen(exe_mem_reg_en),
        .data_i(exe_mem_bus_i),
        .data_o(exe_mem_bus_o)
    );

    // data signals 
    assign pc_plus_4_mem   = exe_mem_bus_o.pc_plus_4;  // 32
    assign pc_jump_mem     = exe_mem_bus_o.pc_jump;
    assign rs2_mem         = exe_mem_bus_o.rs2;
    assign fun3_mem        = exe_mem_bus_o.fun3;
    assign rdata2_frw_mem  = exe_mem_bus_o.rdata2_frw;
    assign imm_mem         = exe_mem_bus_o.imm;
    assign alu_result_mem  = exe_mem_bus_o.crypto_alu_result;
    assign reg_rdata1_mem  = exe_mem_bus_o.reg_rdata1;
    assign csr_addr_mem    = exe_mem_bus_o.csr_addr;
    assign current_pc_mem_ = exe_mem_bus_o.current_pc;
    
    // control signals
    assign reg_write_mem_      = exe_mem_bus_o.reg_write;
    assign mem_write_req_mem   = exe_mem_bus_o.mem_write;
    assign mem_to_reg_req_mem  = exe_mem_bus_o.mem_to_reg;
    assign branch_mem          = exe_mem_bus_o.branch;
    assign jump_mem            = exe_mem_bus_o.jump;
    assign lui_mem             = exe_mem_bus_o.lui; 
    assign zero_mem            = exe_mem_bus_o.zero;
    assign csr_inst_mem        = exe_mem_bus_o.csr_inst;
    assign csr_en_mem          = exe_mem_bus_o.csr_en;
    assign trap_ret_mem        = exe_mem_bus_o.trap_ret;
    assign is_atomic_mem       = exe_mem_bus_o.is_atomic;
    assign is_mul_mem          = exe_mem_bus_o.is_mul;
    assign ecall_mem           = exe_mem_bus_o.ecall;
    assign illegal_inst_mem    = exe_mem_bus_o.illegal_inst;
    assign ebreak_inst_mem     = exe_mem_bus_o.ebreak_inst;

    assign inst_mem            = exe_mem_bus_o.inst;

    // F extension unpacks (MEM stage) — fpu_result_mem is now driven
    // directly by fpu_unit (2-stage pipelined, Strategy #1), not by the
    // EX→MEM pipeline register.
    assign is_fp_mem           = exe_mem_bus_o.is_fp;
    assign fp_reg_write_mem    = exe_mem_bus_o.fp_reg_write;
    assign fp_wb_to_int_mem    = exe_mem_bus_o.fp_wb_to_int;
    assign is_fp_multicycle_mem= exe_mem_bus_o.is_fp_multicycle;

    `ifdef tracer
    assign rs1_mem             = exe_mem_bus_o.rs1;
    `endif

    // ============================================
    //                Memory Stage 
    // ============================================
    
    // generating memory access signals (write/read) 
    // logic added to handle core case in the forwarding 
    logic [31:0] mem_wdata_frw_mem_tmp;
    logic [31:0] mem_wdata_frw_mem_tmp_ff;

    logic        mem_wb_reg_en_ff;
    logic        mem_wb_reg_en_drop;
    logic        mem_wb_reg_en_rise;
    always_ff @(posedge clk, negedge reset_n) begin 
        if(~reset_n) mem_wb_reg_en_ff <= 'b0;
        else         mem_wb_reg_en_ff <= mem_wb_reg_en;
    end

    assign mem_wb_reg_en_drop =  mem_wb_reg_en_ff & ~mem_wb_reg_en;
    assign mem_wb_reg_en_rise = ~mem_wb_reg_en_ff &  mem_wb_reg_en;

    always_ff @(posedge clk, negedge reset_n) begin 
        if (~reset_n) begin 
            mem_wdata_frw_mem_tmp_ff <= 'b0;        
        end else if(mem_wb_reg_en_drop) begin 
            mem_wdata_frw_mem_tmp_ff <= mem_wdata_frw_mem_tmp;
        end
    end
    assign mem_wdata_frw_mem = mem_wb_reg_en_rise ? mem_wdata_frw_mem_tmp_ff : mem_wdata_frw_mem_tmp;

    // forwarding for mem_write_data
    mux2x1 #(32) mem_data_in_mux (
        .sel(forward_rd2_mem),
        .in0(rdata2_frw_mem),
        .in1(reg_wdata_wb),
        .out_(mem_wdata_frw_mem_tmp)
    ); 
    
       
    logic [31:0] mem_addr;
    assign mem_addr = is_atomic_mem ? reg_rdata1_mem : alu_result_mem;
    

    // ============================================
    //              ATOMIC ACCESS LOGIC
    // ============================================

    assign fun5_mem = csr_addr_mem[11:7]; // csr addr is fun12


    lsu lsu_inst (
        .clk(clk),
        .rst(~reset_n),
        .is_atomic_mem(is_atomic_mem),
        .core_halted(core_halted),
        .amo_funct5_mem(fun5_mem),
        .rs2_val_mem(mem_wdata_frw_mem),
        .mem_read_req(mem_to_reg_req_mem),
        .mem_write_req(mem_write_req_mem),
        .mem_addr_req(mem_addr), 
        .mem_wdata_req(mem_wdata_frw_mem),
        .mem_op_mem(fun3_mem),
        
        .mem_read(mem_to_reg_mem),
        .mem_write(mem_write_mem),
        .mem_addr(mem_addr_mem),
        .mem_wdata(mem_wdata_mem),
        .mem_wstrb(mem_wstrb_mem),
        .mem_rdata(mem_rdata_mem),
        .mem_ack(mem_ack_mem),
        .mem_err(mem_err_mem),
        .mem_rdata_aligned(mem_rdata_aligned),

        .stall_mem(atomic_unit_stall),
        .result_rd(atomic_unit_wdata_mem),
        .load_addr_malign(load_addr_malign_mem),
        .load_access_fault(load_access_fault_mem),
        .store_amo_addr_malign(store_amo_addr_malign_mem),
        .store_amo_access_fault(store_amo_access_fault_mem)
    );



    // ============================================
    //               Exception Encoder
    // ============================================
    logic [5:0]  e_code_mem;
    logic [31:0] mtval;
    logic        exception_mem;
    logic        pc_in_boot_rom;
    logic        pc_in_imem;
    logic        pc_in_dmem;
    
    // boot rom now at address 0x00000000 (8kb memory)
    assign pc_in_boot_rom        = (current_pc_mem & 32'hffffe000) == 32'h00000000;
    assign pc_in_imem            = (current_pc_mem & 32'hFFFF8000) == 32'h80000000;
    assign pc_in_dmem            = (current_pc_mem & 32'hFFFFc000) == 32'h80008000;
    assign inst_access_fault_mem = inst_valid_mem & ~(pc_in_boot_rom | pc_in_imem | pc_in_dmem); 
    assign inst_addr_malign_mem  =  current_pc_mem[0]; 
    assign e_code_mem[5]         = 1'b0;
    
    exception_encoder exception_encoder_inst (
        .ecall                   (ecall_mem),
        .ebreak                  (ebreak_inst_mem),
        .inst_addr_malign        (inst_addr_malign_mem),
        .inst_access_fault       (inst_access_fault_mem),
        .load_addr_malign        (load_addr_malign_mem),
        .load_access_fault       (load_access_fault_mem),
        .store_amo_addr_malign   (store_amo_addr_malign_mem),
        .store_amo_access_fault  (store_amo_access_fault_mem),
        .illegal_inst            (illegal_inst_mem),
        .faulting_inst_addr      (current_pc_mem),
        .faulting_lsu_addr       (mem_addr_mem),
        .faulting_instr          (inst_mem),
        .exception_o             (exception_mem),
        .exception_code_o        (e_code_mem[4:0]),
        .mtval_value_o           (mtval)
    );


    // ============================================
    //                   CSR FILE
    // ============================================


    logic [1:0]  csr_cmd_mem;
    logic [31:0] csr_wdata_mem;
    logic [31:0] csr_rdata_mem;
    // logic [31:0] cinst_pc;
    assign csr_cmd_mem   = fun3_mem[1:0];
    assign csr_wdata_mem = fun3_mem[2] ? imm_mem : reg_rdata1_mem; 
    assign trap_ret      = trap_ret_mem;


    always_comb begin   
        if(inst_valid_mem)                            cinst_pc = current_pc_mem;
        else if(inst_valid_exe)                       cinst_pc = current_pc_exe;
        else if(inst_valid_id)                        cinst_pc = current_pc_id;
        else if(inst_valid_if2 & ~if_id_reg_clr_ff)   cinst_pc = current_pc_if2; // TODO shoudt is be correct pc if2?
        else                                          cinst_pc = current_pc_if1; // TODO should it be corrected_pc_if1?
    end

    logic dbg_csr_write;
    
    assign dbg_csr_write = dbg_ar_en & dbg_ar_wr & (dbg_ar_ad < 32'h1000);
    
    // 'func_score': 100.0, 'area_score': 61.12, 'perf_score': 90.28, 'power_score': 32.36, 'overall': 60.96
    // assign dbg_csr_write = dbg_ar_en & dbg_ar_wr & ~|dbg_ar_ad[15 -:4];

    logic [2:0] frm_csr;   // live frm exported from csr_file, drives FPU DYN mode.

    csr_file csr_file_inst (
        .clk             (clk           ),
        .reset_n         (reset_n       ),
        .exe_mem_reg_en  (exe_mem_reg_en),
        .exe_mem_reg_clr (exe_mem_reg_clr),
        .dont_trap       (dont_trap     ),
        .csr_en          (core_halted ? dbg_csr_write   : csr_en_mem    ),
        .csr_cmd         (core_halted ? 2'b01           : csr_cmd_mem   ), // read and write csr through the debug
        .csr_addr        (core_halted ? dbg_ar_ad[11:0] : csr_addr_mem  ),
        .csr_wdata       (core_halted ? dbg_ar_do       : csr_wdata_mem ),
        .csr_rdata       (csr_rdata_mem ),
        .cinst_pc        (cinst_pc      ),
        .exception_i     (exception_mem ),
        .e_code          (e_code_mem    ),
        .timer_irq       (timer_irq     ),
        .external_irq    (external_irq  ),
        .trap            (trap          ),
        .mtvec           (tvec          ),
        .mepc            (trap_return_pc),
        .trap_cause      (trap_cause    ),
        .trap_ret        (trap_ret & ~dont_trap),
        .mtval_i         (mtval),
        .frm_o           (frm_csr)
    );

    assign dbg_csr_result = trap ? csr_rdata_mem : 'b0;

    // selecting result in the memory stage
    // it can be used in the exe, incase it's needed 

    logic alu_to_reg_mem;
    logic [31:0] mem_result_mux_1_o;
    assign alu_to_reg_mem = ~( jump_mem | lui_mem | csr_inst_mem);
    one_hot_mux4x1 #(
        .n(32)
    ) mem_stage_result_sel_mux (
        .sel({csr_inst_mem,lui_mem, jump_mem, alu_to_reg_mem}),
        .in0(alu_result_mem),
        .in1(pc_plus_4_mem),
        .in2(imm_mem),
        .in3(csr_rdata_mem),
        .out_(mem_result_mux_1_o)
    );

    // div result is included in the mem result but mul is not becuase of critical path caused by mul.
    // fp_wb_to_int producers (FCVT.W.S / FCVT.WU.S / FMV.X.W) are 3-stage FP
    // now — their result is NOT available at MEM. The hazard controller
    // stalls any dependent int consumer until the producer reaches WB, so
    // we no longer need a MEM-stage FP path here.
    assign result_mem = div_ready     ? div_result :
                        is_atomic_mem ? atomic_unit_wdata_mem :
                        mem_result_mux_1_o;
    assign rd_mem     = div_ready ? div_rd    : exe_mem_bus_o.rd;  
    assign reg_write_mem  = reg_write_mem_ | is_mul_mem | div_ready;
    assign current_pc_mem = (div_ready | div_busy) ? div_pc : current_pc_mem_; 
    assign inst_valid_mem = exe_mem_bus_o.inst_valid | div_ready;

    // ============================================
    //            MEM-WB Pipeline Register
    // ============================================
    
    mem_wb_reg_t mem_wb_bus_i, mem_wb_bus_o;
    logic [31:0] alu_mem_result_wb;
    logic mem_to_reg_wb;

    assign mem_wb_bus_i = {
    // data signals
    rd_mem,
    result_mem,
    mem_rdata_aligned,
    mul_result_mem,
    // control signals
    reg_write_mem,
    mem_to_reg_req_mem,
    is_mul_mem,
    inst_valid_mem,
    // F extension (Challenge 0013) — order matches mem_wb_reg_t.
    // fpu_result is not flopped here — fpu_unit drives fpu_result_wb1 directly
    // directly from its WB-stage combinational output.
    fp_reg_write_mem,
    fp_wb_to_int_mem,
    is_fp_multicycle_mem

    `ifdef tracer
    ,pc_sel_mem,
    inst_mem, 
    rs1_mem, 
    rs2_mem, 
    reg_rdata1_mem,
    rdata2_frw_mem,
    current_pc_mem,
    mem_wdata_mem, 
    mem_addr_mem
    `endif
    
    };

    n_bit_reg_wclr #(
    `ifdef tracer
        .n($bits(mem_wb_reg_t)) // Automatically sets width
    `else
        .n(108) // 105 + 3 F-extension flag bits (fpu_result moved out; is_fp_multicycle tracked)
    `endif
    ) mem_wb_reg (
        .clk(clk),
        .reset_n(reset_n),
        .clear(mem_wb_reg_clr),
        .wen(mem_wb_reg_en),
        .data_i(mem_wb_bus_i),
        .data_o(mem_wb_bus_o)
    );
    logic [4:0] rd_wb_;
    logic       reg_write_wb_;
    // data signals 
    assign rd_wb_                   = mem_wb_bus_o.rd; 
    assign non_mul_result_wb        = mem_wb_bus_o.result;
    assign mem_rdata_wb             = mem_wb_bus_o.mem_rdata;
    assign mul_result_wb            = mem_wb_bus_o.mul_result;

    // control signals
    assign reg_write_wb_            = mem_wb_bus_o.reg_write;
    assign mem_to_reg_wb            = mem_wb_bus_o.mem_to_reg;
    assign is_mul_wb                = mem_wb_bus_o.is_mul;
    assign inst_valid_wb            = mem_wb_bus_o.inst_valid;

    // F extension unpacks (WB stage).
    assign fp_reg_write_wb          = mem_wb_bus_o.fp_reg_write;
    assign fp_wb_to_int_wb          = mem_wb_bus_o.fp_wb_to_int;
    assign is_fp_multicycle_wb      = mem_wb_bus_o.is_fp_multicycle;

    // --- WB+1 tail register -----------------------------------------------
    // Carries {rd, fp_reg_write, fp_wb_to_int, is_fp_multicycle} one cycle
    // past WB so the delayed fp_reg_file / reg_file (port 2) writes land in
    // the same cycle fpu_unit.result_o is valid. Enabled by mem_wb_reg_en so
    // it advances in lockstep with the main pipeline (and fpu_unit).
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_wb1               <= 5'd0;
            fp_reg_write_wb1     <= 1'b0;
            fp_wb_to_int_wb1     <= 1'b0;
            is_fp_multicycle_wb1 <= 1'b0;
        end else if (mem_wb_reg_en) begin
            rd_wb1               <= rd_wb;
            fp_reg_write_wb1     <= fp_reg_write_wb;
            fp_wb_to_int_wb1     <= fp_wb_to_int_wb;
            is_fp_multicycle_wb1 <= is_fp_multicycle_wb;
        end
    end

    `ifdef tracer 
    assign pc_sel_wb                = mem_wb_bus_o.pc_sel;
    assign inst_wb                  = mem_wb_bus_o.inst;
    assign rs1_wb                   = mem_wb_bus_o.rs1;
    assign rs2_wb                   = mem_wb_bus_o.rs2;
    assign reg_rdata1_wb            = mem_wb_bus_o.reg_rdata1;
    assign reg_rdata2_wb            = mem_wb_bus_o.reg_rdata2;
    assign current_pc_wb            = mem_wb_bus_o.current_pc;
    assign mem_wdata_wb             = mem_wb_bus_o.mem_wdata;
    assign mem_addr_wb              = mem_wb_bus_o.mem_addr;
    `endif


    // ============================================
    //                Write Back Stage 
    // ============================================


    // Int WB writeback path. fp_wb_to_int results are NOT muxed here — they
    // arrive one cycle later at WB+1 and are written via reg_file's port 2.
    assign reg_wdata_wb = is_mul_wb        ? mul_result_wb  :
                          mem_to_reg_wb    ? mem_rdata_wb   :
                          non_mul_result_wb;
    assign rd_wb        = rd_wb_;
    assign reg_write_wb = reg_write_wb_;

    `ifdef tracer
        // 4-stage FPU: FP results commit at WB+1, not WB. All tracer fields
        // pulled from mem_wb_bus_o are flopped one cycle so the emitted tuple
        // lines up with the cycle fpu_unit.result_o (= fpu_result_wb1) is
        // valid. rd_wb1 / fp_reg_write_wb1 already exist as the real WB+1
        // tail; we reuse them here so port-2 writes and rvfi stay in sync.
        // fpu_result_wb1 is the combinational fpu_unit output — grabbed live
        // at emit cycle, NOT flopped again.
        logic [31:0] inst_tr, current_pc_tr;
        logic [31:0] reg_rdata1_tr, reg_rdata2_tr, reg_wdata_tr;
        logic [4:0]  rs1_tr, rs2_tr;
        logic        inst_valid_tr, pc_sel_tr;
        logic [31:0] current_pc_mem_tr, current_pc_if1_tr;

        always_ff @(posedge clk or negedge reset_n) begin
            if (!reset_n) begin
                inst_tr            <= 32'd0;
                rs1_tr             <= 5'd0;
                rs2_tr             <= 5'd0;
                reg_rdata1_tr      <= 32'd0;
                reg_rdata2_tr      <= 32'd0;
                reg_wdata_tr       <= 32'd0;
                current_pc_tr      <= 32'd0;
                current_pc_mem_tr  <= 32'd0;
                current_pc_if1_tr  <= 32'd0;
                inst_valid_tr      <= 1'b0;
                pc_sel_tr          <= 1'b0;
            end else if (mem_wb_reg_en) begin
                inst_tr            <= inst_wb;
                rs1_tr             <= rs1_wb;
                rs2_tr             <= rs2_wb;
                reg_rdata1_tr      <= reg_rdata1_wb;
                reg_rdata2_tr      <= reg_rdata2_wb;
                reg_wdata_tr       <= reg_wdata_wb;
                current_pc_tr      <= current_pc_wb;
                current_pc_mem_tr  <= current_pc_mem;
                current_pc_if1_tr  <= current_pc_if1;
                inst_valid_tr      <= inst_valid_wb;
                pc_sel_tr          <= pc_sel_wb;
            end
        end

        assign rvfi_insn      = inst_tr;
        assign rvfi_rs1_addr  = rs1_tr;
        assign rvfi_rs2_addr  = rs2_tr;
        assign rvfi_rd_addr   = rd_wb1;
        assign rvfi_rs1_rdata = reg_rdata1_tr;
        assign rvfi_rs2_rdata = reg_rdata2_tr;
        assign rvfi_rd_wdata  = fp_reg_write_wb1 ? fpu_result_wb1
                              : fp_wb_to_int_wb1 ? fpu_result_wb1
                                                 : reg_wdata_tr;
        assign rvfi_pc_rdata  = current_pc_tr;
        assign rvfi_pc_wdata  = pc_sel_tr ? current_pc_if1_tr : current_pc_mem_tr;
        assign rvfi_mem_addr  = 32'd0;
        assign rvfi_mem_rdata = 32'd0;
        assign rvfi_mem_wdata = 32'd0;
        assign rvfi_valid     = inst_valid_tr;
    `endif


    // instantiate the tracer ip 
    `ifdef tracer 
        tracer tracer_inst (
        .clk_i           (clk),
        .rst_ni          (reset_n),
        .hart_id_i       (1),
        .rvfi_insn_t     (rvfi_insn),
        .rvfi_rs1_addr_t (rvfi_rs1_addr),
        .rvfi_rs2_addr_t (rvfi_rs2_addr),
        .rvfi_rs3_addr_t (),
        .rvfi_rs3_rdata_t(),
        .rvfi_mem_rmask  (),
        .rvfi_mem_wmask  (),
        .rvfi_rs1_rdata_t(rvfi_rs1_rdata),
        .rvfi_rs2_rdata_t(rvfi_rs2_rdata),
        .rvfi_rd_addr_t  (rvfi_rd_addr),
        .rvfi_rd_wdata_t (rvfi_rd_wdata),
        .rvfi_pc_rdata_t (rvfi_pc_rdata),
        .rvfi_pc_wdata_t (rvfi_pc_wdata),
        .rvfi_mem_addr   (rvfi_mem_addr),
        .rvfi_mem_wdata  (rvfi_mem_wdata),
        .rvfi_mem_rdata  (rvfi_mem_rdata),
        .rvfi_valid      (rvfi_valid)
        );
    `endif

endmodule
