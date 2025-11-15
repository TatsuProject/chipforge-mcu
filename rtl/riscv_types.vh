// riscv_types.vh
// Flattened version of riscv_types package for Yosys (no packages)

    // ALU operation types
    typedef enum logic [9:0]  { 
        ADD, SLL_, SLT, SLTU, XOR, SRL_, OR, AND_, 
        SUB   = 256,
        PACK  = 36,
        PACKH = 39,
        CLMUL = 41, 
        CLMULH = 43,
        XPERM4 = 162,
        XPERM8 = 164,
        XNORN  = 260,
        SRA_   = 261,
        ORN    = 262,
        ANDN   = 263,
        ROL_   = 385,
        ROR_   = 389,
        REV    = 421,
        BREV   = 422,
        ZIP    = 33,
        UNZIP  = 37,
        // encryption and decryption added 
        AES32ESMI = 152,
        AES32ESI  = 136,
        AES32DSI  = 168,
        AES32DSMI = 184,
        // SHA instruction added 
        SHA256 = 65
    } alu_t;

    function automatic logic is_aes32esmi(alu_t op);
        return (op == AES32ESMI || op == 664 || op == 408 || op == 920);
    endfunction

    function automatic logic is_aes32esi(alu_t op);
        return (op == AES32ESI || op == 392 || op == 648 || op == 904);
    endfunction

    function automatic logic is_aes32dsi(alu_t op);
        return (op == AES32DSI || op == 424 || op == 680 || op == 936);
    endfunction

    function automatic logic is_aes32dsmi(alu_t op);
        return (op == AES32DSMI || op == 440 || op == 696 || op == 952);
    endfunction

    function automatic logic is_sha256(alu_t op);
        return (op == SHA256);
    endfunction

    // EXTRA LOGIC  
    function automatic logic get_crypt_en(alu_t op);
        case (op)
            136, 392, 648, 904: get_crypt_en = 1'b0;  // not set for final round 
            152, 408, 664, 920: get_crypt_en = 1'b1;  // set for middle round 
            default:            get_crypt_en = 1'b0;  // Non-crypto operations
        endcase
    endfunction

    // Store operation types
    typedef enum logic [1:0] { 
        STORE_BYTE, STORE_HALFWORD, STORE_WORD 
    } store_t;

    // IF1/IF2 Register Structure
    typedef struct packed {
        logic [31:0] current_pc;
    } if1_if2_reg_t;

    // IF/ID Register Structure
    typedef struct packed {
        logic [31:0] current_pc;
        logic [31:0] pc_plus_4;
        logic [31:0] inst;
        logic        inst_valid;
    } if2_id_reg_t;

    // ID/EX Register Structure
    typedef struct packed {
        logic [31:0] current_pc; 
        logic [31:0] pc_plus_4;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rd; 
        logic [2:0]  fun3;
        logic [6:0]  fun7;
        logic [4:0]  fun5;
        logic [4:0]  sha_sel;
        logic [6:0]  opcode;
        logic [31:0] reg_rdata1;
        logic [31:0] reg_rdata2;
        logic [31:0] imm;
        logic [11:0] csr_addr;
        // Control signals
        logic        reg_write;
        logic        mem_write;
        logic        mem_to_reg;
        logic        branch;
        logic        alu_src;
        logic        jump;
        logic        lui;
        logic        auipc;
        logic        jal;
        logic [1:0]  alu_op;
        logic        csr_inst;
        logic        csr_en;
        logic        trap_ret;
        logic        is_atomic;
        logic        is_mul;
        logic        is_div;
        logic        ecall;
        logic        illegal_inst;
        logic        inst_valid;
        logic        ebreak_inst;
        logic        is_montgomery;
        logic [31:0] inst;
    } id_exe_reg_t;

    // EX/MEM Register Structure
    typedef struct packed {
        logic [31:0] pc_plus_4;
        logic [31:0] pc_jump;      
        logic [4:0]  rs2;
        logic [4:0]  rd; 
        logic [2:0]  fun3;
        logic [31:0] rdata2_frw;
        logic [31:0] imm;
        logic [31:0] crypto_alu_result;
        logic [31:0] reg_rdata1;
        logic [11:0] csr_addr;
        logic [31:0] current_pc;
        // Control signals
        logic        reg_write;
        logic        mem_write;
        logic        mem_to_reg;
        logic        branch;
        logic        jump;
        logic        lui;
        logic        zero;
        logic        csr_inst;
        logic        csr_en;
        logic        trap_ret;
        logic        is_atomic;
        logic        is_mul;
        logic        ecall;
        logic        illegal_inst;
        logic        inst_valid;
        logic        ebreak_inst;
        logic        is_montgomery;
        logic [31:0] inst;
        `ifdef tracer 
            logic [4:0]  rs1;
        `endif
    } exe_mem_reg_t;

    // MEM/WB Register Structure
    typedef struct packed {
        logic [4:0]  rd; 
        logic [31:0] result;
        logic [31:0] mem_rdata;
        logic [31:0] mul_result;
        logic [31:0] pqc_result;
        logic        is_montgomery;
        // Control signals
        logic        reg_write;
        logic        mem_to_reg;
        logic        is_mul;
        logic        inst_valid;
        `ifdef tracer 
            logic        pc_sel;
            logic [31:0] inst;
            logic [4:0]  rs1;
            logic [4:0]  rs2;
            logic [31:0] reg_rdata1;
            logic [31:0] reg_rdata2;
            logic [31:0] current_pc;
            logic [31:0] mem_wdata; 
            logic [31:0] mem_addr;
        `endif
    } mem_wb_reg_t;




    typedef enum logic[0:0] {
        FALSE,
        TRUE
    } onebit_sig_e;


    typedef enum logic[4:0] {
        IDCODE = 5'b00001,
        BYPASS = 5'b11111,
        DTMCS  = 5'b10000,
        DMI    = 5'b10001
    } tap_ins_e;

    typedef enum logic [3:0]{
        TEST_LOGIC_RESET = 4'hF,
        RUN_TEST_IDLE    = 4'hC,
        SELECT_DR_SCAN   = 4'h7,
        CAPTURE_DR       = 4'h6,
        SHIFT_DR         = 4'h2,
        EXIT1_DR         = 4'h1,
        PAUSE_DR         = 4'h3,
        EXIT2_DR         = 4'h0,
        UPDATE_DR        = 4'h5,
        SELECT_IR_SCAN   = 4'h4,
        CAPTURE_IR       = 4'hE,
        SHIFT_IR         = 4'hA,
        EXIT1_IR         = 4'h9,
        PAUSE_IR         = 4'hB,
        EXIT2_IR         = 4'h8,
        UPDATE_IR        = 4'hD
    } tap_states_e;

    typedef enum logic [6:0]{
        DATA0        = 7'h04,
        DATA1        = 7'h05,
        DATA2        = 7'h06,
        DATA3        = 7'h07,
        DATA4        = 7'h08,
        DATA5        = 7'h09,
        DATA6        = 7'h0a,
        DATA7        = 7'h0b,
        DATA8        = 7'h0c,
        DATA9        = 7'h0d,
        DATA10       = 7'h0e,
        DATA11       = 7'h0f,
        DMCONTROL    = 7'h10,
        DMSTATUS     = 7'h11,
        HALTSUM1     = 7'h12,
        HARTINFO     = 7'h13,
        HAWINDOWSEL  = 7'h14,
        HAWINDOW     = 7'h15,
        ABSTRACTCS   = 7'h16,
        COMMAND      = 7'h17,
        ABSTRACTAUTO = 7'h18,
        CONFSTRPTR0  = 7'h19,
        CONFSTRPTR1  = 7'h1A,
        CONFSTRPTR2  = 7'h1B,
        CONFSTRPTR3  = 7'h1C,
        NEXTDM       = 7'h1D,
        PROGBUF0     = 7'h20,
        PROGBUF1     = 7'h21,
        PROGBUF2     = 7'h22,
        PROGBUF3     = 7'h23,
        PROGBUF4     = 7'h24,
        PROGBUF5     = 7'h25,
        PROGBUF6     = 7'h26,
        PROGBUF7     = 7'h27,
        PROGBUF8     = 7'h28,
        PROGBUF9     = 7'h29,
        PROGBUF10    = 7'h2A,
        PROGBUF11    = 7'h2B,
        PROGBUF12    = 7'h2C,
        PROGBUF13    = 7'h2D,
        PROGBUF14    = 7'h2E,
        PROGBUF15    = 7'h2F,
        AUTODATA     = 7'h30,
        HALTSUM2     = 7'h34,
        HALTSUM3     = 7'h35,
        HALTSUM0     = 7'h40
    } dm_addresses_e;

    typedef enum logic [2:0]{
        NO_DBG_CAUSE,
        DBG_EBREAK,
        DBG_HALTREQ = 3'd3,
        DBG_STEP = 3'd4
    } dcause_e;

    typedef enum logic [2:0]{
        NONE,
        BUSY,
        UNSUPPORTED
    } cmderr_e;

    function automatic [7:0] AES_XTIME(input [7:0] in);
        AES_XTIME = in[7] ? ((in << 1) ^ 8'h1B) : (in << 1);
    endfunction

    function automatic [7:0] AES_GFMUL(input [7:0] a, input [3:0] b);
        logic [7:0] result;
        logic [7:0] xt1, xt2, xt3;

        xt1 = AES_XTIME(a);              // a * 2
        xt2 = AES_XTIME(xt1);            // a * 4
        xt3 = AES_XTIME(xt2);            // a * 8

        result = 8'd0;
        if (b[0]) result ^= a;           // b & 1
        if (b[1]) result ^= xt1;         // b & 2
        if (b[2]) result ^= xt2;         // b & 4
        if (b[3]) result ^= xt3;         // b & 8

        AES_GFMUL = result;
    endfunction