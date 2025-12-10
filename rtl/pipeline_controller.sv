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

    // Simplified pipeline control - reduce area
    logic critical_clear, common_stall, data_hazard;
    // logic common_stall_or_data_hazard;

    assign critical_clear = trap | trap_ret | core_halted;
    assign common_stall = div_busy | stall_pipl | atomic_unit_stall;
    assign data_hazard = load_hazard | mul_hazard;

    // assign if_id_reg_clr   = critical_clear | dbg_ret | branch_hazard | inst_fetch_stall_ff;
    
    assign exe_mem_reg_clr = critical_clear  | branch_hazard;
    
    // assign if_id_reg_clr   = critical_clear | branch_hazard | dbg_ret | inst_fetch_stall_ff; 
    // assign id_exe_reg_clr  = critical_clear | branch_hazard | (exe_mem_reg_en & data_hazard);
    
    assign if_id_reg_clr   = exe_mem_reg_clr | dbg_ret | inst_fetch_stall_ff;
    assign id_exe_reg_clr  = exe_mem_reg_clr | (id_exe_reg_en & data_hazard);

    assign mem_wb_reg_clr  = critical_clear;

    // assign common_stall_or_data_hazard = common_stall | data_hazard;

    assign if_id_reg_en   = core_running & ~(common_stall | data_hazard | inst_fetch_stall_ff);
    assign pc_reg_en      = core_running & ~(common_stall | data_hazard | inst_fetch_stall);

    // assign if_id_reg_en   = core_running & ~(common_stall_or_data_hazard | inst_fetch_stall_ff);
    // assign pc_reg_en      = core_running & ~(common_stall_or_data_hazard | inst_fetch_stall);

    assign id_exe_reg_en  = core_running & ~common_stall;
    assign exe_mem_reg_en = id_exe_reg_en;
    assign mem_wb_reg_en  = id_exe_reg_en;

endmodule 