// =============================================================================
//  File        : sub_32x32.v
//  Description : 32-bit signed subtraction module
//  Author      : Muhammad Abdullah
//  Created     : Dec 3, 2025
//  Version     : 1.0
//  Project     : Post-Quantum Cryptography Hardware Accelerator (Kyber NTT)
//  Tool        : Vivado 202x.x
// =============================================================================

module sub_32x32 (
    input  signed [31:0] op1_i,  // Operand 1
    input  signed [31:0] op2_i,  // Operand 2
    output signed [31:0] result  // Result = op1_i - op2_i
);

// Perform signed 32-bit subtraction
assign result = op1_i - op2_i;

endmodule
