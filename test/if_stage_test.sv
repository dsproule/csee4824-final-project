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
    logic [`XLEN-1:0] Icache2mem_addr, proc2Icache_addr, proc2mem_addr, proc2Dmem_addr;
    logic [63:0] mem2Icache_data, Icache2proc_data;
    logic [1:0] Icache2mem_command, proc2Dmem_command, proc2mem_command;
    logic [3:0] mem2Icache_response, mem2Icache_tag;
    logic [31:0] proc2Dmem_data;

    // new signals
    logic [`XLEN-1:0] lastI_addr;
    logic [3:0] nextIcache_tag;
    logic new_addr;

    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data({32'b0, proc2Dmem_data}),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2Icache_response),        // will need to change when Dmem gets introduced
        .mem2proc_data(mem2Icache_data),                // will need to change when Dmem gets introduced
        .mem2proc_tag(mem2Icache_tag)                   // will need to change when Dmem gets introduced
    );

    always_comb begin
        if (proc2Dmem_command == BUS_NONE) begin
            proc2mem_addr    = Icache2mem_addr;
            proc2mem_command = Icache2mem_command;
        end else begin
            proc2mem_addr    = proc2Dmem_addr;
            proc2mem_command = proc2Dmem_command;
        end
    end
    
    // icache icache_0 (
    //     // Inputs
    //     .clock(clock), .reset(reset),
        
    //     .Imem2proc_response(mem2Icache_response),
    //     .Imem2proc_data(mem2Icache_data),
    //     .Imem2proc_tag(mem2Icache_tag),
        
    //     .proc2Icache_addr(proc2Icache_addr),

    //     // Outputs
    //     .proc2Imem_command(Icache2mem_command),
    //     .proc2Imem_addr(Icache2mem_addr),

    //     .Icache_data_out(Icache2proc_data),
    //     .Icache_valid_out(Icache_valid)
    // );

    /* 
     * For now ignoring the Icache because it's not working how i
     * expected. This should pulse on a new addr being put onto the 
     * IF_ID reg. This will trigger a mem load which will get passed 
     * through on the next valid index and so forth.
     */

    if_stage if_stage_0(
        // Inputs
        .clock (clock),
        .reset (reset),
        .if_valid       (Icache_valid),
        .take_branch    (),                 // ignore because this scares me for now
        .branch_target  (),                 // check above comment
        .Imem2proc_data (mem2Icache_data),

        // Outputs
        .if_packet      (IF_packet),
        .proc2Imem_addr (Icache2mem_addr)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    // pulses on new addr in IF_ID_reg (we just got a new inst)
    assign new_addr = (lastI_addr != IF_ID_reg.PC);

    // makes the last_addr trail the PC
    always_ff @(posedge clock) begin
        if (reset) begin
            lastI_addr <= 64'hFFFFFFFFFFFFFFFF;

            IF_ID_reg.inst  <= `NOP;
            IF_ID_reg.valid <= `FALSE;
            IF_ID_reg.NPC   <= 0;
            IF_ID_reg.PC    <= 0;
        end else begin
            lastI_addr <= IF_ID_reg.PC;

            if (IF_packet.valid)
                IF_ID_reg <= IF_packet;
        end
    end

    // when response comes back in turn on the if_stage
    assign Icache_valid = (mem2Icache_tag == nextIcache_tag);

    always_comb begin
        if (new_addr) begin
            Icache2mem_command = BUS_LOAD;
            Icache2mem_addr    = IF_ID_reg.NPC;
            nextIcache_tag     = mem2Icache_response;
        end else begin
            Icache2mem_command = BUS_NONE;
        end
    end

    initial begin
        clock = 0;
        $monitor("Icache_valid: %d", Icache_valid);
        reset = 1;

        @(negedge clock);
        reset = 0;

        // Load data to pull from
        proc2Dmem_addr = `XLEN'd0;
        proc2Dmem_data = 64'h100;
        proc2Dmem_command = BUS_STORE;
        @(negedge clock);
        proc2Dmem_addr = `XLEN'd4;
        proc2Dmem_data = 64'h200;
        proc2Dmem_command = BUS_STORE;
        @(negedge clock);
        proc2Dmem_addr = `XLEN'd8;
        proc2Dmem_data = 64'h300;
        proc2Dmem_command = BUS_STORE;
        @(negedge clock);
        proc2Dmem_command = BUS_NONE;
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;

        // magic should start happening now

        $finish;
    end

endmodule