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

    // task store_mem;
    //     input [`XLEN-1:0] addr;
    //     input [63:0] data;

    //     proc2Dmem_addr = addr;
    //     proc2mem_data = data;
    //     proc2Dmem_command = BUS_STORE;
    //     @(negedge clock);
    //     proc2Dmem_addr = data + 4;
    //     @(negedge clock);
    //     proc2Dmem_command = BUS_NONE;
    // endtask // task store_mem

    logic [`XLEN-1:0] proc2mem_addr;
    logic [63:0]      proc2mem_data, mem2proc_data;
    logic [1:0]       proc2mem_command;
    logic [3:0]       mem2proc_response, mem2proc_tag;
    X_C_PACKET        X_packet, X_C_reg;
    logic [`RS_SZ:0]  X_idx;

    logic [`XLEN-1:0] proc2Dmem_data;
    logic [`XLEN-1:0] proc2Dmem_addr;
    logic [1:0] proc2Dmem_command;
    S_X_PACKET S_X_reg;
    logic mem_store_pend, Dmem_gnt, store_retired;


    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(proc2mem_data),
        .proc2mem_command(proc2mem_command),
    `ifndef CACHE_MODE
        .proc2mem_size(WORD), // BYTE, HALF, WORD or DOUBLE
    `endif

        .mem2proc_response(mem2proc_response),
        .mem2proc_data(mem2proc_data),
        .mem2proc_tag(mem2proc_tag)
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end

    /* Module start */

    always_comb begin
        if (mem_store_pend) begin
            proc2mem_command = BUS_STORE;
            proc2mem_addr = proc2Dmem_addr;
        end else begin
            proc2mem_addr = '0;
            proc2mem_command = BUS_NONE;

        end
        proc2mem_data = {32'b0, proc2Dmem_data};
    end

    func_unit_3 func_unit_03(
        .clock(clock), .reset(reset), 
        .Dmem_gnt(Dmem_gnt), .store_retired(store_retired), 
        .S_X_reg(S_X_reg),

        .mem_store_pend(mem_store_pend),
        .proc2Dmem_addr(proc2Dmem_addr),
        .proc2Dmem_data(proc2Dmem_data),
        .X_packet(X_packet)
    );

    /* Module end */

    initial begin
        clock = 0;
        reset = 1;
        S_X_reg = '0;
        store_retired = `FALSE;
        Dmem_gnt = `TRUE;
        @(negedge clock);
        reset = 0;
        S_X_reg.V1 = `XLEN'h0;
        S_X_reg.inst = 32'h0;            // has offset of 4 embedded in here
        S_X_reg.V2 = `XLEN'hc;
        S_X_reg.T = 3;
        S_X_reg.valid = `TRUE;

        repeat (8) @(negedge clock);
	S_X_reg.V1 = `XLEN'h8;
	S_X_reg.V2 = `XLEN'hdead;
	store_retired = `TRUE;
        @(negedge clock);

        repeat (8) @(negedge clock);

        show_mem_with_decimal(0, 12);

        $finish;
    end

endmodule
