`timescale 1ns/1ps
`include "verilog/sys_defs.svh"
`include "verilog/ISA.svh"

module icache_check;

    logic clock;
    logic reset;

    logic [3:0] mem2proc_response;
    logic [63:0] mem2proc_data;
    logic [3:0] mem2proc_tag;

    logic [`XLEN-1:0] proc2cache_addr;

    logic [1:0]       proc2mem_command;
    logic [`XLEN-1:0] proc2mem_addr;

    // To fetch stage
    logic [63:0] cache_data_out;
    logic        cache_valid_out;

    /* Memory handling section */
    mem mem_ref (
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        // .proc2mem_data(proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size(proc2mem_size),
`endif
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );

    icache icache_0 (
        .clock(clock), .reset(reset),

        // From memory
        .Imem2proc_response(mem2proc_response),
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_tag(mem2proc_tag),

        // From fetch stage
        .proc2Icache_addr(proc2cache_addr),

        // To memory
        .proc2Imem_command(proc2mem_command),
        .proc2Imem_addr(proc2mem_addr),

        // To fetch stage
        .Icache_data_out(cache_data_out),
        .Icache_valid_out(cache_valid_out)
    );
    
    // // guarantees that memory address pointing at will not change unless we do a store
    // store_change: assume property(@(posedge clock)
    //     (proc2mem_command != BUS_STORE) |-> ##1
    //         mem_ref.unified_memory[proc2mem_addr] == $past(mem_ref.unified_memory[proc2mem_addr])
    // );

endmodule