`include "verilog/sys_defs.svh"
`timescale 1ns/1ps

module testbench;
    logic clock;

    always begin
        #(`CLOCK_PERIOD/2.0)
        clock = ~clock;
    end

    initial begin
        clock = 0;
        #(20*`CLOCK_PERIOD)
        $finish;
    end

endmodule