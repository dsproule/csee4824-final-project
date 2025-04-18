`include "verilog/sys_defs.svh"

/* Pipeline test where we will manually feed instructions. Includes I-stage and D-stage */

module testbench;

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
    endtask; // task show_mem_with_decimal

    logic clock, reset;
    logic [`XLEN-1:0] proc2mem_addr;
    logic [63:0] proc2mem_data, mem2proc_data, cache2Dmem_data;
    logic [1:0] proc2mem_command;
    logic [3:0] mem2proc_response, mem2proc_tag;


    mem memory(
        .clk(clock),
        .proc2mem_addr(proc2mem_addr),
        .proc2mem_data(cache2Dmem_data),
        .proc2mem_command(proc2mem_command),

        .mem2proc_response(mem2proc_response),        // will need to change when Dmem gets introduced
        .mem2proc_data(mem2proc_data),                // will need to change when Dmem gets introduced
        .mem2proc_tag(mem2proc_tag)                   // will need to change when Dmem gets introduced
    );

    initial begin
        forever #(`CLOCK_PERIOD / 2.0) clock = ~clock;
    end    

    S_X_PACKET [`RS_SZ-1:0] S_X_regs;
    logic [`XLEN-1:0] proc2Dmem_addr [1:0];
    logic wr_mem, Dmem_req;

    logic [`XLEN-1:0] cache2Dmem_addr;
    logic [1:0]       cache2Dmem_command;
    logic [63:0]      Dcache_data_out;
    logic Dcache_valid_out, take_branch;

    assign Dmem_req = wr_mem;
    assign wr_mem = S_X_regs[3].valid;

    /* Module start */

    logic [63:0] proc2Dcache_data, cache2Dmem_data;
    logic wr_proc, wr_valid;

    always_comb begin
        if (Dmem_req) begin
            proc2mem_command = cache2Dmem_command;
            proc2mem_addr    = cache2Dmem_addr;
        end else begin

        end
    end

    assign wr_proc = wr_mem & Dcache_valid_out & ~wr_valid;

    dcache dache_0(
        .clock(clock), .reset(reset | take_branch),

        // From memory
        .Dmem2proc_response((Dmem_req) ? mem2proc_response : '0), .Dmem2proc_tag(mem2proc_tag),
        .Dmem2proc_data(mem2proc_data),

        // From FU stage
        .proc2Dcache_addr((wr_mem) ? proc2Dmem_addr[0] : proc2Dmem_addr[1]),
        .proc2Dcache_data(proc2Dcache_data),
        .wr_proc(wr_proc),

        // To memory
        .proc2Dmem_command(cache2Dmem_command),
        .proc2Dmem_addr(cache2Dmem_addr),
        .proc2Dmem_data(cache2Dmem_data),

        // To fetch stage
        .Dcache_data_out(Dcache_data_out),
        .Dcache_valid_out(Dcache_valid_out),
        .wr_valid(wr_valid)
    );

    func_unit_3 func_unit_03(
        .clock(clock), .reset(reset), .committed(committed), .wr_valid(wr_valid),
        .Dmem2proc_data(Dcache_data_out),
        .S_X_reg(S_X_regs[3]),

        .proc2Dmem_addr(proc2Dmem_addr[0]),
        .proc2Dcache_data(proc2Dcache_data),
        .X_packet()
);

    initial begin
        clock = 0;
        reset = 1;
        take_branch = 0;
        S_X_regs = '0;
        @(negedge clock);
        memory.unified_memory[0] = 64'h0020011300000000;
        memory.unified_memory[1] = 64'h002081b300210233;
        @(negedge clock);
        reset = 0;

        // checking a store works
        // S_X_reg.V
        // proc2Dmem_addr[0] = `XLEN'h0;
        // S_X_regs[3].valid = `TRUE;
        // @(posedge Dcache_valid_out);
        // proc2Dcache_data = {Dcache_data_out[63:32], 32'h00100093};
        // @(negedge clock);           // let values settle 
        // @(posedge wr_valid);
        // S_X_regs[3].valid = `FALSE;

        show_mem_with_decimal(0, 16);
        
        $finish;
    end

endmodule
