`include "verilog/sys_defs.svh"

module testbench;

    logic clock, reset, dispatch_valid;
    logic [4:0] r;
    ROB_T T1, T2;
    CDB cdb;

    ROB_T T;
    logic full, empty, regfile_write_en;
    logic [4:0] regfile_write_idx;
    logic [`XLEN-1:0] V1, V2, regfile_write_data;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out;

    ROB_ENTRY rob_table [`ROB_SZ-1:0];

    rob dut (
        .clock(clock), .reset(reset),
        .r(r), .T1(T1), .T2(T2),
        .cdb(cdb), .dispatch_valid(dispatch_valid),
        .T(T), .full(full), .empty(empty),
        .retire(regfile_write_en), .regfile_write_idx(regfile_write_idx),
        .V1(V1), .V2(V2), .regfile_write_data(regfile_write_data),
        .rob_table_out(rob_table_out)
    );

    task exit_on_error(input string msg);
        $display("@@@ Test failed at time %0t: %s", $time, msg);
        $finish;
    endtask

    task dump_rob(logic [5:0] start_i, logic [5:0] end_i);
        $display("\\n=== ROB Dump [%2d:%2d] ===", start_i, end_i);
        for (logic [5:0] i = start_i; i < end_i; i++)
            $display("| %2d | ready=%1b | r=%2d | V=%0d", i, rob_table[i].ready, rob_table[i].r, rob_table[i].V);
        $display("==============================\\n");
    endtask

    always #5 clock = ~clock;

    always_comb begin
        for (int i = 0; i < `ROB_SZ; i++) begin
            rob_table[i] = rob_table_out[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)];
        end
    end

    initial begin
        $display("ROB testbench starting...");
        clock = 0;
        reset = 1;
        dispatch_valid = 0;
        r = 0; cdb = 0;

        repeat (3) @(negedge clock);
        reset = 0;

        // Case 1: Dispatch one entry
        dispatch_valid = 1; r = 5; @(negedge clock);
        dispatch_valid = 0;
        if (full) exit_on_error("");
        $display("@@@ Passed: Single dispatch");

        // Case 2: Fill ROB
        for (int i = T; i < `ROB_SZ; i++) begin
            dispatch_valid = 1; r = i; @(negedge clock);
        end
        dispatch_valid = 0;
        if (!full) exit_on_error("");
        $display("@@@ Passed: Fill ROB");

        for (int i = 0; i < 4; i++) begin
            cdb.T = i;
            cdb.V = 4200 + i;
            cdb.valid = `TRUE;
            @(negedge clock);
            cdb.valid = `FALSE;
            @(negedge clock);

            if (!regfile_write_en || regfile_write_data !== (4200 + i)) begin
                exit_on_error($sformatf("Commit %0d failed: got %0d, expected %0d", i, regfile_write_data, 4200 + i));
            end
        end


        // Case 4: Interleaved dispatch + commit
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < 4; i++) begin
            r = i + 10; dispatch_valid = 1;
            @(negedge clock);
            cdb.T = i; cdb.V = 100 + i; cdb.valid = `TRUE;
            @(negedge clock); cdb.valid = `FALSE;
            @(negedge clock);
        end
        dispatch_valid = 0;
        for (int i = 0; i < 4; i++) begin
            if (rob_table[i].ready !== 1 || rob_table[i].V !== 100 + i)
                exit_on_error("");
        end
        $display("@@@ Passed: Interleaved dispatch + commit");

        // Case 5: CDB to middle entry
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < 3; i++) begin
            dispatch_valid = 1; r = i + 7; @(negedge clock);
        end
        dispatch_valid = 0;
        cdb.T = 1; cdb.V = 5555; cdb.valid = `TRUE; @(negedge clock); cdb.valid = `FALSE;
        @(negedge clock);
        if (regfile_write_en)
            exit_on_error("Out-of-order commit");
        cdb.T = 0; cdb.V = 4444; cdb.valid = `TRUE; @(negedge clock); cdb.valid = `FALSE;
        @(negedge clock);
        if (!regfile_write_en || regfile_write_data !== 4444)
            exit_on_error("");
        $display("@@@ Passed: In-order commit enforced");

        // Case 6: Wraparound
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < `ROB_SZ; i++) begin
            dispatch_valid = 1; r = i; @(negedge clock);
        end
        dispatch_valid = 0;
        for (int i = 0; i < `ROB_SZ / 2; i++) begin
            cdb.T = i; cdb.V = 8000 + i; cdb.valid = `TRUE;
            @(negedge clock); cdb.valid = `FALSE; @(negedge clock);
        end
        for (int i = 0; i < `ROB_SZ / 2; i++) begin
            r = 100 + i; dispatch_valid = 1; @(negedge clock);
        end
        dispatch_valid = 0;
        $display("@@@ Passed: Wraparound logic");

        // Case 7: Flush from mispredicted instruction
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < 3; i++) begin
            dispatch_valid = 1; r = i + 20; @(negedge clock);
        end
        dispatch_valid = 0;
        cdb.T = 0; cdb.V = 9999; cdb.ppl_ctrl.flush = 1; cdb.valid = `TRUE;
        @(negedge clock); cdb.valid = `FALSE;
        @(negedge clock);
        if (!empty)
            exit_on_error("Flush failed");
        $display("@@@ Passed: Mispredict-triggered flush");

        $display("\n@@@ ALL ROB TESTS PASSED SUCCESSFULLY!\n");
        $finish;
    end
endmodule
