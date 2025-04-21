`include "verilog/sys_defs.svh"

module func_unit_3(
    input clock, reset, committed, wr_valid,
    input [63:0] Dmem2proc_data,
    input ROB_T T, //pass through
    input MEM_ACCESS mem_access, //for shifting
    input logic [`XLEN-1:0] proc2Dmem_data,

    output [63:0]      proc2Dcache_data,
    output X_C_PACKET X_packet
);

    logic [`XLEN-1:0] rawDmem_addr;
    logic [3:0]       line_offset;
    logic [5:0]       shift;
    logic [63:0]      Dmem_data;
    mem_proc_states   mem_state;

    always_comb begin
        Dmem_data = Dmem2proc_data;
        case (mem_access.mem_size)
            BYTE: begin
                shift = (mem_access.line_offset) << 3;
                case (shift)
                    0: Dmem_data[7:0] = proc2Dmem_data[7:0];
                    8: Dmem_data[15:8] = proc2Dmem_data[7:0];
                    16: Dmem_data[23:16] = proc2Dmem_data[7:0];
                    24: Dmem_data[31:24] = proc2Dmem_data[7:0];
                    32: Dmem_data[39:32] = proc2Dmem_data[7:0];
                    40: Dmem_data[47:40] = proc2Dmem_data[7:0];
                    48: Dmem_data[55:48] = proc2Dmem_data[7:0];
                    56: Dmem_data[63:56] = proc2Dmem_data[7:0];
                endcase
            end
            HALF: begin
                shift = (mem_access.line_offset >> 1) << 4;
                case (shift)
                    0: Dmem_data[15:0] = proc2Dmem_data[15:0];
                    16: Dmem_data[31:16] = proc2Dmem_data[15:0];
                    32: Dmem_data[47:32] = proc2Dmem_data[15:0];
                    48: Dmem_data[63:48] = proc2Dmem_data[15:0];
                endcase
            end
            WORD: begin
                shift = (mem_access.line_offset[2] << 2) << 3;
                case (shift)
                    0: Dmem_data[31:0] = proc2Dmem_data[31:0];
                    32: Dmem_data[63:32] = proc2Dmem_data[31:0];
                endcase
            end
            default: begin
                shift = '0;
            end
        endcase
    end

    assign proc2Dcache_data = Dmem_data;

     // state machine to handle loads
    always_ff @(posedge clock) begin
        if (reset) begin
            X_packet  <= '0;
            mem_state <= MEM_WAIT_FOR_TAG;
        end else begin
            case (mem_state) 
                // if valid pass to X_packet
                MEM_WAIT_FOR_TAG:
                    if (wr_valid) begin
                        X_packet.T         <= T;
                        X_packet.result    <= '0;
                        
                        X_packet.ppln_ctrl <= '0;
                        X_packet.valid     <= `TRUE;
                        X_packet.ppln_ctrl.is_store <= `TRUE;

                        mem_state <= MEM_NONE;
                    end
                MEM_NONE: begin
                    // if committed, return back to state waiting to give to X_packet
                    X_packet <= '0;
                    if (committed)
                        mem_state <= MEM_WAIT_FOR_TAG;
                end
                default: ;

            endcase
        end
    end    

endmodule   // func_unit_3
