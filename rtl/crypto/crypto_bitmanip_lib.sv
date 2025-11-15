

module zip (
    input  logic [31:0] rs,
    output logic [31:0] rd
);
    integer i;
    always_comb begin
        rd = 32'b0;
        for (i = 0; i < 16; i++) begin
            rd[2*i]     = rs[i];       // lower 16 bits
            rd[2*i + 1] = rs[i + 16];  // upper 16 bits
        end
    end
endmodule

module unzip (
    input  logic [31:0] rs,
    output logic [31:0] rd
);
    integer i;
    always_comb begin
        rd = 32'b0;
        for (i = 0; i < 16; i++) begin
            rd[i]      = rs[2*i];      // extract even bits
            rd[i + 16] = rs[2*i + 1];  // extract odd bits
        end
    end
endmodule


module rev8 (
    input  wire [31:0] rs,
    output wire [31:0] rd
);
    assign rd = {rs[7:0], rs[15:8], rs[23:16], rs[31:24]};
endmodule


module clmul (
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    output logic [63:0] rd
);
    integer i;
    logic [63:0] product;
    always_comb begin
        product = 64'b0;
        for (i = 0; i < 32; i++) begin
            if (rs2[i])
                product ^= (64'(rs1) << i);
        end
    end
    assign rd = product;
endmodule




module brev8(
    input  logic [31:0] rs,
    output logic [31:0] rd
);
    function [7:0] reverse8;
        input [7:0] b;
        integer j;
        begin
            for (j = 0; j < 8; j = j + 1)
                reverse8[j] = b[7 - j];
        end
    endfunction

    always_comb begin
        rd = {reverse8(rs[31:24]), reverse8(rs[23:16]), reverse8(rs[15:8]), reverse8(rs[7:0])};
    end
endmodule


module xperm4 (
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    output logic [31:0] rd
);
    integer i;
    logic [31:0] result;
    logic [3:0] index;

    always_comb begin
        result = 32'b0;
        for (i = 0; i < 8; i++) begin
            index = rs2[4*i +: 4];
            if (index < 8)
                result[4*i +: 4] = rs1[4*index +: 4];
        end
        rd = result;
    end
endmodule


module xperm8 (
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    output logic [31:0] rd
);
    integer i;
    logic [31:0] result;
    logic [7:0] index;

    always_comb begin
        result = 32'b0;
        for (i = 0; i < 4; i++) begin
            index = rs2[8*i +: 8];
            if (index < 4)
                result[8*i +: 8] = rs1[8*index +: 8];
        end
        rd = result;
    end
endmodule


module rori(
       input [31:0] rs1,
       input [4:0] shamt,
       output [31:0] rd
    );
    assign rd = (rs1 >> shamt) | (rs1 << (32 - shamt));
endmodule

module sha256sig0(
    input [31:0] rs1,
    output [31:0] rd
    );
    wire [31:0] ror32a;
    wire [31:0] ror32b;
    wire [31:0] ror;
    rori inst1(
        .rs1(rs1),
        .shamt(5'd7),
        .rd(ror32a)
        );
    rori inst2(
        .rs1(rs1),
        .shamt(5'd18),
        .rd(ror32b)
        );
    assign ror = rs1 >> 3;
    assign rd = ror32a^ror32b^ror;
endmodule





module sha256sig1(
    input [31:0] rs1,
    output [31:0] rd
    );
    wire [31:0] ror32a;
    wire [31:0] ror32b;
    wire [31:0] ror;
    rori inst1(
        .rs1(rs1),
        .shamt(5'd17),
        .rd(ror32a)
        );
    rori inst2(
        .rs1(rs1),
        .shamt(5'd19),
        .rd(ror32b)
        );
    assign ror = rs1 >> 10;
    assign rd = ror32a^ror32b^ror;
endmodule




module sha256sum0(
    input [31:0] rs1,
    output [31:0] rd
    );
    wire [31:0] ror32a;
    wire [31:0] ror32b;
    wire [31:0] ror32c;
    rori inst1(
        .rs1(rs1),
        .shamt(5'd2),
        .rd(ror32a)
        );
    rori inst2(
        .rs1(rs1),
        .shamt(5'd13),
        .rd(ror32b)
        );
    rori inst3(
         .rs1(rs1),
         .shamt(5'd22),
         .rd(ror32c)
        );
    assign rd = ror32a^ror32b^ror32c;
endmodule



module sha256sum1(
    input [31:0] rs1,
    output [31:0] rd
    );
    wire [31:0] ror32a;
    wire [31:0] ror32b;
    wire [31:0] ror32c;
    rori inst1(
        .rs1(rs1),
        .shamt(5'd6),
        .rd(ror32a)
        );
    rori inst2(
        .rs1(rs1),
        .shamt(5'd11),
        .rd(ror32b)
        );
    rori inst3(
         .rs1(rs1),
         .shamt(5'd25),
         .rd(ror32c)
        );
    assign rd = ror32a^ror32b^ror32c;
endmodule