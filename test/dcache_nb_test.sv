`include "verilog/sys_defs.svh"

/* Pipeline test where we will manually feed instructions. Includes I-stage and D-stage */

module testbench;
    logic clock, reset;

    // Show contents of a range of Unified Memory, in both hex and decimal
    task show_mem_with_decimal;
        input [31:0] start_addr;
        input [31:0] end_addr;
        int showing_data;
        begin
            $display("@@@");
            showing_data=0;
            for(int k=start_addr;k<=end_addr; k=k+1)
                if (memory.unified_memory[k] != 0) begin
                    $display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                             memory.unified_memory[k]);
                    showing_data=1;
                end else if(showing_data!=0) begin
                    $display("@@@");
                    showing_data=0;
                end
            $display("@@@");
        end
    endtask // task show_mem_with_decimal

    logic [63:0] proc2mem_data, mem2proc_data, Dcache_data_out;
    logic [3:0] mem2proc_tag, mem2proc_response;
    logic [1:0] proc2mem_command, proc2Dcache_command;
    logic [`XLEN-1:0] proc2mem_addr, proc2Dcache_addr;
    logic Dcache_valid_out;

    logic take_branch;

    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );
    
    dcache_nb dcache_0 (
        .clock(clock), .reset(reset),

        // From memory
        .Dmem2proc_response(mem2proc_response),
        .Dmem2proc_data(mem2proc_data),
        .Dmem2proc_tag(mem2proc_tag),

        // From fetch stage
        .proc2Dcache_addr(proc2Dcache_addr),
        .proc2Dcache_command(proc2Dcache_command),

        // To memory
        .proc2Dmem_command(proc2mem_command),
        .proc2Dmem_addr(proc2mem_addr),

        // To fetch stage
        .Dcache_data_out(Dcache_data_out),
        .Dcache_valid_out(Dcache_valid_out)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    initial begin
        clock = 0;
        reset = 1;
        take_branch = 0;

        @(negedge clock);
        memory.unified_memory[0] = 64'h0020011300100093;
        memory.unified_memory[1] = 64'h002081b300210233;
        memory.unified_memory[2] = 64'h0081011310412023;
        memory.unified_memory[3] = 64'h0103229300130313;
        @(negedge clock);
        reset = 0;
        show_mem_with_decimal(0, 12);
        
        proc2Dcache_addr <= `XLEN'h0;
        proc2Dcache_command <= BUS_LOAD;
        @(posedge clock);
        proc2Dcache_addr <= `XLEN'h8;
        @(posedge clock);
        proc2Dcache_command <= BUS_NONE;
        @(posedge Dcache_valid_out);
        $display("\n\n\tmem: %8h", Dcache_data_out);
        repeat (5) @(posedge clock);

        $finish;
    end

endmodule
