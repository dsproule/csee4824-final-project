`include "verilog/sys_defs.svh"

//exists in pipeline interacts with all other units, func units 2 and 3 write addr to it
module lsq(
    // alloc inputs
    input logic clock, reset, take_branch,
    input logic sq_alloc, lq_alloc,
    input logic ROB_wrap,
    input ROB_T T,

    // Data/Addr Update Inputs
    input S_X_PACKET S_X_load,
    input S_X_PACKET S_X_store,
    input logic store_X, load_X, 

    // retire from rob
    input ROB_T retire_T,
    input logic retire_en,

    //Dcache received
    input logic Dcache_valid_out,

    //forwarding outputs
    output X_C_PACKET load_fwd_packet,
    output X_C_PACKET store_X_packet,

    //mem write from head when store is committed
    output logic mem_write_en,
    output logic [`XLEN-1:0] proc2Dmem_addr_store,
    output logic [`XLEN-1:0] proc2Dmem_data_store,
    output MEM_ACCESS mem_access_store,
    output ROB_T store_T,

    // lq output for cdb or D$ if needed
    output logic mem_read_en,
    output logic [`XLEN-1:0] proc2Dmem_addr_load,
    output MEM_ACCESS mem_access_load,
    output ROB_T load_T,

    //control signals for structural hazards
    output logic sq_full, sq_empty, lq_full, lq_empty
);

    /*

    Out of Order:
    Load/store queue (LSQ) Functionality
    • Completed stores write to LSQ
    • When store retires, head of LSQ written to D$
    • When loads execute, access LSQ and D$ in parallel
    • Forward from LSQ if older store with matching address
    
    HOWEVER:
    This LSQ is inorder - as in each load keeps track of dependent stores
    once those store addresses are resolved, the older of the two heads is sent to
    the dcache. This forwards from stores to loads when a sq or lq address is updated and
    there is a match. This lsq uses FU3 and FU2 as the memory controllers with the D$, outputting
    the addr/data/mem_write_en, mem_read_en, as well as some memory access pass throughs.

    To make this out of order, adjust the load_fwd_packet signal to output on update_lq,
    and in the for loop around line 300, do not forward, as this would detect an 
    address ordering violation, set an exception bit that resets the relevant data structures.

    As our dcache is nonblocking for loads, it frees the lq_head as soon as it is valid,
    but it must wait for pending stores before making loads valid.
    */

    // address calculation
    MEM_ACCESS mem_access_load_wire;
    MEM_ACCESS mem_access_store_wire;
    logic [`XLEN-1:0] rawDmem_addr_load;
    logic [`XLEN-1:0] S_X_load_addr;
    logic [`XLEN-1:0] rawDmem_addr_store;
    logic [`XLEN-1:0] S_X_store_addr;

    always_comb begin
        rawDmem_addr_load = S_X_load.V1 + S_X_load.mem_offset;
        S_X_load_addr = {rawDmem_addr_load[`XLEN-1:3], 3'b0};

        mem_access_load_wire.line_offset = rawDmem_addr_load[2:0];
        mem_access_load_wire.rd_unsigned = S_X_load.rd_unsigned;
        mem_access_load_wire.mem_size = S_X_load.mem_size;

        rawDmem_addr_store = S_X_store.V1 + S_X_store.mem_offset;
        S_X_store_addr = {rawDmem_addr_store[`XLEN-1:3], 3'b0};

        mem_access_store_wire.line_offset = rawDmem_addr_store[2:0];
        mem_access_store_wire.rd_unsigned = S_X_store.rd_unsigned;
        mem_access_store_wire.mem_size = S_X_store.mem_size;
    end

    // Queue Regs/Wires

    LQ_ENTRY lq[`LQ_SZ-1:0];
    LQ_T lq_head, lq_tail;
    logic lq_head_wrap, lq_tail_wrap;

    assign lq_full = (lq_head == lq_tail) && (lq_head_wrap != lq_tail_wrap);
    assign lq_empty = (lq_head == lq_tail) && (lq_head_wrap == lq_tail_wrap);

    SQ_ENTRY sq[`SQ_SZ-1:0];
    SQ_T sq_head, sq_tail;
    logic sq_head_wrap, sq_tail_wrap;

    assign sq_full = (sq_head == sq_tail) && (sq_head_wrap != sq_tail_wrap);
    assign sq_empty = (sq_head == sq_tail) && (sq_head_wrap == sq_tail_wrap);
    
    // CAM indices
    SQ_T sq_X_T, retire_sq_T;
    LQ_T lq_X_T;

    // control signals

    logic sq2Dcache, lq2Dcache, fwd_head;
    logic update_sq, update_lq;
    logic sq_older, lq_older; //sq head is older than lq head
    logic ld_valid, st_valid, retire_valid;

    assign update_sq = store_X && sq[sq_X_T].valid && S_X_store.valid && st_valid;
    assign update_lq = load_X && lq[lq_X_T].valid && S_X_load.valid && ld_valid;

    // send store to dcache
    assign sq2Dcache = !sq_empty && (sq[sq_head].retired || (sq_head == retire_sq_T && retire_en && retire_valid)) && 
                        sq[sq_head].addr_valid && sq[sq_head].data_valid && sq_older;

    // send load to cdb instead of dcache
    assign fwd_head = store_X && sq[sq_X_T].valid && ((sq_X_T == lq[lq_head].dep_sq_T) && (lq[lq_head].state == FORWARDED));

    //send load to dcache if head valid and (ready or forward)
    assign lq2Dcache = !lq_empty && lq[lq_head].addr_valid && lq_older && lq[lq_head].valid && ((lq[lq_head].state == LQ_NONE) || (lq[lq_head].state == DATA_READY) || fwd_head);

    // determines which head is older
    assign sq_older = sq[sq_head].valid && (!lq[lq_head].valid || (lq[lq_head].valid && ((sq[sq_head].T < lq[lq_head].T ~^ sq[sq_head].ROB_wrap == lq[lq_head].ROB_wrap))));
    assign lq_older = lq[lq_head].valid && (!sq[sq_head].valid || sq[sq_head].dirty || (sq[sq_head].valid && (sq[sq_head].T > lq[lq_head].T ~^ sq[sq_head].ROB_wrap == lq[lq_head].ROB_wrap)));
    
    //forwarding unit - youngest store older than load forwards to load
    X_C_PACKET fwd_packet_wire;

    /*
        Note: To determine age: the older instruction is the one with a lower ROB_T, as long as the tail has not wrapped around
        so to compensate for this an older load queue entry could be determined with

        (lq_ROB_T < sq_ROB_T && lq_ROB_tail_wrap == sq_ROB_tail_wrap) || (lq_ROB_T > sq_ROB_T && lq_ROB_tail_wrap != sq_ROB_tail_wrap)

        Because the tags are unique, this can be simplified to:
        (lq_ROB_T < sq_ROB_T && lq_ROB_tail_wrap == sq_ROB_tail_wrap) || (lq_ROB_T >= sq_ROB_T && lq_ROB_tail_wrap != sq_ROB_tail_wrap)

        And thus this can be expressed as the XNOR

        (lq_ROB_T < sq_ROB_T ~^ lq_ROB_tail_wrap == sq_ROB_tail_wrap)     

        or (but i find this more confusing)

        (lq_ROB_T < sq_ROB_T) == (lq_ROB_tail_wrap == sq_ROB_tail_wrap)   
  */

    // loop temp logic that gets compiled out, can be optimized with a prediction
    ROB_T best_T_store;
    always_comb begin
        // Forwarding logic
        best_T_store = 0;
        fwd_packet_wire = 0;

        for (int i = 0; i < `SQ_SZ; i++) begin // best_T select largest tag less than load
            if (sq[i].valid && sq[i].addr_valid && sq[i].data_valid &&
                    (sq[i].addr == S_X_load_addr) && update_lq && sq[i].T >= best_T_store) begin
                if (((sq[i].T < S_X_load.T ~^ sq[i].ROB_wrap == lq[lq_X_T].ROB_wrap))) begin
                    best_T_store = sq[i].T;
                    fwd_packet_wire.T =  sq[i].T;
                    fwd_packet_wire.result = sq[i].data;

                    if (mem_access_load_wire.rd_unsigned) begin
                        if (mem_access_load_wire.mem_size == BYTE) fwd_packet_wire.result[`XLEN-1:8] = 0;
                        else if (mem_access_load_wire.mem_size == HALF) fwd_packet_wire.result[`XLEN-1:16] = 0;
                    end else begin
                        if (mem_access_load_wire.mem_size == BYTE) fwd_packet_wire.result[`XLEN-1:8] = {(`XLEN-8){sq[i].data[7]}};
                        else if (mem_access_load_wire.mem_size == HALF) fwd_packet_wire.result[`XLEN-1:16] = {(`XLEN-16){sq[i].data[15]}};
                    end

                    fwd_packet_wire.valid = (sq[i].mem_access == mem_access_load_wire);
                end 
            end
        end
    end

    // CAMS for lq/sq indices --> can load sq_tail and lq_head into
    // RS to reduce logic but for now using this

    always_comb begin
        sq_X_T = 0;
        lq_X_T = 0;
        retire_sq_T = 0;
        store_X_packet = 0;
        ld_valid = 0;
        st_valid = 0;
        retire_valid = 0;

        for (int i = 0; i < `LQ_SZ; i++) begin
            if (S_X_load.T == lq[i].T) begin
                lq_X_T = i;
                ld_valid = 1;
            end
        end

        for (int i = 0; i < `SQ_SZ; i++) begin
            if (S_X_store.T == sq[i].T) begin
                sq_X_T = i;
                st_valid = 1;
            end
            if (retire_T == sq[i].T) begin
                retire_sq_T = i;
                retire_valid = 1;
            end
        end

        if (update_sq) begin
            store_X_packet.T = sq[sq_X_T].T;
            store_X_packet.result = 0;
            store_X_packet.valid = `TRUE;
            store_X_packet.ppln_ctrl.is_store = `TRUE;
        end

        mem_write_en = sq2Dcache && !sq[sq_head].dirty; 
        proc2Dmem_addr_store = sq[sq_head].addr;
        proc2Dmem_data_store = sq[sq_head].data;
        mem_access_store = sq[sq_head].mem_access;
        store_T = sq[sq_head].T;

        proc2Dmem_addr_load = lq[lq_head].addr;
        mem_access_load = lq[lq_head].mem_access;
        load_T = lq[lq_head].T;
        mem_read_en = !lq_empty && lq[lq_head].addr_valid && lq[lq_head].valid && lq[lq_head].state == LQ_NONE && lq_older;
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

            load_fwd_packet <= 0;
        end else if (take_branch) begin
            for (int i = 0; i < `LQ_SZ; i++) begin
                lq[i] <= 0;
            end

            for (int i = 0; i < `SQ_SZ; i++) begin
                if(sq[i].valid && !sq[i].retired ) begin
                    sq[i].dirty <= `TRUE;
                end
            end

            lq_head <= 0;
            lq_tail <= 0;
            lq_head_wrap <= 0;
            lq_tail_wrap <= 0;

            load_fwd_packet <= 0;
        end else begin
            load_fwd_packet <= 0;

            // SQ
            //dispatch alloc on decode, record current lq_tail in rs station as store position
            if (sq_alloc && !sq_full) begin
                sq[sq_tail] <= 0;
                sq[sq_tail].valid <= `TRUE;
                sq[sq_tail].T <= T;
                sq[sq_tail].ROB_wrap <= ROB_wrap;

                //RECORD LAST DEP SQ INDEX
                if (!lq_full) begin
                    lq[lq_tail].dep_sq_T <= sq_tail;
                    lq[lq_tail].state <= WAITING;
                end

                sq_tail <= (sq_tail == `SQ_SZ - 1) ? 0 : (sq_tail + 1);
                sq_tail_wrap <= (sq_tail == `SQ_SZ - 1) ? ~sq_tail_wrap : sq_tail_wrap; // change here
            end

            // store func unit writes address/data into slot, rs gets cleared
            if (update_sq) begin //comes from RS
                sq[sq_X_T].addr <= S_X_store_addr;
                sq[sq_X_T].data <= S_X_store.V2; //to be masked in FU
                sq[sq_X_T].data_valid <= `TRUE;
                sq[sq_X_T].addr_valid <= `TRUE;
                sq[sq_X_T].mem_access <= mem_access_store_wire;

                
                for (int j = 0; j < `LQ_SZ; j++) begin
                    if (sq_X_T == lq[j].dep_sq_T) begin 
                        lq[j].state <= (lq[j].state == FORWARDED) ? DATA_READY : LQ_NONE; // all dep stores done
                    end 

                    if (lq[j].valid && (lq[j].addr == S_X_store_addr) && lq[j].addr_valid &&
                        (lq[j].T > S_X_store.T ~^ lq[j].ROB_wrap == sq[sq_X_T].ROB_wrap) && 
                        lq[j].mem_access == mem_access_store_wire) begin
                        lq[j].data <= S_X_store.V2; //forward early

                        if (mem_access_store_wire.rd_unsigned) begin
                            if (mem_access_store_wire.mem_size == BYTE) lq[j].data[`XLEN-1:8] <= 0;
                            else if (mem_access_store_wire.mem_size == HALF) lq[j].data[`XLEN-1:16] <= 0;
                        end else begin
                            if (mem_access_store_wire.mem_size == BYTE) lq[j].data[`XLEN-1:8] <= {(`XLEN-8){S_X_store.V2[7]}};
                            else if (mem_access_store_wire.mem_size == HALF) lq[j].data[`XLEN-1:8]<= {(`XLEN-16){S_X_store.V2[15]}};
                        end


                        if (sq_X_T == lq[j].dep_sq_T) lq[j].state <= DATA_READY; // all dep stores done
                        else lq[j].state <= FORWARDED; //early forward
                    end     
                end
            end

            if(retire_en && sq[retire_sq_T].addr_valid && sq[retire_sq_T].data_valid && retire_valid) begin //akin to setting ready in ROB
                sq[retire_sq_T].retired <= `TRUE;
            end


            // Write address/data from SQ head to D$, free SQ head
            if(sq2Dcache && (Dcache_valid_out && mem_write_en) || sq[sq_head].dirty) begin
                sq[sq_head] <= 0;
                sq_head <= (sq_head == `SQ_SZ - 1) ? 0 : sq_head + 1; // change here
                sq_head_wrap <= (sq_head == `SQ_SZ - 1) ? ~sq_head_wrap : sq_head_wrap; // change here
            end


            // LQ - In-Flight Load addresses
            //Dispatch, Execute
            if (lq_alloc && !lq_full) begin
                lq[lq_tail] <= 0;
                lq[lq_tail].valid <= `TRUE;
                lq[lq_tail].T <= T;
                lq[lq_tail].ROB_wrap <= ROB_wrap;
                lq[lq_tail].state <= lq[lq_tail].state;
                lq[lq_tail].dep_sq_T <= lq[lq_tail].dep_sq_T;
                // last dep store and state also allocated
                
                lq_tail <= (lq_tail == `LQ_SZ - 1) ? 0 : (lq_tail + 1);
                lq_tail_wrap <= (lq_tail == `LQ_SZ - 1) ? ~lq_tail_wrap : lq_tail_wrap; // change here
            end

            if (update_lq) begin
                lq[lq_X_T].addr <= S_X_load_addr;
                lq[lq_X_T].addr_valid <= `TRUE;
                lq[lq_X_T].mem_access <= mem_access_load_wire;

                if (fwd_packet_wire.valid && lq[lq_X_T].state != WAITING) begin //forwards if the address is already present
                    lq[lq_X_T].data <= fwd_packet_wire.result;
                    lq[lq_X_T].state <= DATA_READY;
                end 
            end

            //output --> send to cache if data isnt ready, otherwise cdb
            if(lq2Dcache) begin
                load_fwd_packet.valid <= (lq[lq_head].state == DATA_READY || fwd_head);
                load_fwd_packet.T <= lq[lq_head].T;
                load_fwd_packet.result <= lq[lq_head].data;
                load_fwd_packet.ppln_ctrl.has_dest <= `TRUE;

                //making mem request if no dependencies
                if ((Dcache_valid_out && mem_read_en) || lq[lq_head].state == DATA_READY || fwd_head ) begin
                    lq[lq_head] <= 0;
                    lq_head <= (lq_head == `LQ_SZ - 1) ? 0 : (lq_head + 1);
                    lq_head_wrap <= (lq_head == `LQ_SZ - 1) ? ~lq_head_wrap : lq_head_wrap;
                end
            end
        end
    end
endmodule