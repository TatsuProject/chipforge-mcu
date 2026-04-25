
/*
input logic clk_i – clock input
input logic resetn_i – active-low reset
output logic illegal_inst-o - should get asserted for any unknown instruction
output logic [31:0] imem_addr_o – instruction memory address output
input logic [31:0] imem_inst_i – instruction memory data input
output logic [31:0] mem_addr_o – data memory address output
output logic [31:0] mem_dat_o – data memory write data output
input logic [31:0] mem_dat_i – data memory read data input
output logic mem_write_o – memory write enable
output logic mem_wstrb_o – memory write strobe output
output logic mem_read_o – memory read enable
input logic mem_ack_i – memory acknowledge (indicates readiness of memory data transfer)
*/
module core_top(
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


   rv32i rv32i_inst (
    .clk(clk_i),
    .reset_n(resetn_i),
    .mem_addr_mem(mem_addr_o),
    .mem_wdata_mem(mem_dat_o),
    .mem_rdata_mem(mem_dat_i),
    .mem_write_mem(mem_write_o),
    .mem_wstrb_mem(mem_wstrb_o),
    .mem_read_mem(mem_read_o),
    .mem_ack_mem(mem_ack_i),
    .mem_err_mem(1'b0),
    .current_pc(imem_addr_o),
    .inst(imem_inst_i),
    .illegal_inst(illegal_inst_o),

    .timer_irq(1'b0),
    .external_irq(1'b0),

    .core_resumeack(),
    .core_running(),
    .core_halted(),

    .dbg_haltreq(1'b0),
    .dbg_resumereq(1'b0),
    .dbg_ar_en(1'b0),
    .dbg_ar_wr(1'b0),
    .dbg_ar_ad(16'h0),
    .dbg_ar_do(32'h0),
    .dbg_ar_di(),
    .dbg_ar_done(),
    .inst_fetch_stall(1'b0)
);

endmodule

// Thin wrapper so the local testbench (verif/tb_top.sv) — which instantiates
// rv32imc_top — can still elaborate. Submission top remains core_top.
module rv32imc_top(
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

  core_top u_core_top (
    .clk_i          (clk_i),
    .resetn_i       (resetn_i),
    .illegal_inst_o (illegal_inst_o),
    .imem_addr_o    (imem_addr_o),
    .imem_inst_i    (imem_inst_i),
    .mem_addr_o     (mem_addr_o),
    .mem_dat_o      (mem_dat_o),
    .mem_dat_i      (mem_dat_i),
    .mem_write_o    (mem_write_o),
    .mem_wstrb_o    (mem_wstrb_o),
    .mem_read_o     (mem_read_o),
    .mem_ack_i      (mem_ack_i)
  );

endmodule
