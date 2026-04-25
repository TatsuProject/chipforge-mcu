module hazard_controller (
    input wire pc_sel_mem,
    input wire exe_use_rs1_id,
    input wire exe_use_rs2_id,
    input wire [4:0] rs1_id,
    input wire [4:0] rs2_id,
    input wire [4:0] rs1_exe,
    input wire [4:0] rs2_exe,
    input wire mem_read_exe,
    input wire [4:0] rd_exe,
    input wire [4:0] rd_mem,
    input wire is_atomic_mem,
    input wire atomic_unit_stall,
    input wire is_mul_exe,

    // FP extension hazard inputs (Challenge 0013, Strategy #1+)
    // 4-stage FP: producer stalls dependent consumer while in EX, MEM *or* WB.
    // When the producer reaches WB+1 its result is flopped in fpu_unit and
    // being written to the reg_file same cycle; reg_file bypass makes it
    // visible to a consumer at ID, so no stall is needed at WB+1.
    input wire [4:0] rd_wb,
    input wire is_fp_multicycle_exe,
    input wire fp_reg_write_exe,
    input wire fp_wb_to_int_exe,
    input wire is_fp_multicycle_mem,
    input wire fp_reg_write_mem,
    input wire fp_wb_to_int_mem,
    input wire is_fp_multicycle_wb,
    input wire fp_reg_write_wb,
    input wire fp_wb_to_int_wb,
    input wire fp_uses_rs1_id,
    input wire fp_uses_rs2_id,

    output wire load_hazard,
    output wire branch_hazard,
    output wire atomic_unit_hazard,
    output wire mul_hazard,
    output wire fp_hazard
);

    assign branch_hazard        = pc_sel_mem;
    assign load_hazard          =   (mem_read_exe  &  (rd_exe !=0))
                                &   (((rd_exe == rs1_id) & exe_use_rs1_id) | ((rd_exe == rs2_id) & exe_use_rs2_id));

    assign atomic_unit_hazard   =   (is_atomic_mem  &  ~atomic_unit_stall & (rd_mem !=0))
                                &   ((rd_mem == rs2_exe) | (rd_mem == rs1_exe));

    assign mul_hazard           =   (( is_mul_exe) & (rd_exe !=0))
                                &   (((rd_exe == rs1_id) & exe_use_rs1_id) | ((rd_exe == rs2_id) & exe_use_rs2_id));

    // FP hazard — producer in EX, MEM or WB stalls dependent consumer in ID.
    wire fp_hazard_exe_fp  = fp_reg_write_exe  & (((rd_exe == rs1_id) & fp_uses_rs1_id)
                                              |   ((rd_exe == rs2_id) & fp_uses_rs2_id));
    wire fp_hazard_exe_int = fp_wb_to_int_exe  & (rd_exe != 0)
                                              & (((rd_exe == rs1_id) & exe_use_rs1_id)
                                              |   ((rd_exe == rs2_id) & exe_use_rs2_id));
    wire fp_hazard_mem_fp  = fp_reg_write_mem  & (((rd_mem == rs1_id) & fp_uses_rs1_id)
                                              |   ((rd_mem == rs2_id) & fp_uses_rs2_id));
    wire fp_hazard_mem_int = fp_wb_to_int_mem  & (rd_mem != 0)
                                              & (((rd_mem == rs1_id) & exe_use_rs1_id)
                                              |   ((rd_mem == rs2_id) & exe_use_rs2_id));
    wire fp_hazard_wb_fp   = fp_reg_write_wb   & (((rd_wb  == rs1_id) & fp_uses_rs1_id)
                                              |   ((rd_wb  == rs2_id) & fp_uses_rs2_id));
    wire fp_hazard_wb_int  = fp_wb_to_int_wb   & (rd_wb  != 0)
                                              & (((rd_wb  == rs1_id) & exe_use_rs1_id)
                                              |   ((rd_wb  == rs2_id) & exe_use_rs2_id));

    assign fp_hazard = (is_fp_multicycle_exe & (fp_hazard_exe_fp | fp_hazard_exe_int))
                     | (is_fp_multicycle_mem & (fp_hazard_mem_fp | fp_hazard_mem_int))
                     | (is_fp_multicycle_wb  & (fp_hazard_wb_fp  | fp_hazard_wb_int));

endmodule : hazard_controller
