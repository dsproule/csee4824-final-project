`include "verilog/sys_defs.svh"

//exists in pipeline interacts with all other units, func units 2 and 3 write addr to it
module lsq(
    // alloc inputs
    input logic clock, reset, 
    input logic dispatch_valid, 
    input logic sq_alloc, lq_alloc,
    input ROB_T T,

    // Data/Addr Update Inputs
    input S_X_PACKET S_X_load,
    input S_X_PACKET S_X_store,
    input logic store_X, load_X, 

    // retire from rob
    input ROB_T retire_T,
    input logic retire_en,

    //forwarding outputs
    output logic [`XLEN-1:0] load_data,
    output logic store_load_fwd,

    //mem write from head when store is committed
    output logic mem_write_en,
    output logic [`XLEN-1:0] proc2Dmem_addr_store,
    output logic [`XLEN-1:0] proc2Dmem_data_store,

    // lq output for cdb or D$ if needed
    output logic [`XLEN-1:0] proc2Dmem_addr_load,
    output logic [`XLEN-1:0] proc2Dmem_data_load,
    output logic load_data_valid,

    //control signals for structural hazards
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
    TODO insert control signals into pipeline
    */

    // address calculation
    MEM_ACCESS mem_access_load;
    MEM_ACCESS mem_access_store;
    logic [`XLEN-1:0] rawDmem_addr_load;
    logic [`XLEN-1:0] S_X_load_addr;
    logic [`XLEN-1:0] rawDmem_addr_store;
    logic [`XLEN-1:0] S_X_store_addr;

    always_comb begin
        rawDmem_addr_load = S_X_load.V1 + S_X_load.mem_offset;
        S_X_load_addr = {rawDmem_addr_load[`XLEN-1:3], 3'b0};

        mem_access_load.line_offset = rawDmem_addr_load[2:0];
        mem_access_load.rd_unsigned = S_X_load.rd_unsigned;
        mem_access_load.mem_size = S_X_load.mem_size;

        rawDmem_addr_store = S_X_store.V1 + S_X_store.mem_offset;
        S_X_store_addr = {rawDmem_addr_store[`XLEN-1:3], 3'b0};

        mem_access_store.line_offset = rawDmem_addr_store[2:0];
        mem_access_store.rd_unsigned = S_X_store.rd_unsigned;
        mem_access_store.mem_size = S_X_store.mem_size;
    end


    LQ_ENTRY lq[`LQ_SZ-1:0];
    LQ_T lq_head, lq_tail;
    logic lq_head_wrap, lq_tail_wrap, lq_alloc;

    assign lq_full = (lq_head == lq_tail) && (lq_head_wrap != lq_tail_wrap);
    assign lq_empty = (lq_head == lq_tail) && (lq_head_wrap == lq_tail_wrap);

    SQ_ENTRY sq[`SQ_SZ-1:0];
    logic SQ_T sq_head, sq_tail;
    logic sq_head_wrap, sq_tail_wrap, sq_alloc;

    assign sq_full = (sq_head == sq_tail) && (sq_head_wrap != sq_tail_wrap);
    assign sq_empty = (sq_head == sq_tail) && (sq_head_wrap == sq_tail_wrap);
    
    SQ_T sq_X_T, retire_sq_T;
    LQ_T lq_X_T;

    //forwarding unit - youngest store older than load forwards to load

    // loop temp logic that should get compiled out
    ROB_T best_T; // may cause synthesis to freak out,  but should be fine
    always_comb begin
        // Forwarding logic
        store_load_fwd = 0;
        load_data = '0;
        best_T = 0;

        for (int i = 0; i < `SQ_SZ; i++) begin // best_T select largest tag less than load
            if (sq[i].valid && !sq[i].committed && sq[i].addr_valid &&
                (sq[i].addr == S_X_load_addr) && (sq[i].T < S_X_load.T)) begin
                if (sq[i].data_valid && load_X && lq[lq_X_T].valid && sq[i].T >= best_T) begin
                    load_data = sq[i].data; 
                    best_T = sq[i].T;
                    store_load_fwd = 1;
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
        for (int i = 0; i < `LQ_SZ; i++) begin
            if (S_X_load.T == lq[i].T)
                lq_X_T = i;
        end

        for (int i = 0; i < `SQ_SZ; i++) begin
                if (S_X_store.T == sq[i].T) begin
                    sq_X_T = i;
                end
                if (retire_T == sq[i].T) begin
                    retire_sq_T = i;
                end
        end
    end

    // TODO flush unit --> sets data to not ready if collision    

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

            mem_write_en <= 0;
            load_data_valid <= 0;
        end else begin
            mem_write_en <= 0;
            load_data_valid <= 0;
            
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
            if (store_X && sq[sq_X_T].valid) begin //comes from RS
                sq[sq_X_T].addr <= S_X_store_addr;
                sq[sq_X_T].data <= S_X_store.V2; //to be masked in FU
                sq[sq_X_T].data_valid <= `TRUE;
                sq[sq_X_T].addr_valid <= `TRUE;
                sq[sq_X_T].mem_access <= mem_access_store;
            end

            if(retire_en && sq[retire_sq_T].addr_valid && sq[retire_sq_T].data_valid) begin //akin to setting ready in ROB
                sq[retire_sq_T].retired <= `TRUE;
            end

            // Write address/data from SQ head to D$, free SQ head
            if(!sq_empty && (sq[sq_head].retired || sq_head == retire_sq_T) && 
                        sq[sq_head].addr_valid && sq[sq_head].data_valid) begin
                
                mem_write_en <= `TRUE;
                proc2Dmem_addr_store <= sq[sq_head].addr;
                proc2Dmem_data_store <= sq[sq_head].data;

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

            if (load_X && lq[lq_X_T].valid) begin
                lq[lq_X_T].addr <= S_X_load_addr;
                lq[lq_X_T].addr_valid <= `TRUE;
                lq[lq_X_T].mem_access <= mem_access_load;

                if (store_load_fwd) begin //forwards if the address is already present
                    lq[lq_X_T].data <= load_data;
                    lq[lq_X_T].data_ready <= `TRUE;
                end
            end

            //output --> send to cache if data isnt ready, otherwise cdb
            if(!lq_empty && lq[lq_head].addr_valid && lq[lq_head].valid) begin
                load_data_valid <= lq[lq_head].data_ready;
                proc2Dmem_addr_load <= lq[lq_head].addr;
                proc2Dmem_data_load <= lq[lq_head].data;

                lq_head <= (lq_head == `LQ_SZ - 1) ? 0 : (lq_head + 1);
                lq_head_wrap <= (lq_head == `LQ_SZ - 1) ? ~lq_head_wrap : lq_head_wrap;
            end
        end
    end
endmodule
