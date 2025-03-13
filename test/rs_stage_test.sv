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

    // Outputs
    logic d_stall;
    S_X_PACKET [`RS_SZ-1:0] S_X_pack;
    integer i, j;

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
        .rs_table(rs_table)
    );

    task print_rs;
        $display("\n(RS_TABLE)\n------------------------------------------");
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:   %b   ready:%b    stall:%b", j, rs_table[j].T, rs_table[j].T1, rs_table[j].T2, rs_table[j].V1, rs_table[j].V2, rs_table[j].busy, rs_table[j].ready, d_stall);
        $display("------------------------------------------");
    endtask

    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    initial begin
        clock = 0;
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

        print_rs();

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

        // st r3, Z(r4) // 3
        V1 = 0;
        V2 = 8;
        T = 0;
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

        // mul r1, r2, r3 // 6
        V1 = 5;
        V2 = 0;
        T = 6;
        ID_EX_reg.rs_idx = 3;
        S_X_reg[0].ready = 0;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 1;
        T1 = {0, 1'b0};
        T2 = {5, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        print_rs();

        // mul r1, r2, r3 // 6
        V1 = 5;
        V2 = 0;
        T = 6;
        ID_EX_reg.rs_idx = 3;
        S_X_reg[0].ready = 0;
        S_X_reg[1].ready = 1;
        S_X_reg[2].ready = 1;
        S_X_reg[3].ready = 1;
        T1 = {0, 1'b0};
        T2 = {5, 1'b0};
        cdb.valid = 0;
        cdb.T = 0;
        cdb.V = 0;
        @(negedge clock);
        print_rs();

        @(negedge clock);
        @(negedge clock);
        $finish;
    end

endmodule