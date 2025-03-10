`include "verilog/sys_defs.svh"

module testbench;
    // Inputs
    logic reset;
    logic [`XLEN-1:0] V1, V2;           // values from ROB/regfile
    CDB cdb;
    ID_EX_PACKET ID_EX_reg;
    S_X_PACKET [`RS_SZ-1:0] S_X_reg;    // commited reg value passing back
    ROB_T T;
    MT_ENTRY T1, T2;                    // from map table

    // Outputs
    logic stall_d;
    S_X_PACKET [`RS_SZ-1:0] S_X_packet;

    RS_STAGE rs_stage(.*);

    initial begin
        #5 reset = 1;
        #5 reset = 0;

        $finish;
    end



endmodule