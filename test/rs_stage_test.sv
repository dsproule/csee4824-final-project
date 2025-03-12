`include "verilog/sys_defs.svh"

module testbench;
    // Inputs
    logic clock;
    logic reset;
    logic [`XLEN-1:0] V1, V2;           // values from ROB/regfile
    CDB cdb;
    ID_EX_PACKET ID_EX_reg;
    S_X_PACKET [`RS_SZ-1:0] S_X_reg;    // commited reg value passing back
    ROB_T T;
    MT_ENTRY T1, T2;                    // from map table

    // Outputs
    logic stall_d;
    S_X_PACKET [`RS_SZ-1:0] S_X_pack;
    integer i, j;

    RS_STAGE rs_stage(
        .reset(reset),
        .cdb(cdb),
        .ID_EX_reg(ID_EX_reg),
        .S_X_reg(S_X_reg), // won't cause combinational loop if you don't have clock?
        .T(T),
        .T1(T1),
        .T2(T2),
        .V1(V1),
        .V2(V2),
        .stall_d(stall_d),
        .S_X_packet(S_X_pack)
    );

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
            2, // the functional unit is use
            1'b0  // valid
        };
        V1 = 0;
        V2 = 0;
        cdb = {
            0, // T
            0, // V
            0 // valid
        };
        T = 0;
        T1 = 0;
        T2 = 0;
        @(posedge clock);
        reset = 1;
        @(posedge clock);
        reset = 0;
        // during reset, clear the reservation table
        
        // ld X(r4), r2
        @(posedge clock);
        ID_EX_reg.rs_idx = 2;
        V1 = 0;
        V2 = 8;
        cdb = {
            0, // T
            0, // V
            0 // valid
        };
        T = 1;
        T1 = 0;
        T2 = 0;
        @(negedge clock);
        for(j = 0; j < `RS_SZ; j=j+1) begin
            $display("index:%d T:%d V1:%d V2:%d ready:%b go:%b", j, S_X_pack[j].T, S_X_pack[j].V1, S_X_pack[j].V2, S_X_pack[j].ready, S_X_pack[j].go);
        end
        $display("-----------------------------------------");

        // mul r1, r2, r3
        @(posedge clock);
        ID_EX_reg.rs_idx = 4;
        V1 = 5;
        V2 = 0;
        cdb = {
            0, // T
            0, // V
            0 // valid
        };
        T = 2;
        T1 = 0;
        T2 = 1;
        for(j = 0; j < `RS_SZ; j=j+1) begin
            $display("index:%d T:%d V1:%d V2:%d ready:%b go:%b", j, S_X_pack[j].T, S_X_pack[j].V1, S_X_pack[j].V2, S_X_pack[j].ready, S_X_pack[j].go);
        end
        $display("-----------------------------------------");

        // st r3, Z(r4)
        @(posedge clock);
        ID_EX_reg.rs_idx = 4;
        V1 = 0;
        V2 = 8;
        cdb = {
            0, // T
            0, // V
            0 // valid
        };
        T = 3;
        T1 = 2;
        T2 = 0;
        for(j = 0; j < `RS_SZ; j=j+1) begin
            $display("index:%d T:%d V1:%d V2:%d ready:%b go:%b", j, S_X_pack[j].T, S_X_pack[j].V1, S_X_pack[j].V2, S_X_pack[j].ready, S_X_pack[j].go);
        end
        $display("-----------------------------------------");

        @(posedge clock);
        @(posedge clock);
        @(posedge clock);
        $finish;
    end

    always_ff @(posedge clock or posedge reset) begin
        if(reset) begin
            for(i = 0; i < `RS_SZ; i=i+1) begin
                S_X_reg[i] <= {
                    0, // T
                    0, // T1
                    0, // T2
                    0, // OPA
                    0, // OPB
                    0, // alu func
                    0, // ready
                    0 // go
                };
            end
        end
        else begin
            for(i = 0; i < `RS_SZ; i=i+1) begin
                S_X_reg[i] <= S_X_pack[i];
            end
        end
    end

endmodule