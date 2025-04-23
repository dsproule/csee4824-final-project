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
`define NB_LINES 2
`define CACHE_LINE_BITS $clog2(`CACHE_LINES)

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
    MSHR_ENTRY [`NB_LINES-1:0] mshr;

    // ---- Addresses and final outputs ---- //

    // Note: cache tags, not memory tags
    logic [12-`CACHE_LINE_BITS:0] current_tag, last_tag;
    logic [`CACHE_LINE_BITS - 1:0] current_index, last_index;

    assign {current_tag, current_index} = proc2Icache_addr[15:3];

    assign Icache_data_out = icache_data[current_index].data;
    assign Icache_valid_out = icache_data[current_index].valid &&
                              (icache_data[current_index].tags == current_tag);

    // ---- Main cache logic ---- //

    logic got_mem_data, miss_outstanding;

    wire changed_addr = (current_index != last_index) || (current_tag != last_tag);

    wire update_mem_tag = changed_addr || miss_outstanding;

    logic cur_mshr_idx, addr_waiting, mem_mshr_idx, resp_mshr_idx;
    always_comb begin
        cur_mshr_idx = 0;                   // allocate mshr
        addr_waiting = Icache_valid_out;
        mem_mshr_idx = 0;                   // handle mem tag for mshr
        resp_mshr_idx = 0;                  // handle mem tag for mshr
        miss_outstanding = 0;
        got_mem_data = 0;                   // handle mem responses

        for (logic [$clog2(`NB_LINES):0] mshr_idx = 0; mshr_idx < `NB_LINES; mshr_idx++) begin

            // if its a new addr, attempts to allocate it to an mshr (latch)
            if (changed_addr) begin
                // if the line is valid (it got freed or init), allocate it
                if (~mshr[mshr_idx].valid)
                    cur_mshr_idx = mshr_idx; 
            end
            
            // cache is already servicing this mem address
            if ((mshr[mshr_idx].addr == proc2Icache_addr[`XLEN-1:3]) & (mshr[mshr_idx].valid))
                addr_waiting = 1;

            // if any MSHR has a miss outstanding, attempt mem request
            if ((mshr[mshr_idx].mem_tag == 0) & mshr[mshr_idx].valid) begin
                mem_mshr_idx = mshr_idx;
                miss_outstanding = 1;
            end

            // if tag matches a value coming in, 
            if (mshr[mshr_idx].mem_tag == Imem2proc_tag && (mshr[mshr_idx].mem_tag != 0)) begin
                resp_mshr_idx = mshr_idx;
                got_mem_data = 1;
            end
        end

    end

    // Keep sending memory requests until we receive a response tag or change addresses
    assign proc2Imem_command = (miss_outstanding && !changed_addr) ? BUS_LOAD : BUS_NONE;
    assign proc2Imem_addr    = {mshr[mem_mshr_idx].addr, 3'b0};

    // ---- Cache state registers ---- //

    always_ff @(posedge clock) begin
        if (reset) begin
            last_index       <= -1; // These are -1 to get ball rolling when
            last_tag         <= -1; // reset goes low because addr "changes"
            mshr             <= 0;
            icache_data      <= 0; // Set all cache data to 0 (including valid bits)
        end else begin
            last_index       <= current_index;
            last_tag         <= current_tag;
            
            // if new addr and not servicing/in cache, alloc it
            if (changed_addr & ~addr_waiting & ~mshr[cur_mshr_idx].valid) begin
                mshr[cur_mshr_idx].addr <= proc2Icache_addr[`XLEN-1:3];
                mshr[cur_mshr_idx].mem_tag <= 0;

                mshr[cur_mshr_idx].valid <= 1;
            end

            if (update_mem_tag) begin
                mshr[mem_mshr_idx].mem_tag <= Imem2proc_response;
            end


            if (got_mem_data) begin // If data came from memory, meaning tag matches
                icache_data[current_index].data  <= Imem2proc_data;
                icache_data[current_index].tags  <= current_tag;
                icache_data[current_index].valid <= 1;

                // free mshr (set valid to 0)
                mshr[resp_mshr_idx] <= 0;
            end
        end
    end

endmodule // icache
