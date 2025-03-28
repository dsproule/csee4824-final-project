`include "verilog/sys_defs.svh"

// rename to 'rs_stage_test.sv' and run 'make rs_stage.out' to run

module testbench;
    // General Inputs
    logic clock;
    logic reset;
    logic en;
    CDB cdb;                    // manually assigned value (should come from later stage)
    D_S_PACKET D_S_reg;         // manually assigned value (should come from previous stage)
    logic [4:0] r, r1, r2;      // manually assigned value (should come from previous stage)
    logic [`RS_SZ-1:0] FU_ready;// manually assigned value (should come from functional units)

    // General Outputs
    S_X_PACKET [`RS_SZ-1:0] S_X_pack; // for next stage

    // Tag
    ROB_T T_wire;               // Destination tag: from ROB -> Map Table & RS
    MT_ENTRY T1_wire, T2_wire;  // Source tag: from Map Table -> RS & ROB & Regfile  

    // Value
    logic [`XLEN-1:0] V1_rs, V2_rs;             // Final value sent into RS
    logic [`XLEN-1:0] V1_rob, V2_rob;           // used when mt_table[i].plus == 1
    logic [`XLEN-1:0] regfile_V1, regfile_V2;   // used when mt_table[i].T == 0
    assign V1_rs = (T1_wire.plus) ? V1_rob : regfile_V1;
    assign V2_rs = (T2_wire.plus) ? V2_rob : regfile_V2;

    // Retire
    logic retire;
    ROB_T retire_T_wire;        // from ROB -> Map Table & Regfile
    logic [4:0] retire_r_wire;  // from ROB -> Map Table & Regfile

    // Reservation Station Signals
    RS_ENTRY [ `RS_SZ-1:0] rs_table;
    logic [`RS_SZ-1:0] busy;    // functional unit in used -> busy
    logic d_stall;              // If that functional unit is occupied -> stall
    
    // Map Table
    MT_ENTRY mt_table [31:0];
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out;

    // ROB Signals
    logic full;
    logic empty;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out; // original ROB output
    ROB_ENTRY rob_table [`ROB_SZ:1];                  // formatted ROB

    // Regfile Write Signals
    logic [4:0] regfile_write_idx;          // Final idx to Regfile
    logic [`XLEN-1:0] regfile_write_data;   // Final data to Regfile
    logic regfile_write_en;                 // Final en to Regfile
    logic [4:0] rob_write_idx;              // ROB -> Regfile
    logic [`XLEN-1:0] rob_write_data;       // ROB -> Regfile
    logic ppl_write_en;                     // initialization
    logic [4:0] ppl_write_idx;              // initialization
    logic [`XLEN-1:0] ppl_write_data;       // initialization
    assign regfile_write_en = en ? retire : ppl_write_en;
    assign regfile_write_data = en ? rob_write_data : ppl_write_data;
    assign regfile_write_idx = en ? retire_r_wire : ppl_write_idx;

    // Count
    integer i, j, k, l, m, n;
    logic [7:0] clock_count;
    logic [5:0] error_count;

    map_table map_table_inst (.clock(clock), .reset(reset), .en(en), .r(r), .r1(r1), .r2(r2), .retire_r(retire_r_wire), 
                              .cdb(cdb), .T(T_wire), .retire_T(retire_T_wire), .T1(T1_wire), .T2(T2_wire), .mt_table_out(mt_table_out));

    always_comb begin
        //re-unpack array for debugging, needed for synthesis debugging   
        for (int i = 0; i < 32; i++) begin
            mt_table[i] = mt_table_out[i * $bits(MT_ENTRY) +: $bits(MT_ENTRY)];
        end
    end

    rs_stage rs_stage_inst (.clock(clock), .reset(reset), .en(en), .cdb(cdb), .D_S_reg(D_S_reg), .FU_ready(FU_ready),
                            .T(T_wire), .T1(T1_wire), .T2(T2_wire), .V1(V1_rs), .V2(V2_rs), .d_stall(d_stall),
                            .S_packet(S_X_pack), .rs_table(rs_table), .busy(busy));

    rob rob_inst (.clock(clock), .reset(reset), .r(r), .T1(T1_wire.T), .T2(T2_wire.T), .cdb(cdb),
                  .dispatch_valid(D_S_reg.valid & ~d_stall), .T(T_wire), .retire_T_out(retire_T_wire), 
                  .ppl_ctrl(), .full(full), .empty(empty), .retire(retire), .regfile_write_idx_out(retire_r_wire), 
                  .V1(V1_rob), .V2(V2_rob), .regfile_write_data(rob_write_data),.rob_table_out(rob_table_out));

    regfile regfile_inst (.clock(clock), .read_idx_1(r1), .read_idx_2(r2), .write_idx(regfile_write_idx),
                          .write_en(regfile_write_en),.write_data(regfile_write_data),
                          .read_out_1(regfile_V1), .read_out_2(regfile_V2));

    task print_rs;
        $display("\n(RS_TABLE)\ttime: %d\n------------------------------------------", clock_count - 6);
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:   %b   ready:%b", j, rs_table[j].T, rs_table[j].T1, rs_table[j].T2, rs_table[j].V1, rs_table[j].V2, busy[j], rs_table[j].ready);
        $display("------------------------------------------");
    endtask

    task print_rob;
        $display("\n(ROB_TABLE)\ttime: %d\n------------------------------------------", clock_count - 6);
        for(n = 1; n < 8; n=n+1)
            $display("index: %4d   r:%4d   V:%4d", n, rob_table[n].r, rob_table[n].V);
        $display("------------------------------------------");
    endtask

    task print_mt;
        $display("\n(MAP_TABLE)\ttime: %d\n------------------------------------------", clock_count - 6);
        for(l = 1; l < 5; l=l+1)
            $display("index: %4d   T:%4d\t  plus:%4d", l, mt_table[l].T, mt_table[l].plus);
        $display("------------------------------------------");
    endtask

    task compare; // compare rs
        input [15:0] idx, t, t1, t2, v1, v2;
        input busy;
        if((rs_table[idx].T != t) || (rs_table[idx].T1 != t1) || (rs_table[idx].T2 != t2) || (rs_table[idx].V1 != v1) || (rs_table[idx].V2 != v2) || (busy[idx] != busy)) begin
            error_count = error_count + 1;
            $display("@@@Failed at time: %d\t", clock_count - 6);
            $display("@@@correct answer should be = index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:%b", idx, t, t1, t2, v1, v2, busy);
            // $finish;
        end
    endtask

    task compare_stall;
        input stall;
        if(d_stall != stall) begin
            error_count = error_count + 1;
            $display("@@@Failed at time: %d\t", clock_count - 6);
            $display("@@@stall error: d_stall: %b", d_stall);
            // $finish;
        end
    endtask

    task compare_mt;
        input [15:0] idx, t, plus;
        if((mt_table[idx].T != t) || (mt_table[idx].plus != plus)) begin
            error_count = error_count + 1;
            $display("@@@Failed at time: %d\t", clock_count - 6);
            $display("@@@correct answer should be = index: %4d   T:%4d   plus:%4d", idx, t, plus);
            // $finish;
        end
    endtask

    task compare_rob;
        input [15:0] idx, r, V;
        if((rob_table[idx].r != r) || (rob_table[idx].V != V)) begin
            error_count = error_count + 1;
            $display("@@@Failed at time: %d\t", clock_count - 6);
            $display("@@@correct answer should be = index: %4d   r:%4d   V:%4d", idx, r, V);
            // $finish;
        end
    endtask

    // Clock Generation
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end
    always@(posedge clock) begin
        clock_count <= clock_count + 1;
    end

    // ROB Table formatting
    always_comb begin
        for (int i = 0; i < `ROB_SZ; i++) begin
            rob_table[i+1] = rob_table_out[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)];
        end
    end

    initial begin
        // reset
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
            1'b0  // valid
        };
        cdb = 0;
        r = 0;
        r1 = 0;
        r2 = 0;
        @(negedge clock);
        reset = 1;
        ppl_write_en = 1;
        ppl_write_idx = 1;
        ppl_write_data = 5;
        @(negedge clock);
        ppl_write_en = 1;
        ppl_write_idx = 2;
        ppl_write_data = 6;
        @(negedge clock);
        ppl_write_en = 1;
        ppl_write_idx = 3;
        ppl_write_data = 7;
        @(negedge clock);
        ppl_write_en = 1;
        ppl_write_idx = 4;
        ppl_write_data = 8;
        @(negedge clock);
        reset = 0;


        @(negedge clock); 
        en = 1;
        D_S_reg.valid = 1;
        // ld X(r4), r2 // 1
        // V1 = 0; V2 = 8; T = 1; T1 = {0, 1'b0}; T2 = {0, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 1;
        r = 2;
        r1 = 0;
        r2 = 4;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 0, 0, 0, 0, 0, 0);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 1, 0);
        compare_mt(3, 0, 0);
        compare_mt(4, 0, 0);
        print_rob();
        compare_rob(1, 2, 0);
        compare_rob(2, 0, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 0, 0);
        compare_rob(5, 0, 0);
        compare_rob(6, 0, 0);
        compare_rob(7, 0, 0);

        // mul r1, r2, r3 // 2
        // V1 = 5; V2 = 0; T = 2; T1 = {0, 1'b0}; T2 = {1, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 3;
        r = 3;
        r1 = 1;
        r2 = 2;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 1, 0, 0, 0, 8, 1);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 0, 0, 0, 0, 0, 0);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 1, 0);
        compare_mt(3, 2, 0);
        compare_mt(4, 0, 0);
        print_rob();
        compare_rob(1, 2, 0);
        compare_rob(2, 3, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 0, 0);
        compare_rob(5, 0, 0);
        compare_rob(6, 0, 0);
        compare_rob(7, 0, 0);

        // stf r3, Z(r4) // 3
        // V1 = 0; V2 = 8; T = 3; T1 = {2, 1'b0}; T2 = {0, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 2;
        r = 0; // question: what should be the r for store function
        r1 = 3;
        r2 = 4;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 2, 0, 1, 5, 0, 1);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 1, 0);
        compare_mt(3, 2, 0);
        compare_mt(4, 0, 0);
        print_rob();
        compare_rob(1, 2, 0);
        compare_rob(2, 3, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 0, 0);
        compare_rob(5, 0, 0);
        compare_rob(6, 0, 0);
        compare_rob(7, 0, 0);
        
        // addi r4, 4, r4 // 4
        // V1 = 8; V2 = 0; T = 4; T1 = {0, 1'b0}; T2 = {0, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 0;
        r = 4;
        r1 = 4;
        r2 = 0;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 2, 0, 0, 5, 10, 1); 
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 1, 1);
        compare_mt(3, 2, 0);
        compare_mt(4, 4, 0);
        print_rob();
        compare_rob(1, 2, 10);
        compare_rob(2, 3, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 0);
        compare_rob(5, 0, 0);
        compare_rob(6, 0, 0);
        compare_rob(7, 0, 0);

        // ldf X(r4), r2 // 5
        // V1 = 0; V2 = 0; T = 5; T1 = {0, 1'b0}; T2 = {4, 1'b0}; retire_r = 2; retire_T = 1;
        D_S_reg.rs_idx = 1;
        r = 2;
        r1 = 0;
        r2 = 4;
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
        compare(0, 4, 0, 0, 8, 0, 1);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 0, 0, 0, 0, 0, 0); 
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 5, 0);
        compare_mt(3, 2, 0);
        compare_mt(4, 4, 0);
        print_rob();
        compare_rob(1, 0, 0);
        compare_rob(2, 3, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 0);
        compare_rob(5, 2, 0);
        compare_rob(6, 0, 0);
        compare_rob(7, 0, 0);

        // mul r1, r2, r3 // 6
        // V1 = 5; V2 = 0; T = 6; T1 = {0, 1'b0}; T2 = {5, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 3;
        r = 3;
        r1 = 1;
        r2 = 2;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 5, 0, 4, 0, 0, 1);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 0, 0, 0, 0, 0, 0);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 5, 0);
        compare_mt(3, 6, 0);
        compare_mt(4, 4, 0);
        print_rob();
        compare_rob(1, 0, 0);
        compare_rob(2, 3, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 0);
        compare_rob(5, 2, 0);
        compare_rob(6, 3, 0);
        compare_rob(7, 0, 0);
        
        // stf r3, Z(r4) (stall) // 7
        // V1 = 0; V2 = 1; T = 7; T1 = {6, 1'b0}; T2 = {0, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 2;
        r = 0;
        r1 = 3;
        r2 = 4;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 5, 0, 0, 0, 12, 1);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 6, 0, 5, 5, 0, 1);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 5, 0);
        compare_mt(3, 6, 0);
        compare_mt(4, 4, 1);
        print_rob();
        compare_rob(1, 0, 0);
        compare_rob(2, 3, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 12);
        compare_rob(5, 2, 0);
        compare_rob(6, 3, 0);
        compare_rob(7, 0, 0);
        
        // stf r3, Z(r4) (stall) // 8
        // V1 = 0; V2 = 1; T = 7; T1 = {6, 1'b0}; T2 = {0, 1'b0}; retire_r = 0; retire_T = 0;
        D_S_reg.rs_idx = 2;
        r = 0;
        r1 = 3;
        r2 = 4;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 0, 0, 11, 8, 1);
        compare(3, 6, 0, 5, 5, 0, 1);    
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 5, 0);
        compare_mt(3, 6, 0);
        compare_mt(4, 4, 1);
        print_rob();
        compare_rob(1, 0, 0);
        compare_rob(2, 3, 11);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 12);
        compare_rob(5, 2, 0);
        compare_rob(6, 3, 0);
        compare_rob(7, 0, 0);
        
        // stf r3, Z(r4) // 9
        // V1 = 0; V2 = 2; T = 7; T1 = {6, 1'b0}; T2 = {4, 1'b1}; retire_r = 3; retire_T = 2;
        D_S_reg.rs_idx = 2;
        r = 0;
        r1 = 3;
        r2 = 4;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 6, 0, 0, 5, 15, 1);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 5, 1);
        compare_mt(3, 6, 0);
        compare_mt(4, 4, 1);
        print_rob();
        compare_rob(1, 0, 0);
        compare_rob(2, 0, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 12);
        compare_rob(5, 2, 15);
        compare_rob(6, 3, 0);
        compare_rob(7, 0, 0);

        // none // 10
        D_S_reg.rs_idx = 0;
        r = 0;
        r1 = 0;
        r2 = 0;
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
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 7, 6, 0, 0, 12, 1);
        compare(3, 0, 0, 0, 0, 0, 0);
        print_mt();
        compare_mt(1, 0, 0);
        compare_mt(2, 5, 1);
        compare_mt(3, 6, 0);
        compare_mt(4, 4, 1);
        print_rob();
        compare_rob(1, 0, 0);
        compare_rob(2, 0, 0);
        compare_rob(3, 0, 0);
        compare_rob(4, 4, 12);
        compare_rob(5, 2, 15);
        compare_rob(6, 3, 0);
        compare_rob(7, 0, 0);

        if(error_count == 0) begin
            $display("@@@Passed");
        end
        @(negedge clock);
        $finish;
    end

endmodule