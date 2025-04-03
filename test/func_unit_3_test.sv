`include "verilog/sys_defs.svh"

/* Pipeline test where we will manually feed instructions. Includes I-stage and D-stage */

module testbench;
    logic clock, reset;

    // Show contents of a range of Unified Memory, in both hex and decimal
    task show_mem_with_decimal;
        input [31:0] start_addr;
        input [31:0] end_addr;
        int showing_data;
        begin
            $display("@@@");
            showing_data=0;
            for(int k=start_addr;k<=end_addr; k=k+1)
                if (memory.unified_memory[k] != 0) begin
                    $display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                             memory.unified_memory[k]);
                    showing_data=1;
                end else if(showing_data!=0) begin
                    $display("@@@");
                    showing_data=0;
                end
            $display("@@@");
        end
    endtask // task show_mem_with_decimal

    logic [`XLEN-1:0]       proc2mem_addr;
    logic [63:0]            proc2mem_data, mem2proc_data;
    logic [1:0]             proc2mem_command;
    logic [3:0]             mem2proc_response, mem2proc_tag;
    X_C_PACKET [`RS_SZ-1:0] X_packets, X_C_regs;
    logic [`RS_SZ:0] X_idx;

    logic [`XLEN-1:0] proc2Dmem_data;
    logic [`XLEN-1:0] proc2Dmem_addr;
    logic [1:0] proc2Dmem_command;
    S_X_PACKET [`RS_SZ-1:0] S_X_regs;
    logic mem_store_pending;


    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    /* Module start */

    assign gnt = X_C_regs[3].valid;

    func_unit_3 func_unit_03(
        .clock(clock), .reset(reset), 
        .Dmem_gnt(1'b1), .store_retired(gnt), 
        .S_X_reg(S_X_regs[3]),

        .mem_store(mem_store_pending),
        .proc2Dmem_addr(proc2Dmem_addr),
        .proc2Dmem_data(proc2Dmem_data),
        .X_packet(X_packets[3])
    );

    // X_C regs
    always_ff @(posedge clock) begin
        for (X_idx = 0; X_idx < `RS_SZ; X_idx++)
            if (reset) begin
                X_C_regs[X_idx] <= '0;
            end else if (X_packets[X_idx].valid) begin
                X_C_regs[X_idx] <= X_packets[X_idx];
            end
    end

    /* Module end */

    initial begin
        clock = 0;
        reset = 1;

        @(negedge clock);
        reset = 0;
        @(negedge clock);

        
        
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        show_mem_with_decimal(0, 12);

        $finish;
    end

endmodule