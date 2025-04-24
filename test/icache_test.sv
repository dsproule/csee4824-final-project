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

    logic [63:0] proc2mem_data, mem2proc_data, Icache_data_out;
    logic [3:0] mem2proc_tag, mem2proc_response;
    logic [1:0] proc2mem_command;
    logic [`XLEN-1:0] proc2mem_addr, proc2Icache_addr;
    logic Icache_valid_out;

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
    
    icache icache_0 (
        .clock(clock), .reset(reset),

        // From memory
        .Imem2proc_response(mem2proc_response),
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_tag(mem2proc_tag),

        // From fetch stage
        .proc2Icache_addr(proc2Icache_addr),

        // To memory
        .proc2Imem_command(proc2mem_command),
        .proc2Imem_addr(proc2mem_addr),

        // To fetch stage
        .Icache_data_out(Icache_data_out),
        .Icache_valid_out(Icache_valid_out)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    /* Module start */


    // if_stage if_stage_0(
    //     .clock(clock), .reset(reset), .Imem_gnt(~Dmem_req),
    //     .take_branch(take_branch),
    //     .branch_target(),
    //     .Imem2proc_data(mem2proc_data),
    //     .Imem2proc_response(mem2proc_response), .Imem2proc_tag(mem2proc_tag),

    //     .mem_req(mem_req),
    //     .IF_packet(IF_packet),
    //     .proc2Imem_command(proc2Imem_command),
    //     .proc2Imem_addr(proc2Imem_addr)
    // );

    // when response comes back in turn on the if_stage

    // always_ff @(posedge clock) begin
    //     if (reset) begin
    //         IF_ID_reg <= '0;
    //     end else begin
    //         IF_ID_reg <= (IF_packet.valid) ? IF_packet : '0;
    //     end
    // end

    /* Module end */

    // always @(posedge clock) begin
    //     if (IF_ID_reg.valid & ~reset)
    //         $display("IF_ID_reg -- PC: %2h, INST: %8h", IF_ID_reg.PC, IF_ID_reg.inst);
    // end

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
        
        proc2Icache_addr = `XLEN'h0;
        @(negedge clock);
        @(posedge clock);
        proc2Icache_addr = `XLEN'h8;
        // @(posedge Icache_valid_out);
        // proc2Icache_addr = `XLEN'h10;
        repeat (9) @(negedge clock);

        $finish;
    end

endmodule
