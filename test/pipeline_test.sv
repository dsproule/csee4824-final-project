/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  pipeline_test.sv                                    //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline;       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

module testbench;
    // used to parameterize which files are used for memory and writeback/pipeline outputs
    // "./simv" uses program.mem, writeback.out, and pipeline.out
    // but now "./simv +MEMORY=<my_program>.mem" loads <my_program>.mem instead
    // use +WRITEBACK=<my_program>.wb and +PIPELINE=<my_program>.ppln for those outputs as well
    string program_memory_file;
    string writeback_output_file;
    // string pipeline_output_file;

    // variables used in the testbench
    logic        clock;
    logic        reset;
    logic [31:0] clock_count;
    logic [31:0] instr_count;
    int          wb_fileno;
    logic [63:0] debug_counter; // counter used for infinite loops, forces termination

    logic [1:0]       proc2mem_command;
    logic [`XLEN-1:0] proc2mem_addr;
    logic [63:0]      proc2mem_data;
    logic [3:0]       mem2proc_response;
    logic [63:0]      mem2proc_data;
    logic [3:0]       mem2proc_tag;
`ifndef CACHE_MODE
    MEM_SIZE          proc2mem_size;
`endif

    logic [3:0]       pipeline_completed_insts;
    EXCEPTION_CODE    pipeline_error_status;
    logic [4:0]       pipeline_commit_wr_idx;
    logic [`XLEN-1:0] pipeline_commit_wr_data;
    logic             pipeline_commit_wr_en;
    logic [`XLEN-1:0] pipeline_commit_NPC;

    // debug tables
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out_dbg;
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out_dbg;
    RS_ENTRY [`RS_SZ-1:0] rs_table_dbg;
    logic [`RS_SZ-1:0] busy_dbg;

    // Debug extra
    CDB cdb_dbg;
    logic [`RS_SZ-1:0] FU_ready_dbg, FU_req_dbg, gnt_dbg;
    ROB_T rob_head_dbg, rob_tail_dbg, retire_T_wire_dbg;
    PPLN_CTRL rob_pipeline_control_dbg;
    
    // Debug regs
    D_S_PACKET              D_S_reg_dbg;
    IF_ID_PACKET            IF_ID_reg_dbg;
    X_C_PACKET [`RS_SZ-1:0] X_C_regs_dbg;
    S_X_PACKET [`RS_SZ-1:0] S_X_regs_dbg;

    // logging
    MT_ENTRY mt_table [31:0];
    ROB_ENTRY rob_table [`ROB_SZ:1];

    integer i, j, k, l, m, n, o, p, q;

    // Instantiate the Pipeline
    pipeline core (
        // Inputs
        .clock             (clock),
        .reset             (reset),
        .mem2proc_response (mem2proc_response),
        .mem2proc_data     (mem2proc_data),
        .mem2proc_tag      (mem2proc_tag),

        // Outputs
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        .pipeline_completed_insts (pipeline_completed_insts),
        .pipeline_error_status    (pipeline_error_status),
        .pipeline_commit_wr_data  (pipeline_commit_wr_data),
        .pipeline_commit_wr_idx   (pipeline_commit_wr_idx),
        .pipeline_commit_wr_en    (pipeline_commit_wr_en),
        .pipeline_commit_NPC      (pipeline_commit_NPC),

        .rob_table_out_dbg(rob_table_out_dbg),
        .mt_table_out_dbg(mt_table_out_dbg),
        .rs_table_dbg(rs_table_dbg),
        .cdb_dbg(cdb_dbg),
        .busy_dbg(busy_dbg),
        .IF_ID_reg_dbg(IF_ID_reg_dbg),
        .D_S_reg_dbg(D_S_reg_dbg),
        .FU_ready_dbg(FU_ready_dbg),
        .FU_req_dbg(FU_req_dbg),
        .gnt_dbg(gnt_dbg),
        .S_X_regs_dbg(S_X_regs_dbg),
        .X_C_regs_dbg(X_C_regs_dbg),
        .rob_head_dbg(rob_head_dbg),
        .rob_tail_dbg(rob_tail_dbg),
        .rob_retire_dbg(rob_retire_dbg),
        .rob_pipeline_control_dbg(rob_pipeline_control_dbg),
        .retire_T_wire_dbg(retire_T_wire_dbg)
    );

    // Instantiate the Data Memory
    mem memory (
        // Inputs
        .clk              (clock),
        .proc2mem_command (proc2mem_command),
        .proc2mem_addr    (proc2mem_addr),
        .proc2mem_data    (proc2mem_data),
`ifndef CACHE_MODE
        .proc2mem_size    (proc2mem_size),
`endif

        // Outputs
        .mem2proc_response (mem2proc_response),
        .mem2proc_data     (mem2proc_data),
        .mem2proc_tag      (mem2proc_tag)
    );


    // Generate System Clock
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    //////////////////////////////////////////////////
    //                                              //
    //               Print Tables                   //
    //                                              //
    //////////////////////////////////////////////////

    always_comb begin
        for (int i = 0; i < 32; i++)
            mt_table[i] = mt_table_out_dbg[i * $bits(MT_ENTRY) +: $bits(MT_ENTRY)];
    end

    always_comb begin
        for (int i = 0; i < `ROB_SZ; i++)
            rob_table[i+1] = rob_table_out_dbg[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)];
    end

    // Task to display # of elapsed clock edges
    task show_clk_count;
        real cpi;
        begin
            cpi = (clock_count + 1.0) / instr_count;
            $display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
                      clock_count+1, instr_count, cpi);
            $display("@@  %4.2f ns total time to execute\n@@\n",
                      clock_count * `CLOCK_PERIOD);
        end
    endtask // task show_clk_count

    task print_if;
        if (IF_ID_reg_dbg.valid) begin
            $display("====================================================================================");
            $display("\n(IF_ID_reg)\ttime: %d\n------------------------------------------", clock_count);
            $display("PC: %2h, INST: %8h", IF_ID_reg_dbg.PC, IF_ID_reg_dbg.inst); 
            $display("------------------------------------------");
        end
    endtask

    task print_ds;
        if (D_S_reg_dbg.valid) begin
            $display("\n(D_S_reg)\ttime: %d\n------------------------------------------", clock_count);
            $display("INST: %0h\nPC: %0h\nNPC: %0h\nr: %0h\nr1: %0h\nr2: %0h\nopa_select: %0h\nopb_select: %0h\ncond_branch: %0b, uncond_branch: %0b, alu_func: %0h\nrs_idx: %0h\nhalt: %0b, illegal: %0b, csr_op: %0b, valid: %0b\n", 
                    D_S_reg_dbg.inst, D_S_reg_dbg.PC, D_S_reg_dbg.NPC, D_S_reg_dbg.r, D_S_reg_dbg.r1, D_S_reg_dbg.r2, D_S_reg_dbg.opa_select, D_S_reg_dbg.opb_select, D_S_reg_dbg.cond_branch,D_S_reg_dbg.uncond_branch,D_S_reg_dbg.alu_func, D_S_reg_dbg.rs_idx, D_S_reg_dbg.halt, D_S_reg_dbg.illegal, D_S_reg_dbg.csr_op, D_S_reg_dbg.valid);
            $display("------------------------------------------");
        end
    endtask

    task print_mt;
        $display("\n(MAP_TABLE)\ttime: %d\n------------------------------------------", clock_count);
        $display("T1:%4d       T2:%4d", core.T1_wire, core.T2_wire);
        for(l = 1; l < 20; l=l+1)
            $display("index: %4d   T:%4d\t  plus:%4d", l, mt_table[l].T, mt_table[l].plus);
        $display("------------------------------------------");
    endtask // print_mt

    task print_rs;
        $display("\n(RS_TABLE)\tstall: %1b time: %d\n------------------------------------------", core.rs_stall, clock_count);
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d   T:%4d   T1:%4d   T2:%4d   V1:%4d   V2:%4d   busy:   %b   ready:%b", j, rs_table_dbg[j].T, rs_table_dbg[j].T1, rs_table_dbg[j].T2, $signed(rs_table_dbg[j].V1), $signed(rs_table_dbg[j].V2), busy_dbg[j], rs_table_dbg[j].ready);
        $display("------------------------------------------");
    endtask // print_rs

    task print_rob;
        $display("\n(ROB_TABLE) h: %2d, t: %2d empty: %1h full: %1h \ttime: %d\n------------------------------------------", rob_head_dbg, rob_tail_dbg, core.rob_empty, core.rob_full, clock_count);
        for(n = 1; n < 32; n=n+1)
            $display("index: %4d   r:%4d   NPC:%4d    V:%4d    ready:%1b", n, rob_table[n].r, rob_table[n].NPC, rob_table[n].V, rob_table[n].ready);
        $display("\n(RETIRE) valid: %1b, ROB_T: %4d, flush: %0d branch_addr: %0h\n------------------------------------------", rob_retire_dbg, retire_T_wire_dbg, rob_pipeline_control_dbg.flush, core.rob_write_data);
    endtask // print_rob

    task print_cdb;
        $display("\n(CDB)\ttime: %d\n------------------------------------------", clock_count);
        $display("T:%4h\t  V:%4h", cdb_dbg.T, cdb_dbg.V);
        $display("FU_ready:%b\t  FU_req:%b\t    gnt:%b", FU_ready_dbg, FU_req_dbg, gnt_dbg);
        $display("------------------------------------------");
    endtask // print_cdb

    task print_xc;
        $display("\n(X_C_Regs)\ttime: %d\n------------------------------------------", clock_count);
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d T: %2h, result: %h, valid: %1h", j,  X_C_regs_dbg[j].T, X_C_regs_dbg[j].result, X_C_regs_dbg[j].valid);
        $display("------------------------------------------");
    endtask

    task print_x_pkt;
        $display("\n(X_Packet)\ttime: %d\n------------------------------------------", clock_count);
        for(j = 0; j < `RS_SZ; j=j+1)
            $display("index: %4d T: %2h, result: %h, valid: %1h", j,  core.X_packets[j].T, core.X_packets[j].result, core.X_packets[j].valid);
        $display("------------------------------------------");
    endtask

    task print_sx;
        $display("\n(S_X_Regs)\ttime: %d\n------------------------------------------", clock_count);
        for(p = 0; p <`RS_SZ; p++)
            $display("index: %4d PC: %2h, INST: %8h, T: %0h, V1: %0h, V2: %0h, halt: %b, valid: %b",
                        p, S_X_regs_dbg[p].PC, S_X_regs_dbg[p].inst, S_X_regs_dbg[p].T, S_X_regs_dbg[p].V1, S_X_regs_dbg[p].V2, S_X_regs_dbg[p].halt, S_X_regs_dbg[p].valid);
        $display("------------------------------------------");
    endtask

    task print_regs;
        $display("\n(Regs)\ttime: %d\n------------------------------------------", clock_count);
        for(q = 0; q < 32; q++)
            $display("r[%2d]: %8h", q, core.regfile_inst.registers[q]);
        $display("------------------------------------------");
    endtask

    task print_mem;
        if (proc2mem_command != BUS_NONE) begin
            $display("\n(Mem)\ttime: %d\n------------------------------------------", clock_count);
            $display("mem_addr: %8h, mem_command: %1d, mem_response: %2d, mem_tag: %2d, mem_data: %8h", proc2mem_addr, proc2mem_command, mem2proc_response, mem2proc_tag, mem2proc_data);
            $display("Dmem_gnt: %2b, take_branch: %1b", core.Dmem_gnt, core.take_branch);
            $display("------------------------------------------");
        end
    endtask

    // Show contents of a range of Unified Memory, in both hex and decimal
    task show_mem_with_decimal;
        input [31:0] start_addr;
        input [31:0] end_addr;
        int showing_data;
        begin
            $display("@@@");
            showing_data=0;
            for(int k=start_addr;k<=end_addr; k=k+1)
                if (memory.unified_memory[k] != 0) begin
                    $display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k],
                                                             memory.unified_memory[k]);
                    showing_data=1;
                end else if(showing_data!=0) begin
                    $display("@@@");
                    showing_data=0;
                end
            $display("@@@");
        end
    endtask // task show_mem_with_decimal

    //////////////////////////////////////////////////
    //                                              //
    //                Execution                     //
    //                                              //
    //////////////////////////////////////////////////

    // Shows modules
    logic prog_start = 0;
    always @(posedge clock) begin
        if (~reset) begin
            // only start printing after first inst arrives
            if (IF_ID_reg_dbg.valid & (IF_ID_reg_dbg.PC >= `XLEN'd600))
            // if (IF_ID_reg_dbg.valid & (IF_ID_reg_dbg.PC >= `XLEN'h10))
                prog_start <= 1;


            if (prog_start) begin
                // print_if;
                // print_ds;
                // print_rs;
                // print_mt;
                // print_cdb;
                // print_rob;
                // print_regs;
                // print_sx;
                // print_mem;
                // print_xc;
                
                // print_x_pkt;
            end
            if(clock_count > 200000)
                $finish;
        end
    end



    initial begin
        // $dumpvars;
        // $dumpfile("pipeline_test.vcd");

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Loading memory file: %s", program_memory_file);
        end else begin
            $display("Loading default memory file: program.mem");
            program_memory_file = "program.mem";
        end
        if ($value$plusargs("WRITEBACK=%s", writeback_output_file)) begin
            $display("Using writeback output file: %s", writeback_output_file);
        end else begin
            $display("Using default writeback output file: writeback.out");
            writeback_output_file = "writeback.out";
        end
        // if ($value$plusargs("PIPELINE=%s", pipeline_output_file)) begin
        //     $display("Using pipeline output file: %s", pipeline_output_file);
        // end else begin
        //     $display("Using default pipeline output file: pipeline.out");
        //     pipeline_output_file = "pipeline.out";
        // end

        clock = 1'b0;
        reset = 1'b0;

        // Pulse the reset signal
        $display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
        reset = 1'b1;
        @(posedge clock);
        @(posedge clock);

        // store the compiled program's hex data into memory
        $readmemh(program_memory_file, memory.unified_memory);

        @(posedge clock);
        @(posedge clock);
        #1;
        // This reset is at an odd time to avoid the pos & neg clock edges

        reset = 1'b0;
        $display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);

        wb_fileno = $fopen(writeback_output_file);

        // Open the pipeline output file after throwing reset
        // open_pipeline_output_file(pipeline_output_file);
        // print_header("removed for line length");
    end

    // Count the number of posedges and number of instructions completed
    // till simulation ends
    always @(posedge clock) begin
        if(reset) begin
            clock_count <= 0;
            instr_count <= 0;
        end else begin
            clock_count <= (clock_count + 1);
            instr_count <= (instr_count + pipeline_completed_insts);
        end
    end

    always @(negedge clock) begin
        if(reset) begin
            $display("@@\n@@  %t : System STILL at reset, can't show anything\n@@",
                     $realtime);
            debug_counter <= 0;
        end else begin
            #2;

            // print register write information to the writeback output file
            if (pipeline_completed_insts > 0) begin
                if(pipeline_commit_wr_en)
                    $fdisplay(wb_fileno, "PC=%x, REG[%d]=%x",
                              pipeline_commit_NPC - 4,
                              pipeline_commit_wr_idx,
                              pipeline_commit_wr_data);
                else
                    $fdisplay(wb_fileno, "PC=%x, ---", pipeline_commit_NPC - 4);
            end

            // deal with any halting conditions
            if(pipeline_error_status != NO_ERROR || debug_counter > 500000) begin
                // print_regs;
                // print_sx;
                // print_mem;
                // print_xc;

                $display("@@@ Unified Memory contents hex on left, decimal on right: ");
                show_mem_with_decimal(0,`MEM_64BIT_LINES - 1);
                // 8Bytes per line, 16kB total

                $display("@@  %t : System halted\n@@", $realtime);

                case(pipeline_error_status)
                    LOAD_ACCESS_FAULT:
                        $display("@@@ System halted on memory error");
                    HALTED_ON_WFI:
                        $display("@@@ System halted on WFI instruction");
                    ILLEGAL_INST:
                        $display("@@@ System halted on illegal instruction");
                    default:
                        $display("@@@ System halted on unknown error code %x",
                            pipeline_error_status);
                endcase
                $display("@@@\n@@");
                show_clk_count;
                // print_close(); // close the pipe_print output file
                $fclose(wb_fileno);
                #100;
                $finish;
            end
            debug_counter <= debug_counter + 1;
        end // if(reset)
    end

endmodule // testbench
