`timescale 1 ns / 1 ps

// Enable RISCV_FORMAL when tracer is enabled
`ifdef tracer
`define RISCV_FORMAL
`endif

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

    wire        mem_valid;
    wire        mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;
    wire        trap;

    // Look-ahead memory interface signals
    wire        mem_la_read;
    wire        mem_la_write;
    wire [31:0] mem_la_addr;
    wire [31:0] mem_la_wdata;
    wire [ 3:0] mem_la_wstrb;

    reg mem_state;

`ifdef tracer
    // RVFI signals for tracing
    wire        rvfi_valid;
    wire [63:0] rvfi_order;
    wire [31:0] rvfi_insn;
    wire        rvfi_trap;
    wire        rvfi_halt;
    wire        rvfi_intr;
    wire [ 1:0] rvfi_mode;
    wire [ 1:0] rvfi_ixl;
    wire [ 4:0] rvfi_rs1_addr;
    wire [ 4:0] rvfi_rs2_addr;
    wire [31:0] rvfi_rs1_rdata;
    wire [31:0] rvfi_rs2_rdata;
    wire [ 4:0] rvfi_rd_addr;
    wire [31:0] rvfi_rd_wdata;
    wire [31:0] rvfi_pc_rdata;
    wire [31:0] rvfi_pc_wdata;
    wire [31:0] rvfi_mem_addr;
    wire [ 3:0] rvfi_mem_rmask;
    wire [ 3:0] rvfi_mem_wmask;
    wire [31:0] rvfi_mem_rdata;
    wire [31:0] rvfi_mem_wdata;
`endif

    picorv32 #(
        .ENABLE_COUNTERS(1),
        .ENABLE_COUNTERS64(0),
        .ENABLE_REGS_16_31(1),
        .ENABLE_REGS_DUALPORT(1),
        .LATCHED_MEM_RDATA(0),
        .TWO_STAGE_SHIFT(1),
        .BARREL_SHIFTER(0),
        .TWO_CYCLE_COMPARE(0),
        .TWO_CYCLE_ALU(0),
        .COMPRESSED_ISA(0),
        .CATCH_MISALIGN(1),
        .CATCH_ILLINSN(1),
        .ENABLE_PCPI(0),
        .ENABLE_MUL(0),
        .ENABLE_FAST_MUL(0),
        .ENABLE_DIV(0),
        .ENABLE_IRQ(0),
        .ENABLE_IRQ_QREGS(0),
        .ENABLE_IRQ_TIMER(0),
        .ENABLE_TRACE(0),
        .REGS_INIT_ZERO(1),
        .PROGADDR_RESET(32'h8000_0000),
        .PROGADDR_IRQ(32'h0000_0010),
        .STACKADDR(32'hffff_ffff)
    ) cpu (
        .clk(clk_i),
        .resetn(resetn_i),
        .trap(trap),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),
        .mem_la_read(mem_la_read),
        .mem_la_write(mem_la_write),
        .mem_la_addr(mem_la_addr),
        .mem_la_wdata(mem_la_wdata),
        .mem_la_wstrb(mem_la_wstrb),
        .pcpi_valid(),
        .pcpi_insn(),
        .pcpi_rs1(),
        .pcpi_rs2(),
        .pcpi_wr(1'b0),
        .pcpi_rd(32'b0),
        .pcpi_wait(1'b0),
        .pcpi_ready(1'b0),
        .irq(32'b0),
        .eoi(),
        .trace_valid(),
        .trace_data()
`ifdef tracer
        ,
        .rvfi_valid(rvfi_valid),
        .rvfi_order(rvfi_order),
        .rvfi_insn(rvfi_insn),
        .rvfi_trap(rvfi_trap),
        .rvfi_halt(rvfi_halt),
        .rvfi_intr(rvfi_intr),
        .rvfi_mode(rvfi_mode),
        .rvfi_ixl(rvfi_ixl),
        .rvfi_rs1_addr(rvfi_rs1_addr),
        .rvfi_rs2_addr(rvfi_rs2_addr),
        .rvfi_rs1_rdata(rvfi_rs1_rdata),
        .rvfi_rs2_rdata(rvfi_rs2_rdata),
        .rvfi_rd_addr(rvfi_rd_addr),
        .rvfi_rd_wdata(rvfi_rd_wdata),
        .rvfi_pc_rdata(rvfi_pc_rdata),
        .rvfi_pc_wdata(rvfi_pc_wdata),
        .rvfi_mem_addr(rvfi_mem_addr),
        .rvfi_mem_rmask(rvfi_mem_rmask),
        .rvfi_mem_wmask(rvfi_mem_wmask),
        .rvfi_mem_rdata(rvfi_mem_rdata),
        .rvfi_mem_wdata(rvfi_mem_wdata)
`endif
    );

`ifdef tracer
    // Instantiate the tracer
    tracer tracer_inst (
        .clk_i(clk_i),
        .rst_ni(resetn_i),
        .hart_id_i(32'h00000001),
        .rvfi_valid(rvfi_valid),
        .rvfi_insn_t(rvfi_insn),
        .rvfi_rs1_addr_t(rvfi_rs1_addr),
        .rvfi_rs2_addr_t(rvfi_rs2_addr),
        .rvfi_rs3_addr_t(5'b0),
        .rvfi_rs1_rdata_t(rvfi_rs1_rdata),
        .rvfi_rs2_rdata_t(rvfi_rs2_rdata),
        .rvfi_rs3_rdata_t(32'b0),
        .rvfi_rd_addr_t(rvfi_rd_addr),
        .rvfi_rd_wdata_t(rvfi_rd_wdata),
        .rvfi_pc_rdata_t(rvfi_pc_rdata),
        .rvfi_pc_wdata_t(rvfi_pc_wdata),
        .rvfi_mem_addr(rvfi_mem_addr),
        .rvfi_mem_rmask(rvfi_mem_rmask),
        .rvfi_mem_wmask(rvfi_mem_wmask),
        .rvfi_mem_rdata(rvfi_mem_rdata),
        .rvfi_mem_wdata(rvfi_mem_wdata)
    );
`endif

    // Split unified memory interface into instruction and data
    // Use look-ahead address for instruction memory to compensate for 1-cycle delay
    // Translate 0x8000xxxx addresses to 0x0000xxxx for memory models
    assign imem_addr_o = mem_la_addr - 32'h80000000;

    // Data memory control signals
    // Translate 0x8000xxxx addresses to 0x0000xxxx for memory models
    assign mem_addr_o = mem_addr - 32'h80000000;
    assign mem_dat_o = mem_wdata;
    assign mem_wstrb_o = mem_wstrb;
    assign mem_write_o = mem_valid && !mem_instr && |mem_wstrb;
    assign mem_read_o = mem_valid && !mem_instr && !mem_write_o;

    // Illegal instruction detection
    assign illegal_inst_o = trap;

    // Memory interface state machine
    always @(posedge clk_i) begin
        if (!resetn_i) begin
            mem_state <= 1'b0;
            mem_ready <= 1'b0;
            mem_rdata <= 32'b0;
        end else begin
            if (mem_state == 1'b0) begin
                if (mem_valid) begin
                    if (mem_instr) begin
                        mem_ready <= 1'b1;
                        mem_rdata <= imem_inst_i;
                    end else if (mem_write_o || mem_read_o) begin
                        mem_state <= 1'b1;
                        mem_ready <= 1'b0;
                    end else begin
                        mem_ready <= 1'b0;
                    end
                end else begin
                    mem_ready <= 1'b0;
                end
            end else begin
                if (mem_ack_i) begin
                    mem_ready <= 1'b1;
                    mem_rdata <= mem_read_o ? mem_dat_i : 32'b0;
                    mem_state <= 1'b0;
                end else begin
                    mem_ready <= 1'b0;
                end
            end
        end
    end

endmodule