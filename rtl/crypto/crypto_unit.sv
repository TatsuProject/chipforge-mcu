// `include "../riscv_types.vh"


module crypto_unit (
    input logic [31:0] rs1,
    input logic [31:0] rs2,
    input logic [1:0] sha_sel,
    input alu_t crypto_ctrl,
    output logic [31:0] crypto_result,
    output logic result_valid
);

    logic [1:0] aes_bs;
    logic aes_en_dec;
    logic aes_mix_en;
    logic is_aes;
    logic [31:0] aes_result;

    assign aes_bs = crypto_ctrl[9:8];


    // AES configuration signals based on instruction type
    always_comb begin
        aes_en_dec = 1'b0;
        aes_mix_en = 1'b0;
        is_aes     = 1'b0;

        case (crypto_ctrl & 10'h0ff)
            AES32ESMI: begin aes_en_dec = 1'b1; aes_mix_en = 1'b1; is_aes = 1'b1; end
            AES32ESI : begin aes_en_dec = 1'b1; aes_mix_en = 1'b0; is_aes = 1'b1; end
            AES32DSMI: begin aes_en_dec = 1'b0; aes_mix_en = 1'b1; is_aes = 1'b1; end
            AES32DSI : begin aes_en_dec = 1'b0; aes_mix_en = 1'b0; is_aes = 1'b1; end
        endcase
    end

    // Unified AES module
    aes_unit aes_core (
        .rs1(rs1),
        .rs2(rs2),
        .bs(aes_bs),
        .en_dec(aes_en_dec),
        .use_mixcolumn(aes_mix_en),
        .rd(aes_result)
    );

    // SHA function outputs
    logic [31:0] sha256sig0_out, sha256sig1_out;
    logic [31:0] sha256sum0_out, sha256sum1_out;

    // SHA module instantiations
    sha256sig0 SHA_SIG0 (.rs1(rs1), .rd(sha256sig0_out));
    sha256sig1 SHA_SIG1 (.rs1(rs1), .rd(sha256sig1_out));
    sha256sum0 SHA_SUM0 (.rs1(rs1), .rd(sha256sum0_out));
    sha256sum1 SHA_SUM1 (.rs1(rs1), .rd(sha256sum1_out));

    // Result selection
    always_comb begin
        if (crypto_ctrl == SHA256)
        begin 
                case (sha_sel)
                    2'b00: crypto_result = sha256sum0_out;
                    2'b01: crypto_result = sha256sum1_out;
                    2'b10: crypto_result = sha256sig0_out;
                    2'b11: crypto_result = sha256sig1_out;
                endcase
        end else begin 
            crypto_result = aes_result;
        end
    end


    assign result_valid = is_aes | (crypto_ctrl == SHA256);

endmodule