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

    output X_C_PACKET X_C_packet
);
    logic take_conditional;

    // Pass-throughs
    assign X_C_packet.T = S_X_reg.T;
    assign X_C_packet.branch = (S_X_reg.cond_branch | S_X_reg.uncond_branch);
    assign X_C_packet.ready = `TRUE;

    // ultimate "take branch" signal:
    // unconditional, or conditional and the condition is true
    assign ex_packet.take_branch = S_X_reg.uncond_branch || (S_X_reg.cond_branch && take_conditional);

    // Assume the muxing from before is handled by RS/decode stage
    alu alu_0 (
        // Inputs
        .opa(S_X_reg.V1),
        .opb(S_X_reg.V2),
        .func(S_X_reg.alu_func),

        // Output
        .result(X_C_reg.result)
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
