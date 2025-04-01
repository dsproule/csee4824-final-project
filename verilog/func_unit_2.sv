`include "verilog/sys_defs.svh"

module func_unit_2(
    input S_X_PACKET S_X_reg,

    output X_C_PACKET        X_packet
);
    // TODO: check lsq for mem addr -> X_C_valid if present and data forwarded

    // TODO: else lsq doesn't have it, make mem req 
        // TODO: when data comes back, save it to reg and load to X_C_packet

endmodule