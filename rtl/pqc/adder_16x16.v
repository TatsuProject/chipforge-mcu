// =============================================================================
//  File        : adder_16x16.v
//  Description : 16-bit signed adder
//  Author      : Muhammad Abdullah
//  Created     : Dec 3, 2025
//  Version     : 1.0
//  Project     : Post-Quantum Cryptography Hardware Accelerator (Kyber NTT)
//  Tool        : Vivado 202x.x
// =============================================================================

module adder_16x16 (
    input  signed [15:0] op1_i,   // Operand 1
    input  signed [15:0] op2_i,   // Operand 2
    output signed [15:0] result   // Result = op1_i + op2_i
);

// Perform signed addition
assign result = op1_i + op2_i;

endmodule
