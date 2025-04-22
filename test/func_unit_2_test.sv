`include "verilog/sys_defs.svh"

/* Pipeline test where we will manually feed instructions. Includes I-stage and D-stage */

module testbench;
    logic clock, reset;
    MEM_SIZE proc2mem_size;

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
    logic mem_load_pend, Dmem_gnt, load_retired;

    // Memory instantiation
    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );

    // Clock generation
    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    // Connect memory inputs
    always_comb begin
        if (mem_load_pend) begin
            proc2mem_command = BUS_LOAD;
            proc2mem_addr = proc2Dmem_addr;
        end else begin
            proc2mem_addr = `XLEN'bx;
            proc2mem_command = BUS_NONE;
        end
        proc2mem_data = {32'b0, proc2Dmem_data};
    end

    // Unit under test
    func_unit_2 func_unit_02 (
        .clock(clock), .reset(reset), .Dmem_gnt(Dmem_gnt),
        .retired(load_retired),
        .mem2proc_response(mem2proc_response), .mem2proc_tag(mem2proc_tag),
        .Dmem2proc_data(mem2proc_data),
        .S_X_reg(S_X_reg),

        .mem_load_pend(mem_load_pend),
        .proc2Dmem_addr(proc2Dmem_addr),
        .X_packet(X_packet)
    );

    // Track pass/fail
    int test_idx;
    int passed_tests;

    // Print loaded results
    always_ff @(posedge clock) begin
        if (X_packet.valid) begin
            $display("\n@@ @@ Loaded data from mem: %0d\n", X_packet.result);
            case (test_idx)
                0: if (X_packet.result !== 64'hdeadface) begin
                        $display("@@@ Incorrect on test 1: expected %x", 64'hdeadface);
                        $finish;
                    end
                1: if (X_packet.result !== 64'hfffeeada) begin
                        $display("@@@ Incorrect on test 2: expected %x", 64'hfffeeada);
                        $finish;
                    end
            endcase
            test_idx++;
            passed_tests++;
        end
    end

    initial begin
        clock = 0;
        reset = 1;
        Dmem_gnt = 1;
        load_retired = 0;

        // preload memory
        @(negedge clock);
        memory.unified_memory[0] = 64'hdeadface;
        memory.unified_memory[1] = 64'hfffeeada;

        repeat (3) @(negedge clock);
        reset = 0;

        // Test 1
        S_X_reg.mem_offset = 0;
        S_X_reg.mem_size = WORD;
        S_X_reg.V1 = 0;             // addr = 0
        S_X_reg.valid = `TRUE;
        repeat (8) @(negedge clock);
        S_X_reg.valid = `FALSE;
        load_retired = `TRUE;
        @(negedge clock);
        load_retired = `FALSE;

        // Test 2
        S_X_reg.V1 = 8;             // addr = 8
        S_X_reg.valid = `TRUE;
        repeat (8) @(negedge clock);
        S_X_reg.valid = `FALSE;
        load_retired = `TRUE;
        @(negedge clock);
        load_retired = `FALSE;

        // Final check
        if (passed_tests == 2) begin
            $display("\n@@@ Passed\n");
        end

        show_mem_with_decimal(0, 12);
        $finish;
    end

endmodule
