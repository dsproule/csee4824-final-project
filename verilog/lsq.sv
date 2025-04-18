`include "verilog/sys_defs.svh"

//exists in pipeline interacts with all other units, func units 2 and 3 write addr to it
module lsq(
    // alloc inputs
    input logic clock, reset, 
    input logic dispatch_valid, 
    input logic sq_alloc, lq_alloc,
    input ROB_T T,

    //addr data computed by func unit
    input logic store_X, load_X,
    input SQ_T sq_X_T,
    input LQ_T lq_X_T,
    input logic [`XLEN-1:0] store_addr,
    input logic [`XLEN-1:0] load_addr, 

    input logic [63:0] store_data,

    // retire from rob
    input SQ_T retire_sq_T,
    input logic retire_en,

    //query LSQ for load execution
    input logic load_exec_en,
    input logic [`XLEN-1:0] load_addr,
    input ROB_T load_T,

    output logic [`XLEN-1:0] load_data,
    output logic store_load_fwd,

    //mem write from head when store is committed
    output logic mem_write_en,
    output logic [`XLEN-1:0] proc2mem_addr,
    output logic [`XLEN-1:0] proc2mem_data,

    //control signals for structural hazards
    output LQ_T lq_tail, // for reservation station on dispatch
    output SQ_T sq_tail,
    output logic sq_full, sq_empty, lq_full, lq_empty
);

    /*
    Load/store queue (LSQ) Functionality
    • Completed stores write to LSQ
    • When store retires, head of LSQ written to D$
    • When loads execute, access LSQ and D$ in parallel
    • Forward from LSQ if older store with matching address
    */
    /*
    TODO: update RS with the relevant load and store positions
    TODO insert control signals into pipeline
    */


    LQ_ENTRY lq[`LQ_SZ-1:0];
    logic [LQ_PTR-1:0] lq_head, lq_tail;
    logic lq_head_wrap, lq_tail_wrap, lq_alloc;

    //assign lq_alloc = (alloc_mem_command == LOAD) && dispatch_valid && !lq_full;

    assign lq_full = (lq_head == lq_tail) && (lq_head_wrap != lq_tail_wrap);
    assign lq_empty = (lq_head == lq_tail) && (lq_head_wrap == lq_tail_wrap);

    SQ_ENTRY sq[`SQ_SZ-1:0];
    logic [SQ_PTR-1:0] sq_head, sq_tail;
    logic sq_head_wrap, sq_tail_wrap, sq_alloc;

   // assign sq_alloc = (alloc_mem_command == STORE) && dispatch_valid && !sq_full;

    assign sq_full = (sq_head == sq_tail) && (sq_head_wrap != sq_tail_wrap);
    assign sq_empty = (sq_head == sq_tail) && (sq_head_wrap == sq_tail_wrap);

    //forwarding unit - youngest store older than load forwards to load
    always_comb begin


    end

    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 0; i < `LQ_SZ; i++) begin
                lq[i] <= 0;
            end
            for (int i = 0; i < `SQ_SZ; i++) begin
                sq[i] <= 0;
            end
            lq_head <= 0;
            lq_tail <= 0;
            lq_head_wrap <= 0;
            lq_tail_wrap <= 0;

            sq_head <= 0;
            sq_tail <= 0;
            sq_head_wrap <= 0;
            sq_tail_wrap <= 0;
        end else begin
            // SQ
            //dispatch alloc on decode, record current lq_tail in rs station as store position
            if (sq_alloc  && !sq_full) begin
                sq[sq_tail] <= 0;
                sq[sq_tail].valid <= `TRUE;
                sq[sq_tail].T <= T;

                sq_tail <= (sq_tail == `SQ_SZ - 1) ? 0 : (sq_tail + 1);
                sq_tail_wrap <= (sq_tail == `SQ_SZ - 1) ? ~sq_tail_wrap : sq_tail_wrap; // change here
            end

            // store func unit writes address/data into slot, rs gets cleared
            if (store_X) begin //comes from RS
                sq[sq_X_T].addr <= store_addr;
                sq[sq_X_T].data <= store_data;
                sq[sq_X_T].data_valid <= `TRUE;
                sq[sq_X_T].addr_valid <= `TRUE;
            end

            if(retire_en) begin //akin to setting ready in ROB
                sq[retire_sq_T].retired <= `TRUE;
            end

            // Write address/data from SQ head to D$, free SQ head
            if(!sq_empty && sq[sq_head].retired && sq[sq_head].addr_valid && sq[sq_head].data_valid) begin
                mem_write_en <= `TRUE;
                proc2mem_addr <= sq[sq_head].addr;
                proc2mem_data <= sq[sq_head].data;

                sq_head <= (sq_head == `SQ_SZ - 1) ? 1 : sq_head + 1; // change here
                sq_head_wrap <= (sq_head == `SQ_SZ - 1) ? ~sq_head_wrap : sq_head_wrap; // change here
            end


            // LQ - In-Flight Load addresses
            //Dispatch, Execute
            if (lq_alloc && !lq_full) begin
                lq[lq_tail] <= 0;
                lq[lq_tail].valid <= `TRUE;
                lq[lq_tail].T <= T;

                lq_tail <= (lq_tail == `LQ_SZ - 1) ? 0 : (lq_tail + 1);
                lq_tail_wrap <= (lq_tail == `LQ_SZ - 1) ? ~lq_tail_wrap : lq_tail_wrap; // change here
            end

            if (load_X) begin
                lq[lq_X_T].addr <= load_addr;
                lq[lq_X_T].addr_valid <= `TRUE;
            end

            if(!lq_empty && lq[lq_head].)
        end
    end
endmodule


    //OLD CODE

    // if a retire happens, write head to D$
    assign mem_write_en = queue[head].valid && queue[head].is_store && retire_en && (queue[head].T == retire_T);
    assign proc2mem_addr = queue[head].addr;
    assign proc2mem_data = queue[head].data;

    //forwarding unit, if load is executing check here and in D$
    // TODO check with TA, basically if head>tail, higher number is younger, if tail>head lower number is younger
    always_comb begin
        store_load_fwd = 0;
        load_data = '0;
        if (load_exec_en) begin
            for (int i = LSQ_SZ - 1; i >= 0; i--) begin
                if (queue[i].valid && queue[i].is_store && queue[i].ready && queue[i].addr == load_addr && queue[i].T < load_T) begin
                    store_load_fwd = 1;
                    load_data = queue[i].data;
                end
            end
        end
    end




