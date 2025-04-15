`include "verilog/sys_defs.svh"

module lsq#(
    parameter  LSQ_SZ     = 8,
    localparam PTR_WIDTH  = $clog2(LSQ_SZ))(
    // alloc inputs
    input logic clock, reset, 
    input logic alloc_en, 
    input LSQ_ENTRY lsq_entry,

    // retire from rob
    input ROB_T retire_T,
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
    output logic full, empty
);

    /*
    Load/store queue (LSQ) Functionality
    • Completed stores write to LSQ
    • When store retires, head of LSQ written to D$
    • When loads execute, access LSQ and D$ in parallel
    • Forward from LSQ if older store with matching address
    */


    LSQ_ENTRY queue[LSQ_SZ];
    logic [PTR_WIDTH:0] big_head, big_tail; //one extra bit for easy full/empty check and built in wraparound
    logic [PTR_WIDTH-1:0] head, tail;

    assign head = big_head[PTR_WIDTH-1:0];
    assign tail = big_tail[PTR_WIDTH-1:0];

    assign full = (head == tail) && (big_tail[PTR_WIDTH] != big_head[PTR_WIDTH]);
    assign empty = (big_head == big_tail);

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

    
    always_ff @(posedge clock) begin
        if (reset) begin
            big_head <= 0;
            big_tail <= 0;
            for (int i = 0; i < LSQ_SZ; i++) begin
                queue[i] <= '0;
            end
        end else begin 
            // allocating to LSQ
            if (alloc_en && !full) begin
                queue[tail] <= lsq_entry;
                queue[tail].valid <= 1;
                queue[tail].ready <= lsq_entry.is_store; // TODO store address is ready at issue here, but really set by EX stage so need to set
                big_tail <= big_tail + 1;
            end

            // deallocating from LSQ
            if (mem_write_en) begin
                queue[head].valid <= 0;
                queue[head].ready <= 0;
                big_head <= big_head + 1;
            end
        end
    end


endmodule

