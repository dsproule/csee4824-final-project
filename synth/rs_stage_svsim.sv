`ifndef SYNTHESIS

//
// This is an automatically generated file from 
// dc_shell Version U-2022.12-SP7 -- Oct 10, 2023
//

// For simulation only. Do not modify.

module rs_stage_svsim(
    input clock, reset, en,
    input CDB                       cdb,
    input logic [4-1:0]                    rs_idx,
    input S_X_PACKET   [4-1:0] S_X_reg,
    input ROB_T                     T,                    input MT_ENTRY                  T1, T2,
    input [32-1:0]               V1, V2,           
    output d_stall,              
    output [4-1:0] busy,           
    output S_X_PACKET [4-1:0] S_X_packet,
    output RS_ENTRY [ 4-1:0] rs_table
);
    

  rs_stage rs_stage( {>>{ clock }}, {>>{ reset }}, {>>{ en }}, {>>{ cdb }}, 
        {>>{ rs_idx }}, {>>{ S_X_reg }}, {>>{ T }}, {>>{ T1 }}, {>>{ T2 }}, 
        {>>{ V1 }}, {>>{ V2 }}, {>>{ d_stall }}, {>>{ busy }}, 
        {>>{ S_X_packet }}, {>>{ rs_table }} );
endmodule
`endif
