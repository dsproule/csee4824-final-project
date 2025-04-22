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
            showing_data = 0;
            for (int k = start_addr; k <= end_addr; k = k + 1)
                if (memory.unified_memory[k] != 0) begin
                    $display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                             memory.unified_memory[k]);
                    showing_data = 1;
                end else if (showing_data != 0) begin
                    $display("@@@");
                    showing_data = 0;
                end
            $display("@@@");
        end
    endtask // task show_mem_with_decimal

    logic [`XLEN-1:0] proc2mem_addr;
    logic [63:0]      proc2mem_data, mem2proc_data;
    logic [1:0]       proc2mem_command;
    logic [3:0]       mem2proc_response, mem2proc_tag;
    X_C_PACKET        X_packet, X_C_reg;
    logic [`RS_SZ:0]  X_idx;

    logic [`XLEN-1:0] proc2Dmem_data;
    logic [`XLEN-1:0] proc2Dmem_addr;
    logic [1:0] proc2Dmem_command;
    S_X_PACKET S_X_reg;
    logic mem_store_pend, Dmem_gnt, store_retired;

    // Memory instantiation
    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
        .proc2mem_command(proc2mem_command),
    `ifndef CACHE_MODE
        .proc2mem_size(WORD), // BYTE, HALF, WORD or DOUBLE
    `endif
        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );

    // Clock generation
    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    /* Module start */

    always_comb begin
        if (mem_store_pend) begin
            proc2mem_command = BUS_STORE;
            proc2mem_addr = proc2Dmem_addr;
        end else begin
            proc2mem_addr = '0;
            proc2mem_command = BUS_NONE;
        end
        proc2mem_data = {32'b0, proc2Dmem_data};
    end

    func_unit_3 func_unit_03(
        .clock(clock), .reset(reset), 
        .Dmem_gnt(Dmem_gnt), .retired(store_retired), 
        .S_X_reg(S_X_reg),

        .mem_store_pend(mem_store_pend),
        .proc2Dmem_addr(proc2Dmem_addr),
        .proc2Dmem_data(proc2Dmem_data),
        .X_packet(X_packet)
    );

    /* Module end */

    initial begin
        clock = 0;
        reset = 1;
        S_X_reg = '0;
        store_retired = `FALSE;
        Dmem_gnt = `TRUE;

        @(negedge clock);
        reset = 0;

        // Write value 0x00cdeadf to address 0
        S_X_reg.V1 = `XLEN'h0;
        S_X_reg.mem_offset = 32'h0;
        S_X_reg.V2 = 64'h00000000_00cdeadf;
        S_X_reg.T = 3;
        S_X_reg.valid = `TRUE;

        repeat (8) @(negedge clock);

        // Write value 0xdead to address 8
        S_X_reg.V1 = `XLEN'h8;
        S_X_reg.V2 = 64'h00000000_0000dead;
        store_retired = `TRUE;
        @(negedge clock);

        S_X_reg.valid = `FALSE;
        store_retired = `FALSE;

        repeat (8) @(negedge clock);

        show_mem_with_decimal(0, 12);

        // ==== Check memory results ====
        if (memory.unified_memory[0] !== 64'h00000000_00cdeadf) begin
            $display("@@@ Incorrect store at addr 0: got %x, expected %x", memory.unified_memory[0], 64'h00000000_00cdeadf);
            $finish;
        end

        if (memory.unified_memory[1] !== 64'h00000000_0000dead) begin
            $display("@@@ Incorrect store at addr 8: got %x, expected %x", memory.unified_memory[1], 64'h00000000_0000dead);
            $finish;
        end

        $display("\n@@@ Passed\n");
        $finish;
    end

endmodule
