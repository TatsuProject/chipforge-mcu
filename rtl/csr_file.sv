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

    input  logic [31:0]  mtval_i
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

    localparam MSTATUS_WR_MASK  = 32'h00000088;
    localparam MIE_WR_MASK      = 32'h00000880;
    localparam MTVEC_WR_MASK    = 32'hFFFFFFFD;
    localparam MSCRATCH_WR_MASK = 32'hFFFFFFFF;
    localparam MCAUSE_WR_MASK   = 32'h9000003F;
    localparam MTVAL_WR_MASK    = 32'hFFFFFFFF;
    localparam MEPC_WR_MASK     = 32'hFFFFFFFE;

    logic [31:0] mstatus_reg, mie_reg, mtvec_reg, mepc_reg, mcause_reg;
    logic [31:0] mtval_reg, mscratch_reg, mip_reg;

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

    always_comb begin
        case (csr_addr)
            ADDR_MSTATUS:  csr_rdata = mstatus_reg;
            ADDR_MIE:      csr_rdata = mie_reg;
            ADDR_MTVEC:    csr_rdata = mtvec_reg;
            ADDR_MSCRATCH: csr_rdata = mscratch_reg;
            ADDR_MEPC:     csr_rdata = mepc_reg;
            ADDR_MCAUSE:   csr_rdata = mcause_reg;
            ADDR_MTVAL:    csr_rdata = mtval_reg;
            ADDR_MIP:      csr_rdata = mip_reg;
            ADDR_MISA:     csr_rdata = 32'h40001105;
            default:       csr_rdata = 32'h0;
        endcase
    end

endmodule