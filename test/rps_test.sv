`include "verilog/sys_defs.svh"

/* Pipeline test where we will manually feed instructions. Includes I-stage and D-stage */

module testbench;
    logic clock, reset;
    
    logic en, cdb_valid, req_up;
    logic [5:0] FU_ready, gnt; 

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    rps arb (
        .clock(clock), .reset(reset),
        .req(FU_ready),
        .en(1'b1),

        .gnt(gnt), .req_up(cdb_valid)
    );

    initial begin
        $monitor("FU_ready: %6b, gnt: %6b, req_up: %1b", FU_ready, gnt, cdb_valid);
        clock = 0;
        reset = 1;
        FU_ready = '0;

        @(negedge clock);
        reset = 0;
        
        @(negedge clock);
        FU_ready = 6'b011001;
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);


        $finish;
    end

endmodule