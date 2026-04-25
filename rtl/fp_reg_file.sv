// Floating-point register file — 32 x 32-bit, 2R/1W.
// Unlike the integer regfile, f0 is a regular writable register (no x0-hardwire).
//
// Read ports use write-before-read bypass so the 4-stage FPU's WB+1 write
// is visible to a consumer at ID on the same rising edge. This replaces the
// separate WB→ID forwarding mux previously in data_path.
module fp_reg_file #(
    parameter DEPTH = 32,
    parameter WIDTH = 32
) (
    input  logic         clk,
    input  logic         reset_n,
    input  logic         reg_write,
    input  logic [4:0]   raddr1,
    input  logic [4:0]   raddr2,
    input  logic [4:0]   waddr,
    input  logic [31:0]  wdata,
    output logic [31:0]  rdata1,
    output logic [31:0]  rdata2
);

    logic [WIDTH-1:0] fp_regs [0:DEPTH-1];

    int i;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (i = 0; i < DEPTH; i = i + 1)
                fp_regs[i] <= 32'd0;
        end else if (reg_write) begin
            fp_regs[waddr] <= wdata;
        end
    end

    wire hit1 = reg_write && (waddr == raddr1);
    wire hit2 = reg_write && (waddr == raddr2);

    assign rdata1 = hit1 ? wdata : fp_regs[raddr1];
    assign rdata2 = hit2 ? wdata : fp_regs[raddr2];

`ifdef verilator
    logic [31:0] f0,f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14,f15;
    logic [31:0] f16,f17,f18,f19,f20,f21,f22,f23,f24,f25,f26,f27,f28,f29,f30,f31;
    assign f0  = fp_regs[0];
    assign f1  = fp_regs[1];
    assign f2  = fp_regs[2];
    assign f3  = fp_regs[3];
    assign f4  = fp_regs[4];
    assign f5  = fp_regs[5];
    assign f6  = fp_regs[6];
    assign f7  = fp_regs[7];
    assign f8  = fp_regs[8];
    assign f9  = fp_regs[9];
    assign f10 = fp_regs[10];
    assign f11 = fp_regs[11];
    assign f12 = fp_regs[12];
    assign f13 = fp_regs[13];
    assign f14 = fp_regs[14];
    assign f15 = fp_regs[15];
    assign f16 = fp_regs[16];
    assign f17 = fp_regs[17];
    assign f18 = fp_regs[18];
    assign f19 = fp_regs[19];
    assign f20 = fp_regs[20];
    assign f21 = fp_regs[21];
    assign f22 = fp_regs[22];
    assign f23 = fp_regs[23];
    assign f24 = fp_regs[24];
    assign f25 = fp_regs[25];
    assign f26 = fp_regs[26];
    assign f27 = fp_regs[27];
    assign f28 = fp_regs[28];
    assign f29 = fp_regs[29];
    assign f30 = fp_regs[30];
    assign f31 = fp_regs[31];
`endif

endmodule
