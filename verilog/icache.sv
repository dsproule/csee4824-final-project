
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
`define MSHR_SLOTS 5

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
} MSHR_ENTRY_I;


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
    `ifdef FORMAL
        typedef struct packed {
            logic [`XLEN-1:3] addr;
            logic valid;
        } LAST_ICACHE;
    `endif

    // ---- Cache data ---- //

    ICACHE_ENTRY [`CACHE_LINES-1:0] icache_data;
    MSHR_ENTRY_I [`MSHR_SLOTS-1:0] mshr;

    // ---- Addresses and final outputs ---- //

    // Note: cache tags, not memory tags
    logic [12-`CACHE_LINE_BITS:0] current_tag, main_tag;
    logic [`CACHE_LINE_BITS - 1:0] current_index, main_index;
    logic mem_forward;

    logic fetch_main_addr, current_in_cache;
    logic [`XLEN-1:0] cur_addr;
    
    // ---- MSHR non-blocking logic ---- // 

    assign {current_tag, current_index} = cur_addr[15:3];
    assign {main_tag, main_index} = proc2Icache_addr[15:3];

    // forwarding logic to squeeze data out of cache a cycle sooner
    always_comb begin
        current_in_cache = icache_data[current_index].valid &&
                                (icache_data[current_index].tags == current_tag);
        if (mem_forward) begin
            Icache_data_out = Imem2proc_data;
            Icache_valid_out = `TRUE; 
        end else begin 
            Icache_data_out = icache_data[main_index].data;
            Icache_valid_out = icache_data[main_index].valid &&
                                (icache_data[main_index].tags == main_tag);
        end
    end

    `ifdef FORMAL
        LAST_ICACHE last_icache_addr [`CACHE_LINES-1:0];

        always_ff @(posedge clock) begin
            if (reset)
                for (int formal_i = 0; formal_i < `CACHE_LINES; formal_i++) begin
                    last_icache_addr[formal_i] <= '0;
                end
        end

        // address only will ever occupy one mshr slot
        int o;
        logic addr_seen;
        always_comb begin
            addr_seen = 1'b0;
            for (o = 0; o < `MSHR_SLOTS; o++) begin
                if (o != `MSHR_SLOTS - 1) 
                    addr_seen |= (mshr[o].valid && (mshr[o].addr == mshr[`MSHR_SLOTS-1].addr));
            end
        end
        unique_addr: assert property(@(posedge clock) mshr[`MSHR_SLOTS-1].valid |-> !addr_seen);

        // if cache_valid out -> address is same as requested

        // cache will respond to memory servicing
        try_service: assert property(@(posedge clock) miss_outstanding |-> BUS_LOAD == proc2Imem_command);

        // cache will continue trying to service cache_addr until done
        not_stalled: assert property(@(posedge clock)
            !Icache_valid_out |-> alloc_count() > 1 || will_alloc || current_in_cache
        );

        // if possible, cache will attempt prefetch

        // cache will occupy all mshr slots
        genvar i;
        generate for (i = 0; i < `MSHR_SLOTS; i++) begin
            slot_used: cover property(@(posedge clock) mshr[i].valid);
        end endgenerate

        // cache will not clobber mshr already in use
        wont_clobber: assert property(@(posedge clock) alloc_count() == `MSHR_SLOTS |-> !will_alloc);

        // cache never fills (interesting because we didn't know this)
        never_full: assert property(@(posedge clock) alloc_count() < `MSHR_SLOTS);
        
        ever_full: cover property(@(posedge clock) alloc_count() == `MSHR_SLOTS);

        // count progesses 
        count_progresses: assert property(@(posedge clock) disable iff (reset)
            alloc_count() |-> ##1 (alloc_count() == $past(alloc_count()) + 1) || 
                                  (alloc_count() == $past(alloc_count()) - 1) ||
                                  (alloc_count() == $past(alloc_count())));
        
        // if a miss is outstanding -> cache will try again
        continue_attempts: assert property(@(posedge clock)
            miss_outstanding |-> proc2Imem_command == BUS_LOAD);
        
    `endif

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
    logic last_fetch_hit;
    wire prefetch_valid = fetch_main_addr | last_fetch_hit;

    assign cur_addr = prefetch_valid ? proc2Icache_addr + 12 : proc2Icache_addr;

    assign mem_forward = (proc2Icache_addr[`XLEN-1:3] == mshr[mshr_resp_idx].addr) & (got_mem_data);

    // ---- Memory access logic ---- //

    // Keep sending memory requests until we receive a response tag or change addresses
    assign proc2Imem_command = (miss_outstanding) ? BUS_LOAD : BUS_NONE;
    assign proc2Imem_addr    = {mshr[mshr_req_idx].addr, 3'b0};

    `ifdef FORMAL
    logic will_alloc;
    assign will_alloc = (~mshr[mshr_next_idx].valid & ~current_in_mshr & ~current_in_cache);
    `endif

    // ---- Cache state registers ---- //

    always_ff @(posedge clock) begin
        if (reset) begin
            mshr           <= 0;
            icache_data    <= 0; // Set all cache data to 0 (including valid bits)
            fetch_main_addr <= 0;
            last_fetch_hit <= 0;
        end else begin
            last_fetch_hit <= Icache_valid_out;
            // if slot is empty and the req address is not present, allocate it
            if (~mshr[mshr_next_idx].valid & ~current_in_mshr & ~current_in_cache) begin
                mshr[mshr_next_idx].addr    <= cur_addr[`XLEN-1:3];
                mshr[mshr_next_idx].mem_tag <= 0;

                if (cur_addr == proc2Icache_addr)
                    fetch_main_addr <= 1;

                mshr[mshr_next_idx].valid   <= `TRUE;
            end

            if (miss_outstanding)
                mshr[mshr_req_idx].mem_tag <= Imem2proc_response;

            // if memory tag corresponds with a mshr entry, save the value and free the slot
            if (got_mem_data) begin
                icache_data[resp_index].data  <= Imem2proc_data;
                icache_data[resp_index].tags  <= resp_tag;
                icache_data[resp_index].valid <= 1;

                `ifdef FORMAL
                last_icache_addr[resp_index].addr  <= mshr[mshr_resp_idx].addr;
                last_icache_addr[resp_index].valid <= 1'b1;
                `endif

                if (mshr[mshr_resp_idx].addr == proc2Icache_addr[`XLEN-1:3])
                    fetch_main_addr <= 0;

                mshr[mshr_resp_idx] <= 0;
            end
        end
    end

    `ifdef FORMAL

    function automatic int alloc_count();
        alloc_count = 0;
        for (int i = 0; i < `MSHR_SLOTS; i++) begin
            alloc_count += mshr[i].valid;
        end
    endfunction

    `endif

endmodule // icache
