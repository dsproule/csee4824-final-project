`include "verilog/sys_defs.svh"

// assumes ROB_SZ >= 10
module testbench;

    // Inputs
    logic clock, reset;
    logic [4:0] r, r1, r2, retire_r;
    CDB cdb;
    ROB_T T, retire_T;
    MT_ENTRY mt_table [31:0];

    // Outputs
    MT_ENTRY T1, T2;

    MAP_TABLE mt(.*);

    task exit_on_error;
        begin
            $display("@@@ Failed at time %d", $time);
            $finish;
        end
    endtask

    task dump_mt(logic [5:0] start_i, logic [5:0] end_i);
        $display("(Map table [%2d:%2d])", start_i, end_i);
        for (logic [5:0] i = start_i; i < end_i; i++) 
            $display("r: %3d    Tag: %3d    Plus: %3d    ", i, mt_table[i].T, mt_table[i].plus);
    endtask

    always begin
        #5 clock = ~clock;
    end

    initial begin
        $display("Map table testbench starting...");
        // $monitor("r: %2d, r1: %2d, r2: %2d\n", r, r1, r2);
        r = 0;
        clock = 0;
        r1 = 0;
        r2 = 0;
        retire_r = 0;
        cdb = 0;

        reset = 1;
        @(negedge clock); reset = 0;
        

        // Set tags for r1, r2, r3
        r = 1; T = 9; @(negedge clock);
        r = 2; T = 8; @(negedge clock);
        r = 3; T = 7; @(negedge clock);

        // Read r1 and r3 while setting r4
        r = 0; r1 = 1; r2 = 3; @(negedge clock);
        if (T1.T != 9 || T2.T != 7) begin
            $display("\n@@@ Failed basic read check! Expected T1=9, T2=7. Got T1=%d, T2=%d", T1.T, T2.T);
            exit_on_error;
        end else $display("\n@@@ Passed basic read check!");

        retire_r = 1; retire_T = 9; @(negedge clock);
        r1 = 1; r2 = 0; @(negedge clock);
        if (T1.T != 0 || T2.T != 0) begin
            $display("\n@@@ Failed retire check! Expected T1=0, T2=0. Got T1=%d, T2=%d", T1.T, T2.T);
            exit_on_error;
        end else $display("\n@@@ Passed retire check!");


        r = 1; T = 8; @(negedge clock);
        r = 1; T = 9; retire_r = 1; retire_T = 8; @(negedge clock);
        r = 0; r1 = 1; r2 = 0; @(negedge clock);
        if (T1.T != 9) begin
            $display("\n@@@ Failed retire while setting check! Expected T1=9. Got T1=%d", T1.T);
            exit_on_error;
        end else $display("\n@@@ Passed retire while setting check!");


        cdb.T = 9; cdb.V = 5; cdb.valid = `TRUE; @(negedge clock);
        r = 0; r1 = 1; r2 = 2; @(negedge clock);
        if (T1.plus != `TRUE || T2.plus != `FALSE) begin
            $display("\n@@@ Failed CDB broadcast check! Expected plus1=1, plus2=0. Got plus1=%d, plus2=%d", T1.plus, T2.plus);
            exit_on_error;
        end else $display("\n@@@ Passed CDB broadcast check!");


        r = 5; T = 11; @(negedge clock);
        r = 5; T = 12; @(negedge clock);
        r1 = 5; @(negedge clock);
        if (T1.T != 12) begin
            $display("\n@@@ Failed WAW hazard test! Expected T1=12. Got T1=%d", T1.T);
            exit_on_error;
        end else $display("\n@@@ Passed WAW hazard test!");

        dump_mt(6, 7);
        r1 = 6; r = 6; T = 14; @(negedge clock);
        if (T1.T == 14) begin
            dump_mt(6, 7);
            $display("\n@@@ Failed WAR hazard test! r1 should read old value.");
            exit_on_error;
        end else $display("\n@@@ Passed WAR hazard test!");


        r = 0; T = 20; @(negedge clock);
        r1 = 0; r2 = 0; @(negedge clock);
        if (T1.T != 0 || T2.T != 0) begin
            $display("\n@@@ Failed register 0 test! Expected T1=0, T2=0. Got T1=%d, T2=%d", T1.T, T2.T);
            exit_on_error;
        end else $display("\n@@@ Passed register 0 test!");


        r = 7; T = 15; @(negedge clock);
        retire_r = 7; retire_T = 15; @(negedge clock);
        r1 = 7; @(negedge clock);
        if (T1.T != 0) begin
            $display("\n@@@ Failed retire test! Expected T1=0. Got T1=%d", T1.T);
            exit_on_error;
        end else $display("\n@@@ Passed retire test!");

        r = 8; T = 17; r1 = 8; r2 = 8; @(negedge clock);
        if (T1.T == 17 || T2.T == 17) begin
            $display("\n@@@ Failed read-while-writing test! r1/r2 should read old value.");
            exit_on_error;
        end else $display("\n@@@ Passed read-while-writing test!");

        $display("\n@@@ All tests passed successfully!");
        $finish;
    end

endmodule
