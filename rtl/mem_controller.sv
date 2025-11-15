/*
 * Memory Controller for RISC-V AMO/LR/SC Instructions
 *
 * Developed entirely by Qamar Moavia using ChatGPT (OpenAI GPT-4).
 * This code implements atomic memory operation handling (AMOs and LR/SC)
 * for single-core RISC-V pipelines with memory-mapped interfaces such as Wishbone.
 */

module mem_controller (
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

    // Interface to memory bus or Wishbone controller
    output reg         mem_read,
    output reg         mem_write,
    output reg [31:0]  mem_addr,
    output reg [31:0]  mem_wdata,
    input      [31:0]  mem_rdata,
    input              mem_ack,
    input              mem_err,
    // Output to pipeline
    output reg         stall_mem,
    output reg [31:0]  result_rd,         // Data to write back to rd

    // Memory Access exceptions 
    output logic load_addr_malign,
    output logic store_amo_addr_malign,
    output logic load_access_fault,
    output logic store_amo_access_fault
);


    // AMO Operation Encoding
    localparam AMO_LR   = 5'b00010;
    localparam AMO_SC   = 5'b00011;
    localparam AMO_SWAP = 5'b00001;
    localparam AMO_ADD  = 5'b00000;
    localparam AMO_XOR  = 5'b00100;
    localparam AMO_AND  = 5'b01100;
    localparam AMO_OR   = 5'b01000;
    localparam AMO_MIN  = 5'b10000;
    localparam AMO_MAX  = 5'b10100;
    localparam AMO_MINU = 5'b11000;
    localparam AMO_MAXU = 5'b11100;

    typedef enum logic [2:0] {
        IDLE,
        READ,
        EXECUTE,
        WRITE,
        LR_WAIT,
        LR_DONE,
        SC_WRITE
    } state_t;

    state_t state, next_state;

    reg  [31:0] read_val;
    reg  [31:0] computed_val, computed_val_ff;
    wire [32:0] add_o;
    reg         reservation_valid;
    reg  [31:0] reservation_addr;

    assign add_o = read_val + rs2_val_mem;

    // FSM state transition and data register updates
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            reservation_valid <= 1'b0;
            read_val <= 32'b0;
            reservation_addr <= 'b0;
        end else begin
            state <= next_state;

            if (state == LR_WAIT && mem_ack) begin
                read_val <= mem_rdata;
                reservation_valid <= 1'b1;
                reservation_addr <= mem_addr_req;
            end else if (state == READ && mem_ack) begin
                read_val <= mem_rdata;
            end else if (state == SC_WRITE && mem_ack) begin
                reservation_valid <= 1'b0; // Always drop reservation after SC
            end
        end
    end

    // Combinational logic (The output logic and the next state logic both are in one always block which is not recommended)
    always_comb begin
        next_state = state;
        stall_mem  = 1'b0;
        mem_read   = mem_read_req;
        mem_write  = mem_write_req;
        mem_addr   = mem_addr_req;
        mem_wdata  = mem_wdata_req;
        result_rd  = read_val;
        computed_val = 'd0;

        if(core_halted) begin 
            next_state = IDLE;
        end else begin 
            case (state)
                IDLE: begin
                    if (is_atomic_mem) begin
                        case (amo_funct5_mem)
                            AMO_LR: next_state = LR_WAIT;
                            AMO_SC: next_state = SC_WRITE;
                            default: next_state = READ;
                        endcase
                        stall_mem = 1'b1;
                    end
                end

                LR_WAIT: begin
                    mem_read = 1'b1;
                    stall_mem = 1'b1;
                    if (mem_ack) begin
                        next_state = LR_DONE;
                    end
                end

                LR_DONE: begin 
                    next_state = IDLE;
                    result_rd  = read_val;
                end

                SC_WRITE: begin
                    stall_mem = 1'b1;
                    if (reservation_valid && reservation_addr == mem_addr_req) begin
                        result_rd = 32'b0; // success = rd = 0
                        mem_write = 1'b1;
                        mem_wdata = rs2_val_mem;
                        if (mem_ack) begin
                            stall_mem = 1'b0;
                            next_state = IDLE;
                        end
                    end else begin
                        result_rd = 32'b1; // failure = rd = non-zero
                        next_state = IDLE;
                        stall_mem = 1'b0;
                    end
                end

                READ: begin
                    mem_read = 1'b1;
                    stall_mem = 1'b1;
                    if (mem_ack) begin
                        next_state = EXECUTE;
                    end
                end

                EXECUTE: begin
                    stall_mem = 1'b1;
                    case (amo_funct5_mem)
                        AMO_ADD:  computed_val = add_o[31:0];
                        AMO_XOR:  computed_val = read_val ^ rs2_val_mem;
                        AMO_OR:   computed_val = read_val | rs2_val_mem;
                        AMO_AND:  computed_val = read_val & rs2_val_mem;
                        AMO_MIN:  computed_val = ($signed(read_val) < $signed(rs2_val_mem)) ? read_val : rs2_val_mem;
                        AMO_MAX:  computed_val = ($signed(read_val) > $signed(rs2_val_mem)) ? read_val : rs2_val_mem;
                        AMO_MINU: computed_val = (read_val < rs2_val_mem) ? read_val : rs2_val_mem;
                        AMO_MAXU: computed_val = (read_val > rs2_val_mem) ? read_val : rs2_val_mem;
                        AMO_SWAP: computed_val = rs2_val_mem;
                        default:  computed_val = read_val;
                    endcase
                    next_state = WRITE;
                end

                WRITE: begin
                    mem_write = 1'b1;
                    mem_wdata = computed_val_ff;
                    stall_mem = 1'b1;
                    result_rd = read_val; 
                    if (mem_ack) begin
                        next_state = IDLE;
                        stall_mem = 1'b0;
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk, posedge rst) begin
    if(rst)
        computed_val_ff <= 'b0;
    else
        if(state == EXECUTE) computed_val_ff <= computed_val;
    end 



    // Alignment check for non-atomic accesses only
    assign load_addr_malign = !is_atomic_mem && mem_read_req &&
                               ((mem_op_mem == 3'b010 && mem_addr_req[1:0] != 2'b00) || // lw and not word aligned
                                (mem_op_mem == 3'b001 && mem_addr_req[0]   != 1'b0));  //  lh and not half word aligned

    assign store_amo_addr_malign = !is_atomic_mem && mem_write_req &&
                                   ((mem_op_mem == 3'b010 && mem_addr_req[1:0] != 2'b00) || // sw and not word aligned (amo not checked, as its always aligned in RV32)
                                    (mem_op_mem == 3'b001 && mem_addr_req[0]   != 1'b0));   // sh and not half word algiend (amo not checked)

    assign load_access_fault = (state == IDLE) ? mem_read & mem_err : 1'b0;
    assign store_amo_access_fault = (state == IDLE) ? 
                                    (mem_write & mem_err) : 
                                    ((mem_write | mem_read) & mem_err);

endmodule