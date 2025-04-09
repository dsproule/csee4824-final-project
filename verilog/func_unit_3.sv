`include "verilog/sys_defs.svh"

module func_unit_3(
    input clock, reset, 
    input Dmem_gnt,                 // signal that the memory was listening to this module
    input retired,                  // the current mem_store has been 
    input [3:0]  mem2proc_response, mem2proc_tag,
    input [63:0] Dmem2proc_data,
    input S_X_PACKET S_X_reg,

    output logic mem_store_pend,          // the module is attempting to store a value
    output [`XLEN-1:0] proc2Dmem_addr,
    output [63:0] proc2Dmem_data, // CHANGE: 64 bits
    output logic [1:0] proc2Dmem_command,
    output X_C_PACKET X_packet
);

    // then needs to single out part of data to modify
    // then needs to push it back like before

    logic [`XLEN-1:0] rawDmem_addr;
    logic [3:0]       nextDmem_tag, line_offset;
    logic [5:0]       shift, size_offset;
    logic [63:0]      rawDmem_data, Dmem_data;
    mem_proc_states   fetchDmem_state, storeDmem_state;
    logic             fetchDmem_valid, store_pend, load_pend, store_valid;

    // should be word-aligned. If a value is invalid proc_resp will be 0
    assign rawDmem_addr   = S_X_reg.V1 + S_X_reg.mem_offset;
    assign proc2Dmem_addr = {rawDmem_addr[`XLEN-1:3], 3'b0};
    assign line_offset    = rawDmem_addr[2:0];

    always_ff @(posedge clock) begin
        if (reset) begin
            nextDmem_tag    <= '0;
            fetchDmem_state <= MEM_WAIT_FOR_ADDR;
            load_pend  <= `FALSE;
        end else begin
            case (fetchDmem_state)
                MEM_WAIT_FOR_ADDR: begin
                    fetchDmem_valid <= `FALSE;
                    // waits here for a mem req to hit S_X_reg
                    if (S_X_reg.valid) begin
                        load_pend    <= `TRUE;
                        fetchDmem_state   <= MEM_NEW_ADDR;
                        proc2Dmem_command <= BUS_LOAD;
                    end
                end
                MEM_NEW_ADDR: begin
                    // saves every  seen tag and when we know the tag corresp to current req, move to next state
                    nextDmem_tag <= mem2proc_response;
                    if (Dmem_gnt & (nextDmem_tag != 0)) begin
                        load_pend <= `FALSE;
                        fetchDmem_state <= MEM_WAIT_FOR_TAG;
                        proc2Dmem_command <= BUS_NONE;
                    end
                end
                MEM_WAIT_FOR_TAG: begin
                    // if the memory is responding to us, save it and wait to be retired
                    if (mem2proc_tag == nextDmem_tag) begin
                        // triggers the next state machine
                        rawDmem_data <= Dmem2proc_data;
                        fetchDmem_valid <= `TRUE;

                        nextDmem_tag <= '0;
                        fetchDmem_state <= MEM_NONE;
                    end
                end
                MEM_NONE: begin
                    fetchDmem_valid <= `FALSE;
                    proc2Dmem_command <= BUS_STORE;
                    if (retired) begin
                        fetchDmem_state <= MEM_WAIT_FOR_ADDR;
                        proc2Dmem_command <= BUS_NONE;
                    end
                end
            endcase
        end
    end    

    always_comb begin
        Dmem_data = rawDmem_data;
        case (S_X_reg.mem_size)
            BYTE: begin
                shift = (line_offset) << 3;
                case (shift)
                    0: Dmem_data[7:0] = S_X_reg.V2[7:0];
                    8: Dmem_data[15:8] = S_X_reg.V2[7:0];
                    16: Dmem_data[23:16] = S_X_reg.V2[7:0];
                    24: Dmem_data[31:24] = S_X_reg.V2[7:0];
                    32: Dmem_data[39:32] = S_X_reg.V2[7:0];
                    40: Dmem_data[47:40] = S_X_reg.V2[7:0];
                    48: Dmem_data[55:48] = S_X_reg.V2[7:0];
                    56: Dmem_data[63:56] = S_X_reg.V2[7:0];
                endcase
            end
            HALF: begin
                shift = (line_offset >> 1) << 4;
                case (shift)
                    0: Dmem_data[15:0] = S_X_reg.V2[15:0];
                    16: Dmem_data[31:16] = S_X_reg.V2[15:0];
                    32: Dmem_data[47:32] = S_X_reg.V2[15:0];
                    48: Dmem_data[63:48] = S_X_reg.V2[15:0];
                endcase
            end
            WORD: begin
                shift = (line_offset[2] << 2) << 3;
                case (shift)
                    0: Dmem_data[31:0] = S_X_reg.V2[31:0];
                    32: Dmem_data[63:32] = S_X_reg.V2[31:0];
                endcase
            end
            default: begin
                shift = '0;
                size_offset = '0;
            end
        endcase

        // handling X_C_reg
        // if (Dmem_gnt) begin
        //     X_packet.T = S_X_reg.T;
        //     X_packet.result = '0;
            
        //     X_packet.ppln_ctrl = '0;
        //     X_packet.ppln_ctrl.is_store = `TRUE;
        //     X_packet.valid = store_valid;
        // end else
        //     X_packet = '0;
    end

    assign proc2Dmem_data = Dmem_data;
    assign mem_store_pend = load_pend | store_pend;

    // state machine enforces one memory load 
    always_ff @(posedge clock) begin
        if (reset) begin
            store_pend <= `FALSE;
            storeDmem_state <= MEM_WAIT_FOR_ADDR;
            store_valid <= `FALSE;
            X_packet <= 0;
        end else begin
            case (storeDmem_state)
                MEM_WAIT_FOR_ADDR:
                    if (fetchDmem_valid) begin
                        store_pend <= `TRUE;
                        storeDmem_state <= MEM_NEW_ADDR;
                    end
                MEM_NEW_ADDR:
                    if (Dmem_gnt) begin
                        store_pend <= `FALSE;
                        storeDmem_state <= MEM_NONE;
                        store_valid <= `TRUE;
                        X_packet.T <= S_X_reg.T;
                        X_packet.result <= '0;
                        
                        X_packet.ppln_ctrl <= '0;
                        X_packet.ppln_ctrl.is_store <= `TRUE;
                        X_packet.valid <= `TRUE;
                    end
                MEM_NONE: begin
                    X_packet <= 0;
                    if (retired) 
                        storeDmem_state <= MEM_WAIT_FOR_ADDR;
                end
            endcase
        end
    end

endmodule   // func_unit_3
