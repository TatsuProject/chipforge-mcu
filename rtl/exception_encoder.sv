module exception_encoder (
    input  logic ecall,
    input  logic ebreak,
    input  logic inst_addr_malign,
    input  logic inst_access_fault,
    input  logic load_addr_malign,
    input  logic load_access_fault,
    input  logic store_amo_addr_malign,
    input  logic store_amo_access_fault,
    input  logic illegal_inst,

    input  logic [31:0] faulting_lsu_addr,   // address that caused access fault/misalignment
    input  logic [31:0] faulting_inst_addr,   // address that caused access fault/misalignment
    input  logic [31:0] faulting_instr,     // illegal instruction / ebreak instruction

    output logic exception_o,
    output logic [4:0] exception_code_o,
    output logic [31:0] mtval_value_o       // value to write to mtval CSR
);

    // RISC-V exception codes from privileged spec
    localparam logic [4:0] EXC_INST_ADDR_MISALIGNED      = 5'd0;
    localparam logic [4:0] EXC_INST_ACCESS_FAULT         = 5'd1;
    localparam logic [4:0] EXC_ILLEGAL_INSTRUCTION       = 5'd2;
    localparam logic [4:0] EXC_BREAKPOINT                = 5'd3;
    localparam logic [4:0] EXC_LOAD_ADDR_MISALIGNED      = 5'd4;
    localparam logic [4:0] EXC_LOAD_ACCESS_FAULT         = 5'd5;
    localparam logic [4:0] EXC_STORE_AMO_ADDR_MISALIGNED = 5'd6;
    localparam logic [4:0] EXC_STORE_AMO_ACCESS_FAULT    = 5'd7;
    localparam logic [4:0] EXC_ECALL_MMODE               = 5'd11;

    // Exception code encoding (priority-based)
    always_comb begin
        unique case (1'b1)
            inst_addr_malign:           exception_code_o = EXC_INST_ADDR_MISALIGNED;
            inst_access_fault:          exception_code_o = EXC_INST_ACCESS_FAULT;
            illegal_inst:               exception_code_o = EXC_ILLEGAL_INSTRUCTION;
            ebreak:                     exception_code_o = EXC_BREAKPOINT;
            load_addr_malign:          exception_code_o = EXC_LOAD_ADDR_MISALIGNED;
            load_access_fault:         exception_code_o = EXC_LOAD_ACCESS_FAULT;
            store_amo_addr_malign:     exception_code_o = EXC_STORE_AMO_ADDR_MISALIGNED;
            store_amo_access_fault:    exception_code_o = EXC_STORE_AMO_ACCESS_FAULT;
            ecall:                     exception_code_o = EXC_ECALL_MMODE;
            default:                   exception_code_o = 5'd0;
        endcase
    end

    // Global exception signal
    assign exception_o = inst_addr_malign
                       | inst_access_fault
                       | illegal_inst
                       | ebreak
                       | load_addr_malign
                       | load_access_fault
                       | store_amo_addr_malign
                       | store_amo_access_fault
                       | ecall;

    // mtval value generation based on exception type
    always_comb begin
        mtval_value_o = 32'b0;
        unique case (1'b1)
            inst_addr_malign,
            inst_access_fault:         mtval_value_o = faulting_inst_addr;

            illegal_inst,
            ecall,                     
            ebreak:                    mtval_value_o = faulting_instr;

            load_addr_malign,
            load_access_fault,
            store_amo_addr_malign,
            store_amo_access_fault:    mtval_value_o = faulting_lsu_addr;

            default:                   mtval_value_o = 32'b0;
        endcase
    end


endmodule
