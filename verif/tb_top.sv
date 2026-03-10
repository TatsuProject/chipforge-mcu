/*
module rv32i_top(
  input         clk_i,
  input         resetn_i,
  output        illegal_inst_o,
  output [31:0] imem_addr_o,
  input  [31:0] imem_inst_i,
  output [31:0] mem_addr_o,
  output [31:0] mem_dat_o,
  input  [31:0] mem_dat_i,
  output        mem_write_o,
  output [3:0]  mem_wstrb_o,
  output        mem_read_o,
  input         mem_ack_i
);

*/

module tb_top;


logic        clk = 0; 
logic        reset_n; 
logic [31:0] imem_addr;
logic [31:0] imem_inst;
logic [31:0] mem_addr;
logic [31:0] mem_wdata;
logic [31:0] mem_rdata;
logic        mem_write;
logic [3:0]  mem_wstrb;
logic        mem_read;
logic        mem_ack;

logic        illegal_inst;

rv32imc_top DUT (
  .clk_i(clk),
  .resetn_i(reset_n),
  .illegal_inst_o(illegal_inst),
  .imem_addr_o(imem_addr),
  .imem_inst_i(imem_inst),
  .mem_addr_o(mem_addr),
  .mem_dat_o(mem_wdata),
  .mem_dat_i(mem_rdata),
  .mem_write_o(mem_write),
  .mem_wstrb_o(mem_wstrb),
  .mem_read_o(mem_read),
  .mem_ack_i(mem_ack)
);


imem imem_instance (
    .clk(clk),
    .addr(imem_addr),
    .inst(imem_inst)
);

dmem dmem_inst (
    .clk(clk),
    .reset_n(reset_n),
    .addr(mem_addr),
    .wstrb(mem_wstrb),
    .write_en(mem_write),
    .read_en(mem_read),
    .rdata(mem_rdata),
    .wdata(mem_wdata),
    .ack(mem_ack)
);


// clk and reset generation 

always #5 clk = ~clk; // 100 MHz clock

initial begin
    reset_n = 0;
    repeat(2) @(negedge clk);
    reset_n = 1;
end


// Dump file and ending the simulation conditionally 

initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
end

initial begin

    fork
    begin
           wait(illegal_inst); // wait for any unknown inst
    end
    begin
        repeat(100000) begin
            @(posedge clk);
        end
    end
    join_any

    repeat(5) begin
        @(posedge clk);
    end

    $finish;
end

endmodule