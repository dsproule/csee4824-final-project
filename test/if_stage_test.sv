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

    logic Icache_valid;
    IF_ID_PACKET IF_ID_reg, IF_packet;
    D_S_PACKET D_S_reg, D_packet;
    logic [`XLEN-1:0] Icache2mem_addr, proc2Icache_addr, proc2mem_addr, proc2Dmem_addr, next_addr;
    logic [63:0] mem2Icache_data, Icache2proc_data;
    logic [1:0] Icache2mem_command, proc2Dmem_command, proc2mem_command;
    logic [3:0] mem2Icache_response, mem2Icache_tag;
    logic [31:0] proc2Dmem_data_lsb, proc2Dmem_data_msb;

    // new signals
    logic [`XLEN-1:0] lastI_addr;
    logic [3:0] nextIcache_tag;
    logic new_addr;

    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data({proc2Dmem_data_msb, proc2Dmem_data_lsb}),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2Icache_response),        // will need to change when Dmem gets introduced
        .mem2proc_data(mem2Icache_data),                // will need to change when Dmem gets introduced
        .mem2proc_tag(mem2Icache_tag)                   // will need to change when Dmem gets introduced
    );
    
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

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    /* Module start */

    always_comb begin
        if (proc2Dmem_command == BUS_NONE) begin
            proc2mem_addr    = Icache2mem_addr;
            proc2mem_command = Icache2mem_command;
        end else begin
            proc2mem_addr    = proc2Dmem_addr;
            proc2mem_command = proc2Dmem_command;
        end
    end

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

    // makes the last_addr trail the PC
    always_ff @(posedge clock) begin
        new_addr <= (lastI_addr != IF_ID_reg.NPC) & ~reset & IF_ID_reg.valid;

        if (reset) begin
            lastI_addr <= `XLEN'hFFFFFFFF;

            IF_ID_reg.inst  <= `NOP;
            IF_ID_reg.valid <= `TRUE;
            IF_ID_reg.NPC   <= 'h0;
            IF_ID_reg.PC    <= 0;
        end else begin
            lastI_addr <= IF_ID_reg.PC;

            // if (IF_packet.valid)
            IF_ID_reg <= (IF_packet.valid) ? IF_packet : '0;
        end
    end

    // when response comes back in turn on the if_stage
    assign Icache_valid = (mem2Icache_tag == nextIcache_tag) & (nextIcache_tag != '0);

    always_comb begin
        if (new_addr) begin
            Icache2mem_command = BUS_LOAD;
            nextIcache_tag     = mem2Icache_response;
        end else begin
            Icache2mem_command = BUS_NONE;
        end
    end

    d_stage d_stage_0(
        .IF_ID_reg(IF_ID_reg),

        .D_packet(D_packet)
    );

    // always_ff @(posedge clock) begin
    //     if (reset) begin
    //         D_S_reg <= '0;
    //     end else begin
    //         D_S_reg <= (D_packet.valid) ? D_packet : '0;
    //     end
    // end

    /* Module end */

    always @(posedge clock) begin
        if (IF_ID_reg.inst != 0) begin
            $display("IF_ID_reg -- PC: %0h, INST: %0h", IF_ID_reg.PC, IF_ID_reg.inst);
            $display("D_packet -- INST: %0h\nPC: %0h\nNPC: %0h\nr: %0h\nr1: %0h\nr2: %0h\nopa_select: %0h\nopb_select: %0h\ncond_branch: %0b, uncond_branch: %0b, alu_func: %0h\nrs_idx: %0h\nhalt: %0b, illegal: %0b, csr_op: %0b, valid: %0b\n", 
                    D_packet.inst, D_packet.PC, D_packet.NPC, D_packet.r, D_packet.r1, D_packet.r2, D_packet.opa_select, D_packet.opb_select, D_packet.cond_branch,D_packet.uncond_branch,D_packet.alu_func, D_packet.rs_idx, D_packet.halt, D_packet.illegal, D_packet.csr_op, D_packet.valid);
        end
            
    end

    initial begin
        clock = 0;
        // $monitor("PC: %0h, INST: %0h", IF_ID_reg.PC, IF_ID_reg.inst);
        reset = 1;

        @(negedge clock);
        reset = 0;
        @(negedge clock);

        // Load data to pull from
        proc2Dmem_addr = `XLEN'h0;
        proc2Dmem_data_lsb = 32'h00100093;
        proc2Dmem_data_msb = 32'h00200113;
        proc2Dmem_command = BUS_STORE;
        @(negedge clock);
        proc2Dmem_addr = `XLEN'd4;
        proc2Dmem_command = BUS_STORE;          // no idea why but this needs to be here to load properly
        @(negedge clock);
        proc2Dmem_addr = `XLEN'd8;
        proc2Dmem_data_lsb = 32'h00210233;
        proc2Dmem_data_msb = 32'h002081b3;
        proc2Dmem_command = BUS_STORE;
        @(negedge clock);
        proc2Dmem_command = BUS_NONE;
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        show_mem_with_decimal(0, 12);
        reset = 1;
        @(negedge clock);
        reset = 0;

        // magic should start happening now
        @(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);
        @(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);

        $finish;
    end

endmodule