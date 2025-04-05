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

    IF_ID_PACKET IF_ID_reg, IF_packet;
    D_S_PACKET D_S_reg, D_packet;
    logic [63:0] proc2mem_data;
    logic [63:0] mem2proc_data;
    logic [3:0] mem2proc_tag;
    logic [3:0] mem2proc_response;
    logic [1:0] proc2Dmem_command, proc2Imem_command, proc2mem_command;
    logic [`XLEN-1:0] proc2Imem_addr, proc2Dmem_addr, proc2mem_addr;
    logic take_branch;
    logic [`XLEN-1:0] branch_target;

    task store_mem;
        input [`XLEN-1:0] addr;
        input [63:0] data;

        proc2Dmem_addr = addr;
        proc2mem_data = data;
        proc2Dmem_command = BUS_STORE;
        @(negedge clock);
        proc2Dmem_addr = data + 4;
        @(negedge clock);
        proc2Dmem_command = BUS_NONE;
    endtask;

    // new signals
    logic [3:0] nextImem_tag;
    logic new_addr, Imem_req, Dmem_req;

    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2proc_response),        // will need to change when Dmem gets introduced
        .mem2proc_data(mem2proc_data),                // will need to change when Dmem gets introduced
        .mem2proc_tag(mem2proc_tag)                   // will need to change when Dmem gets introduced
    );
    
    // icache icache_0 (
    //     // Inputs
    //     .clock(clock), .reset(reset),
        
    //     .Imem2proc_response(mem2proc_response),
    //     .mem2proc_data(mem2proc_data),
    //     .Imem2proc_tag(mem2proc_tag),
        
    //     .proc2Icache_addr(proc2Icache_addr),

    //     // Outputs
    //     .proc2Imem_command(proc2Imem_command),
    //     .proc2Imem_addr(proc2Imem_addr),

    //     .Icache_data_out(Icache2proc_data),
    //     .Imem2proc_valid_out(Imem2proc_valid)
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

    assign Dmem_req = (proc2Dmem_command != BUS_NONE);

    always_comb begin
        if (Dmem_req) begin
            proc2mem_addr    = proc2Dmem_addr;
            proc2mem_command = proc2Dmem_command;
        end else begin
            proc2mem_addr    = proc2Imem_addr;
            proc2mem_command = proc2Imem_command;
        end
    end


    if_stage if_stage_0(
        .clock(clock), .reset(reset), .Imem_gnt(~Dmem_req),
        .take_branch(take_branch),
        .branch_target(),
        .Imem2proc_data(mem2proc_data),
        .Imem2proc_response(mem2proc_response), .Imem2proc_tag(mem2proc_tag),

        .mem_req(mem_req),
        .IF_packet(IF_packet),
        .proc2Imem_command(proc2Imem_command),
        .proc2Imem_addr(proc2Imem_addr)
    );

    // when response comes back in turn on the if_stage

    always_ff @(posedge clock) begin
        if (reset) begin
            IF_ID_reg <= '0;
        end else begin
            IF_ID_reg <= (IF_packet.valid) ? IF_packet : '0;
        end
    end

    d_stage d_stage_0(
        .IF_ID_reg(IF_ID_reg),

        .D_packet(D_packet)
    );
    
    always_ff @(posedge clock) begin
        if (reset) begin
            D_S_reg <= '0;
        end else begin
            D_S_reg <= (D_packet.valid) ? D_packet : '0;
        end
    end


    /* Module end */

    always @(posedge clock) begin
        if (IF_ID_reg.valid & ~reset)
            $display("IF_ID_reg -- PC: %2h, INST: %8h", IF_ID_reg.PC, IF_ID_reg.inst);
        if (D_S_reg.valid)
            $display("D_packet -- INST: %0h\nPC: %0h\nNPC: %0h\nr: %0h\nr1: %0h\nr2: %0h\nopa_select: %0h\nopb_select: %0h\ncond_branch: %0b, uncond_branch: %0b, alu_func: %0h\nrs_idx: %0h\nhalt: %0b, illegal: %0b, csr_op: %0b, valid: %0b\n", 
                    D_S_reg.inst, D_S_reg.PC, D_S_reg.NPC, D_S_reg.r, D_S_reg.r1, D_S_reg.r2, D_S_reg.opa_select, D_S_reg.opb_select, D_S_reg.cond_branch,D_S_reg.uncond_branch,D_S_reg.alu_func, D_S_reg.rs_idx, D_S_reg.halt, D_S_reg.illegal, D_S_reg.csr_op, D_S_reg.valid);
    end

    initial begin
        clock = 0;
        // $monitor("PC: %0h, INST: %0h", IF_ID_reg.PC, IF_ID_reg.inst);
        reset = 1;
        take_branch = 0;

        @(negedge clock);
        reset = 0;
        @(negedge clock);

        store_mem(`XLEN'h0,  64'h0020011300100093);
        store_mem(`XLEN'h8,  64'h002081b300210233);
        store_mem(`XLEN'h10, 64'h0081011310412023);
        store_mem(`XLEN'h18, 64'h0103229300130313);
        
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        show_mem_with_decimal(0, 12);
        reset = 1;
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        reset = 0;
        branch_target = 32'h4;

        // magic should start happening now
        @(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);
        @(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);
        take_branch = 1;
        @(negedge clock);
        take_branch = 0;
        @(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);@(negedge clock);


        $finish;
    end

endmodule
