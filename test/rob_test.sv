`include "verilog/sys_defs.svh"

module rob_testbench;

    logic clock, reset, dispatch_valid;
    logic [4:0] r;
    ROB_T T1, T2;
    CDB cdb;

    ROB_T T, retire_T;
    logic full, empty, regfile_write_en;
    logic [4:0] regfile_write_idx;
    logic [`XLEN-1:0] V1, V2, regfile_write_data;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out;

    ROB_ENTRY rob_table [`ROB_SZ-1:0];
    logic [4:0] expected_r [`ROB_SZ-1:0];
    logic [`XLEN-1:0] expected_V [`ROB_SZ-1:0];

    rob dut (
        .clock(clock), .reset(reset),
        .r(r), .T1(T1), .T2(T2),
        .cdb(cdb), .dispatch_valid(dispatch_valid),
        .T(T), .retire_T(retire_T), .full(full), .empty(empty),
        .retire(regfile_write_en), .regfile_write_idx(regfile_write_idx),
        .V1(V1), .V2(V2), .regfile_write_data(regfile_write_data),
        .rob_table_out(rob_table_out)
    );

    task exit_on_error(input string msg);
        $display("@@@ Test failed at time %0t: %s", $time, msg);
        $finish;
    endtask

    task dump_rob(logic [5:0] start_i, logic [5:0] end_i);
        $display("\n=== ROB Dump [%2d:%2d] === head: %d tail: %d", start_i, end_i, dut.head, dut.tail);
        for (logic [5:0] i = start_i; i < end_i; i++)
            $display("| %2d | ready=%1b | r=%2d | V=%0d", i, rob_table[i].ready, rob_table[i].r, rob_table[i].V);
        $display("==============================\n");
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

        // === Case 1: Single dispatch ===
        dispatch_valid = 1; r = 5; expected_r[0] = 5; @(negedge clock);
        dispatch_valid = 0;
        if (full) exit_on_error("ROB should not be full after one dispatch");
        $display("@@@ Passed: Single dispatch");

        // === Case 2: Fill ROB ===
        for (int i = T; i < `ROB_SZ; i++) begin
            dispatch_valid = 1; r = i; expected_r[i] = r; @(negedge clock);
        end
        dispatch_valid = 0;
        if (!full) exit_on_error("ROB should be full after filling");
        $display("@@@ Passed: Fill ROB");
        

        // === Case 3: Commit multiple entries ===
        for (int i = 0; i < 4; i++) begin
            cdb.T = i; cdb.V = 4200 + i; expected_V[i] = cdb.V;
            cdb.valid = `TRUE;
            @(negedge clock); cdb.valid = `FALSE; @(negedge clock);

            if (!regfile_write_en) exit_on_error("retire signal not high");
            if (regfile_write_data !== expected_V[i])
                exit_on_error($sformatf("Commit %0d: data mismatch (got %0d, expected %0d)", i, regfile_write_data, expected_V[i]));
            if (regfile_write_idx !== expected_r[i])
                exit_on_error($sformatf("Commit %0d: regfile idx mismatch (got %0d, expected %0d)", i, regfile_write_idx, expected_r[i]));
            if (retire_T !== i)
                exit_on_error($sformatf("Commit %0d: retire_T mismatch (got %0d)", i, retire_T));
        end
        $display("@@@ Passed: Commit multiple");

        //dump_rob(0,`ROB_SZ);
        //$display("head: %d retire_T: %d regfile_write_idx: %d", dut.head,  retire_T, regfile_write_idx);

        // === Case 4: Simulataneous dispatch + commit ===
        reset = 1; @(negedge clock); reset = 0;


        dispatch_valid = 1;
        r = 9; expected_r[0] = r; @(negedge clock);
        for (int i = 0; i < 15; i++) begin
            r = i + 10; expected_r[i+1] = r;
            dispatch_valid = 1;
            cdb.T = i; cdb.V = 100 + i; expected_V[i] = cdb.V;

            cdb.valid = `TRUE; @(negedge clock); //ready been written, next cycle will have data. Pipelined but latency of a cycle

            $display("i: %d\n", i);
            if (i != 0)
                if (!regfile_write_en || regfile_write_data !== expected_V[i-1] || regfile_write_idx !== expected_r[i-1])
                    exit_on_error("Simultaneous dispatch + commit failed");

        end
        dispatch_valid = 0;
        $display("@@@ Passed: Simultaneous dispatch + commit");

        // === Case 5: CDB to middle entry ===
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < 3; i++) begin
            dispatch_valid = 1; r = i + 7; expected_r[i] = r; @(negedge clock);
        end
        dispatch_valid = 0;

        // Write to T=1 first (out of order)
        cdb.T = 1; cdb.V = 5555; cdb.valid = `TRUE; @(negedge clock); cdb.valid = `FALSE;
        @(negedge clock);
        if (regfile_write_en)
            exit_on_error("Out-of-order commit occurred");

        // Now retire T=0
        cdb.T = 0; cdb.V = 4444; expected_V[0] = cdb.V; cdb.valid = `TRUE;
        @(negedge clock); cdb.valid = `FALSE; @(negedge clock);
        if (!regfile_write_en || regfile_write_data !== 4444 || regfile_write_idx !== expected_r[0] || retire_T !== 0)
            exit_on_error("In-order commit failed");
        $display("@@@ Passed: In-order enforced with middle CDB");

        // === Case 6: Wraparound ===
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < `ROB_SZ; i++) begin
            r = i; dispatch_valid = 1; expected_r[i] = r; @(negedge clock);
        end
        dispatch_valid = 0;
        for (int i = 0; i < `ROB_SZ / 2; i++) begin
            cdb.T = i; cdb.V = 8000 + i; expected_V[i] = cdb.V;
            cdb.valid = `TRUE;
            @(negedge clock); cdb.valid = `FALSE; @(negedge clock);
            if (!regfile_write_en || regfile_write_data !== expected_V[i] || regfile_write_idx !== expected_r[i])
                exit_on_error("Wraparound commit mismatch");
        end
        for (int i = 0; i < `ROB_SZ / 2; i++) begin
            r = 100 + i; dispatch_valid = 1; @(negedge clock);
        end
        dispatch_valid = 0;
        $display("@@@ Passed: Wraparound logic");

        // === Case 7: Flush from mispredicted instruction ===
        reset = 1; @(negedge clock); reset = 0;
        for (int i = 0; i < 3; i++) begin
            dispatch_valid = 1; r = i + 20; @(negedge clock);
        end
        dispatch_valid = 0;
        cdb.T = 0; cdb.V = 9999; cdb.ppl_ctrl.flush = 1; cdb.valid = `TRUE;
        @(negedge clock); cdb.valid = `FALSE;
        @(negedge clock);
        if (!empty) exit_on_error("Flush failed to clear ROB");
        $display("@@@ Passed: Mispredict-triggered flush");

        $display("\n@@@ ALL ROB TESTS PASSED SUCCESSFULLY!\n");
        $finish;
    end
endmodule
