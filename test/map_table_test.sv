`include "verilog/sys_defs.svh"

// assumes ROB_SZ >= 10
module testbench;

    // Inputs
    logic reset;
    logic [4:0] r, r1, r2, retire_r;
    CDB cdb;
    ROB_T T, retire_T;

    // Outputs
    MT_ENTRY T1, T2;

    MAP_TABLE mt(.*);

    task exit_on_error;
        begin
            $display("@@@ Failed at time %d", $time);
            $finish;
        end
    endtask

    initial begin
        $display("Map table testbench starting...");
        $monitor("r: %2d, r1: %2d, r2: %2d\n", r, r1, r2);
        r = 0;
        r1 = 0;
        r2 = 0;
        retire_r = 0;
        cdb = 0;

        reset = 1;
        #5 reset = 0;
        

        // Set tags for r1, r2, r3
        r = 1; T = 9; #5;
        r = 2; T = 8; #5;
        r = 3; T = 7; #5;

        // Read r1 and r3 while setting r4
        r = 0; r1 = 1; r2 = 3; #5;
        if (T1.T != 9 || T2.T != 7) begin
            $display("\n@@@ Failed basic read check! Expected T1=9, T2=7. Got T1=%d, T2=%d", T1.T, T2.T);
            exit_on_error;
        end else $display("\n@@@ Passed basic read check!");

        retire_r = 1; retire_T = 9; #5;
        r1 = 1; r2 = 0; #5;
        if (T1.T != 0 || T2.T != 0) begin
            $display("\n@@@ Failed retire check! Expected T1=0, T2=0. Got T1=%d, T2=%d", T1.T, T2.T);
            exit_on_error;
        end else $display("\n@@@ Passed retire check!");


        r = 1; T = 8; #5;
        r = 1; T = 9; retire_r = 1; retire_T = 8; #5;
        r = 0; r1 = 1; r2 = 0; #5;
        if (T1.T != 9) begin
            $display("\n@@@ Failed retire while setting check! Expected T1=9. Got T1=%d", T1.T);
            exit_on_error;
        end else $display("\n@@@ Passed retire while setting check!");


        cdb.T = 9; cdb.V = 5; cdb.valid = `TRUE; #5;
        r = 0; r1 = 1; r2 = 2; #5;
        if (T1.plus != `TRUE || T2.plus != `FALSE) begin
            $display("\n@@@ Failed CDB broadcast check! Expected plus1=1, plus2=0. Got plus1=%d, plus2=%d", T1.plus, T2.plus);
            exit_on_error;
        end else $display("\n@@@ Passed CDB broadcast check!");


        r = 5; T = 11; #5;
        r = 5; T = 12; #5;
        r1 = 5; #5;
        if (T1.T != 12) begin
            $display("\n@@@ Failed WAW hazard test! Expected T1=12. Got T1=%d", T1.T);
            exit_on_error;
        end else $display("\n@@@ Passed WAW hazard test!");


        r1 = 6; r = 6; T = 14; #5;
        if (T1.T == 14) begin
            $display("\n@@@ Failed WAR hazard test! r1 should read old value.");
            exit_on_error;
        end else $display("\n@@@ Passed WAR hazard test!");


        r = 0; T = 20; #5;
        r1 = 0; r2 = 0; #5;
        if (T1.T != 0 || T2.T != 0) begin
            $display("\n@@@ Failed register 0 test! Expected T1=0, T2=0. Got T1=%d, T2=%d", T1.T, T2.T);
            exit_on_error;
        end else $display("\n@@@ Passed register 0 test!");


        r = 7; T = 15; #5;
        retire_r = 7; retire_T = 15; #5;
        r1 = 7; #5;
        if (T1.T != 0) begin
            $display("\n@@@ Failed retire test! Expected T1=0. Got T1=%d", T1.T);
            exit_on_error;
        end else $display("\n@@@ Passed retire test!");

        r = 8; T = 17; r1 = 8; r2 = 8; #5;
        if (T1.T == 17 || T2.T == 17) begin
            $display("\n@@@ Failed read-while-writing test! r1/r2 should read old value.");
            exit_on_error;
        end else $display("\n@@@ Passed read-while-writing test!");

        $display("\n@@@ All tests passed successfully!");
        $finish;
    end

endmodule
