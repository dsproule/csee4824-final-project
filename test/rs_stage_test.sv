`include "verilog/sys_defs.svh"

module testbench;
    logic clock, reset, en;
    logic [`XLEN-1:0] V1, V2;
    CDB cdb;
    D_S_PACKET D_S_reg;
    logic [`RS_SZ-1:0] FU_ready;
    ROB_T T;
    MT_ENTRY T1, T2;
    logic d_stall;
    S_X_PACKET [`RS_SZ-1:0] S_pack;
    RS_ENTRY [`RS_SZ-1:0] rs_table;
    logic [`RS_SZ-1:0] busy;

    integer j;
    logic [7:0] clock_count;
    logic [5:0] error_count;

    rs_stage rs_stage_inst (
        .clock(clock),
        .reset(reset),
        .alloc_en(en),
        .cdb(cdb),
        .D_S_reg(D_S_reg),
        .FU_ready(FU_ready),
        .T(T),
        .T1(T1),
        .T2(T2),
        .V1(V1),
        .V2(V2),
        .rs_idx_full(d_stall),
        .S_packet(S_pack),
        .rs_table(rs_table),
        .busy(busy)
    );

    always begin
        #(`CLOCK_PERIOD/2.0) clock = ~clock;
    end

    always @(negedge clock)
        clock_count <= clock_count + 1;

    task print_rs;
        $display("\n(RS_TABLE) time %0d\n------------------------------------------", (clock_count-2)/2);
        for (j = 0; j < `RS_SZ; j = j + 1) begin
            $display("idx:%0d T:%0d T1:%0d T2:%0d V1:%0d V2:%0d busy:%b ready:%b",
                     j, rs_table[j].T, rs_table[j].T1, rs_table[j].T2,
                     rs_table[j].V1, rs_table[j].V2, busy[j], rs_table[j].ready);
        end
        $display("------------------------------------------");
    endtask

    task compare;
        input int idx, t, t1, t2, v1, v2;
        input bit exp_busy;
        if ((rs_table[idx].T != t) || (rs_table[idx].T1 != t1) || (rs_table[idx].T2 != t2) ||
            (rs_table[idx].V1 != v1) || (rs_table[idx].V2 != v2) || (busy[idx] != exp_busy)) begin
            error_count++;
            $display("@@@Failed at time %0d", (clock_count-2)/2);
            $display("@@@Expected idx:%0d T:%0d T1:%0d T2:%0d V1:%0d V2:%0d busy:%b",
                     idx, t, t1, t2, v1, v2, exp_busy);
            $finish;
        end
    endtask

    task compare_stall;
        input bit exp_stall;
        if (d_stall !== exp_stall) begin
            error_count++;
            $display("@@@Failed stall at time %0d: got %b expected %b", (clock_count-2)/2, d_stall, exp_stall);
            $finish;
        end
    endtask

    initial begin
        clock = 0;
        reset = 0;
        en = 0;
        error_count = 0;
        clock_count = 0;
        V1 = 0; V2 = 0;
        cdb = '{default:0};
        FU_ready = '{default:0};
        T = 0; T1 = '{default:0}; T2 = '{default:0};
        D_S_reg = '{default:0};

        // Reset
        @(negedge clock) reset = 1;
        @(negedge clock) reset = 0;

        // --- Cycle 1: issue load ---
        @(negedge clock);
        en = 1;
        D_S_reg.rs_idx = 1;
        T = 1; T1 = '{0,1'b0}; T2 = '{0,1'b0};
        V1 = 0; V2 = 8;
        D_S_reg.valid = 1;
        @(posedge clock);
        D_S_reg.valid = 0;
        compare_stall(0);
        @(negedge clock);
        @(negedge clock);
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,1,0,0,0,8,1);
        compare(2,0,0,0,0,0,0);
        compare(3,0,0,0,0,0,0);

        // --- Cycle 2: issue mul ---
        @(negedge clock);
        D_S_reg.rs_idx = 3;
        T = 2; T1 = '{0,1'b0}; T2 = '{1,1'b0};
        V1 = 5; V2 = 0;
        D_S_reg.valid = 1;
        @(posedge clock);
        D_S_reg.valid = 0;
        compare_stall(0);
        @(negedge clock);
        @(negedge clock);
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,1,0,0,0,8,1);
        compare(2,0,0,0,0,0,0);
        compare(3,2,0,1,5,0,1);

        // --- Cycle 3: store ---
        @(negedge clock);
        D_S_reg.rs_idx = 2;
        T = 3; T1 = '{2,1'b0}; T2 = '{0,1'b0};
        V1 = 0; V2 = 8;
        D_S_reg.valid = 1;
        @(posedge clock);
        D_S_reg.valid = 0;
        compare_stall(0);
        @(posedge clock);
        @(negedge clock);
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,1,0,0,0,8,1);
        compare(2,3,2,0,0,8,1);
        compare(3,2,0,1,5,0,1);

        // --- Cycle 4: addi ---
        @(negedge clock);
        D_S_reg.rs_idx = 0;
        T = 4; T1 = '{0,1'b0}; T2 = '{0,1'b0};
        V1 = 8; V2 = 0;
        D_S_reg.valid = 1;
        @(posedge clock);
        D_S_reg.valid = 0;
        compare_stall(0);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        print_rs();
        compare(0,4,0,0,8,0,1);
        compare(1,1,0,0,0,8,1);
        compare(2,3,2,0,0,8,1);
        compare(3,2,0,1,5,0,1);

        // --- Cycle 5: ldf ---
        @(negedge clock);
        D_S_reg.rs_idx = 1;
        T = 5; T1 = '{0,1'b0}; T2 = '{4,1'b0};
        V1 = 0; V2 = 0;
        D_S_reg.valid = 1;
        @(posedge clock);
        D_S_reg.valid = 0;
        compare_stall(1);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        FU_ready = 4'b0010;
        print_rs();
        compare(0,4,0,0,8,0,1);
        compare(1,1,0,0,0,8,1);
        compare(2,3,2,0,0,8,1);
        compare(3,2,0,1,5,0,1);

        // --- Cycle 6: mul ---
        @(negedge clock);
        D_S_reg.rs_idx = 3;
        T = 6; T1 = '{0,1'b0}; T2 = '{5,1'b0};
        V1 = 5; V2 = 0;
        D_S_reg.valid = 1;
        @(posedge clock);
        D_S_reg.valid = 0;
        compare_stall(1);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        FU_ready = 4'b0001;
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,5,0,4,0,0,1);
        compare(2,3,2,0,0,8,1);
        compare(3,0,0,0,0,0,0);

        // --- Cycle 7: wakeup via CDB (T=4) ---
        @(negedge clock);
        D_S_reg.rs_idx = 2;
        T = 7; T1 = '{6,1'b0}; T2 = '{0,1'b0};
        V1 = 0; V2 = 1;
        cdb.valid = 1;
        cdb.T = 4;
        cdb.V = 12;
        @(posedge clock);
        D_S_reg.valid = 0;
        cdb.valid = 0;
        compare_stall(1);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        FU_ready = 4'b0001;
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,5,0,0,0,12,1);
        compare(2,3,2,0,0,8,1);
        compare(3,6,0,5,5,0,1);

        // --- Cycle 8: wakeup via CDB (T=2) ---
        @(negedge clock);
        D_S_reg.rs_idx = 2;
        T = 7; T1 = '{6,1'b0}; T2 = '{0,1'b0};
        V1 = 0; V2 = 1;
        cdb.valid = 1;
        cdb.T = 2;
        cdb.V = 11;
        @(posedge clock);
        D_S_reg.valid = 0;
        cdb.valid = 0;
        compare_stall(1);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        FU_ready = '{default:0};
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,0,0,0,0,0,0);
        compare(2,3,0,0,11,8,0);
        compare(3,6,0,5,5,0,1);

        // --- Cycle 9: final wakeup/store ---
        @(negedge clock);
        D_S_reg.rs_idx = 2;
        T = 7; T1 = '{6,1'b0}; T2 = '{4,1'b1};
        V1 = 0; V2 = 1;
        cdb.valid = 1;
        cdb.T = 4 ;
        cdb.V = 15;
        @(posedge clock);
        D_S_reg.valid = 0;
        cdb.valid = 0;
        compare_stall(1);
        @(negedge clock);
        @(posedge clock);
        FU_ready = 4'b0001;
        @(negedge clock);
        @(posedge clock);
        FU_ready = '{default:0};
        @(negedge clock);
        print_rs();
        compare(0,0,0,0,0,0,0);
        compare(1,0,0,0,0,0,0);
        compare(2,0,0,0,0,0,0);
        compare(3,6,0,0,5,15,1);

        $display("@@@Passed");
        @(negedge clock);
        $finish;
    end
endmodule


