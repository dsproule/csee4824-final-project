`include "verilog/sys_defs.svh"

module ROB(
    input dispatch_valid,         // when true, allocation to new RS entry on posedge
    output [$clog2(ROB_SZ)-1:0] ROB_T;  // ROB tag passed to the reservation station
);

endmodule