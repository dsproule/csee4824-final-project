`include "verilog/sys_defs.svh"

// rename to 'rs_stage_test.sv' and run 'make rs_stage.out' to run

module testbench;
    // Inputs
    logic clock;
    logic reset;
    logic en;
    logic d_valid;
    logic [`XLEN-1:0] V1, V2;           // values from ROB/regfile
    CDB cdb;
    D_S_PACKET D_S_reg;
    S_X_PACKET [`RS_SZ-1:0] S_X_reg;    // commited reg value passing back
    ROB_T T;
    ROB_T T_wire;   // from ROB to rs/map table
    // MT_ENTRY T1, T2;                    
    MT_ENTRY T1_wire, T2_wire;                    // from map table
    RS_ENTRY [ `RS_SZ-1:0] rs_table;
    logic [`RS_SZ-1:0] busy;
    logic [4:0] r, r1, r2; // the original register value
    ROB_T retire_T;
    logic [4:0] retire_r;

    // Outputs
    logic d_stall;
    S_X_PACKET [`RS_SZ-1:0] S_X_pack;
    integer i, j, k, l;
    logic [7:0] clock_count;
    logic [5:0] error_count;
    logic [`RS_SZ-1:0] FU_ready;

    // for rob
    logic full;
    logic empty;
    logic regfile_write_en;
    logic [4:0] regfile_write_idx;
    logic [`XLEN-1:0] regfile_write_data;
    logic [`XLEN-1:0] V1_rob, V2_rob;

    logic [`XLEN-1:0] V1_rs, V2_rs;
    MT_ENTRY mt_table [31:0];

    assign V1_rs = (T1_wire.plus) ? V1_rob : V1;
    assign V2_rs = (T2_wire.plus) ? V2_rob : V2;

    map_table map_table(
        .clock(clock),
        .reset(reset),
        .r(r), // 5 bits // finished
        .r1(r1), // 5 bits // finished 
        .r2(r2), // 5 bits // finished
        .retire_r(retire_r), // 5 bits
        .cdb(cdb), // CDB
        .T(T_wire), // ROB_T
        .retire_T(retire_T), // ROB_T
        .T1(T1_wire), // MT_ENTRY // output // finished 
        .T2(T2_wire), // MT_ENTRY // output // finished
        .mt_table(mt_table)
    );

    rs_stage rs_stage(
        .clock(clock),
        .reset(reset),
        .en(en),
        .cdb(cdb),
        .D_S_reg(D_S_reg),
        // .S_X_reg(S_X_reg), 
        .FU_ready(FU_ready),
        .T(T_wire),
        .T1(T1_wire),
        .T2(T2_wire),
        .V1(V1_rs),
        .V2(V2_rs),

        .d_stall(d_stall),
        .S_packet(S_X_pack),
        .rs_table(rs_table),
        .busy(busy)
    );

    rob rob_inst (
        .clock(clock), 
        .reset(reset), 
        .flush(1'b0), // 0 for now
        .r(r), 
        .T1(T1_wire), // for getting the ROB value
        .T2(T2_wire), // for getting the ROB value
        .cdb(cdb),
        .dispatch_valid(D_S_reg.valid & ~d_stall), // ?
        .T(T_wire), 
        .full(full), 
        .empty(empty),
        .regfile_write_en(regfile_write_en), 
        .regfile_write_idx(regfile_write_idx),
        .V1(V1_rob), 
        .V2(V2_rob), 
        .regfile_write_data(regfile_write_data)
    );

    // regfile regfile_0(
    //     // Inputs
    //     .clock(clock),
    //     .read_idx_1(r1), .read_idx_2(r2), .write_idx(regfile_write_idx),
    //     .write_en(regfile_write_en),
    //     .write_data(regfile_write_data),

    //     // Outputs
    //     .read_out_1(regfile_V1), .read_out_2(regfile_V2)
    // );

    task print_rs;
        $display("\n(RS_TABLE)\ttime: %d\n------------------------------------------", clock_count - 3);
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:   %b   ready:%b", j, rs_table[j].T, rs_table[j].T1, rs_table[j].T2, rs_table[j].V1, rs_table[j].V2, busy[j], rs_table[j].ready);
        $display("------------------------------------------");
    endtask

    task print_mt;
        $display("\n(MAP_TABLE)\ttime: %d\n------------------------------------------", clock_count - 3);
        for(l = 1; l < 5; l=l+1)
            $display("index: %4d   T:%4d\t  plus:%4d", l, mt_table[l].T, mt_table[l].plus);
        $display("------------------------------------------");
    endtask

    task compare;
        input [15:0] idx, t, t1, t2, v1, v2;
        input busy;
        if((rs_table[idx].T != t) || (rs_table[idx].T1 != t1) || (rs_table[idx].T2 != t2) || (rs_table[idx].V1 != v1) || (rs_table[idx].V2 != v2) || (busy[idx] != busy)) begin
            error_count = error_count + 1;
            $display("@@@Failed at time: %d\t", clock_count - 3);
            $display("@@@correct answer should be = index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:%b", idx, t, t1, t2, v1, v2, busy);
            // $finish;
        end
    endtask

    task compare_stall;
        input stall;
        if(d_stall != stall) begin
            error_count = error_count + 1;
            $display("@@@Failed at time: %d\t", clock_count - 3);
            $display("@@@stall error: d_stall: %b", d_stall);
            // $finish;
        end
    endtask

    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    always@(posedge clock) begin
        clock_count <= clock_count + 1;
    end

    initial begin
        clock = 0;
        error_count = 0;
        clock_count = 0;
        reset = 0;
        en = 0;
        FU_ready = 4'b1111;
        D_S_reg = {
            `NOP, 
            {`XLEN{1'b0}}, // PC
            {`XLEN{1'b0}}, // NPC
            {`XLEN{1'b0}}, // r
            {`XLEN{1'b0}}, // r1
            {`XLEN{1'b0}}, // r2
            OPA_IS_RS1,
            OPB_IS_RS2,
            1'b0,          // cond
            1'b0,          // uncond
            ALU_ADD,       // alu_func
            `RS_SZ'd2, // the functional unit is use
            1'b0, // halt
            1'b0, // illegal
            1'b0, // csr_op
            1'b1  // valid
        };
        V1 = 0;
        V2 = 0;
        cdb = 0;
        T = 0;
        // T1 = 0;
        // T2 = 0;
        r = 0;
        r1 = 0;
        r2 = 0;
        retire_r = 0;
        retire_T = 0;
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;
        // during reset, clear the reservation table

        @(negedge clock); 
        en = 1;
        // ld X(r4), r2 // 1
        V1 = 0;
        V2 = 8;
        // T = 1;
        D_S_reg.rs_idx = 1;
        // T1 = {0, 1'b0};
        // T2 = {0, 1'b0};
        r = 2;
        r1 = 0;
        r2 = 4;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 1;
        compare_stall(0);
        @(negedge clock); // 1
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 0, 0, 0, 0, 0, 0);

        // expected change
        // index:    0   T:   1   T1:   0   T2:   0   V1:   5   V2:   1   busy:   1   ready:11
        // 1

        // @(negedge clock); 
        // mul r1, r2, r3 // 2
        V1 = 5;
        V2 = 0;
        // T = 2;
        D_S_reg.rs_idx = 3;
        // T1 = {0, 1'b0};
        // T2 = {1, 1'b0};
        r = 3;
        r1 = 1;
        r2 = 2;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 1;
        compare_stall(0);
        // 2
        @(negedge clock);
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 1, 0, 0, 0, 8, 1);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 0, 0, 0, 0, 0, 0);

        // @(negedge clock);
        // st r3, Z(r4) // 3
        V1 = 0;
        V2 = 8;
        // T = 3;
        D_S_reg.rs_idx = 2;
        // T1 = {2, 1'b0};
        // T2 = {0, 1'b0};
        r = 0; // question: what should be the r for store function
        r1 = 3;
        r2 = 4;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 1;
        compare_stall(0);
        @(negedge clock);
        // 3
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 2, 0, 1, 5, 0, 1);
    
        // @(negedge clock); 
        // addi r4, 4, r4 // 4
        V1 = 8;
        V2 = 0;
        // T = 4;
        D_S_reg.rs_idx = 0;
        // T1 = {0, 1'b0};
        // T2 = {0, 1'b0};
        r = 4;
        r1 = 4;
        r2 = 0;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 1;
        cdb.T = 1;
        cdb.V = 10;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 1;
        compare_stall(0);
        // 4
        @(negedge clock);
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 2, 0, 0, 5, 10, 1); 

        // @(negedge clock); 
        // ldf X(r4), r2 // 5
        V1 = 0;
        V2 = 0;
        // T = 5;
        D_S_reg.rs_idx = 1;
        // T1 = {0, 1'b0};
        // T2 = {4, 1'b0};
        r = 2;
        r1 = 0;
        r2 = 4;
        retire_r = 2;
        retire_T = 1;
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 0;
        compare_stall(0);
        @(negedge clock);
        // 5
        print_rs();
        print_mt();
        compare(0, 4, 0, 0, 8, 0, 1);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 0, 0, 0, 0, 0, 0); 
        

        // @(negedge clock); 
        // mul r1, r2, r3 // 6
        V1 = 5;
        V2 = 0;
        // T = 6;
        D_S_reg.rs_idx = 3;
        // T1 = {0, 1'b0};
        // T2 = {5, 1'b0};
        r = 3;
        r1 = 1;
        r2 = 2;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(posedge clock); #2
        FU_ready[0] = 0;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 0;
        compare_stall(0);
        // 6
        @(negedge clock);
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 5, 0, 4, 0, 0, 1);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 0, 0, 0, 0, 0, 0);
        

        // @(negedge clock); 
        // 7
        V1 = 0;
        V2 = 1;
        // T = 7;
        D_S_reg.rs_idx = 2;
        // T1 = {6, 1'b0};
        // T2 = {0, 1'b0};
        r = 0;
        r1 = 3;
        r2 = 4;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 1;
        cdb.T = 4;
        cdb.V = 12;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 0;
        compare_stall(1);
        // 7
        @(negedge clock);
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 5, 0, 0, 0, 12, 1);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 6, 0, 5, 5, 0, 1);
        
        // @(negedge clock); 
        // 8
        V1 = 0;
        V2 = 1;
        // T = 7;
        D_S_reg.rs_idx = 2;
        // T1 = {6, 1'b0};
        // T2 = {0, 1'b0};
        r = 0;
        r1 = 3;
        r2 = 4;
        retire_r = 0;
        retire_T = 0;
        cdb.valid = 1;
        cdb.T = 2;
        cdb.V = 11;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 0;
        FU_ready[2] = 1;
        FU_ready[3] = 1;
        compare_stall(1);
        @(negedge clock); 
        // 8
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 0, 0, 11, 8, 1);
        compare(3, 6, 0, 5, 5, 0, 1);    
        
    
        // st r3, Z(r4) // 9
        // @(negedge clock); 
        V1 = 0;
        V2 = 0;
        // T = 7;
        D_S_reg.rs_idx = 2;
        // T1 = {6, 1'b0};
        // T2 = {4, 1'b1};
        r = 0;
        r1 = 3;
        r2 = 4;
        retire_r = 3;
        retire_T = 2; // question: do store inst need to retire?
        cdb.valid = 1;
        cdb.T = 5;
        cdb.V = 15;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 0;
        FU_ready[3] = 1;
        compare_stall(0);
        // 9
        @(negedge clock);
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 6, 0, 0, 5, 15, 1);

        // none // 10
        // @(negedge clock); 
        V1 = 0;
        V2 = 0;
        // T = 7;
        D_S_reg.rs_idx = 0;
        // T1 = {6, 1'b0};
        // T2 = {4, 1'b1};
        r = 0;
        r1 = 0;
        r2 = 0;
        retire_r = 0;
        retire_T = 0; // question: do store inst need to retire?
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(posedge clock); #2
        FU_ready[0] = 1;
        FU_ready[1] = 1;
        FU_ready[2] = 1;
        FU_ready[3] = 0;
        compare_stall(0);
        // 10
        @(negedge clock);
        print_rs();
        print_mt();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 7, 6, 0, 0, 12, 1);
        compare(3, 0, 0, 0, 0, 0, 0);

        if(error_count == 0) begin
            $display("@@@Passed");
        end
        @(negedge clock);
        $finish;
    end

endmodule