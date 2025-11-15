import riscv_types::*;
module wishbone_controller (  // combinational controller
    // from the processor
    input  wire [31:0]  proc_addr,     // Processor address
    input  wire [31:0]  proc_wdata,    // Processor write data
    input  wire         proc_write,    // Processor write enable
    input  wire         proc_read,     // Processor write enable
    input  wire [2:0]   proc_op,       // Processor operation
    // to the processor
    output wire  [31:0] proc_rdata,    // Processor read data
    output logic        proc_ack,
    output logic        proc_stall_pipl,
    // to the memory 
    output wire [31:0] mem_addr_o, 
    output wire [31:0] mem_dat_o, 
    output wire [3:0]  mem_wstrb_o, 
    output wire        mem_write_o, 
    output wire        mem_read_o,
    // from the memory
    input wire         mem_ack_i, 
    input wire         mem_dat_i
);

   
    // assign core_wb_dat_o = proc_wdata;
    store_aligner store_alignment_unit(
        .wdata(proc_wdata),
        .store_type(store_t'(proc_op)),
        .addr(mem_addr_o[1:0]),
        .mem_write(proc_write),
        .wsel(mem_wstrb_o),
        .aligned_data(mem_dat_o)
    );


    // assign proc_rdata = core_wb_dat_i;
    load_aligner load_alignment_unit (
        .addr(mem_addr_o[1:0]),
        .fun3(proc_op),
        .rdata(mem_dat_i),
        .aligned_data(proc_rdata)
    );

    assign mem_addr_o      = proc_addr;
    assign mem_read_o      = proc_read;
    assign mem_write_o     = proc_write;
    assign proc_ack        = mem_ack_i;
    assign proc_stall_pipl = (proc_read | proc_write) & ~mem_ack_i;


endmodule
