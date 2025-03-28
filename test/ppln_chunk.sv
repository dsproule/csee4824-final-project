`include "verilog/sys_defs.svh"

module testbench_chunk;
    logic clock, reset;
    logic [3:0]  mem2proc_response;
    logic [1:0]  proc2mem_command;
    logic [63:0] mem2proc_data, proc2mem_data;
    logic [3:0]  mem2proc_tag;      
    logic [`XLEN-1:0] proc2mem_addr;

    mem memory (
        // Inputs
        .clk              (clock),
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),

        // Outputs
        .mem2proc_response (mem2proc_response),
        .mem2proc_data     (mem2proc_data),
        .mem2proc_tag      (mem2proc_tag)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    initial begin
        clock = 0;
        // load in values
        proc2mem_command = BUS_NONE;
        proc2mem_addr = '0;
        proc2mem_data = 64'hdeaddead;

        @(negedge clock);
        proc2mem_command = BUS_STORE;

        // @(mem2proc_response);
        @(negedge clock);
        // proc2mem_command = BUS_NONE;
        proc2mem_command = BUS_LOAD;
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);

        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);


        $finish;
    end

endmodule