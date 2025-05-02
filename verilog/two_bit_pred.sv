`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

// hardwired branch predictor to always assume branch taken
module two_bit_pred(
    input clock, reset, en, 
    input D_S_PACKET D_packet,

    output [`XLEN-1:0] branch_target,
    output branch_pred
);
    // set right now to "assume branch taken"
    assign branch_pred   = en;
    assign branch_target = D_packet.PC + `RV32_signext_Bimm(D_packet.inst);

endmodule