`include "verilog/sys_defs.svh"

// rename to 'rs_stage_test.sv' and run 'make rs_stage.out' to run

module testbench;
    // Inputs
    logic clock;
    logic reset;
    logic d_valid;
    logic [`XLEN-1:0] V1, V2;           // values from ROB/regfile
    CDB cdb;
    ID_EX_PACKET ID_EX_reg;
    S_X_PACKET [`RS_SZ-1:0] S_X_reg;    // commited reg value passing back
    ROB_T T;
    MT_ENTRY T1, T2;                    // from map table
    RS_ENTRY [ `RS_SZ-1:0] rs_table;
    logic [`RS_SZ-1:0] busy;

    // Outputs
    logic d_stall;
    S_X_PACKET [`RS_SZ-1:0] S_X_pack;
    integer i, j;
    logic [3:0] clock_count;
    logic error_count;

    rs_stage rs_stage(
        .clock(clock),
        .reset(reset),
        .en(1'b1),
        .cdb(cdb),
        .rs_idx(ID_EX_reg.rs_idx),
        .S_X_reg(S_X_reg), 
        .T(T),
        .T1(T1),
        .T2(T2),
        .V1(V1),
        .V2(V2),

        .d_stall(d_stall),
        .S_X_packet(S_X_pack),
        .rs_table(rs_table),
        .busy(busy)
    );

    task print_rs;
        $display("\n(RS_TABLE)\ttime: %d\n------------------------------------------", clock_count - 1);
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:   %b   ready:%b", j, rs_table[j].T, rs_table[j].T1, rs_table[j].T2, rs_table[j].V1, rs_table[j].V2, busy[j], rs_table[j].ready);
        $display("------------------------------------------");
    endtask

    task compare;
        input [15:0] idx, t, t1, t2, v1, v2, busy;
        if((rs_table[idx].T != t) || (rs_table[idx].T1 != t1) || (rs_table[idx].T2 != t2) || (rs_table[idx].V1 != v1) || (rs_table[idx].V2 != v2)) begin
            error_count = error_count + 1;
            $display("@@@error time: %d\t", clock_count - 1);
            $display("@@@correct answer should be = index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:   %b", idx, t, t1, t2, v1, v2, busy);
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
        clock_count = 0;
        reset = 0;
        ID_EX_reg = {
            `NOP, 
            {`XLEN{1'b0}}, // PC
            {`XLEN{1'b0}}, // NPC
            {`XLEN{1'b0}}, // rs1 value // XLEN is 32 for now
            {`XLEN{1'b0}}, // rs2 value
            OPA_IS_RS1,
            OPB_IS_RS2,
            `ZERO_REG,
            ALU_ADD,
            1'b0, // rd_mem
            1'b0, // wr_mem
            1'b0, // cond
            1'b0, // uncond
            1'b0, // halt
            1'b0, // illegal
            1'b0, // csr_op
            `RS_SZ'd2, // the functional unit is use
            1'b0  // valid
        };
        V1 = 0;
        V2 = 0;
        cdb = 0;
        T = 0;
        T1 = 0;
        T2 = 0;
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;
        // during reset, clear the reservation table

        // ld X(r4), r2 // 1
        V1 = 0;
        V2 = 8;
        T = 1;
        ID_EX_reg.rs_idx = 1;
        S_X_reg[0].ready = 1;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 1;
        T1 = {0, 1'b0};
        T2 = {0, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        // expected change
        // index:    0   T:   1   T1:   0   T2:   0   V1:   5   V2:   1   busy:   1   ready:11
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 1, 0, 0, 0, 8, 1);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 0, 0, 0, 0, 0, 0);

        // mul r1, r2, r3 // 2
        V1 = 5;
        V2 = 0;
        T = 2;
        ID_EX_reg.rs_idx = 3;
        S_X_reg[0].ready = 1;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 1;
        T1 = {0, 1'b0};
        T2 = {1, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 2, 0, 1, 5, 0, 1);

        // st r3, Z(r4) // 3
        V1 = 0;
        V2 = 8;
        T = 3;
        ID_EX_reg.rs_idx = 2;
        S_X_reg[0].ready = 0;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 1;
        T1 = {2, 1'b0};
        T2 = {0, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 2, 0, 1, 5, 0, 1);

        // addi r4, 4, r4 // 4
        V1 = 8;
        V2 = 0;
        T = 4;
        ID_EX_reg.rs_idx = 0;
        S_X_reg[0].ready = 1;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 1;
        T1 = {0, 1'b0};
        T2 = {0, 1'b0};
        cdb.valid = 1;
        cdb.T = 1;
        cdb.V = 10;
        @(negedge clock);
        print_rs();
        compare(0, 4, 0, 0, 8, 0, 1);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 0, 0, 0, 0, 0, 0);

        // ldf X(r4), r2 // 5
        V1 = 0;
        V2 = 0;
        T = 5;
        ID_EX_reg.rs_idx = 1;
        S_X_reg[0].ready = 1;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 0;
        T1 = {0, 1'b0};
        T2 = {4, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 5, 0, 4, 0, 0, 1);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 0, 0, 0, 0, 0, 0);

        // mul r1, r2, r3 // 6
        V1 = 5;
        V2 = 0;
        T = 6;
        ID_EX_reg.rs_idx = 3;
        S_X_reg[0].ready = 0;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 0;
        T1 = {0, 1'b0};
        T2 = {5, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 5, 0, 4, 0, 0, 1);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 6, 0, 5, 5, 0, 1);

        // 7
        cdb.valid = 1;
        cdb.T = 4;
        cdb.V = 12;
        S_X_reg[0].ready = 1;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 0;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 3, 2, 0, 0, 8, 1);
        compare(3, 6, 0, 5, 5, 0, 1);

        // 8
        cdb.valid = 1;
        cdb.T = 2;
        cdb.V = 11;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 0, 0, 0, 0, 0, 0);
        compare(3, 6, 0, 5, 5, 0, 1);
    
        // st r3, Z(r4) // 9
        V1 = 0;
        V2 = 1;
        T = 7;
        ID_EX_reg.rs_idx = 2;
        S_X_reg[0].ready = 1;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 0;
        S_X_reg[3].ready = 1;
        T1 = {6, 1'b0};
        T2 = {0, 1'b0};
        cdb.valid = 1;
        cdb.T = 5;
        cdb.V = 15;
        @(negedge clock);
        print_rs();
        compare(0, 0, 0, 0, 0, 0, 0);
        compare(1, 0, 0, 0, 0, 0, 0);
        compare(2, 7, 6, 0, 0, 1, 1);
        compare(3, 0, 0, 0, 0, 0, 0);

        @(negedge clock);
        if(error_count == 0) begin
            $display("@@@correct");
        end
        else begin
            $display("@@@error");
        end
        @(negedge clock);
        $finish;
    end

endmodule