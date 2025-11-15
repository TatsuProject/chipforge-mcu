module aes_unit (
    input  logic [31:0] rs1,
    input  logic [31:0] rs2,
    input  logic [1:0]  bs,
    input  logic        en_dec,           // 1 = encrypt, 0 = decrypt
    input  logic        use_mixcolumn,    // 1 = apply MixColumn
    output logic [31:0] rd
);

    logic [7:0] selected_byte;
    logic [7:0] sbox_out;
    logic [31:0] mixcolumn_out;
    logic [31:0] rotated;

    assign selected_byte = rs2 >> (8 * bs);

    // S-Box
    aes_sbox sbox_inst (
        .si(selected_byte),
        .enc_dec(en_dec),
        .so(sbox_out)
    );

    // MixColumn Unit
    aes_mixcolumn mix_inst (
        .x(sbox_out),
        .enc_dec(en_dec),
        .use_mixcolumn(use_mixcolumn),
        .mix_out(mixcolumn_out)
    );

    // Byte rotation
    byte_rotate rot_inst (
        .data_in(mixcolumn_out),
        .bs(bs),
        .data_out(rotated)
    );

    assign rd = rs1 ^ rotated;

endmodule

module aes_mixcolumn (
    input  logic [7:0] x,
    input  logic       enc_dec,
    input  logic       use_mixcolumn,
    output logic [31:0] mix_out
);



    logic [7:0] y0, y1, y2, y3;

    always_comb begin
        if (!use_mixcolumn) begin
            y0 = 'b0;
            y1 = 'b0;
            y2 = 'b0;
            y3 = 'b0;
            mix_out = {24'b0, x};
        end else if (enc_dec) begin
            y0 = AES_GFMUL(x, 4'h3);
            y1 = x;
            y2 = x;
            y3 = AES_GFMUL(x, 4'h2);
            mix_out = {y0, y1, y2, y3};
        end else begin
            y0 = AES_GFMUL(x, 4'hB);
            y1 = AES_GFMUL(x, 4'hD);
            y2 = AES_GFMUL(x, 4'h9);
            y3 = AES_GFMUL(x, 4'hE);
            mix_out = {y0, y1, y2, y3};
        end
    end

endmodule


module aes_sbox (
    input logic [7:0] si, 
    input logic enc_dec,
    output logic [7:0] so 
);

    logic [7:0] sbox_o;
    logic [7:0] inv_sbox_o;

    s_box s_box_inst (
        .si(si),
        .so(sbox_o)
    );

    inv_sbox inv_sbox_inst (
        .si(si),
        .so(inv_sbox_o)
    );

    assign so = enc_dec ? sbox_o : inv_sbox_o;

endmodule


module s_box(input [7:0] si, output reg [7:0]so);
	always @(*) begin
		case(si) 
			8'h00: so=8'h63;
			8'h01: so=8'h7c;
			8'h02: so=8'h77;
			8'h03: so=8'h7b;
			8'h04: so=8'hf2;
			8'h05: so=8'h6b;
			8'h06: so=8'h6f;
			8'h07: so=8'hc5;
			8'h08: so=8'h30;
			8'h09: so=8'h01;
			8'h0a: so=8'h67;
			8'h0b: so=8'h2b;
			8'h0c: so=8'hfe;
			8'h0d: so=8'hd7;
			8'h0e: so=8'hab;
			8'h0f: so=8'h76;
			8'h10: so=8'hca;
			8'h11: so=8'h82;
			8'h12: so=8'hc9;
			8'h13: so=8'h7d;
			8'h14: so=8'hfa;
			8'h15: so=8'h59;
			8'h16: so=8'h47;
			8'h17: so=8'hf0;
			8'h18: so=8'had;
			8'h19: so=8'hd4;
			8'h1a: so=8'ha2;
			8'h1b: so=8'haf;
			8'h1c: so=8'h9c;
			8'h1d: so=8'ha4;
			8'h1e: so=8'h72;
			8'h1f: so=8'hc0;
			8'h20: so=8'hb7;
			8'h21: so=8'hfd;
			8'h22: so=8'h93;
			8'h23: so=8'h26;
			8'h24: so=8'h36;
			8'h25: so=8'h3f;
			8'h26: so=8'hf7;
			8'h27: so=8'hcc;
			8'h28: so=8'h34;
			8'h29: so=8'ha5;
			8'h2a: so=8'he5;
			8'h2b: so=8'hf1;
			8'h2c: so=8'h71;
			8'h2d: so=8'hd8;
			8'h2e: so=8'h31;
			8'h2f: so=8'h15;
			8'h30: so=8'h04;
			8'h31: so=8'hc7;
			8'h32: so=8'h23;
			8'h33: so=8'hc3;
			8'h34: so=8'h18;
			8'h35: so=8'h96;
			8'h36: so=8'h05;
			8'h37: so=8'h9a;
			8'h38: so=8'h07;
			8'h39: so=8'h12;
			8'h3a: so=8'h80;
			8'h3b: so=8'he2;
			8'h3c: so=8'heb;
			8'h3d: so=8'h27;
			8'h3e: so=8'hb2;
			8'h3f: so=8'h75;
			8'h40: so=8'h09;
			8'h41: so=8'h83;
			8'h42: so=8'h2c;
			8'h43: so=8'h1a;
			8'h44: so=8'h1b;
			8'h45: so=8'h6e;
			8'h46: so=8'h5a;
			8'h47: so=8'ha0;
			8'h48: so=8'h52;
			8'h49: so=8'h3b;
			8'h4a: so=8'hd6;
			8'h4b: so=8'hb3;
			8'h4c: so=8'h29;
			8'h4d: so=8'he3;
			8'h4e: so=8'h2f;
			8'h4f: so=8'h84;
			8'h50: so=8'h53;
			8'h51: so=8'hd1;
			8'h52: so=8'h00;
			8'h53: so=8'hed;
			8'h54: so=8'h20;
			8'h55: so=8'hfc;
			8'h56: so=8'hb1;
			8'h57: so=8'h5b;
			8'h58: so=8'h6a;
			8'h59: so=8'hcb;
			8'h5a: so=8'hbe;
			8'h5b: so=8'h39;
			8'h5c: so=8'h4a;
			8'h5d: so=8'h4c;
			8'h5e: so=8'h58;
			8'h5f: so=8'hcf;
			8'h60: so=8'hd0;
			8'h61: so=8'hef;
			8'h62: so=8'haa;
			8'h63: so=8'hfb;
			8'h64: so=8'h43;
			8'h65: so=8'h4d;
			8'h66: so=8'h33;
			8'h67: so=8'h85;
			8'h68: so=8'h45;
			8'h69: so=8'hf9;
			8'h6a: so=8'h02;
			8'h6b: so=8'h7f;
			8'h6c: so=8'h50;
			8'h6d: so=8'h3c;
			8'h6e: so=8'h9f;
			8'h6f: so=8'ha8;
			8'h70: so=8'h51;
			8'h71: so=8'ha3;
			8'h72: so=8'h40;
			8'h73: so=8'h8f;
			8'h74: so=8'h92;
			8'h75: so=8'h9d;
			8'h76: so=8'h38;
			8'h77: so=8'hf5;
			8'h78: so=8'hbc;
			8'h79: so=8'hb6;
			8'h7a: so=8'hda;
			8'h7b: so=8'h21;
			8'h7c: so=8'h10;
			8'h7d: so=8'hff;
			8'h7e: so=8'hf3;
			8'h7f: so=8'hd2;
			8'h80: so=8'hcd;
			8'h81: so=8'h0c;
			8'h82: so=8'h13;
			8'h83: so=8'hec;
			8'h84: so=8'h5f;
			8'h85: so=8'h97;
			8'h86: so=8'h44;
			8'h87: so=8'h17;
			8'h88: so=8'hc4;
			8'h89: so=8'ha7;
			8'h8a: so=8'h7e;
			8'h8b: so=8'h3d;
			8'h8c: so=8'h64;
			8'h8d: so=8'h5d;
			8'h8e: so=8'h19;
			8'h8f: so=8'h73;
			8'h90: so=8'h60;
			8'h91: so=8'h81;
			8'h92: so=8'h4f;
			8'h93: so=8'hdc;
			8'h94: so=8'h22;
			8'h95: so=8'h2a;
			8'h96: so=8'h90;
			8'h97: so=8'h88;
			8'h98: so=8'h46;
			8'h99: so=8'hee;
			8'h9a: so=8'hb8;
			8'h9b: so=8'h14;
			8'h9c: so=8'hde;
			8'h9d: so=8'h5e;
			8'h9e: so=8'h0b;
			8'h9f: so=8'hdb;
			8'ha0: so=8'he0;
			8'ha1: so=8'h32;
			8'ha2: so=8'h3a;
			8'ha3: so=8'h0a;
			8'ha4: so=8'h49;
			8'ha5: so=8'h06;
			8'ha6: so=8'h24;
			8'ha7: so=8'h5c;
			8'ha8: so=8'hc2;
			8'ha9: so=8'hd3;
			8'haa: so=8'hac;
			8'hab: so=8'h62;
			8'hac: so=8'h91;
			8'had: so=8'h95;
			8'hae: so=8'he4;
			8'haf: so=8'h79;
			8'hb0: so=8'he7;
			8'hb1: so=8'hc8;
			8'hb2: so=8'h37;
			8'hb3: so=8'h6d;
			8'hb4: so=8'h8d;
			8'hb5: so=8'hd5;
			8'hb6: so=8'h4e;
			8'hb7: so=8'ha9;
			8'hb8: so=8'h6c;
			8'hb9: so=8'h56;
			8'hba: so=8'hf4;
			8'hbb: so=8'hea;
			8'hbc: so=8'h65;
			8'hbd: so=8'h7a;
			8'hbe: so=8'hae;
			8'hbf: so=8'h08;
			8'hc0: so=8'hba;
			8'hc1: so=8'h78;
			8'hc2: so=8'h25;
			8'hc3: so=8'h2e;
			8'hc4: so=8'h1c;
			8'hc5: so=8'ha6;
			8'hc6: so=8'hb4;
			8'hc7: so=8'hc6;
			8'hc8: so=8'he8;
			8'hc9: so=8'hdd;
			8'hca: so=8'h74;
			8'hcb: so=8'h1f;
			8'hcc: so=8'h4b;
			8'hcd: so=8'hbd;
			8'hce: so=8'h8b;
			8'hcf: so=8'h8a;
			8'hd0: so=8'h70;
			8'hd1: so=8'h3e;
			8'hd2: so=8'hb5;
			8'hd3: so=8'h66;
			8'hd4: so=8'h48;
			8'hd5: so=8'h03;
			8'hd6: so=8'hf6;
			8'hd7: so=8'h0e;
			8'hd8: so=8'h61;
			8'hd9: so=8'h35;
			8'hda: so=8'h57;
			8'hdb: so=8'hb9;
			8'hdc: so=8'h86;
			8'hdd: so=8'hc1;
			8'hde: so=8'h1d;
			8'hdf: so=8'h9e;
			8'he0: so=8'he1;
			8'he1: so=8'hf8;
			8'he2: so=8'h98;
			8'he3: so=8'h11;
			8'he4: so=8'h69;
			8'he5: so=8'hd9;
			8'he6: so=8'h8e;
			8'he7: so=8'h94;
			8'he8: so=8'h9b;
			8'he9: so=8'h1e;
			8'hea: so=8'h87;
			8'heb: so=8'he9;
			8'hec: so=8'hce;
			8'hed: so=8'h55;
			8'hee: so=8'h28;
			8'hef: so=8'hdf;
			8'hf0: so=8'h8c;
			8'hf1: so=8'ha1;
			8'hf2: so=8'h89;
			8'hf3: so=8'h0d;
			8'hf4: so=8'hbf;
			8'hf5: so=8'he6;
			8'hf6: so=8'h42;
			8'hf7: so=8'h68;
			8'hf8: so=8'h41;
			8'hf9: so=8'h99;
			8'hfa: so=8'h2d;
			8'hfb: so=8'h0f;
			8'hfc: so=8'hb0;
			8'hfd: so=8'h54;
			8'hfe: so=8'hbb;
			8'hff: so=8'h16;
		endcase
	
	
	end	
endmodule


module byte_rotate (
    input  logic [31:0] data_in,
    input  logic [1:0]  bs,
    output logic [31:0] data_out
);
    always_comb begin
        case (bs)
            2'd0: data_out = data_in;
            2'd1: data_out = {data_in[23:0], data_in[31:24]};
            2'd2: data_out = {data_in[15:0], data_in[31:16]};
            2'd3: data_out = {data_in[7:0],  data_in[31:8]};
        endcase
    end
endmodule




module inv_sbox(si,so);
input  [7:0] si; 
output reg [7:0] so;

 always@(*)
 begin  
    case(si)
				8'h00:so =8'h52;
				8'h01:so =8'h09;
				8'h02:so =8'h6a;
				8'h03:so =8'hd5;
				8'h04:so =8'h30;
				8'h05:so =8'h36;
				8'h06:so =8'ha5;
				8'h07:so =8'h38;
				8'h08:so =8'hbf;
				8'h09:so =8'h40;
				8'h0a:so =8'ha3;
				8'h0b:so =8'h9e;
				8'h0c:so =8'h81;
				8'h0d:so =8'hf3;
				8'h0e:so =8'hd7;
				8'h0f:so =8'hfb;
				8'h10:so =8'h7c;
				8'h11:so =8'he3;
				8'h12:so =8'h39;
				8'h13:so =8'h82;
				8'h14:so =8'h9b;
				8'h15:so =8'h2f;
				8'h16:so =8'hff;
				8'h17:so =8'h87;
				8'h18:so =8'h34;
				8'h19:so =8'h8e;
				8'h1a:so =8'h43;
				8'h1b:so =8'h44;
				8'h1c:so =8'hc4;
				8'h1d:so =8'hde;
				8'h1e:so =8'he9;
				8'h1f:so =8'hcb;
				8'h20:so =8'h54;
				8'h21:so =8'h7b;
				8'h22:so =8'h94;
				8'h23:so =8'h32;
				8'h24:so =8'ha6;
				8'h25:so =8'hc2;
				8'h26:so =8'h23;
				8'h27:so =8'h3d;
				8'h28:so =8'hee;
				8'h29:so =8'h4c;
				8'h2a:so =8'h95;
				8'h2b:so =8'h0b;
				8'h2c:so =8'h42;
				8'h2d:so =8'hfa;
				8'h2e:so =8'hc3;
				8'h2f:so =8'h4e;
				8'h30:so =8'h08;
				8'h31:so =8'h2e;
				8'h32:so =8'ha1;
				8'h33:so =8'h66;
				8'h34:so =8'h28;
				8'h35:so =8'hd9;
				8'h36:so =8'h24;
				8'h37:so =8'hb2;
				8'h38:so =8'h76;
				8'h39:so =8'h5b;
				8'h3a:so =8'ha2;
				8'h3b:so =8'h49;
				8'h3c:so =8'h6d;
				8'h3d:so =8'h8b;
				8'h3e:so =8'hd1;
				8'h3f:so =8'h25;
				8'h40:so =8'h72;
				8'h41:so =8'hf8;
				8'h42:so =8'hf6;
				8'h43:so =8'h64;
				8'h44:so =8'h86;
				8'h45:so =8'h68;
				8'h46:so =8'h98;
				8'h47:so =8'h16;
				8'h48:so =8'hd4;
				8'h49:so =8'ha4;
				8'h4a:so =8'h5c;
				8'h4b:so =8'hcc;
				8'h4c:so =8'h5d;
				8'h4d:so =8'h65;
				8'h4e:so =8'hb6;
				8'h4f:so =8'h92;
				8'h50:so =8'h6c;
				8'h51:so =8'h70;
				8'h52:so =8'h48;
				8'h53:so =8'h50;
				8'h54:so =8'hfd;
				8'h55:so =8'hed;
				8'h56:so =8'hb9;
				8'h57:so =8'hda;
				8'h58:so =8'h5e;
				8'h59:so =8'h15;
				8'h5a:so =8'h46;
				8'h5b:so =8'h57;
				8'h5c:so =8'ha7;
				8'h5d:so =8'h8d;
				8'h5e:so =8'h9d;
				8'h5f:so =8'h84;
				8'h60:so =8'h90;
				8'h61:so =8'hd8;
				8'h62:so =8'hab;
				8'h63:so =8'h00;
				8'h64:so =8'h8c;
				8'h65:so =8'hbc;
				8'h66:so =8'hd3;
				8'h67:so =8'h0a;
				8'h68:so =8'hf7;
				8'h69:so =8'he4;
				8'h6a:so =8'h58;
				8'h6b:so =8'h05;
				8'h6c:so =8'hb8;
				8'h6d:so =8'hb3;
				8'h6e:so =8'h45;
				8'h6f:so =8'h06;
				8'h70:so =8'hd0;
				8'h71:so =8'h2c;
				8'h72:so =8'h1e;
				8'h73:so =8'h8f;
				8'h74:so =8'hca;
				8'h75:so =8'h3f;
				8'h76:so =8'h0f;
				8'h77:so =8'h02;
				8'h78:so =8'hc1;
				8'h79:so =8'haf;
				8'h7a:so =8'hbd;
				8'h7b:so =8'h03;
				8'h7c:so =8'h01;
				8'h7d:so =8'h13;
				8'h7e:so =8'h8a;
				8'h7f:so =8'h6b;
				8'h80:so =8'h3a;
				8'h81:so =8'h91;
				8'h82:so =8'h11;
				8'h83:so =8'h41;
				8'h84:so =8'h4f;
				8'h85:so =8'h67;
				8'h86:so =8'hdc;
				8'h87:so =8'hea;
				8'h88:so =8'h97;
				8'h89:so =8'hf2;
				8'h8a:so =8'hcf;
				8'h8b:so =8'hce;
				8'h8c:so =8'hf0;
				8'h8d:so =8'hb4;
				8'h8e:so =8'he6;
				8'h8f:so =8'h73;
				8'h90:so =8'h96;
				8'h91:so =8'hac;
				8'h92:so =8'h74;
				8'h93:so =8'h22;
				8'h94:so =8'he7;
				8'h95:so =8'had;
				8'h96:so =8'h35;
				8'h97:so =8'h85;
				8'h98:so =8'he2;
				8'h99:so =8'hf9;
				8'h9a:so =8'h37;
				8'h9b:so =8'he8;
				8'h9c:so =8'h1c;
				8'h9d:so =8'h75;
				8'h9e:so =8'hdf;
				8'h9f:so =8'h6e;
				8'ha0:so =8'h47;
				8'ha1:so =8'hf1;
				8'ha2:so =8'h1a;
				8'ha3:so =8'h71;
				8'ha4:so =8'h1d;
				8'ha5:so =8'h29;
				8'ha6:so =8'hc5;
				8'ha7:so =8'h89;
				8'ha8:so =8'h6f;
				8'ha9:so =8'hb7;
				8'haa:so =8'h62;
				8'hab:so =8'h0e;
				8'hac:so =8'haa;
				8'had:so =8'h18;
				8'hae:so =8'hbe;
				8'haf:so =8'h1b;
				8'hb0:so =8'hfc;
				8'hb1:so =8'h56;
				8'hb2:so =8'h3e;
				8'hb3:so =8'h4b;
				8'hb4:so =8'hc6;
				8'hb5:so =8'hd2;
				8'hb6:so =8'h79;
				8'hb7:so =8'h20;
				8'hb8:so =8'h9a;
				8'hb9:so =8'hdb;
				8'hba:so =8'hc0;
				8'hbb:so =8'hfe;
				8'hbc:so =8'h78;
				8'hbd:so =8'hcd;
				8'hbe:so =8'h5a;
				8'hbf:so =8'hf4;
				8'hc0:so =8'h1f;
				8'hc1:so =8'hdd;
				8'hc2:so =8'ha8;
				8'hc3:so =8'h33;
				8'hc4:so =8'h88;
				8'hc5:so =8'h07;
				8'hc6:so =8'hc7;
				8'hc7:so =8'h31;
				8'hc8:so =8'hb1;
				8'hc9:so =8'h12;
				8'hca:so =8'h10;
				8'hcb:so =8'h59;
				8'hcc:so =8'h27;
				8'hcd:so =8'h80;
				8'hce:so =8'hec;
				8'hcf:so =8'h5f;
				8'hd0:so =8'h60;
				8'hd1:so =8'h51;
				8'hd2:so =8'h7f;
				8'hd3:so =8'ha9;
				8'hd4:so =8'h19;
				8'hd5:so =8'hb5;
				8'hd6:so =8'h4a;
				8'hd7:so =8'h0d;
				8'hd8:so =8'h2d;
				8'hd9:so =8'he5;
				8'hda:so =8'h7a;
				8'hdb:so =8'h9f;
				8'hdc:so =8'h93;
				8'hdd:so =8'hc9;
				8'hde:so =8'h9c;
				8'hdf:so =8'hef;
				8'he0:so =8'ha0;
				8'he1:so =8'he0;
				8'he2:so =8'h3b;
				8'he3:so =8'h4d;
				8'he4:so =8'hae;
				8'he5:so =8'h2a;
				8'he6:so =8'hf5;
				8'he7:so =8'hb0;
				8'he8:so =8'hc8;
				8'he9:so =8'heb;
				8'hea:so =8'hbb;
				8'heb:so =8'h3c;
				8'hec:so =8'h83;
				8'hed:so =8'h53;
				8'hee:so =8'h99;
				8'hef:so =8'h61;
				8'hf0:so =8'h17;
				8'hf1:so =8'h2b;
				8'hf2:so =8'h04;
				8'hf3:so =8'h7e;
				8'hf4:so =8'hba;
				8'hf5:so =8'h77;
				8'hf6:so =8'hd6;
				8'hf7:so =8'h26;
				8'hf8:so =8'he1;
				8'hf9:so =8'h69;
				8'hfa:so =8'h14;
				8'hfb:so =8'h63;
				8'hfc:so =8'h55;
				8'hfd:so =8'h21;
				8'hfe:so =8'h0c;
				8'hff:so =8'h7d;
				endcase
end

endmodule

