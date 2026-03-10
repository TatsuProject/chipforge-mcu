
/*
imem imem_inst (
    .addr(imem_addr),
    .inst(imem_inst)
);
*/
module imem #(
    parameter IMEM_DEPTH = 32*256
)(
    input logic clk, 
    input logic [31:0] addr,
    output logic [31:0] inst
);

logic [31:0] imem [0:IMEM_DEPTH-1];

always_ff @(posedge clk) begin
    inst <= imem[addr >> 2];
end

// initialize the imem using imem.mem file
initial begin
    `ifdef verilator
        $readmemh("imem.mem", imem);
    `else 
        $readmemh("imem.mem", imem);
    `endif
end

endmodule
