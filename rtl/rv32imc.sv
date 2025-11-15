module rv32i #(
    parameter DMEM_DEPTH = 1024, 
    parameter IMEM_DEPTH = 1024
)(
    input logic clk, 
    input logic reset_n,

    // memory bus
    output logic [31:0] mem_addr_mem, 
    output logic [31:0] mem_wdata_mem, 
    output logic [3:0] mem_wstrb_mem,
    output logic mem_write_mem, 
    input logic [31:0] mem_rdata_mem,
    output logic mem_read_mem,
    input logic mem_ack_mem,
    input logic mem_err_mem,


    // inst mem access 
    output logic [31:0] current_pc,
    input logic [31:0] inst,


    // timer interrupt from the clint
    input logic timer_irq,
    input logic external_irq,

    // Debug Signals 
    output logic core_resumeack,
    output logic core_running,
    output logic core_halted,

    input  logic dbg_haltreq,
    input  logic dbg_resumereq,

    input  logic        dbg_ar_en,
    input  logic        dbg_ar_wr,
    input  logic [15:0] dbg_ar_ad,
    output logic [31:0] dbg_ar_di,
    output logic        dbg_ar_done,
    input  logic [31:0] dbg_ar_do,
    input  logic        inst_fetch_stall,
    output logic        illegal_inst
);


    logic if_id_reg_en;

    
    // controller to the data path 
    logic reg_write_id; 
    logic mem_write_id;
    logic mem_to_reg_id; 
    logic branch_id; 
    logic alu_src_id;
    logic jump_id; 
    logic lui_id;
    logic auipc_id; 
    logic jal_id;
    logic r_type_id;
    logic [1:0] alu_op_id;
    logic sys_inst_id;
    logic is_atomic_id;
    logic illegal_inst_id;
    logic [9:0] alu_ctrl_exe;
    logic pc_sel_mem;
    logic trap;
    logic trap_ret;
    logic atomic_unit_stall;
    logic is_atomic_mem;
    logic is_mul_exe;
    logic div_busy;

    // data path to the controller 
    logic [6:0] opcode_id;
    logic [2:0] fun3_exe, fun3_mem;
    logic zero_mem;
    logic [1:0] alu_op_exe;
    logic jump_mem; 
    logic branch_mem;

    // additional signal has been added 
    logic [6:0] fun7_exe;


    // data path to the controller (forwarding unit)
    wire [4:0] rs1_id;
    wire [4:0] rs2_id;
    wire [4:0] rs1_exe;
    wire [4:0] rs2_exe;
    wire [4:0] rs2_mem;
    wire [4:0] rd_mem;
    wire [4:0] rd_wb;
    wire       reg_write_mem;
    wire       reg_write_wb;
    wire       is_montgomery_id;
    wire       is_montgomery_exe;

    // controller(forwarding unit) to the data path 
    wire       forward_rd1_id;
    wire       forward_rd2_id;
    wire [1:0] forward_rd1_exe;
    wire [1:0] forward_rd2_exe;
    wire       forward_rd2_mem;


    // data path to the controller (hazard handler)
    wire mem_to_reg_exe;
    wire [4:0] rd_exe;

    // signals to control the flow of the pipeline (handling hazards, stalls ... )
    logic if_id_reg_clr;
    logic id_exe_reg_clr;
    logic exe_mem_reg_clr;
    logic mem_wb_reg_clr;

    logic id_exe_reg_en;
    logic exe_mem_reg_en;
    logic mem_wb_reg_en;
    logic pc_reg_en;

    // inst mem access
    logic [31:0] current_pc_if;
    logic [31:0] inst_if;

    logic mem_to_reg_mem;

    logic inst_valid_wb;
    logic [31:0] cinst_pc;

    logic dbg_ret;


    assign current_pc = current_pc_if;
    assign inst_if = inst;

    // dbg
    logic [31:0] dbg_gpr_rdata;
    logic [31:0] dbg_csr_result;
    logic [31:0] next_pc_if1;
    logic        ebreak_inst_mem;
    logic        dont_trap;
    logic        inst_fetch_stall_ff;

    logic        load_hazard;
    logic        mul_hazard;

    logic        stall_pipl;


