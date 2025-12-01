


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
    input logic is_montgomery_id,

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
    output logic is_montgomery_exe,
    input  logic inst_fetch_stall,
    output logic inst_fetch_stall_ff,
    input  logic load_hazard,
    input  logic mul_hazard

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
    logic [31:0] imm_id,imm_exe, imm_mem, imm_wb;
    logic [31:0] pc_plus_4_if1, pc_plus_4_id, pc_plus_4_exe, pc_plus_4_mem,pc_plus_4_wb;
    logic [31:0] pc_minus_2_if1;
    logic [31:0] corrected_pc_if1, corrected_pc_if2;
    logic [31:0] pc_jump_exe, pc_jump_mem;
    logic [31:0] non_mul_result_wb;
    logic [31:0] tvec,  trap_return_pc;
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

    logic is_montgomery_mem, is_montgomery_wb;


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
    logic if_id_reg_en_ff;
    logic if_id_reg_clr_ff;

    assign inst_fetch_stall_ff = 'b0;


    assign pc_plus_4_if1  = hold_pc ? (corrected_pc_if1) : (corrected_pc_if1 + 4);
    assign pc_minus_2_if1 = current_pc_if1 - 2;

    assign no_jump = ~pc_sel_mem;

    always_comb begin 
        if (pc_sel_mem)      next_pc_if1 = pc_jump_mem;
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
        .wen(pc_reg_en | ~no_jump),
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

    assign pc_plus_2_if2  = corrected_pc_if2 + 2;
    assign pc_plus_4_if2  = corrected_pc_if2 + 4;
    assign inst_valid_if2 =  |inst_if2_uncomp; // valid if not zero

    // ============================================
    //              IF2-ID Pipeline Register
    // ============================================
    
    if2_id_reg_t if2_id_bus_i, if2_id_bus_o;

    assign if2_id_bus_i = {
        corrected_pc_if2,
        is_comp_if2 ? (pc_plus_2_if2):(pc_plus_4_if2),
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
    logic [6:0]  fun7_id;
    logic [2:0]  fun3_id;
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


    assign csr_inst_id    = 'b0;
    assign csr_en_id      = 'b0;
    assign ecall_inst_id  = 'b0;
    assign ebreak_inst_id = 'b0;
    assign mret_inst_id   = 'b0;
    assign wfi_inst_id    = 'b0;
    assign trap_ret_id    = 'b0;
    assign is_mul_id      = r_type_id   & fun7_id[0] & ~|fun7_id[6:1]    & ~fun3_id[2];
    assign is_div_id      = r_type_id   & fun7_id[0] & ~|fun7_id[6:1]    &  fun3_id[2];

    assign reg_write_id_  = reg_write_id; 

    logic [31:0] reg_rdata1, reg_rdata2;
    assign dbg_gpr_rdata = reg_rdata1;


    // register file (decode stage)
    reg_file reg_file_inst (
        .clk         (clk        ),
        .reset_n     (reset_n    ),
        .reg_write   (reg_write_wb),
        .raddr1      (rs1_id),
        .raddr2      (rs2_id),
        .waddr       (rd_wb),
        .wdata       (reg_wdata_wb),
        .rdata1      (reg_rdata1),
        .rdata2      (reg_rdata2)
    );


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
        is_montgomery_id,
        inst_id
    };

    n_bit_reg_wclr #(
    `ifdef tracer
        .n($bits(id_exe_reg_t)) // Automatically sets width
    `else 
        .n(268)
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
    assign is_montgomery_exe = id_exe_bus_o.is_montgomery;
    assign inst_exe          = id_exe_bus_o.inst;



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


`ifdef PQC
        logic [31:0] pqc_result_mem;
        logic [31:0] pqc_result_wb;
        pqc_top pqc_top_inst (
            .clk, 
            .reset_n,
            .en(exe_mem_reg_en),
            .operand1_i    (rdata1_frw_exe),          
            .operand2_i    (rdata2_frw_exe),         
            .inst_28_27_26 (fun7_exe[3:1]),          // bits [28:26] of your decoded instruction
            .result_o      (pqc_result_mem)          
        );
`endif

        assign result_exe = crypto_alu_result_exe;



    // ============================================
    //               Two Stage Multiplier
    // ============================================
    mul_unit #(32) mul_inst (
        .clk(clk),
        .reset_n(reset_n),
        .stall_i(~exe_mem_reg_en),
        .funct3_i(fun3_exe),
        .rs1_i(rdata1_frw_exe),
        .rs2_i(rdata2_frw_exe),
        .result_o(mul_result_mem)
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
    current_pc_exe,
    // control signals
    reg_write_exe,
    mem_write_exe,
    mem_to_reg_exe, 
    branch_exe,
    jump_exe,
    lui_exe,
    zero_exe,
    is_mul_exe,
    is_atomic_exe,
    inst_valid_exe,

`ifdef CSR_FILE
    csr_addr_exe,
    csr_inst_exe,
    csr_en_exe,
    trap_ret_exe,
    ecall_exe,
    illegal_inst_exe,
    ebreak_inst_exe,
`endif
    is_montgomery_exe,
    inst_exe
    `ifdef tracer 
        ,rs1_exe
    `endif
    };

    n_bit_reg_wclr #(
    `ifdef tracer
        .n($bits(exe_mem_reg_t)) // Automatically sets width
    `else 
        .n(280)
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
    assign current_pc_mem_ = exe_mem_bus_o.current_pc;
    
    // control signals
    assign reg_write_mem_      = exe_mem_bus_o.reg_write;
    assign mem_write_req_mem   = exe_mem_bus_o.mem_write;
    assign mem_to_reg_req_mem  = exe_mem_bus_o.mem_to_reg;
    assign branch_mem          = exe_mem_bus_o.branch;
    assign jump_mem            = exe_mem_bus_o.jump;
    assign lui_mem             = exe_mem_bus_o.lui; 
    assign zero_mem            = exe_mem_bus_o.zero;
    assign is_atomic_mem       = exe_mem_bus_o.is_atomic;
    assign is_mul_mem          = exe_mem_bus_o.is_mul;

