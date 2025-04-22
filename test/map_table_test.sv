`include "verilog/sys_defs.svh"

// assumes ROB_SZ >= 10
module testbench;

    // Inputs
    logic clock, reset;
    logic [4:0] r, r1, r2, retire_r;
    CDB cdb;
    logic en;
    logic has_dest;
    ROB_T T, retire_T;
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out;
    MT_ENTRY mt_table [31:0];

    // Outputs
    MT_ENTRY T1, T2;

    map_table mt(
        .clock(clock),
        .reset(reset),
        .en(en),
        .has_dest(has_dest),
        .r(r),
        .r1(r1),
        .r2(r2),
        .retire_r(retire_r),
        .cdb(cdb),
        .T(T),
        .T1(T1),
        .T2(T2),
        .retire_T(retire_T),
        .mt_table_out(mt_table_out)
    );

    always_comb begin
        //re-unpack array for debugging    
        for (int i = 0; i < 32; i++) begin
            mt_table[i] = mt_table_out[i * $bits(MT_ENTRY) +: $bits(MT_ENTRY)];
        end
    end

    task exit_on_error;
        $display("@@@ Failed at time %0t", $time);
        $finish;
    endtask

    task dump_mt(logic [5:0] start_i, logic [5:0] end_i);
        $display("(Map table [%2d:%2d])", start_i, end_i);
        for (logic [5:0] i = start_i; i < end_i; i++) 
            $display("r: %3d    Tag: %3d    Plus: %3d", i, mt_table[i].T, mt_table[i].plus);
    endtask

    always #5 clock = ~clock;

    initial begin
        $display("Map table testbench starting...");

        r = 0; r1 = 0; r2 = 0;
        retire_r = 0; retire_T = 0;
        clock = 0; cdb = 0; en = 1;
        reset = 1;

        @(negedge clock); reset = 0;
        @(negedge clock); @(negedge clock);
        for (int i = 0; i < 32; i++) begin
                if (mt_table[i] !== 0) begin
                    $display("@@@ Failed reset! Expected all 0. Got T1=%0d, T2=%0d", T1.T, T2.T);
                    exit_on_error();
            end
        end

        has_dest = 1;

        // Set tags for r1, r2, r3
        r = 1; T = 9;  @(negedge clock);
        r = 2; T = 8;  @(negedge clock);
        r = 3; T = 7;  @(negedge clock);

        // Wait one cycle to allow tag writes to commit before reading
        r = 0; T = 0; en = 0;
        @(negedge clock); 
        en = 0;
        @(negedge clock);

        // Read r1 and r3 while setting r4
        r = 0; r1 = 1; r2 = 3; @(negedge clock);


        if (T1.T !== 9 || T2.T !== 7) begin
            $display("@@@ Failed basic read check! Expected T1=9, T2=7. Got T1=%0d, T2=%0d", T1.T, T2.T);
            exit_on_error();
        end else $display("@@@ Passed basic read check!");

        // Retire r1
        retire_r = 1; retire_T = 9; @(negedge clock);
        r1 = 1; r2 = 0; @(negedge clock);
        if (T1.T !== 0 || T2.T !== 0) begin
            $display("@@@ Failed retire check! Expected T1=0, T2=0. Got T1=%0d, T2=%0d", T1.T, T2.T);
            exit_on_error();
        end else $display("@@@ Passed retire check!");

        /* Retire while setting
        r = 1; T = 8; @(negedge clock);
        r = 1; T = 9; retire_r = 1; retire_T = 8; @(negedge clock);
        r = 0; r1 = 1; r2 = 0; @(negedge clock);
*/
        r = 1; T = 8; has_dest = 1; en = 1; @(negedge clock);
        retire_r = 1; retire_T = 8; r = 1; T = 9; has_dest = 1; en = 1; @(negedge clock);
        retire_r = 0; retire_T = 0; // clear retire
        r = 0; has_dest = 0; en = 0;
        r1 = 1; r2 = 0; @(negedge clock);

        if (T1.T !== 9) begin
            $display("@@@ Failed retire while setting check! Expected T1=9. Got T1=%0d", T1.T);
            exit_on_error();
        end else $display("@@@ Passed retire while setting check!");

        // CDB broadcast check
        cdb.T = 9; cdb.V = 5; cdb.valid = `TRUE; @(negedge clock);
        r = 0; r1 = 1; r2 = 2; @(negedge clock);
        if (T1.plus !== `TRUE || T2.plus !== `FALSE) begin
            $display("@@@ Failed CDB broadcast check! Expected plus1=1, plus2=0. Got plus1=%0d, plus2=%0d", T1.plus, T2.plus);
            exit_on_error();
        end else $display("@@@ Passed CDB broadcast check!");

        // WAW Hazard test
        has_dest = 1; en = 1;
        r = 5; T = 11; @(negedge clock);
        r = 5; T = 12; @(negedge clock);
        en = 0; has_dest = 0;  // Stop writing
        r1 = 5; @(negedge clock);
        if (T1.T !== 12) begin
            $display("@@@ Failed WAW hazard test! Expected T1=12. Got T1=%0d", T1.T);
            exit_on_error();
        end else $display("@@@ Passed WAW hazard test!");

        // WAR hazard test
        r1 = 6; r = 6; T = 14; @(negedge clock);
        if (T1.T === 14) begin
            $display("@@@ Failed WAR hazard test! r1 should read old value.");
            dump_mt(6, 7);
            exit_on_error();
        end else $display("@@@ Passed WAR hazard test!");

        // Register 0 test
        r = 0; T = 20; @(negedge clock);
        r1 = 0; r2 = 0; @(negedge clock);
        if (T1.T !== 0 || T2.T !== 0) begin
            $display("@@@ Failed register 0 test! Expected T1=0, T2=0. Got T1=%0d, T2=%0d", T1.T, T2.T);
            exit_on_error();
        end else $display("@@@ Passed register 0 test!");

        // Retire test
        r = 7; T = 15; @(negedge clock);
        r = 0; T = 0;  @(negedge clock);
        retire_r = 7; retire_T = 15; @(negedge clock);
        r1 = 7; @(negedge clock);
        if (T1.T !== 0) begin
            $display("@@@ Failed retire test! Expected T1=0. Got T1=%0d", T1.T);
            exit_on_error();
        end else $display("@@@ Passed retire test!");

        // Read-while-writing test
        r = 8; T = 17; r1 = 8; r2 = 8; @(negedge clock);
        if (T1.T === 17 || T2.T === 17) begin
            $display("@@@ Failed read-while-writing test! r1/r2 should read old value.");
            exit_on_error();
        end else $display("@@@ Passed read-while-writing test!");

        $display("\n@@@ All tests passed successfully!");
        $finish;
    end

endmodule
