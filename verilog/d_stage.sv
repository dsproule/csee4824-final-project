
// The decoder, copied from p3/stage_id.sv without changes

`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

module decoder (
    input INST  inst,
    input logic valid, // when low, ignore inst. Output will look like a NOP

    output ALU_OPA_SELECT opa_select,
    output ALU_OPB_SELECT opb_select,
    output logic          has_dest, // if there is a destination register
    output ALU_FUNC       alu_func,
    output logic          rd_mem, wr_mem, cond_branch, uncond_branch,
    output logic          csr_op, // used for CSR operations, we only use this as a cheap way to get the return code out
    output logic          halt,   // non-zero on a halt
    output logic          illegal // non-zero on an illegal instruction
);

    // Note: I recommend using an IDE's code folding feature on this block
    always_comb begin
        // Default control values (looks like a NOP)
        // See sys_defs.svh for the constants used here
        opa_select    = OPA_IS_RS1;
        opb_select    = OPB_IS_RS2;
        alu_func      = ALU_ADD;
        has_dest      = `FALSE;
        csr_op        = `FALSE;
        rd_mem        = `FALSE;
        wr_mem        = `FALSE;
        cond_branch   = `FALSE;
        uncond_branch = `FALSE;
        halt          = `FALSE;
        illegal       = `FALSE;

        if (valid) begin
            casez (inst)
                `RV32_LUI: begin
                    has_dest   = `TRUE;
                    opa_select = OPA_IS_ZERO;
                    opb_select = OPB_IS_U_IMM;
                end
                `RV32_AUIPC: begin
                    has_dest   = `TRUE;
                    opa_select = OPA_IS_PC;
                    opb_select = OPB_IS_U_IMM;
                end
                `RV32_JAL: begin
                    has_dest      = `TRUE;
                    opa_select    = OPA_IS_PC;
                    opb_select    = OPB_IS_J_IMM;
                    uncond_branch = `TRUE;
                end
                `RV32_JALR: begin
                    has_dest      = `TRUE;
                    opa_select    = OPA_IS_RS1;
                    opb_select    = OPB_IS_I_IMM;
                    uncond_branch = `TRUE;
                end
                `RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE,
                `RV32_BLTU, `RV32_BGEU: begin
                    opa_select  = OPA_IS_PC;
                    opb_select  = OPB_IS_B_IMM;
                    cond_branch = `TRUE;
                end
                `RV32_LB, `RV32_LH, `RV32_LW,
                `RV32_LBU, `RV32_LHU: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    rd_mem     = `TRUE;
                end
                `RV32_SB, `RV32_SH, `RV32_SW: begin
                    opb_select = OPB_IS_S_IMM;
                    wr_mem     = `TRUE;
                end
                `RV32_ADDI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                end
                `RV32_SLTI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLT;
                end
                `RV32_SLTIU: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLTU;
                end
                `RV32_ANDI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_AND;
                end
                `RV32_ORI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_OR;
                end
                `RV32_XORI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_XOR;
                end
                `RV32_SLLI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLL;
                end
                `RV32_SRLI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SRL;
                end
                `RV32_SRAI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SRA;
                end
                `RV32_ADD: begin
                    has_dest   = `TRUE;
                end
                `RV32_SUB: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SUB;
                end
                `RV32_SLT: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLT;
                end
                `RV32_SLTU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLTU;
                end
                `RV32_AND: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_AND;
                end
                `RV32_OR: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_OR;
                end
                `RV32_XOR: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_XOR;
                end
                `RV32_SLL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLL;
                end
                `RV32_SRL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SRL;
                end
                `RV32_SRA: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SRA;
                end
                `RV32_MUL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MUL;
                end
                `RV32_MULH: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MULH;
                end
                `RV32_MULHSU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MULHSU;
                end
                `RV32_MULHU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MULHU;
                end
                `RV32_CSRRW, `RV32_CSRRS, `RV32_CSRRC: begin
                    csr_op = `TRUE;
                end
                `WFI: begin
                    halt = `TRUE;
                end
                default: begin
                    illegal = `TRUE;
                end
        endcase // casez (inst)
        end // if (valid)
    end // always

endmodule // decoder

module d_stage (
    input IF_ID_PACKET IF_ID_reg,

    output D_S_PACKET D_packet
);

    logic has_dest, rd_mem, wr_mem;
    logic [`RS_SZ-1:0] rs_idx;   

    // Pass throughs (Used by the X stage if needed)
    assign D_packet.inst = IF_ID_reg.inst;
    assign D_packet.PC   = IF_ID_reg.PC;
    assign D_packet.NPC  = IF_ID_reg.NPC;

    // Register values for map table signals
    assign D_packet.r = (has_dest) ? IF_ID_reg.inst.r.rd : `ZERO_REG;
    assign D_packet.r1 = IF_ID_reg.inst.r.rs1;
    assign D_packet.r2 = (D_packet.opb_select != OPB_IS_RS2) ? '0 : IF_ID_reg.inst.r.rs2;
    assign D_packet.has_dest = has_dest;

    // mem details
    assign D_packet.mem_offset = (rd_mem) ? `RV32_signext_Iimm(IF_ID_reg.inst) : 
	    			 (wr_mem) ? `RV32_signext_Simm(IF_ID_reg.inst) : '0;
    assign D_packet.rd_unsigned  = IF_ID_reg.inst.r.funct3[2]; // 1 if unsigned, 0 if signed
    assign D_packet.mem_size     = MEM_SIZE'(IF_ID_reg.inst.r.funct3[1:0]);
    
    assign D_packet.valid = IF_ID_reg.valid & ~D_packet.illegal;

    always_comb begin
        // FU assignment
        if (rd_mem)
            D_packet.rs_idx = `NUM_FU_LOAD;   
        else if (wr_mem)
            D_packet.rs_idx = `NUM_FU_STORE;
        else if (D_packet.alu_func == ALU_MUL    | D_packet.alu_func == ALU_MULHSU |
                 D_packet.alu_func == ALU_MULHSU | D_packet.alu_func == ALU_MULHU)
            D_packet.rs_idx = `NUM_FU_MULT;
        else
            D_packet.rs_idx = `NUM_FU_ALU;
    end

    decoder decoder_0 (
        // Inputs
        .inst  (IF_ID_reg.inst),
        .valid (IF_ID_reg.valid),

        // Outputs
        .opa_select    (D_packet.opa_select),
        .opb_select    (D_packet.opb_select),
        .alu_func      (D_packet.alu_func),
        .has_dest      (has_dest),
        .rd_mem        (rd_mem),
        .wr_mem        (wr_mem),
        .cond_branch   (D_packet.cond_branch),
        .uncond_branch (D_packet.uncond_branch),
        .csr_op        (D_packet.csr_op),
        .halt          (D_packet.halt),
        .illegal       (D_packet.illegal)
    );

endmodule // d_stage