`ifdef tracer
     logic [31:0] rvfi_insn;
     logic [4:0]  rvfi_rs1_addr;
     logic [4:0]  rvfi_rs2_addr;
     logic [31:0] rvfi_rs1_rdata;
     logic [31:0] rvfi_rs2_rdata;
     logic [4:0]  rvfi_rd_addr;
     logic [31:0] rvfi_rd_wdata;
     logic [31:0] rvfi_pc_rdata;
     logic [31:0] rvfi_pc_wdata;
     logic [31:0] rvfi_mem_addr;
     logic [31:0] rvfi_mem_wdata;
     logic [31:0] rvfi_mem_rdata;
     logic        rvfi_valid;

    logic tracer_aggregate;

     assign tracer_aggregate = ^{rvfi_insn,
     rvfi_rs1_addr,
     rvfi_rs2_addr,
     rvfi_rs1_rdata,
     rvfi_rs2_rdata,
     rvfi_rd_addr,
     rvfi_rd_wdata,
     rvfi_pc_rdata,
     rvfi_pc_wdata,
     rvfi_mem_addr,
     rvfi_mem_wdata,
     rvfi_mem_rdata,
     rvfi_valid};

`endif


    data_path #(
        .DMEM_DEPTH(DMEM_DEPTH),
        .IMEM_DEPTH(IMEM_DEPTH)
    ) data_path_inst (
        .*
    );

    control_unit controller_inst(
        .*
    );

    assign mem_read_mem = mem_to_reg_mem;


    // TODO
    // FIXME
    
    logic [31:0] dcsr, dpc;
    core_dbg_fsm u_core_dbg_fsm (
        .clk_i             (clk),
        .reset_i           (~reset_n),
        .ebreak_inst_mem   (ebreak_inst_mem),
        .dbg_resumereq_i   (dbg_resumereq),
        .dbg_haltreq_i     (dbg_haltreq),
        .core_resumeack_o  (core_resumeack),
        .core_running_o    (core_running),
        .core_halted_o     (core_halted),
        .dont_trap         (dont_trap),
        .cinst_pc          (cinst_pc),
        .next_pc_if1       (next_pc_if1),
        .dbg_ret           (dbg_ret),
        .trap              (trap),
        .trap_ret          (trap_ret),
        .inst_valid_wb     (inst_valid_wb),

        .dcsr_o            (dcsr),
        .dpc_o             (dpc),

        // abstract register access interface
        .dbg_ar_en         (dbg_ar_en),
        .dbg_ar_wr         (dbg_ar_wr),
        .dbg_ar_ad         (dbg_ar_ad),
        .dbg_ar_do         (dbg_ar_do)
    );

    always_comb begin 
        if(dbg_ar_ad < 32'h1000)
            case(dbg_ar_ad)
                16'h07b0: dbg_ar_di = dcsr;
                16'h07b1: dbg_ar_di = dpc;
                default:  dbg_ar_di = dbg_csr_result;
            endcase
        else if(dbg_ar_ad >= 32'h1000 && dbg_ar_ad <= 32'h101f)
             dbg_ar_di = dbg_gpr_rdata;
    `ifdef tracer
        else dbg_ar_di = {31'd0,tracer_aggregate};
    `else
        else dbg_ar_di = 'd0;
    `endif
    end
    assign dbg_ar_done = dbg_ar_en;


    always_comb begin 
        if(mem_write_mem | mem_read_mem) begin 
            stall_pipl = ~mem_ack_mem;
        end else begin
            stall_pipl = 1'b0;
        end
    end

    assign illegal_inst = illegal_inst_id;

endmodule   
