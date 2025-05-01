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

    logic [63:0] proc2mem_data, mem2proc_data, Dcache_data_out, proc2Dcache_data;
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
        .proc2Dcache_data(proc2Dcache_data),

        // To memory
        .proc2Dmem_command(proc2mem_command),
        .proc2Dmem_addr(proc2mem_addr),
        .proc2Dmem_data(proc2mem_data),

        // To fetch stage
        .Dcache_data_out(Dcache_data_out),
        .Dcache_valid_out(Dcache_valid_out)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    /*
        You can use this module in 2 ways:
            1. pretend its a blocking cache and use it accordingly
            2. pipeline the loads and use the stores blocking

            - stores need to be placed and then left alone until Dcache_valid_out is high,
                they work under the assumption that Dcache_data_out is being shifted properly
                and will be available on the next posedge. This means you just set:
                        Dmem_command = BUS_STORE
                        Dmem_addr    = addr
                        Dmem_data    = shift_logic_applied(Dcache_data_out)
            - the loads can be pipelined. So you can:
                        Dmem_command = BUS_LOAD
                        Dmem_addr    = addr
                and go to other addresses. When you come back to this addr, 
                if the mem responded to the cache, it will be Dcache_valid_out.
                alternatively you can leave it.
            
            Examples of all signals are below.
            
    */

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
        show_mem_with_decimal(0, 12);
        reset = 0;
        
        // basic load
        proc2Dcache_addr <= `XLEN'h0;
        proc2Dcache_command <= BUS_LOAD;
        @(posedge clock);
        proc2Dcache_command <= BUS_NONE;    // does not need to stay loading
        @(posedge Dcache_valid_out);

        if (Dcache_data_out != 64'h0020011300100093)
            $finish;
        $display("\n\nBasic load test complete.");

        // pipelined loads
        @(posedge clock);
        proc2Dcache_addr <= `XLEN'h8;
        proc2Dcache_command <= BUS_LOAD;
        @(posedge clock);
        proc2Dcache_addr <= `XLEN'h10;
        @(posedge clock);
        proc2Dcache_addr <= `XLEN'h18;
        @(posedge clock);
        proc2Dcache_addr <= `XLEN'h8;
        @(posedge clock);
        proc2Dcache_command <= BUS_NONE;
        @(posedge Dcache_valid_out);
        
        if (Dcache_data_out != 64'h002081b300210233)
            $finish;
        @(posedge clock);
        
        proc2Dcache_addr <= `XLEN'h10;
        @(negedge clock);
        if (Dcache_data_out != 64'h0081011310412023 && Dcache_valid_out)
            $finish;
        @(posedge clock);
        
        proc2Dcache_addr <= `XLEN'h18;
        @(negedge clock);
        if (Dcache_data_out != 64'h0103229300130313 && Dcache_valid_out)
            $finish;
        @(posedge clock);
        $display("Pipelined loads test working.");

        proc2Dcache_addr <= `XLEN'h20;
        proc2Dcache_command <= BUS_STORE;       // needs to stay storing
        proc2Dcache_data <= 64'hdeadface;
        @(posedge Dcache_valid_out);
        $display("Store on miss works.");
        proc2Dcache_addr <= `XLEN'h20;
        proc2Dcache_command <= BUS_STORE;       // needs to stay storing
        proc2Dcache_data <= 64'hfacefeeddeadface;
        @(posedge clock);
        $display("Store on cache hit works.");


        repeat (2) @(posedge clock);
        show_mem_with_decimal(0, 20);
        $finish;
    end

endmodule
