`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

module alu (
    input [`XLEN-1:0] opa,
    input [`XLEN-1:0] opb,
    ALU_FUNC          func,

    output logic [`XLEN-1:0] result
);

    logic signed [`XLEN-1:0]   signed_opa, signed_opb;

    assign signed_opa   = opa;
    assign signed_opb   = opb;

    always_comb begin
        case (func)
            ALU_ADD:    result = opa + opb;
            ALU_SUB:    result = opa - opb;
            ALU_AND:    result = opa & opb;
            ALU_SLT:    result = signed_opa < signed_opb;
            ALU_SLTU:   result = opa < opb;
            ALU_OR:     result = opa | opb;
            ALU_XOR:    result = opa ^ opb;
            ALU_SRL:    result = opa >> opb[4:0];
            ALU_SLL:    result = opa << opb[4:0];
            ALU_SRA:    result = signed_opa >>> opb[4:0]; // arithmetic from logical shift

            default:    result = `XLEN'hfacebeec;  // here to prevent latches
        endcase
    end

endmodule // alu


// Conditional branch module: compute whether to take conditional branches
// This module is purely combinational
module conditional_branch (
    input [2:0]       func, // Specifies which condition to check
    input [`XLEN-1:0] rs1,  // Value to check against condition
    input [`XLEN-1:0] rs2,

    output logic take // True/False condition result
);

    logic signed [`XLEN-1:0] signed_rs1, signed_rs2;
    assign signed_rs1 = rs1;
    assign signed_rs2 = rs2;
    always_comb begin
        case (func)
            3'b000:  take = signed_rs1 == signed_rs2; // BEQ
            3'b001:  take = signed_rs1 != signed_rs2; // BNE
            3'b100:  take = signed_rs1 < signed_rs2;  // BLT
            3'b101:  take = signed_rs1 >= signed_rs2; // BGE
            3'b110:  take = rs1 < rs2;                // BLTU
            3'b111:  take = rs1 >= rs2;               // BGEU
            default: take = `FALSE;
        endcase
    end

endmodule // conditional_branch


module func_unit_0 (
    input S_X_PACKET S_X_reg,

    output X_C_PACKET X_packet
);
    logic [`XLEN-1:0] opa_mux_out, opb_mux_out;
    PPLN_CTRL ppln_ctrl;
    logic take_conditional;

    // Pass-throughs
    assign X_packet.T = S_X_reg.T;
    assign X_packet.valid = S_X_reg.valid;

    // pipeline control
    assign ppln_ctrl.flush = S_X_reg.uncond_branch || (S_X_reg.cond_branch && take_conditional);
    assign ppln_ctrl.is_store = `FALSE;
    assign ppln_ctrl.is_branch = S_X_reg.uncond_branch | S_X_reg.cond_branch;

    assign ppln_ctrl.illegal = 0;
    assign ppln_ctrl.halt = S_X_reg.halt;

    assign X_packet.ppln_ctrl = ppln_ctrl;

        // ALU opA mux
    always_comb begin
        case (S_X_reg.opa_select)
            OPA_IS_RS1:  opa_mux_out = S_X_reg.V1;
            OPA_IS_NPC:  opa_mux_out = S_X_reg.NPC;
            OPA_IS_PC:   opa_mux_out = S_X_reg.PC;
            OPA_IS_ZERO: opa_mux_out = 0;
            default:     opa_mux_out = `XLEN'hdeadface; // dead face
        endcase
    end

    // ALU opB mux
    always_comb begin
        case (S_X_reg.opb_select)
            OPB_IS_RS2:   opb_mux_out = S_X_reg.V2;
            OPB_IS_I_IMM: opb_mux_out = `RV32_signext_Iimm(S_X_reg.inst);
            OPB_IS_B_IMM: opb_mux_out = `RV32_signext_Bimm(S_X_reg.inst);
            OPB_IS_U_IMM: opb_mux_out = `RV32_signext_Uimm(S_X_reg.inst);
            OPB_IS_J_IMM: opb_mux_out = `RV32_signext_Jimm(S_X_reg.inst);
            default:      opb_mux_out = `XLEN'hfacefeed; // face feed
        endcase
    end

    
    alu alu_0 (
        // Inputs
        .opa(opa_mux_out),
        .opb(opb_mux_out),
        .func(S_X_reg.alu_func),

        // Output
        .result(X_packet.result)
    );

    // Instantiate the conditional branch module
    conditional_branch conditional_branch_0 (
        // Inputs
        .func(S_X_reg.inst.b.funct3), // instruction bits for which condition to check
        .rs1(S_X_reg.V1),
        .rs2(S_X_reg.V2),

        // Output
        .take(take_conditional)
    );

endmodule // stage_ex
