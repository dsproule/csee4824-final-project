`include "verilog/sys_defs.svh"

module testbench;
    logic clock, reset;

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end
    
    branch_pred branch_pred_inst (
    // from current instruction
        .clk(clock),
        .reset(reset),
        .pc(),
    // for model update (from cdb?)
        .update_en(),
        .update_take_branch(),
        .update_address(),    

    // output
        .take_branch(),
        .next_addr()
);

endmodule