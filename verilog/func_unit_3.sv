`include "verilog/sys_defs.svh"

module func_unit_3(
    input clock, reset,
    input S_X_PACKET S_X_reg,

    // output lsq i/o so we can load it
    output X_C_PACKET X_C_packet
);
    logic lsq_full;

    assign X_C_packet.valid = ~lsq_full;        // no cdb values so nothing to pass to arb

    // load the lsq

endmodule   // func_unit_3