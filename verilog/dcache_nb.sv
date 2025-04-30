
/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  dcache.sv                                           //
//                                                                     //
//  Description :  The instruction cache module that reroutes memory   //
//                 accesses to decrease misses.                        //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

// Internal macros, no other file should need these
`define CACHE_LINES 32
`define CACHE_LINE_BITS $clog2(`CACHE_LINES)
// how many outstanding misses to handle at a time
`define MSHR_SLOTS 5

typedef struct packed {
    logic [63:0]                  data;
    // (13 bits) since only need 16 bits to access all memory and 3 are the offset
    logic                         ready_for_write;
    logic                         is_write;
    logic [12-`CACHE_LINE_BITS:0] tags;
    logic                         valid;
} DCACHE_ENTRY;

typedef struct packed {
    logic [`XLEN-1:3] addr;
    logic [12-`CACHE_LINE_BITS:0] cache_tag;
    logic [`CACHE_LINE_BITS - 1:0] cache_index;

    logic [3:0] mem_tag;
    logic [1:0] mem_command;

    logic valid;
} MSHR_ENTRY;

module dcache_nb (
    input clock,
    input reset,

    // From memory
    input [3:0]  Dmem2proc_response, // Should be zero unless there is a response
    input [63:0] Dmem2proc_data,
    input [3:0]  Dmem2proc_tag,

    // From fetch stage
    input [`XLEN-1:0] proc2Dcache_addr,
    input [1:0]       proc2Dcache_command,

    // To memory
    output logic [1:0]       proc2Dmem_command,
    output logic [`XLEN-1:0] proc2Dmem_addr,

    // To fetch stage
    output logic [63:0] Dcache_data_out, // Data is mem[proc2Dcache_addr]
    output logic        Dcache_valid_out // When valid is high
);

    // ---- Cache data ---- //

    DCACHE_ENTRY [`CACHE_LINES-1:0] dcache_data;
    MSHR_ENTRY [`MSHR_SLOTS-1:0] mshr;

    // ---- Addresses and final outputs ---- //

    // Note: cache tags, not memory tags
    logic [12-`CACHE_LINE_BITS:0] current_tag;
    logic [`CACHE_LINE_BITS - 1:0] current_index;
    logic mem_forward;

    logic current_in_cache;
    
    // ---- MSHR non-blocking logic ---- // 

    assign {current_tag, current_index} = proc2Dcache_addr[15:3];

    // forwarding logic to squeeze data out of cache a cycle sooner
    always_comb begin
        current_in_cache = dcache_data[current_index].valid &&
                                (dcache_data[current_index].tags == current_tag);
        if (mem_forward) begin
            Dcache_data_out = Dmem2proc_data;
            Dcache_valid_out = `TRUE; 
        end else begin 
            Dcache_data_out = dcache_data[current_index].data;
            Dcache_valid_out = dcache_data[current_index].valid &&
                                (dcache_data[current_index].tags == current_tag);
        end
    end

    logic [$clog2(`MSHR_SLOTS)-1:0] mshr_next_idx;
    logic current_in_mshr;
    // checks mshr for current addr presence also saves open slot  
    always_comb begin
        mshr_next_idx   = 0;
        current_in_mshr = `FALSE;

        for (logic [$clog2(`MSHR_SLOTS):0] mshr_set_idx = 0; mshr_set_idx < `MSHR_SLOTS; mshr_set_idx++) begin
            if (mshr[mshr_set_idx].valid & ((mshr[mshr_set_idx].cache_tag == current_tag) & (mshr[mshr_set_idx].cache_index == current_index)))
                current_in_mshr = `TRUE;

            if (~mshr[mshr_set_idx].valid)
                mshr_next_idx = mshr_set_idx;
        end
    end

    logic [$clog2(`MSHR_SLOTS)-1:0] mshr_req_idx;
    logic miss_outstanding;
    // checks mshr for any addr without mem tags (means they need to request an addr)
    always_comb begin
        miss_outstanding = 0;

        for (logic [$clog2(`MSHR_SLOTS):0] mshr_miss_idx = 0; mshr_miss_idx < `MSHR_SLOTS; mshr_miss_idx++) begin
            if ((mshr[mshr_miss_idx].mem_tag == 0) & mshr[mshr_miss_idx].valid) begin
                mshr_req_idx = mshr_miss_idx;
                miss_outstanding = 1;
            end
        end
    end

    logic [$clog2(`MSHR_SLOTS)-1:0] mshr_resp_idx;
    logic [12-`CACHE_LINE_BITS:0] resp_tag;
    logic [`CACHE_LINE_BITS - 1:0] resp_index;
    logic got_mem_data;
    // if any of the mem_tags match the memory response, set the flag and save the idx
    always_comb begin
        got_mem_data = 0;

        for (logic [$clog2(`MSHR_SLOTS):0] mshr_miss_idx = 0; mshr_miss_idx < `MSHR_SLOTS; mshr_miss_idx++) begin
            if ((mshr[mshr_miss_idx].mem_tag == Dmem2proc_tag) & mshr[mshr_miss_idx].valid & (Dmem2proc_tag != 0)) begin
                mshr_resp_idx = mshr_miss_idx;
                got_mem_data = 1;
            end
        end

        {resp_tag, resp_index} = mshr[mshr_resp_idx].addr[15:3];
    end

    assign mem_forward = (proc2Dcache_addr[`XLEN-1:3] == mshr[mshr_resp_idx].addr) & (got_mem_data);

    // ---- Memory access logic ---- //

    // Keep sending memory requests until we receive a response tag or change addresses
    assign proc2Dmem_command = (miss_outstanding) ? mshr[mshr_req_idx].mem_command : BUS_NONE;
    assign proc2Dmem_addr    = {mshr[mshr_req_idx].addr, 3'b0};

    // ---- Cache state registers ---- //

    always_ff @(posedge clock) begin
        if (reset) begin
            mshr           <= 0;
            dcache_data    <= 0; // Set all cache data to 0 (including valid bits)
        end else begin
            // if slot is empty and the req address is not present, allocate it
            if (~mshr[mshr_next_idx].valid & ~current_in_mshr & ~current_in_cache) begin
                mshr[mshr_next_idx].addr        <= proc2Dcache_addr[`XLEN-1:3];
                mshr[mshr_next_idx].cache_tag   <= current_tag;
                mshr[mshr_next_idx].cache_index <= current_index;
                
                mshr[mshr_next_idx].mem_tag     <= 0;
                mshr[mshr_next_idx].mem_command <= proc2Dcache_command;

                mshr[mshr_next_idx].valid   <= `TRUE;
            end

            if (miss_outstanding)
                mshr[mshr_req_idx].mem_tag <= Dmem2proc_response;

            // if memory tag corresponds with a mshr entry, save the value and free the slot
            if (got_mem_data) begin
                dcache_data[resp_index].data  <= Dmem2proc_data;
                dcache_data[resp_index].tags  <= resp_tag;

                // TODO: Ready for store here

                dcache_data[resp_index].valid <= 1;

                mshr[mshr_resp_idx] <= 0;
            end
        end
    end

endmodule // dcache
