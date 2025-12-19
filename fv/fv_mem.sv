/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename : mem.sv                                                //
//                                                                     //
// Description : This is a clock-based latency, pipelined memory with  //
//               3 buses (address in, data in, data out) and a limit   //
//               on the number of outstanding memory operations        //
//               allowed at any time.                                  //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module mem (
    input             clk,           // Memory clock
    input             reset,           // Memory clock
    input [`XLEN-1:0] proc2mem_addr, // address for current command
                                     // support for memory model with byte level addressing
    input [63:0]      proc2mem_data, // address for current command
    input [1:0]       proc2mem_command, // `BUS_NONE `BUS_LOAD or `BUS_STORE

    output logic [3:0]  mem2proc_response, // 0 = can't accept, other=tag of transaction
    output logic [63:0] mem2proc_data,     // data resulting from a load
    output logic [3:0]  mem2proc_tag       // 0 = no value, other=tag of transaction
);
    logic [63:0] fv_load_data;

    assume property(@(negedge clk) !$isunknown(fv_load_data));

    typedef struct packed {
        logic [`XLEN-1:3] addr;
        logic [63:0] data;
        logic valid;
    } MEM_REQ;

    logic [63:0] next_mem2proc_data;
    logic [3:0]  next_mem2proc_response, next_mem2proc_tag;

    logic [63:0]                   loaded_data    [`NUM_MEM_TAGS:1];
    logic [`NUM_MEM_TAGS:1] [15:0] cycles_left;
    logic [`NUM_MEM_TAGS:1]        waiting_for_bus;

    logic acquire_tag;
    logic bus_filled;

    // Implement the Memory function
    wire valid_address = (proc2mem_addr[2:0]==3'b0) &
                         (proc2mem_addr<`MEM_SIZE_IN_BYTES);
    
    // Maintain record of recent `NUM_MEM_TAGS requests (guaranteed state)
    MEM_REQ     data_recent    [`NUM_MEM_TAGS:0];
    
    logic   in_recent;
    logic [3:0] in_recent_i;

    always @(negedge clk) begin
        if (reset) begin
            mem2proc_data = 64'bx;
            mem2proc_tag = 4'd0;
            mem2proc_response = 4'd0;
            for(int i = 1;i <= `NUM_MEM_TAGS; i = i + 1) begin
                cycles_left[i] = 16'd0;
                waiting_for_bus[i] = 1'b0;
                data_recent[i] = '0;
            end

            data_recent[0] = '0;

        end else begin
            next_mem2proc_tag      = 4'b0;
            next_mem2proc_response = 4'b0;
            next_mem2proc_data     = 64'bx;
            bus_filled             = 1'b0;
            acquire_tag            = ((proc2mem_command == BUS_LOAD) ||
                                    (proc2mem_command == BUS_STORE)) && valid_address;

            // memory management
            in_recent = 1'b0;
            for (int i = 0; i <= `NUM_MEM_TAGS; i++) begin
                if (data_recent[i].valid && data_recent[i].addr == proc2mem_addr[`XLEN-1:3]) begin
                    in_recent   = 1'b1;
                    in_recent_i = i;
                end
            end

            for(int i = 1; i <= `NUM_MEM_TAGS; i = i + 1) begin
                if(cycles_left[i]>16'd0) begin
                    cycles_left[i] = cycles_left[i]-16'd1;

                // receives the value
                end else if (acquire_tag && !waiting_for_bus[i]) begin
                    next_mem2proc_response = i;
                    acquire_tag            = 1'b0;
                    cycles_left[i]         = `MEM_LATENCY_IN_CYCLES;

                    if (proc2mem_command == BUS_LOAD) begin
                        waiting_for_bus[i] = 1'b1;
                        loaded_data[i] = (!in_recent) ? fv_load_data : data_recent[in_recent_i].data;
                    end 

                    if (in_recent) begin
                        // update value
                        if (proc2mem_command == BUS_STORE)
                            data_recent[in_recent_i].data = proc2mem_data;
                    end else begin
                        // shift entire array
                        for (int j = 0; j < `NUM_MEM_TAGS - 1; j++)
                            data_recent[j] = data_recent[j + 1];
                        
                        // add new one to end
                        data_recent[`NUM_MEM_TAGS].valid = 1'b1;
                        data_recent[`NUM_MEM_TAGS].data  = loaded_data[i];
                        data_recent[`NUM_MEM_TAGS].addr  = proc2mem_addr[`XLEN-1:3];
                    end

                end

                // places value for proper response
                if((cycles_left[i]==16'd0) && waiting_for_bus[i] && !bus_filled) begin
                        bus_filled         = 1'b1;
                        next_mem2proc_tag  = i;
                        next_mem2proc_data = loaded_data[i];
                        waiting_for_bus[i] = 1'b0;
                end
            end
            mem2proc_response <= next_mem2proc_response;
            mem2proc_data     <= next_mem2proc_data;
            mem2proc_tag      <= next_mem2proc_tag;
        end
    end

    // guarantees value provided matches what was loaded from mem
    data_out_lock: assume property(@(negedge clk)
        (mem2proc_tag != 0) |-> mem2proc_data == data_recent[in_recent_i].data);

    // guarantees that if providing a value, we were waiting on a valid request
    data_in_flight: assume property (@(negedge clk)
        (mem2proc_tag != 0) |-> $past(waiting_for_bus[mem2proc_tag]));

    assume property(@(negedge clk) !$isunknown(fv_load_data));

    function automatic logic [63:0] recent_data_for_addr(
        input logic [`XLEN-1:3] addr,
        
        output logic found
    );
        found = 1'b0;
        recent_data_for_addr = '0;
        for (int j = 0; j <= `NUM_MEM_TAGS; j++) begin
            if (data_recent[j].valid && data_recent[j].addr == addr) begin
                found = 1'b1;
                recent_data_for_addr = data_recent[j].data;
            end
        end
    endfunction

endmodule // module mem
