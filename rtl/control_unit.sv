`default_nettype wire
module control_unit(
    input logic [6:0] opcode_id,
    input logic [6:0] fun7_id,         // F-extension decode inputs
    input logic [2:0] fun3_id,
    input logic [6:0] fun7_exe,
    input logic [2:0] fun3_exe, fun3_mem,
    input logic zero_mem,
    input logic [1:0] alu_op_exe,
    input logic jump_mem,
    input logic branch_mem,

    // outputs from the decode controller
    output logic reg_write_id,
    output logic mem_write_id,
    output logic mem_to_reg_id,
    output logic branch_id,
    output logic alu_src_id,
    output logic jump_id,
    output logic lui_id,
    output logic auipc_id,
    output logic jal_id,
    output logic r_type_id,
    output logic [1:0] alu_op_id,
    output logic sys_inst_id,
    output logic is_atomic_id,
    output logic illegal_inst_id,

    // F-extension decode outputs (Challenge 0013)
    output logic       is_fp_id,
    output logic       fp_reg_write_id,
    output logic       fp_wb_to_int_id,
    output logic       fp_uses_rs1_id,
    output logic       fp_uses_rs2_id,
    output logic [4:0] fpu_op_id,
    output logic [2:0] fp_rm_id,


    // alu_controller output
    output [9:0] alu_ctrl_exe,

    // branch controller output 
    output wire pc_sel_mem,

    // forwarding unit stuff
    input wire [4:0] rs1_id,
    input wire [4:0] rs2_id,
    input wire [4:0] rs1_exe,
    input wire [4:0] rs2_exe,
    input wire [4:0] rs2_mem,
    input wire [4:0] rd_mem,
    input wire [4:0] rd_wb,
    input wire reg_write_mem,
    input wire reg_write_wb,

    output wire forward_rd1_id,
    output wire forward_rd2_id,
    output wire [1:0] forward_rd1_exe,
    output wire [1:0] forward_rd2_exe,
    output wire forward_rd2_mem,


    // hazard handler data required from the data path
    input wire mem_to_reg_exe,
    input wire [4:0] rd_exe,

    // signals to control the flow of the pipeline
    output logic if_id_reg_clr, 
    output logic id_exe_reg_clr,
    output logic exe_mem_reg_clr,
    output logic mem_wb_reg_clr,

    output logic if_id_reg_en, 
    output logic id_exe_reg_en,
    output logic exe_mem_reg_en,
    output logic mem_wb_reg_en,
    output logic pc_reg_en,

    input  logic stall_pipl,
    input  logic trap,
    input  logic trap_ret,
    input  logic atomic_unit_stall,
    input  logic is_atomic_mem,
    input  logic is_mul_exe,
    input  logic div_busy,
    input  logic core_halted,
    input  logic core_running,
    input  logic dbg_ret,

    // F extension pipelining (Challenge 0013, 4-stage FPU)
    input  logic is_fp_multicycle_exe,
    input  logic fp_reg_write_exe,
    input  logic fp_wb_to_int_exe,
    input  logic is_fp_multicycle_mem,
    input  logic fp_reg_write_mem,
    input  logic fp_wb_to_int_mem,
    input  logic is_fp_multicycle_wb,
    input  logic fp_reg_write_wb,
    input  logic fp_wb_to_int_wb,

    input  logic inst_fetch_stall,
    input  logic inst_fetch_stall_ff,
    output logic load_hazard,
    output logic mul_hazard,
    output logic fp_hazard
);

    decode_control dec_ctrl_inst (
        .opcode      (opcode_id),
        .funct7      (fun7_id),
        .funct3      (fun3_id),
        .rs2_field   (rs2_id),     // reuse forwarding-unit input (inst[24:20])
        .reg_write   (reg_write_id),
        .mem_write   (mem_write_id),
        .mem_to_reg  (mem_to_reg_id),
        .branch      (branch_id),
        .alu_src     (alu_src_id),
        .jump        (jump_id),
        .alu_op      (alu_op_id),
        .lui         (lui_id),
        .auipc       (auipc_id),
        .jal         (jal_id),
        .r_type      (r_type_id),
        .sys_inst    (sys_inst_id),
        .is_atomic   (is_atomic_id),
        .illegal_inst(illegal_inst_id),
        // F extension
        .is_fp       (is_fp_id),
        .fp_reg_write(fp_reg_write_id),
        .fp_wb_to_int(fp_wb_to_int_id),
        .fp_uses_rs1 (fp_uses_rs1_id),
        .fp_uses_rs2 (fp_uses_rs2_id),
        .fpu_op      (fpu_op_id),
        .fp_rm       (fp_rm_id)
    );

    wire exe_use_rs1_id;
    wire exe_use_rs2_id;

    assign exe_use_rs1_id = ~(auipc_id | lui_id);
    assign exe_use_rs2_id = r_type_id | branch_id | is_atomic_id;

    alu_control alu_controller_inst (
        .fun3(fun3_exe),
        .fun7(fun7_exe),
        .rs2(rs2_exe),
        .alu_op(alu_op_exe),
        .alu_ctrl(alu_ctrl_exe)
    );

    branch_controller branch_controller_inst (
        .fun3(branch_t'(fun3_mem)),
        .branch(branch_mem),
        .jump(jump_mem),
        .zero(zero_mem),
        .pc_sel(pc_sel_mem)
    );

    // 
    forwarding_unit forwarding_unit_inst(
        .*
    );

    // detect if there is load hazard
    wire branch_hazard;
    wire atomic_unit_hazard;
    logic mem_read_exe;
    assign mem_read_exe = mem_to_reg_exe;
    
    hazard_controller hazard_handler_inst (
        .*
    );

    pipeline_controller pipeline_controller_inst(
        .*
    );

endmodule
