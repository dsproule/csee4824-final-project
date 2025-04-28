/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  icache.sv                                           //
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
`define MSHR_SLOTS 3

typedef struct packed {
    logic [63:0]                  data;
    // (13 bits) since only need 16 bits to access all memory and 3 are the offset
    logic [12-`CACHE_LINE_BITS:0] tags;
    logic                         valid;
} ICACHE_ENTRY;

typedef struct packed {
    logic [`XLEN-1:3] addr;
    logic [3:0] mem_tag;

    logic valid;
} MSHR_ENTRY;

module icache (
    input clock,
    input reset,

    // From memory
    input [3:0]  Imem2proc_response, // Should be zero unless there is a response
    input [63:0] Imem2proc_data,
    input [3:0]  Imem2proc_tag,

    // From fetch stage
    input [`XLEN-1:0] proc2Icache_addr,

    // To memory
    output logic [1:0]       proc2Imem_command,
    output logic [`XLEN-1:0] proc2Imem_addr,

    // To fetch stage
    output logic [63:0] Icache_data_out, // Data is mem[proc2Icache_addr]
    output logic        Icache_valid_out // When valid is high
);

    // ---- Cache data ---- //

    ICACHE_ENTRY [`CACHE_LINES-1:0] icache_data;
    MSHR_ENTRY [`MSHR_SLOTS-1:0] mshr;

    // ---- Addresses and final outputs ---- //

    // Note: cache tags, not memory tags
    logic [12-`CACHE_LINE_BITS:0] current_tag, last_tag;
    logic [`CACHE_LINE_BITS - 1:0] current_index, last_index;
    logic mem_forward;

    logic prefetch_valid;
    logic [`XLEN-1:0] cur_addr;
    
    // ---- MSHR non-blocking logic ---- // 

    assign {current_tag, current_index} = cur_addr[15:3];

    // forwarding logic to squeeze data out of cache a cycle sooner
    always_comb begin
        if (mem_forward) begin
            Icache_data_out = Imem2proc_data;
            Icache_valid_out = `TRUE; 
        end else begin 
            Icache_data_out = icache_data[current_index].data;
            Icache_valid_out = icache_data[current_index].valid &&
                                (icache_data[current_index].tags == current_tag);
        end
    end

    logic [$clog2(`MSHR_SLOTS)-1:0] mshr_next_idx;
    logic current_in_mshr;
    // checks mshr for current addr presence also saves open slot  
    always_comb begin
        mshr_next_idx   = 0;
        current_in_mshr = `FALSE;

        for (logic [$clog2(`MSHR_SLOTS):0] mshr_set_idx = 0; mshr_set_idx < `MSHR_SLOTS; mshr_set_idx++) begin
            if (mshr[mshr_set_idx].valid & (mshr[mshr_set_idx].addr == cur_addr[`XLEN-1:3]))
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
            if ((mshr[mshr_miss_idx].mem_tag == Imem2proc_tag) & mshr[mshr_miss_idx].valid & (Imem2proc_tag != 0)) begin
                mshr_resp_idx = mshr_miss_idx;
                got_mem_data = 1;
            end
        end

        {resp_tag, resp_index} = mshr[mshr_resp_idx].addr[15:3];
    end

    // ---- Prefetch logic ---- //
    assign cur_addr = prefetch_valid ? proc2Icache_addr + 8 : proc2Icache_addr;

    assign mem_forward = (proc2Icache_addr[`XLEN-1:3] == mshr[mshr_resp_idx].addr) & (got_mem_data);

    // ---- Memory access logic ---- //

    // Keep sending memory requests until we receive a response tag or change addresses
    assign proc2Imem_command = (miss_outstanding) ? BUS_LOAD : BUS_NONE;
    assign proc2Imem_addr    = {mshr[mshr_req_idx].addr, 3'b0};

    // ---- Cache state registers ---- //

    always_ff @(posedge clock) begin
        if (reset) begin
            mshr           <= 0;
            icache_data    <= 0; // Set all cache data to 0 (including valid bits)
            prefetch_valid <= 0;
        end else begin
            // if slot is empty and the req address is not present, allocate it
            if (~mshr[mshr_next_idx].valid & ~current_in_mshr & ~Icache_valid_out) begin
                mshr[mshr_next_idx].addr    <= cur_addr[`XLEN-1:3];
                mshr[mshr_next_idx].mem_tag <= 0;

                if (cur_addr == proc2Icache_addr)
                    prefetch_valid <= 1;

                mshr[mshr_next_idx].valid   <= `TRUE;
            end

            if (miss_outstanding)
                mshr[mshr_req_idx].mem_tag <= Imem2proc_response;

            // if memory tag corresponds with a mshr entry, save the value and free the slot
            if (got_mem_data) begin
                icache_data[resp_index].data  <= Imem2proc_data;
                icache_data[resp_index].tags  <= resp_tag;
                icache_data[resp_index].valid <= 1;

                if (mshr[mshr_resp_idx].addr == proc2Icache_addr[`XLEN-1:3])
                    prefetch_valid <= 0;

                mshr[mshr_resp_idx] <= 0;
            end
        end
    end

endmodule // icache