`ifdef CSR_FILE
    assign csr_addr_mem        = exe_mem_bus_o.csr_addr;
    assign csr_inst_mem        = exe_mem_bus_o.csr_inst;
    assign csr_en_mem          = exe_mem_bus_o.csr_en;
    assign trap_ret_mem        = exe_mem_bus_o.trap_ret;
    assign ecall_mem           = exe_mem_bus_o.ecall;
    assign illegal_inst_mem    = exe_mem_bus_o.illegal_inst;
    assign ebreak_inst_mem     = exe_mem_bus_o.ebreak_inst;
`else 
    assign ebreak_inst_mem     = 'b0;
    assign csr_inst_mem        = 'b0;
`endif

    assign is_montgomery_mem   = exe_mem_bus_o.is_montgomery;

    assign inst_mem            = exe_mem_bus_o.inst;
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
    
    

    // ============================================
    //              ATOMIC ACCESS LOGIC
    // ============================================

    logic [31:0] mem_addr;
    assign mem_addr = alu_result_mem;

    store_aligner store_alignment_unit(
        .wdata(mem_wdata_frw_mem),
        .store_type(store_t'(fun3_mem)),
        .addr(mem_addr[1:0]),
        .mem_write(mem_write_mem),
        .wsel(mem_wstrb_mem),
        .aligned_data(mem_wdata_mem)
    );

    load_aligner load_alignment_unit (
        .addr(mem_addr[1:0]),
        .fun3(fun3_mem),
        .rdata(mem_rdata_mem),
        .aligned_data(mem_rdata_aligned)
    );

    assign mem_to_reg_mem    = mem_to_reg_req_mem;
    assign mem_write_mem     = mem_write_req_mem;
    assign mem_addr_mem      = mem_addr;


    assign atomic_unit_stall = 1'b0;


    // ============================================
    //               Exception Encoder
    // ============================================

`ifdef CSR_FILE
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
    assign dbg_csr_write = dbg_ar_en & dbg_ar_wr & 
                           (dbg_ar_ad< 32'h1000);
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
        .mtval_i         (mtval)
    );

    assign dbg_csr_result = csr_rdata_mem;
`else 
    assign trap = 1'b0;
    assign trap_return_pc = 32'b0;
    assign tvec = 32'b0;
    assign trap_cause = 32'b0;
    assign dbg_csr_result = 32'b0;
    assign cinst_pc = 32'b0;
    assign trap_ret = 1'b0;
`endif




    // selecting result in the memory stage
    // it can be used in the exe, incase it's needed 

    logic alu_to_reg_mem;
    logic [31:0] mem_result_mux_1_o;
    assign alu_to_reg_mem = ~( jump_mem | lui_mem | csr_inst_mem);
    one_hot_mux3x1 #(
        .n(32)
    ) mem_stage_result_sel_mux (
        .sel({lui_mem, jump_mem, alu_to_reg_mem}),
        .in0(alu_result_mem),
        .in1(pc_plus_4_mem),
        .in2(imm_mem),
        .out_(mem_result_mux_1_o)
    );

    // div result is included in the mem result but mul is not becuase of critical path caused by mul
    assign result_mem = div_ready                ? div_result : mem_result_mux_1_o; 
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
`ifdef PQC
    pqc_result_mem,
    is_montgomery_mem,
`endif
    // control signals
    reg_write_mem,
    mem_to_reg_req_mem,
    is_mul_mem,
    inst_valid_mem

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
        .n(105)
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
`ifdef PQC
    assign pqc_result_wb        = mem_wb_bus_o.pqc_result;
    assign is_montgomery_wb     = mem_wb_bus_o.is_montgomery;
`endif
    // control signals
    assign reg_write_wb_            = mem_wb_bus_o.reg_write;
    assign mem_to_reg_wb            = mem_wb_bus_o.mem_to_reg;
    assign is_mul_wb                = mem_wb_bus_o.is_mul;
    assign inst_valid_wb            = mem_wb_bus_o.inst_valid;

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


    assign reg_wdata_wb = is_mul_wb ? mul_result_wb:
`ifdef PQC
                          is_montgomery_wb ? pqc_result_wb: 
`endif
                          mem_to_reg_wb    ? mem_rdata_wb : non_mul_result_wb; 
    assign rd_wb        = rd_wb_;
    assign reg_write_wb = reg_write_wb_;

    `ifdef tracer
        assign rvfi_insn      = inst_wb;
        assign rvfi_rs1_addr  = rs1_wb;
        assign rvfi_rs2_addr  = rs2_wb;
        assign rvfi_rd_addr   = rd_wb;
        assign rvfi_rs1_rdata = reg_rdata1_wb;
        assign rvfi_rs2_rdata = reg_rdata2_wb;
        assign rvfi_rd_wdata  = reg_wdata_wb;
        assign rvfi_pc_rdata  = current_pc_wb;
        assign rvfi_pc_wdata  = pc_sel_wb ? current_pc_if1 : current_pc_mem;
        assign rvfi_mem_addr  = 32'd0;
        assign rvfi_mem_rdata = 32'd0;
        assign rvfi_mem_wdata = 32'd0;
        assign rvfi_valid     = inst_valid_wb;
    `endif

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
