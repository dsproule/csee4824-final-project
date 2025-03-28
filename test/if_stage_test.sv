`include "verilog/sys_defs.svh"

/* Pipeline test where we will manually feed instructions*/

module testbench_chunk;
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

    logic Icache_valid;
    IF_ID_PACKET IF_ID_reg, IF_packet;
    logic [`XLEN-1:0] Icache2mem_addr, proc2Icache_addr;
    logic [63:0] mem2Icache_data, Icache2proc_data;
    logic [1:0] Icache2mem_command;
    logic [3:0] mem2Icache_response, mem2Icache_tag;

    mem memory(
    .clk(clock),
    .proc2mem_addr(Icache2mem_addr),
    .proc2mem_data(),                       // icache doesnt store any data
    .proc2mem_command(Icache2mem_command),  // (these will get muxed/used when we have an LSQ)

    .mem2proc_response(mem2Icache_response),
    .mem2proc_data(mem2Icache_data),
    .mem2proc_tag(mem2Icache_tag)
);
    
    icache icache_0 (
        // Inputs
        .clock(clock), .reset(reset),
        
        .Imem2proc_response(mem2Icache_response),
        .Imem2proc_data(mem2Icache_data),
        .Imem2proc_tag(mem2Icache_tag),
        
        .proc2Icache_addr(proc2Icache_addr),

        // Outputs
        .proc2Imem_command(Icache2mem_command),
        .proc2Imem_addr(Icache2mem_addr),

        .Icache_data_out(Icache2proc_data),
        .Icache_valid_out(Icache_valid)
    );

    if_stage if_stage_0(
        // Inputs
        .clock (clock),
        .reset (reset),
        .if_valid       (Icache_valid),
        .take_branch    (),                 // ignore because this scares me for now
        .branch_target  (),                 // check above comment
        .Imem2proc_data (Icache2proc_data),

        // Outputs
        .if_packet      (IF_packet),
        .proc2Imem_addr (proc2Icache_addr)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end


    initial begin
        clock = 0;
        $readmemh("programs/if_stage_test.mem", memory.unified_memory);
        reset = 1;

        @(negedge clock);
        @(negedge clock);
        reset = 0;

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