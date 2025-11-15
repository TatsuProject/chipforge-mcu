    // // ALU operation types
    // typedef enum logic [9:0]  { 
    //     ADD, SLL_, SLT, SLTU, XOR, SRL_, OR, AND_, 
    //     SUB   = 256,
    //     PACK  = 36,
    //     PACKH = 39,
    //     CLMUL = 41, 
    //     CLMULH = 43,
    //     XPERM4 = 162,
    //     XPERM8 = 164,
    //     XNORN  = 260,
    //     SRA_   = 261,
    //     ORN    = 262,
    //     ANDN   = 263,
    //     ROL_   = 385,
    //     ROR_   = 389,
    //     REV    = 421,
    //     BREV   = 422,
    //     ZIP    = 33,
    //     UNZIP  = 37,
    //     // encryption and decryption added 
    //     AES32ESMI = 152,
    //     AES32ESI  = 136,
    //     AES32DSI  = 168,
    //     AES32DSMI = 184,
    //     // SHA instruction added 
    //     SHA256 = 65
    // } alu_t;


module alu_control (
    input logic [2:0] fun3,
    // additional signal added 
    input logic [6:0] fun7,
    input logic [1:0] alu_op,
    input logic [4:0] rs2, 
    output alu_t alu_ctrl
);

// alu_op 00 for load/store
// alu_op 10 r-type
// alu_op 11 i-type 
// alu_op 01 for branches
parameter LOAD_STORE = 2'b00, R_TYPE = 2'b11, I_TYPE = 2'b01, B_TYPE = 2'b10;

always_comb begin 
    case(alu_op)
        R_TYPE: begin 
           alu_ctrl = alu_t'({fun7, fun3});
        end
        I_TYPE: begin 
            if (fun3 == 3'b001) begin
            `ifdef SYNTHESIS
                alu_ctrl = {fun7, fun3};
            `else
                alu_ctrl = alu_t'({fun7, fun3});
            `endif
            end else if (fun3 == 3'b101 && fun7 == 7'b0100000) begin 
                `ifdef SYNTHESIS
                    alu_ctrl = {1'b0, fun7[5], 5'b0, fun3};
                `else
                    alu_ctrl = alu_t'({1'b0, fun7[5], 5'b0, fun3});
                `endif
            end else if (fun3 == 3'b101 && fun7 == 7'b0110100 && rs2 == 5'b00111) begin 
                alu_ctrl = BREV;
            end else if (fun3 == 3'b101) begin 
                `ifdef SYNTHESIS
                    alu_ctrl = {fun7, fun3};
                `else
                    alu_ctrl = alu_t'({fun7, fun3});
                `endif
            end else begin 
                `ifdef SYNTHESIS
                    alu_ctrl = {7'b0, fun3};
                `else
                    alu_ctrl = alu_t'({7'b0, fun3});
                `endif
            end
        end
        LOAD_STORE: begin
            alu_ctrl = ADD; 
        end

        B_TYPE: begin 
            case(fun3[2:1])
                2'b00: alu_ctrl = SUB;
                2'b01: alu_ctrl = SUB;
                2'b10: alu_ctrl = SLT;
                2'b11: alu_ctrl = SLTU;
            endcase
        end
    endcase
end

endmodule : alu_control