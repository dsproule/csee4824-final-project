/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  vtuber_test.sv                                      //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline        //
//                 for the VisUal TestBencheR                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

extern void initcurses(int,int,int,int,int,int,int,int, int, int); //count = 10
extern void flushpipe();
extern void waitforresponse();
extern void initmem();
extern int get_instr_at_pc(int);
extern int not_valid_pc(int);

int slot = 0;

module testbench;
    // used to parameterize which file is loaded into memory
    // "./vis_simv" still just uses program.mem
    // but now "./simv +MEMORY=<my_program>.mem" loads <my_program>.mem instead
    string program_memory_file;

    // Registers and wires used in the testbench
    logic        clock;
    logic        reset;
    logic [31:0] clock_count;
    logic [31:0] instr_count;
    int          wb_fileno;
    logic [63:0] debug_counter; // counter used for when pipeline infinite loops, forces termination

    logic [1:0]       proc2mem_command;
    logic [`XLEN-1:0] proc2mem_addr;
    logic [63:0]      proc2mem_data;
    logic [3:0]       mem2proc_response;
    logic [63:0]      mem2proc_data;
    logic [3:0]       mem2proc_tag;

    IF_ID_PACKET            IF_ID_reg_dbg;
    RS_ENTRY [`RS_SZ-1:0] rs_table_dbg;
    CDB cdb_dbg;
    logic [`RS_SZ-1:0] busy_dbg;
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out_dbg;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out_dbg;
    ROB_T rob_head_dbg, rob_tail_dbg, retire_T_wire_dbg;
    D_S_PACKET              D_S_reg_dbg;
    X_C_PACKET [`RS_SZ-1:0] X_C_regs_dbg;
    S_X_PACKET [`RS_SZ-1:0] S_X_regs_dbg;
    LQ_ENTRY [`LQ_SZ-1:0] lq_dbg;
    SQ_ENTRY [`SQ_SZ-1:0] sq_dbg;

`ifndef CACHE_MODE
    MEM_SIZE          proc2mem_size;
`endif

    logic [3:0]       pipeline_completed_insts;
    EXCEPTION_CODE    pipeline_error_status;
    logic [4:0]       pipeline_commit_wr_idx;
    logic [`XLEN-1:0] pipeline_commit_wr_data;
    logic             pipeline_commit_wr_en;
    logic [`XLEN-1:0] pipeline_commit_NPC;
    

    // Instantiate the Pipeline
    pipeline pipeline_0 (
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
        .proc2mem_size    (proc2mem_size),

        .pipeline_completed_insts (pipeline_completed_insts),
        .pipeline_error_status    (pipeline_error_status),
        .pipeline_commit_wr_data  (pipeline_commit_wr_data),
        .pipeline_commit_wr_idx   (pipeline_commit_wr_idx),
        .pipeline_commit_wr_en    (pipeline_commit_wr_en),
        .pipeline_commit_NPC      (pipeline_commit_NPC),

        .IF_ID_reg_dbg(IF_ID_reg_dbg),
        .rs_table_dbg   (rs_table_dbg),
        .cdb_dbg        (cdb_dbg),
        .busy_dbg       (busy_dbg),
        .mt_table_out_dbg   (mt_table_out_dbg),
        .rob_table_out_dbg  (rob_table_out_dbg),
        .rob_head_dbg (rob_head_dbg),
        .rob_tail_dbg (rob_tail_dbg),
        .rob_retire_dbg(rob_retire_dbg),
        .retire_T_wire_dbg(retire_T_wire_dbg),
        .D_S_reg_dbg(D_S_reg_dbg),
        .S_X_regs_dbg(S_X_regs_dbg),
        .X_C_regs_dbg(X_C_regs_dbg),
        .lq_dbg(lq_dbg),
        .sq_dbg(sq_dbg)
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


    // Count the number of posedges and number of instructions completed
    // till simulation ends
    always @(posedge clock) begin
        if (reset) begin
            clock_count <= 0;
            instr_count <= 0;
        end else begin
            clock_count <= (clock_count + 1);
            instr_count <= (instr_count + pipeline_completed_insts);
        end
    end


    initial begin
        clock = 0;
        reset = 0;

        // Call to initialize visual debugger
        // Note that after this, all stdout output goes to visual debugger
        // each argument is number of registers/signals for the group
        initcurses( // count = 10
            2,  // IF
            `RS_SZ,  // Reservation Station
            3,  // CDB
            32, // Map Table
            `ROB_SZ,  // ROB
            12, //D_S
            `RS_SZ, // X_C
            `RS_SZ, // S_X
            `SQ_SZ, // SQ
            `LQ_SZ // LQ
        );

        // Pulse the reset signal
        reset = 1'b1;
        @(posedge clock);
        @(posedge clock);

        // set paramterized strings, see comment at start of module
        if ($value$plusargs("MEMORY=%s", program_memory_file)) begin
            $display("Loading memory file: %s", program_memory_file);
        end else begin
            $display("Loading default memory file: program.mem");
            program_memory_file = "program.mem";
        end

        // Read program contents into memory array
        $readmemh(program_memory_file, memory.unified_memory);

        @(posedge clock);
        @(posedge clock);
        #1;
        // This reset is at an odd time to avoid the pos & neg clock edges
        reset = 1'b0;
    end


    always @(negedge clock) begin
        if (!reset) begin
            #2;

            // deal with any halting conditions
            if (pipeline_error_status!=NO_ERROR) begin
                #100
                $display("\nDONE\n");
                // waitforresponse();
                // flushpipe();
                $finish;
            end
        end
    end


    // This block is where we dump all of the signals that we care about to
    // the visual debugger.  Notice this happens at every clock edge.
    always @(clock) begin
        #2;

        // Dump clock and time onto stdout
        $display("c%h%7.0d",clock,clock_count);
        $display("t%8.0f",$time);
        $display("z%h",reset);

        // Dump interesting register/signal contents onto stdout
        // format is "<reg group prefix><name> <width in hex chars>:<data>"
        // Current register groups (and prefixes) are:
        // f: IF d: D_S r: RS b: CDB o: ROB Mt: Map Table 
        
        // IF/ID packet - prefix 'f'
        if (IF_ID_reg_dbg.valid) begin
            $display("fPC 8:%h", IF_ID_reg_dbg.PC);
            $display("finst 8:%h", IF_ID_reg_dbg.inst);
        end


        // Reservation Station signals (`RS_SZ) - prefix 'r'
        $display("rRS_busy 2:%h", busy_dbg);
        // Entries
        for (int i = 0; i < `RS_SZ; i++) begin
            if (busy_dbg[i]) begin
                $display("rRS%0d_T 2:%02h", i, rs_table_dbg[i].T);
                $display("rRS%0d_T1 2:%02h", i, rs_table_dbg[i].T1);
                $display("rRS%0d_T2 2:%02h", i, rs_table_dbg[i].T2);
                $display("rRS%0d_V1 2:%02h", i, rs_table_dbg[i].V1);
                $display("rRS%0d_V2 2:%02h", i, rs_table_dbg[i].V2);
                $display("rRS%0d_ready 1:%02h", i, rs_table_dbg[i].ready);
            end
        end


        // CDB - prefix 'b'
        // Show CDB state
        $display("bCDB_valid %h", cdb_dbg.valid);
        $display("bCDB_T %h", cdb_dbg.T);
        $display("bCDB_V %h", cdb_dbg.V);

        
        // Map - Table - prefix 'Mt'
        for (int i = 0; i < 32; i++) begin
            MT_ENTRY entry;
            entry = mt_table_out_dbg[i * $bits(MT_ENTRY) +: $bits(MT_ENTRY)];
            $display("tMT_entry %0d T:%4d plus:%1d", i, entry.T, entry.plus);
        end

        
        // ROB - prefix 'o'
        $display("ohead %h", rob_head_dbg);
        $display("otail %h", rob_tail_dbg);
        $display("oretire %h", rob_retire_dbg);
        // Entries
        for (int i = 1; i < `ROB_SZ; i++) begin
            ROB_ENTRY entry;
            entry = rob_table_out_dbg[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)];
            $display("oROB_entry:%0d %4d->   r:%4d  V:%4d  ready:%1d", i, i, entry.r, entry.V, entry.ready);
                    
        end


        // D_S packet - prefix 'd'
        if (D_S_reg_dbg.valid) begin
            $display("dINST %0h", D_S_reg_dbg.inst);
            $display("dPC   %0h", D_S_reg_dbg.PC);
            $display("dNPC  %0h", D_S_reg_dbg.NPC);
            $display("dsr    %0h", D_S_reg_dbg.r);
            $display("dpr1   %0h", D_S_reg_dbg.r1);
            $display("dqr2   %0h", D_S_reg_dbg.r2);
            $display("dopa  %0h", D_S_reg_dbg.opa_select);
            $display("dopb  %0h", D_S_reg_dbg.opb_select);
            $display("dbranch %b %b", D_S_reg_dbg.cond_branch, D_S_reg_dbg.uncond_branch);
            $display("dalu   %0h", D_S_reg_dbg.alu_func);
            $display("drsidx %0h", D_S_reg_dbg.rs_idx);
            $display("dflags %b %b %b %b", D_S_reg_dbg.halt, D_S_reg_dbg.illegal, D_S_reg_dbg.csr_op, D_S_reg_dbg.valid);
        end


        // X_C - prefix 'x'
        for (int i = 0; i < `RS_SZ; i++) begin
        X_C_PACKET xc;
        xc = X_C_regs_dbg[i];
        $display("xXC %0d %h %h %b", i, xc.T, xc.result, xc.valid);
        end

        // S_X - prefix 'y'
        for (int i = 0; i < `RS_SZ; i++) begin
        S_X_PACKET sx;
        sx = S_X_regs_dbg[i];
        $display("ySX %0d %h %8h %0h %0h %0h %b %b", i, sx.PC, sx.inst, sx.T, sx.V1, sx.V2, sx.halt, sx.valid);
        end

        // Store Queue — prefix 'q'
        for (int i = 0; i < `SQ_SZ; i++) begin
        if (sq_dbg[i].valid) begin
            $display( "qSQ %0d %b %0d %h %h %b", i, sq_dbg[i].valid, sq_dbg[i].T, sq_dbg[i].addr, sq_dbg[i].data, sq_dbg[i].addr_valid);
        end
        end

        // Load Queue — prefix 'l'
        for (int i = 0; i < `LQ_SZ; i++) begin
        if (lq_dbg[i].valid) begin
            $display( "lLQ %0d %b %0d %h %h %b %0d", i, lq_dbg[i].valid, lq_dbg[i].T, lq_dbg[i].addr, lq_dbg[i].data, lq_dbg[i].addr_valid, lq_dbg[i].state);
        end
        end


        // must come last
        $display("break");

        // This is a blocking call to allow the debugger to control when we
        // advance the simulation
        waitforresponse();
    end

endmodule // module testbench
