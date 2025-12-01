


module alu (
    input alu_t alu_ctrl,
    input logic [31:0] op1,
    input logic [31:0] op2,
    output logic [31:0] alu_result, 
    output logic zero
);



    // Internal results
    logic [63:0] clmul_o;
    logic [31:0] rev8_o, brev8_o;
    logic [31:0] xperm4_o, xperm8_o;
    logic [31:0] zip_o, unzip_o;

    // Optimized shared adder/subtractor with carry-in
    // For addition: op1 + op2 + 0
    // For subtraction: op1 + ~op2 + 1 (two's complement)
    logic        is_sub;
    logic [31:0] op2_conditional;
    logic [32:0] addsub_result;

    assign is_sub = (alu_ctrl == SUB || alu_ctrl == SLT || alu_ctrl == SLTU);

    // XOR each bit of op2 with is_sub for efficient conditional inversion
    assign op2_conditional = op2 ^ {32{is_sub}};

    // Single adder with 1-bit carry-in: result = op1 + op2_conditional + is_sub
    // Synthesizes to one 32-bit adder with carry-in, not three separate adders
    assign addsub_result = op1 + op2_conditional + is_sub;

    // Optimized barrel shifter with shared logic
    logic [31:0] shift_left, shift_right, shift_arith;
    logic [31:0] rotate_result;

    assign shift_left  = op1 << op2[4:0];
    assign shift_right = op1 >> op2[4:0];
    assign shift_arith = $signed(op1) >>> op2[4:0];

    // Unified rotate logic - more efficient than separate ROL/ROR
    assign rotate_result = (alu_ctrl == ROL_) ?
                          (shift_left | (op1 >> (5'd0 - op2[4:0]))) :
                          (shift_right | (op1 << (5'd0 - op2[4:0])));

    // Optimized comparison using addsub result
    logic cmp_signed, cmp_unsigned;
    assign cmp_signed   = (op1[31] != op2[31]) ? op1[31] : addsub_result[31];
    assign cmp_unsigned = ~addsub_result[32];

    always_comb begin
        case(alu_ctrl)
            // Arithmetic operations use shared adder/subtractor
            ADD:  alu_result = addsub_result[31:0];
            SUB:  alu_result = addsub_result[31:0];

            // Optimized comparisons using subtraction result
            SLT:  alu_result = {31'h0, cmp_signed};
            SLTU: alu_result = {31'h0, cmp_unsigned};

            // Optimized shift operations
            SLL_: alu_result = shift_left;
            SRL_: alu_result = shift_right;
            SRA_: alu_result = shift_arith;

            // Unified rotate operations
            ROL_: alu_result = rotate_result;
            ROR_: alu_result = rotate_result;

            // Bitwise operations
            AND_:  alu_result = op1 & op2;
            OR:    alu_result = op1 | op2;
            XOR:   alu_result = op1 ^ op2;
            ANDN:  alu_result = op1 & ~op2;
            ORN:   alu_result = op1 | ~op2;
            XNORN: alu_result = ~(op1 ^ op2);

            // Pack operations
            PACK:  alu_result = {op2[15:0], op1[15:0]};
            PACKH: alu_result = {16'b0, op2[7:0], op1[7:0]};

            // Crypto/bitmanip operations (instantiated modules)
            CLMUL:  alu_result = clmul_o[31:0];
            CLMULH: alu_result = clmul_o[63:32];
            XPERM4: alu_result = xperm4_o;
            XPERM8: alu_result = xperm8_o;
            ZIP:    alu_result = zip_o;
            UNZIP:  alu_result = unzip_o;
            REV:    alu_result = rev8_o;
            BREV:   alu_result = brev8_o;

            default: alu_result = 32'd0;
        endcase
    end
    

    // Instantiations R
    clmul   u_clmul  (.rs1(op1), .rs2(op2), .rd(clmul_o));
    xperm4  u_xperm4 (.rs1(op1), .rs2(op2), .rd(xperm4_o));
    xperm8  u_xperm8 (.rs1(op1), .rs2(op2), .rd(xperm8_o));


    // Instantiations R1
    brev8   u_brev8  (.rs (op1),            .rd(brev8_o ));
    rev8    u_rev8   (.rs (op1),            .rd(rev8_o  ));
    zip     u_zip    (.rs (op1),            .rd(zip_o   ));
    unzip   u_unzip  (.rs (op1),            .rd(unzip_o ));
    
    assign zero = (alu_result == 0);
endmodule