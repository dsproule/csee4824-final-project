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

typedef struct packed {
    logic [63:0]                  data;
    // (13 bits) since only need 16 bits to access all memory and 3 are the offset
    logic [12-`CACHE_LINE_BITS:0] tags;
    logic                         valid;
} DCACHE_ENTRY;

module dcache (
    input clock, reset,

    // From memory
    input [3:0]  Dmem2proc_response, Dmem2proc_tag,
    input [63:0] Dmem2proc_data,

    // From FU stage
    input [`XLEN-1:0] proc2Dcache_addr,
    input [63:0]      proc2Dcache_data,
    input             wr_proc,

    // To memory
    output logic [1:0]       proc2Dmem_command,
    output logic [`XLEN-1:0] proc2Dmem_addr,
    output logic [63:0]      proc2Dmem_data,

    // To fetch stage
    output logic [63:0] Dcache_data_out,
    output logic        Dcache_valid_out,
    output logic        wr_valid
);
    // ---- Cache data ---- //

    DCACHE_ENTRY [`CACHE_LINES-1:0] icache_data;

    // ---- Addresses and final outputs ---- //

    // Note: cache tags, not memory tags
    logic [12-`CACHE_LINE_BITS:0] current_tag, last_tag;
    logic [`CACHE_LINE_BITS - 1:0] current_index, last_index;

    logic wr_mem;

    assign {current_tag, current_index} = proc2Dcache_addr[15:3];

    assign wr_mem = (wr_proc & Dcache_valid_out);

    logic [63:0] Dcache_data_out_reg;
    logic Dcache_valid_out_reg;

    assign Dcache_data_out = icache_data[current_index].data;
    assign Dcache_valid_out = icache_data[current_index].valid &&
                              (icache_data[current_index].tags == current_tag);

    // ---- Main cache logic ---- //

    logic [3:0] current_mem_tag; // The current memory tag we might be waiting on
    logic miss_outstanding; // Whether a miss has received its response tag to wait on

    wire got_mem_data = (current_mem_tag == Dmem2proc_tag) && (current_mem_tag != 0);

    wire changed_addr = (current_index != last_index) || (current_tag != last_tag);

    wire update_mem_tag = changed_addr || miss_outstanding || got_mem_data;

    wire unanswered_miss = changed_addr ? !Dcache_valid_out
                                        : miss_outstanding && (Dmem2proc_response == 0);

    // Keep sending memory requests until we receive a response tag or change addresses
    assign proc2Dmem_command = (miss_outstanding && !changed_addr) ? BUS_LOAD : 
                               (wr_mem)                            ? BUS_STORE : BUS_NONE;
    assign proc2Dmem_addr    = {proc2Dcache_addr[31:3],3'b0};

    always_comb begin
        if (wr_proc & Dcache_valid_out & (Dmem2proc_response != 0)) begin
            proc2Dmem_data = proc2Dcache_data;
            wr_valid = `TRUE;
        end else begin
            wr_valid = `FALSE;
        end
    end

    // ---- Cache state registers ---- //

    always_ff @(posedge clock) begin
        if (reset) begin
            last_index       <= -1; // These are -1 to get ball rolling when
            last_tag         <= -1; // reset goes low because addr "changes"
            current_mem_tag  <= 0;
            miss_outstanding <= 0;
            icache_data      <= 0; // Set all cache data to 0 (including valid bits)
        end else begin
            last_index       <= current_index;
            last_tag         <= current_tag;
            miss_outstanding <= unanswered_miss;
            if (update_mem_tag) begin
                current_mem_tag <= Dmem2proc_response;
            end
            if (got_mem_data) begin // If data came from memory, meaning tag matches
                icache_data[current_index].data  <= Dmem2proc_data;
                icache_data[current_index].tags  <= current_tag;
                icache_data[current_index].valid <= 1;
            end

            if (wr_mem)
                icache_data[current_index].data <= proc2Dcache_data;
        end
    end

endmodule // dcache
