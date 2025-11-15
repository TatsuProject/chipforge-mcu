


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
    
    logic [32:0] add_o, sub_o;

    assign add_o = op1 + op2;
    assign sub_o = op1 - op2;

    always_comb begin 
        case(alu_ctrl)
			ADD: alu_result    = add_o[31:0];
            ROL_: alu_result   = (op1 << op2[4:0]) | (op1 >> (32 - op2[4:0]));
            ROR_: alu_result   = (op1 >> op2[4:0]) | (op1 << (32 - op2[4:0]));
            SUB: alu_result    = sub_o[31:0];
      		SLT: alu_result    = $signed(op1) < $signed(op2) ? 1'b1 : 1'b0;
	        SLL_: alu_result   = op1 << op2[4:0];
            ANDN: alu_result   = op1 & ~op2;
            ORN: alu_result    = op1 | ~op2;
            XNORN: alu_result  = ~op1 ^ op2;
            PACK: alu_result   = {op2[15:0], op1[15:0]};
            PACKH: alu_result  = {16'b0, op2[7:0], op1[7:0]};
            SRL_: alu_result   = op1 >> op2[4:0];
            SRA_: alu_result   = $signed(op1) >>> op2[4:0];
            XOR: alu_result    = op1 ^ op2;
            AND_: alu_result   = op1 & op2;
            OR: alu_result     = op1 | op2;
            SLTU: alu_result   = {31'h0, {op1 < op2}};
            CLMUL: alu_result  = clmul_o[31:0];
            CLMULH: alu_result = clmul_o[63:32];
            XPERM4: alu_result = xperm4_o;
            XPERM8: alu_result = xperm8_o;
            ZIP   : alu_result = zip_o;
            UNZIP : alu_result = unzip_o;
            REV   : alu_result = rev8_o;
            BREV  : alu_result = brev8_o;


            
            
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