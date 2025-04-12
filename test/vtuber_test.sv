/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  vtuber_test.sv                                      //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline        //
//                 for the VisUal TestBencheR                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`include "verilog/sys_defs.svh"

extern void initcurses(int,int,int,int,int); //count = 5
extern void flushpipe();
extern void waitforresponse();
extern void initmem();
extern int get_instr_at_pc(int);
extern int not_valid_pc(int);

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

    RS_ENTRY [`RS_SZ-1:0] rs_table_dbg;
    CDB cdb_dbg;
    logic [`RS_SZ-1:0] busy_dbg;
    logic [$bits(MT_ENTRY)*32-1:0] mt_table_out_dbg;
    logic [$bits(ROB_ENTRY)*`ROB_SZ-1:0] rob_table_out_dbg;
    ROB_T rob_head_dbg, rob_tail_dbg, retire_T_wire_dbg;
    PPLN_CTRL rob_pipeline_control_dbg;

`ifndef CACHE_MODE
    MEM_SIZE          proc2mem_size;
`endif

    logic [3:0]       pipeline_completed_insts;
    EXCEPTION_CODE    pipeline_error_status;
    logic [4:0]       pipeline_commit_wr_idx;
    logic [`XLEN-1:0] pipeline_commit_wr_data;
    logic             pipeline_commit_wr_en;
    logic [`XLEN-1:0] pipeline_commit_NPC;
    

    // logic [`XLEN-1:0] if_NPC_dbg;
    // logic [31:0]      if_inst_dbg;
    // logic             if_valid_dbg;

    


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

        // .if_NPC_dbg       (if_NPC_dbg),
        // .if_inst_dbg      (if_inst_dbg),
        // .if_valid_dbg     (if_valid_dbg),

        .rs_table_dbg   (rs_table_dbg),
        .cdb_dbg        (cdb_dbg),
        .busy_dbg       (busy_dbg),
        .mt_table_out_dbg   (mt_table_out_dbg),
        .rob_table_out_dbg  (rob_table_out_dbg),
        .rob_head_dbg (rob_head_dbg),
        .rob_tail_dbg (rob_tail_dbg),
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
        initcurses( // count = 5
            0,  // IF
            `RS_SZ,  // Reservation Station
            3,  // CDB
            32, // Map Table
            `ROB_SZ  // ROB
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

       // Dump register file contents
        // $write("a");
        // for(int i = 0; i < 32; i=i+1) begin
        //     $write("%h", pipeline_0.stage_id_0.regfile_0.registers[i]);
        // end
        // $display("");

        // // Dump instructions and their validity for each stage
        // $write("p");
        // $write("%h%h%h%h%h%h%h%h%h%h ",
        //        if_inst_dbg,      if_valid_dbg,
        //        if_id_inst_dbg,   if_id_valid_dbg,
        //        id_ex_inst_dbg,   id_ex_valid_dbg,
        //        ex_mem_inst_dbg,  ex_mem_valid_dbg,
        //        mem_wb_inst_dbg,  mem_wb_valid_dbg);
        // $display("");

        // Dump interesting register/signal contents onto stdout
        // format is "<reg group prefix><name> <width in hex chars>:<data>"
        // Current register groups (and prefixes) are:
        // f: IF  r: RS b: CDB o: ROB Mt: Map Table

        // // IF signals (5) - prefix 'f'
        // $display("fNPC 8:%h",         pipeline_0.if_packet.NPC);
        // $display("finst 8:%h",        pipeline_0.if_packet.inst);
        // $display("fImem_addr 8:%h",   pipeline_0.stage_if_0.proc2Imem_addr);
        // $display("fPC_reg 8:%h",      pipeline_0.stage_if_0.PC_reg);
        // $display("fvalid 1:%h",       pipeline_0.if_packet.valid);
        // // haven't updated VTUBER to use rd_unsigned yet
        // $display("imem_size 1:%h",    {pipeline_0.ex_mem_reg.rd_unsigned, pipeline_0.ex_mem_reg.mem_size});


        // ROB - prefix 'o'
        $display("ohead %h", rob_head_dbg);
        $display("otail %h", rob_tail_dbg);
        
        for (int i = 1; i < `ROB_SZ; i++) begin
            ROB_ENTRY entry;
            entry = rob_table_out_dbg[i * $bits(ROB_ENTRY) +: $bits(ROB_ENTRY)];
            // $display("oROB_entry:%0d idx:%4d   r:%4d   V:%4d   retire:%1b   retire_T:%4d   flush:%1b   write_data:%8h",
            //                 i, i, entry.r, entry.V, rob_retire_dbg, retire_T_wire_dbg, rob_pipeline_control_dbg.flush, pipeline_0.rob_write_data);
            $display("oROB_entry:%0d idx:%4d   r:%4d   V:%4d", i, i, entry.r, entry.V);
                    
        end


        // Map - Table 'Mt'

        for (int i = 0; i < 32; i++) begin
            MT_ENTRY entry;
            entry = mt_table_out_dbg[i * $bits(MT_ENTRY) +: $bits(MT_ENTRY)];
            $display("tMT_entry %0d T:%4d plus:%1d", i, entry.T, entry.plus);
        end

        // CDB - prefix 'b'
        // Show CDB state
        $display("bCDB_valid :%h", cdb_dbg.valid);
        $display("bCDB_T :%h", cdb_dbg.T);
        $display("bCDB_V :%h", cdb_dbg.V);


        // Reservation Station signals (`RS_SZ) - prefix 'r'

        $display("rRS_busy 2:%h", busy_dbg);

        // Show key info for busy entries
        for (int i = 0; i < `RS_SZ; i++) begin
            if (busy_dbg[i]) begin
                $display("rRS%0d_T 2:%02h", i, rs_table_dbg[i].T);
                $display("rRS%0d_T1 2:%02h", i, rs_table_dbg[i].T1);
                $display("rRS%0d_T2 2:%02h", i, rs_table_dbg[i].T2);
                $display("rRS%0d_ready 1:%02h", i, rs_table_dbg[i].ready);
            end
        end

        // must come last
        $display("break");

        // This is a blocking call to allow the debugger to control when we
        // advance the simulation
        waitforresponse();
    end

endmodule // module testbench
