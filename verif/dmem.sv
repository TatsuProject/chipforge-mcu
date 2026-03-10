/*
dmem dmem_inst (
    .clk(clk),
    .reset_n(reset_n),
    .addr(mem_addr),
    .wdata(mem_dat),
    .wstrb(mem_wstrb),
    .write_en(mem_write),
    .read_en(mem_read),
    .rdata(mem_rdata),
    .wdata(mem_wdata),
    .ack(mem_ack)
);

*/

module dmem #(
    parameter DMEM_DEPTH = 32*256
)(
    input logic clk,
    input logic reset_n,
    input logic [31:0] addr,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    input logic write_en,
    input logic read_en,
    output logic [31:0] rdata,
    output logic ack
);

logic [31:0] dmem [0:DMEM_DEPTH-1];

always_ff @(posedge clk) begin
    if (write_en) begin
        if (wstrb[0]) dmem[addr[31:2]][7:0] <= wdata[7:0];
        if (wstrb[1]) dmem[addr[31:2]][15:8] <= wdata[15:8];
        if (wstrb[2]) dmem[addr[31:2]][23:16] <= wdata[23:16];
        if (wstrb[3]) dmem[addr[31:2]][31:24] <= wdata[31:24];
    end
    if (read_en) begin
        rdata <= dmem[addr[31:2]];
    end
end

// acknowledge the transaction
always_ff @(posedge clk, negedge reset_n) begin
    if(~reset_n) begin
        ack <= 1'b0;
    end else begin
        ack <= (write_en | read_en) & ~ack;
    end
end

// initialize the memory using dmem.mem
initial begin
    `ifdef verilator
        $readmemh("dmem.mem", dmem);
    `else 
        $readmemh("dmem.mem", dmem);
    `endif
end


endmodule
