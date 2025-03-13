`include "verilog/sys_defs.svh"

module lsq(
    // i dont know all of these yet but these are my predictions for the FIFO.
    // this just has to issue stores and support CAM for the ld inst
    input clock, reset, en, ld_req, st_req,
    input logic [`XLEN-1:0] mem2proc_data,
    input logic [63:0] mem2proc_addr,                   // fifo and ld can both use this port

    output logic lsq_has_ld,
    output logic [`XLEN-1:0] lsq2mem_val,
    output logic [`XLEN-1:0] proc2mem_addr,
    // mem is 64 bit line so maybe pack 2 values into 1 if they're both ready to commit? 
    // In this case add more i/o for ROB but I'll let you investigate
    output logic [63:0]      proc2mem_data
);

endmodule