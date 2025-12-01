module lsu (
    input         clk,
    input         rst,

    input logic core_halted,
    // Inputs from MEM stage
    input         is_atomic_mem,          // Is this an atomic instruction?
    input  [4:0]  amo_funct5_mem,         // AMO funct5 field (from funct7[6:2])
    input  [31:0] rs2_val_mem,            // rs2 value (for SC and AMOs)
    input         mem_read_req,           // read enable from MEM stage
    input         mem_write_req,          // write enable from MEM stage
    input  [31:0] mem_addr_req,           // address from MEM stage
    input  [31:0] mem_wdata_req,          // write data from MEM stage
    input  [2:0]  mem_op_mem,

    output logic [31:0] mem_rdata_aligned,

    // Interface to memory bus or Wishbone controller
    output wire         mem_read,
    output wire         mem_write,
    output wire [31:0]  mem_addr,
    output wire [31:0]  mem_wdata,
    output wire [3:0]   mem_wstrb,
    input  wire [31:0]  mem_rdata,
    input  wire         mem_ack,
    input  wire         mem_err,
    // Output to pipeline
    output wire         stall_mem,
    output wire [31:0]  result_rd,         // Data to write back to rd

    // Memory Access exceptions 
    output wire load_addr_malign,
    output wire store_amo_addr_malign,
    output wire load_access_fault,
    output wire store_amo_access_fault
);


    // assign core_wb_dat_o = proc_wdata;
    store_aligner store_alignment_unit(
        .wdata(mem_wdata_req),
        .store_type(store_t'(mem_op_mem)),
        .addr(mem_addr[1:0]),
        .mem_write(mem_write),
        .wsel(mem_wstrb),
        .aligned_data(mem_wdata)
    );

    // assign proc_rdata = core_wb_dat_i;
    load_aligner load_alignment_unit (
        .addr(mem_addr[1:0]),
        .fun3(mem_op_mem),
        .rdata(mem_rdata),
        .aligned_data(mem_rdata_aligned)
    );



    // mem_controller mem_controller_inst (
    //     .clk(clk),
    //     .rst(rst),
    //     .core_halted(core_halted),
    //     .is_atomic_mem(is_atomic_mem),
    //     .amo_funct5_mem(amo_funct5_mem),
    //     .rs2_val_mem(rs2_val_mem),
    //     .mem_read_req(mem_read_req),
    //     .mem_write_req(mem_write_req),
    //     .mem_addr_req(mem_addr_req),
    //     .mem_wdata_req(mem_wdata_req),
    //     .mem_op_mem(mem_op_mem),
    //     .mem_read(mem_read),
    //     .mem_write(mem_write),
    //     .mem_addr(mem_addr),
    //     .mem_wdata(mem_wdata_unaligned),
    //     .mem_rdata(mem_rdata_aligned),
    //     .mem_ack(mem_ack),
    //     .mem_err(mem_err)
    //     // .stall_mem(stall_mem),
    //     // .result_rd(result_rd),
    //     // .load_addr_malign(load_addr_malign),
    //     // .store_amo_addr_malign(store_amo_addr_malign),
    //     // .load_access_fault(load_access_fault),
    //     // .store_amo_access_fault(store_amo_access_fault)
    // );


    assign mem_write              = mem_write_req;
    assign mem_read               = mem_read_req;
    assign mem_addr               = mem_addr_req;
    

    assign stall_mem              = 'b0;
    assign result_rd              = 'b0;
    assign load_addr_malign       = 1'b0;
    assign store_amo_addr_malign  = 1'b0;
    assign load_access_fault      = 1'b0;
    assign store_amo_access_fault = 1'b0;

endmodule