module pipeline_controller (
    input logic load_hazard,
    input logic branch_hazard,
    input logic stall_pipl,
    input logic atomic_unit_stall,
    input logic atomic_unit_hazard,
    input logic mul_hazard,
    input logic div_busy,
    input logic trap,
    input logic trap_ret,
    input logic core_halted,
    input logic core_running,
    input logic dbg_ret,
    input logic inst_fetch_stall,
    input logic inst_fetch_stall_ff,

    output logic if_id_reg_clr, 
    output logic id_exe_reg_clr,
    output logic exe_mem_reg_clr,
    output logic mem_wb_reg_clr,

    output logic if_id_reg_en, 
    output logic id_exe_reg_en,
    output logic exe_mem_reg_en,
    output logic mem_wb_reg_en,
    output logic pc_reg_en
);

    assign if_id_reg_clr   = dbg_ret | core_halted | branch_hazard |                                                  trap | trap_ret | inst_fetch_stall_ff;
    assign id_exe_reg_clr  =           core_halted | branch_hazard | (exe_mem_reg_en & (load_hazard | mul_hazard))  | trap | trap_ret;
    assign exe_mem_reg_clr =           core_halted | branch_hazard |                                                | trap | trap_ret;
    assign mem_wb_reg_clr  =           core_halted |                                                                | trap | trap_ret; 

    assign if_id_reg_en   =  core_running & ~( div_busy   | stall_pipl | (load_hazard | mul_hazard) |                    | atomic_unit_stall | inst_fetch_stall_ff); // TODO. (core_halted) no need to disable enable when clearing
    assign id_exe_reg_en  =  core_running & ~( div_busy   | stall_pipl |                                                 | atomic_unit_stall);
    assign exe_mem_reg_en =  core_running & ~( div_busy   | stall_pipl |                                                 | atomic_unit_stall);
    assign mem_wb_reg_en  =  core_running & ~( div_busy   | stall_pipl |                                                 | atomic_unit_stall);
    assign pc_reg_en      =  core_running & ~( div_busy   | stall_pipl | (load_hazard | mul_hazard) |                    | atomic_unit_stall | inst_fetch_stall);

endmodule 