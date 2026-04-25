// Final csr_file.sv with trap-safe delayed CSR writes

module csr_file (
    input  logic         clk,
    input  logic         reset_n,

    input  logic         csr_en,
    input  logic [1:0]   csr_cmd,
    input  logic [11:0]  csr_addr,
    input  logic [31:0]  csr_wdata,
    output logic [31:0]  csr_rdata,

    input  logic [31:0]  cinst_pc,
    input  logic         exception_i,
    input  logic [5:0]   e_code,

    input  logic         timer_irq,
    input  logic         external_irq,

    output logic         trap,
    output logic [31:0]  mtvec,
    output logic [31:0]  mepc,
    output logic [5:0]   trap_cause,
    input  logic         trap_ret,

    input  logic         dont_trap,

    input  logic         exe_mem_reg_clr,
    input  logic         exe_mem_reg_en,

    input  logic [31:0]  mtval_i,

    // F-extension dynamic rounding mode, bypass-aware so a back-to-back
    // `csrrw frm; fadd.s` issues with the updated rm. Bound to the FPU.
    output logic [2:0]   frm_o
);

    localparam ADDR_MSTATUS   = 12'h300;
    localparam ADDR_MISA      = 12'h301;
    localparam ADDR_MIE       = 12'h304;
    localparam ADDR_MTVEC     = 12'h305;
    localparam ADDR_MSCRATCH  = 12'h340;
    localparam ADDR_MEPC      = 12'h341;
    localparam ADDR_MCAUSE    = 12'h342;
    localparam ADDR_MTVAL     = 12'h343;
    localparam ADDR_MIP       = 12'h344;
    // Floating-point CSRs (Challenge 0013 — required for DYN rounding mode).
    localparam ADDR_FFLAGS    = 12'h001;   // fcsr[4:0]
    localparam ADDR_FRM       = 12'h002;   // fcsr[7:5]
    localparam ADDR_FCSR      = 12'h003;   // {reserved, frm[2:0], fflags[4:0]}

    localparam MSTATUS_WR_MASK  = 32'h00000088;
    localparam MIE_WR_MASK      = 32'h00000880;
    localparam MTVEC_WR_MASK    = 32'hFFFFFFFD;
    localparam MSCRATCH_WR_MASK = 32'hFFFFFFFF;
    localparam MCAUSE_WR_MASK   = 32'h9000003F;
    localparam MTVAL_WR_MASK    = 32'hFFFFFFFF;
    localparam MEPC_WR_MASK     = 32'hFFFFFFFE;
    localparam FCSR_WR_MASK     = 32'h000000FF;   // only fcsr[7:0] are live

    logic [31:0] mstatus_reg, mie_reg, mtvec_reg, mepc_reg, mcause_reg;
    logic [31:0] mtval_reg, mscratch_reg, mip_reg;
    logic [2:0]  frm_reg;
    logic [4:0]  fflags_reg;

    logic        csr_valid_d;
    logic [1:0]  csr_cmd_d;
    logic [11:0] csr_addr_d;
    logic [31:0] csr_wdata_d;

    // Pipeline register
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            csr_valid_d <= 'b0;
            csr_cmd_d   <= 'b0;
            csr_addr_d  <= 'b0;
            csr_wdata_d <= 'b0;
        end else begin
            if (exe_mem_reg_clr) begin
                csr_valid_d <= 'b0;
                csr_cmd_d   <= 'b0;
                csr_addr_d  <= 'b0;
                csr_wdata_d <= 'b0;
            end else if (exe_mem_reg_en) begin
                csr_valid_d <= csr_en;
                csr_cmd_d   <= csr_cmd;
                csr_addr_d  <= csr_addr;
                csr_wdata_d <= csr_wdata;
            end
        end
    end

    // MSTATUS
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mstatus_reg <= 32'h0;
        else if (trap) begin
            mstatus_reg[7] <= mstatus_reg[3];
            mstatus_reg[3] <= 1'b0;
        end else if (trap_ret) begin
            mstatus_reg[3] <= mstatus_reg[7];
            mstatus_reg[7] <= 1'b1;
        end else if (csr_valid_d && csr_addr_d == ADDR_MSTATUS) begin
            case (csr_cmd_d)
                2'b01: mstatus_reg <= csr_wdata_d & MSTATUS_WR_MASK;
                2'b10: mstatus_reg <= mstatus_reg | (csr_wdata_d & MSTATUS_WR_MASK);
                2'b11: mstatus_reg <= mstatus_reg & ~(csr_wdata_d & MSTATUS_WR_MASK);
            endcase
        end
    end

    // MIE
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mie_reg <= 32'h0;
        else if (csr_valid_d && csr_addr_d == ADDR_MIE) begin
            case (csr_cmd_d)
                2'b01: mie_reg <= csr_wdata_d & MIE_WR_MASK;
                2'b10: mie_reg <= mie_reg | (csr_wdata_d & MIE_WR_MASK);
                2'b11: mie_reg <= mie_reg & ~(csr_wdata_d & MIE_WR_MASK);
            endcase
        end
    end

    // MTVEC
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mtvec_reg <= 32'h0;
        else if (csr_valid_d && csr_addr_d == ADDR_MTVEC) begin
            case (csr_cmd_d)
                2'b01: mtvec_reg <= csr_wdata_d & MTVEC_WR_MASK;
                2'b10: mtvec_reg <= mtvec_reg | (csr_wdata_d & MTVEC_WR_MASK);
                2'b11: mtvec_reg <= mtvec_reg & ~(csr_wdata_d & MTVEC_WR_MASK);
            endcase
        end
    end

    // MSCRATCH
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mscratch_reg <= 32'h0;
        else if (csr_valid_d && csr_addr_d == ADDR_MSCRATCH) begin
            case (csr_cmd_d)
                2'b01: mscratch_reg <= csr_wdata_d & MSCRATCH_WR_MASK;
                2'b10: mscratch_reg <= mscratch_reg | (csr_wdata_d & MSCRATCH_WR_MASK);
                2'b11: mscratch_reg <= mscratch_reg & ~(csr_wdata_d & MSCRATCH_WR_MASK);
            endcase
        end
    end

    // MTVAL
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mtval_reg <= 32'h0;
        else if (trap) begin
            mtval_reg <= mtval_i;
        end else if (csr_valid_d && csr_addr_d == ADDR_MTVAL) begin
            case (csr_cmd_d)
                2'b01: mtval_reg <= csr_wdata_d & MTVAL_WR_MASK;
                2'b10: mtval_reg <= mtval_reg | (csr_wdata_d & MTVAL_WR_MASK);
                2'b11: mtval_reg <= mtval_reg & ~(csr_wdata_d & MTVAL_WR_MASK);
            endcase
        end
    end


    // MCAUSE
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mcause_reg <= 32'h0;
        else if (trap) begin
            mcause_reg <= (~exception_i << 31) | {26'd0, trap_cause};
        end else if (csr_valid_d && csr_addr_d == ADDR_MCAUSE) begin
            case (csr_cmd_d)
                2'b01: mcause_reg <= csr_wdata_d & MCAUSE_WR_MASK;
                2'b10: mcause_reg <= mcause_reg | (csr_wdata_d & MCAUSE_WR_MASK);
                2'b11: mcause_reg <= mcause_reg & ~(csr_wdata_d & MCAUSE_WR_MASK);
            endcase
        end
    end

    // MEPC
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) mepc_reg <= 32'h0;
        else if (trap) begin
            mepc_reg <= cinst_pc;
        end else if (csr_valid_d && csr_addr_d == ADDR_MEPC) begin
            case (csr_cmd_d)
                2'b01: mepc_reg <= csr_wdata_d & MEPC_WR_MASK;
                2'b10: mepc_reg <= mepc_reg | (csr_wdata_d & MEPC_WR_MASK);
                2'b11: mepc_reg <= mepc_reg & ~(csr_wdata_d & MEPC_WR_MASK);
            endcase
        end
    end

    // MIP 


    logic external_irq_ff, timer_irq_ff;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) external_irq_ff <= 'b0;
        else          external_irq_ff <= external_irq;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) timer_irq_ff    <= 'b0;
        else          timer_irq_ff    <= timer_irq;
    end

    assign mip_reg[31:0] = {20'b0, external_irq_ff, 3'b0, timer_irq_ff, 7'b0};



    // F-extension: frm (0x002) and fflags (0x001). Writes via fcsr (0x003)
    // update bits [7:5] → frm and [4:0] → fflags in one transaction.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) frm_reg <= 3'd0;
        else if (csr_valid_d && csr_addr_d == ADDR_FRM) begin
            case (csr_cmd_d)
                2'b01: frm_reg <= csr_wdata_d[2:0];
                2'b10: frm_reg <= frm_reg | csr_wdata_d[2:0];
                2'b11: frm_reg <= frm_reg & ~csr_wdata_d[2:0];
                default: ;
            endcase
        end else if (csr_valid_d && csr_addr_d == ADDR_FCSR) begin
            case (csr_cmd_d)
                2'b01: frm_reg <= csr_wdata_d[7:5];
                2'b10: frm_reg <= frm_reg | csr_wdata_d[7:5];
                2'b11: frm_reg <= frm_reg & ~csr_wdata_d[7:5];
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) fflags_reg <= 5'd0;
        else if (csr_valid_d && csr_addr_d == ADDR_FFLAGS) begin
            case (csr_cmd_d)
                2'b01: fflags_reg <= csr_wdata_d[4:0];
                2'b10: fflags_reg <= fflags_reg | csr_wdata_d[4:0];
                2'b11: fflags_reg <= fflags_reg & ~csr_wdata_d[4:0];
                default: ;
            endcase
        end else if (csr_valid_d && csr_addr_d == ADDR_FCSR) begin
            case (csr_cmd_d)
                2'b01: fflags_reg <= csr_wdata_d[4:0];
                2'b10: fflags_reg <= fflags_reg | csr_wdata_d[4:0];
                2'b11: fflags_reg <= fflags_reg & ~csr_wdata_d[4:0];
                default: ;
            endcase
        end
    end

    // TRAP LOGIC
    logic mei, mtip, meip, mtie, meie;
    assign mei  = mstatus_reg[3];
    assign mtip = mip_reg[7];
    assign meip = mip_reg[11];
    assign mtie = mie_reg[7];
    assign meie = mie_reg[11];

    assign trap = ((mei & ((mtie & mtip) | (meie & meip))) | exception_i) & ~dont_trap;
    assign trap_cause = (exception_i) ? e_code :
                        (meip ? 6'd11 : 6'd7);



    // REG READ LOGIC
    assign mepc = mepc_reg;
    assign mtvec = mtvec_reg;

    // Bypass: the staged CSR write (csr_valid_d) only commits into the
    // register at the end of the current cycle, so a back-to-back CSR read
    // on the next cycle would otherwise see the stale value. When the _d
    // write targets the same address we are reading, compute the would-be
    // new value combinationally and return that.
    function automatic logic [31:0] csr_bypass(
        input logic [31:0] cur_reg,
        input logic [1:0]  cmd,
        input logic [31:0] wdata,
        input logic [31:0] mask
    );
        logic [31:0] masked;
        masked = wdata & mask;
        unique case (cmd)
            2'b01:   csr_bypass = masked;
            2'b10:   csr_bypass = cur_reg | masked;
            2'b11:   csr_bypass = cur_reg & ~masked;
            default: csr_bypass = cur_reg;
        endcase
    endfunction

    logic bypass_hit_mstatus, bypass_hit_mie, bypass_hit_mtvec;
    logic bypass_hit_mscratch, bypass_hit_mepc, bypass_hit_mcause;
    logic bypass_hit_mtval;
    logic bypass_hit_frm, bypass_hit_fflags, bypass_hit_fcsr;

    assign bypass_hit_mstatus  = csr_valid_d & (csr_addr_d == ADDR_MSTATUS);
    assign bypass_hit_mie      = csr_valid_d & (csr_addr_d == ADDR_MIE);
    assign bypass_hit_mtvec    = csr_valid_d & (csr_addr_d == ADDR_MTVEC);
    assign bypass_hit_mscratch = csr_valid_d & (csr_addr_d == ADDR_MSCRATCH);
    assign bypass_hit_mepc     = csr_valid_d & (csr_addr_d == ADDR_MEPC);
    assign bypass_hit_mcause   = csr_valid_d & (csr_addr_d == ADDR_MCAUSE);
    assign bypass_hit_mtval    = csr_valid_d & (csr_addr_d == ADDR_MTVAL);
    assign bypass_hit_frm      = csr_valid_d & (csr_addr_d == ADDR_FRM);
    assign bypass_hit_fflags   = csr_valid_d & (csr_addr_d == ADDR_FFLAGS);
    assign bypass_hit_fcsr     = csr_valid_d & (csr_addr_d == ADDR_FCSR);

    // Live frm value exported to the FPU. Accounts for the 1-cycle _d stage.
    // When a write to frm or fcsr is in flight, compute the effective value
    // this cycle rather than waiting for the register commit.
    logic [2:0] frm_live;
    always_comb begin
        if (bypass_hit_frm) begin
            unique case (csr_cmd_d)
                2'b01:   frm_live =  csr_wdata_d[2:0];
                2'b10:   frm_live =  frm_reg | csr_wdata_d[2:0];
                2'b11:   frm_live =  frm_reg & ~csr_wdata_d[2:0];
                default: frm_live =  frm_reg;
            endcase
        end else if (bypass_hit_fcsr) begin
            unique case (csr_cmd_d)
                2'b01:   frm_live =  csr_wdata_d[7:5];
                2'b10:   frm_live =  frm_reg | csr_wdata_d[7:5];
                2'b11:   frm_live =  frm_reg & ~csr_wdata_d[7:5];
                default: frm_live =  frm_reg;
            endcase
        end else begin
            frm_live = frm_reg;
        end
    end
    assign frm_o = frm_live;

    // Precompute the fflags bypass value. Yosys (the synthesis frontend the
    // evaluator uses) doesn't accept inline bit-selects on function calls
    // (i.e. `func(...)[4:0]`), so we stage the 32-bit result in a wire and
    // slice it below.
    logic [31:0] fflags_bypass_32;
    always_comb begin
        if (bypass_hit_fflags)
            fflags_bypass_32 = csr_bypass({27'd0, fflags_reg}, csr_cmd_d, csr_wdata_d, 32'h0000001F);
        else if (bypass_hit_fcsr)
            fflags_bypass_32 = csr_bypass({27'd0, fflags_reg}, csr_cmd_d, csr_wdata_d, 32'h0000001F);
        else
            fflags_bypass_32 = {27'd0, fflags_reg};
    end

    always_comb begin
        case (csr_addr)
            ADDR_MSTATUS:  csr_rdata = bypass_hit_mstatus  ? csr_bypass(mstatus_reg,  csr_cmd_d, csr_wdata_d, MSTATUS_WR_MASK)  : mstatus_reg;
            ADDR_MIE:      csr_rdata = bypass_hit_mie      ? csr_bypass(mie_reg,      csr_cmd_d, csr_wdata_d, MIE_WR_MASK)      : mie_reg;
            ADDR_MTVEC:    csr_rdata = bypass_hit_mtvec    ? csr_bypass(mtvec_reg,    csr_cmd_d, csr_wdata_d, MTVEC_WR_MASK)    : mtvec_reg;
            ADDR_MSCRATCH: csr_rdata = bypass_hit_mscratch ? csr_bypass(mscratch_reg, csr_cmd_d, csr_wdata_d, MSCRATCH_WR_MASK) : mscratch_reg;
            ADDR_MEPC:     csr_rdata = bypass_hit_mepc     ? csr_bypass(mepc_reg,     csr_cmd_d, csr_wdata_d, MEPC_WR_MASK)     : mepc_reg;
            ADDR_MCAUSE:   csr_rdata = bypass_hit_mcause   ? csr_bypass(mcause_reg,   csr_cmd_d, csr_wdata_d, MCAUSE_WR_MASK)   : mcause_reg;
            ADDR_MTVAL:    csr_rdata = bypass_hit_mtval    ? csr_bypass(mtval_reg,    csr_cmd_d, csr_wdata_d, MTVAL_WR_MASK)    : mtval_reg;
            ADDR_MIP:      csr_rdata = mip_reg;
            ADDR_MISA:     csr_rdata = 32'h40001105;
            ADDR_FFLAGS:   csr_rdata = {27'd0, fflags_bypass_32[4:0]};
            ADDR_FRM:      csr_rdata = {29'd0, frm_live};
            ADDR_FCSR:     csr_rdata = bypass_hit_fcsr ? csr_bypass({24'd0, frm_reg, fflags_reg}, csr_cmd_d, csr_wdata_d, FCSR_WR_MASK) :
                                                        {24'd0, frm_live, fflags_reg};
            default:       csr_rdata = 32'h0;
        endcase
    end

endmodule
