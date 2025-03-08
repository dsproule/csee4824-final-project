`include "verilog/sys_defs.svh"

// assumes ROB_SZ >= 10
module testbench;

    // inputs
    logic reset;
    logic [4:0] r, r1, r2, retire_r;
    CDB cdb;
    ROB_T T, retire_T;

    // outputs
    MT_ENTRY T1, T2;

    MAP_TABLE mt(.*);

    initial begin
        $display("Map table tb starting...");
        $monitor("r: %2d, r1: %2d, r2: %2d", r, r1, r2);
        r = 0;
        r1 = 0;
        r2 = 0;
        retire_r = 0;
        cdb = 0;

        reset = 1;
        #5 reset = 0;
        
        // set tag for r1
        r = 1;
        T = 9;
        #5;
        // set tag for r2
        r = 2;
        T = 8;
        #5;
        // set tag for r3
        r = 3;
        T = 7;
        #5;

        // set r4 while requesting r1 and r3
        r = 0;
        r1 = 1;
        r2 = 3;
        #5;
        if (T1.T != 9 || T2.T != 7) begin
            $display("\n@@@ Failed test! Expected t1=10, t2=30. Recv t1=%d, t2=%d", T1.T, T2.T);
            $finish;
        end else $display("\n@@@ Passed basic read check!");
        
        // retire r1 and confirm MT[0] never is not 0
        retire_r = 1;
        retire_T = 9;
        #5;
        r1 = 1;
        r2 = 0;
        #5;
        if (T1.T != 0 || T2.T != 0) begin
            $display("\n@@@ Failed test! Expected t1=0, t2=0. Recv t1=%d, t2=%d", T1.T, T2.T);
            $finish;
        end else $display("\n@@@ Passed basic retire check!");

        // retire while setting
        r = 1;
        T = 8;
        #5;
        r = 1;
        T = 9;
        retire_r = 1;
        retire_r = 8;
        #5;
        r = 0;
        r1 = 1;
        r2 = 0;
        #5;
        if (T1.T != 9) begin
            $display("\n@@@ Failed test! Expected t1=9. Recv t1=%d", T1.T);
            $finish;
        end else $display("\n@@@ Passed retire while setting check!");

        // cdb broadcast sets proper flags (doesnt affect another entry while updating its own)
        cdb.T = 9;
        cdb.V = 5;
        cdb.valid = `TRUE;
        
        #5;
        r = 0;
        r1 = 1;
        r2 = 2;
        #5;
        if (T1.plus != `TRUE || T2.plus != `FALSE) begin
            $display("\n@@@ Failed test! Expected plus1=1, plus2=0. Recv plus1=%d, plus2=%d", T1.plus, T2.plus);
            $finish;
        end else $display("\n@@@ Passed cdb broadcast check!");

        $finish;
    end

endmodule