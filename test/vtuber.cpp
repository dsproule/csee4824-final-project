#include "DirectC.h"
#include <curses.h>
#include <stdio.h>
#include <signal.h>
#include <ctype.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <string.h>

#include "riscv_inst.h"

#define PARENT_READ     readpipe[0]
#define CHILD_WRITE     readpipe[1]
#define CHILD_READ      writepipe[0]
#define PARENT_WRITE    writepipe[1]
#define NUM_HISTORY     256
#define NUM_ARF         32
#define NUM_STAGES      5
#define NOOP_INST       0x00000013
#define NUM_REG_GROUPS  4
#define REG_SIZE_IN_HEX 8

// random variables/stuff
int fd[2], writepipe[2], readpipe[2];
int stdout_save;
int stdout_open;
void signal_handler_IO (int status);
int wait_flag=0;
char done_state;
char echo_data;
FILE *fp;
FILE *fp2;
int setup_registers = 0;
int stop_time;
int done_time = -1;
char time_wrapped = 0;

// Structs to hold information about each register/signal group
typedef struct win_info {
    int height;
    int width;
    int starty;
    int startx;
    int color;
} win_info_t;

typedef struct reg_group {
    WINDOW *reg_win;
    char ***reg_contents;
    char **reg_names;
    int num_regs;
    win_info_t reg_win_info;
} reg_group_t;

// Window pointers for ncurses windows
WINDOW *title_win;
WINDOW *comment_win;
WINDOW *time_win;
WINDOW *sim_time_win;
WINDOW *instr_win;
WINDOW *clock_win;
WINDOW *pipe_win;
WINDOW *if_win;
WINDOW *vtuber_win;
WINDOW *rs_win; //changed
WINDOW *cdb_win; // changed
WINDOW *rob_win; // changed
WINDOW *mt_win; // changed

// arrays for register contents and names
int history_num=0;
int num_if_regs = 0;

int num_rs_regs = 0;
int num_cdb_regs = 0;
int num_rob_regs = 0;
int num_mt_regs = 0;

char readbuffer[1024];
char **timebuffer;
char **cycles;
char *clocks;
char *resets;
char **inst_contents;
char ***if_contents;

char ***rs_contents;   // Reservation Station
char ***cdb_contents;  // Common Data Bus
char ***rob_contents;  // Reorder Buffer
char ***mt_contents;   // Map Table
char **if_reg_names;
char **rs_reg_names; //changed 
char **cdb_reg_names; // changed 
char **rob_reg_names; // changed 
char **mt_reg_names; // changed

char *get_opcode_str(int inst, int valid_inst);
void parse_register(char* readbuf, int reg_num, char*** contents, char** reg_names);
int get_time();

int rs_width = 60;               // Width of the RS window
int rs_height = 12;              // Height for the RS window (make sure this is enough to fit all your entries)

// Helper function for ncurses gui setup
WINDOW *create_newwin(int height, int width, int starty, int startx, int color) {
    WINDOW *local_win;
    local_win = newwin(height, width, starty, startx);
    wbkgd(local_win,COLOR_PAIR(color));
    wattron(local_win,COLOR_PAIR(color));
    box(local_win,0,0);
    wrefresh(local_win);
    return local_win;
}

// Function to draw positive edge or negative edge in clock window
void update_clock(char clock_val) {
    static char cur_clock_val = 0;
    // Adding extra check on cycles because:
    //  - if the user, right at the beginning of the simulation, jumps to a new
    //    time right after a negative clock edge, the clock won't be drawn
    if ((clock_val != cur_clock_val) || strncmp(cycles[history_num],"      0",7) == 1) {
        mvwaddch(clock_win,3,7,ACS_VLINE | A_BOLD);
        if (clock_val == 1) {

            // we have a posedge
            mvwaddch(clock_win,2,1,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,ACS_ULCORNER | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            mvwaddch(clock_win,4,1,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_LRCORNER | A_BOLD);
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
        } else {

            // we have a negedge
            mvwaddch(clock_win,4,1,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,ACS_LLCORNER | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            mvwaddch(clock_win,2,1,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_HLINE | A_BOLD);
            waddch(clock_win,ACS_URCORNER | A_BOLD);
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
            waddch(clock_win,' ');
        }
    }
    cur_clock_val = clock_val;
    wrefresh(clock_win);
}

// Function to create and initialize the gui

void setup_gui(FILE *fp, int rs_regs) {
    initscr();
    if (has_colors()) {
        start_color();
        init_pair(1,COLOR_CYAN,COLOR_BLACK);    // shell background
        init_pair(2,COLOR_YELLOW,COLOR_RED);
        init_pair(3,COLOR_RED,COLOR_BLACK);
        init_pair(4,COLOR_YELLOW,COLOR_BLUE);   // title window
        init_pair(5,COLOR_YELLOW,COLOR_BLACK);  // register/signal windows
        init_pair(6,COLOR_RED,COLOR_BLACK);
        init_pair(7,COLOR_MAGENTA,COLOR_BLACK); // pipeline window
        init_pair(8,COLOR_BLUE, COLOR_BLACK);
    }
    curs_set(0);
    noecho();
    cbreak();
    keypad(stdscr,TRUE);
    wbkgd(stdscr,COLOR_PAIR(1));
    wrefresh(stdscr);
    int pipe_width=0;

    // instantiate the title window at top of screen
    title_win = create_newwin(3,COLS,0,0,4);
    mvwprintw(title_win,1,1,"SIMULATION INTERFACE V1");
    mvwprintw(title_win,1,COLS-22,"BEN KEMPKE/JOSH SMITH");
    wrefresh(title_win);

    // instantiate time window at right hand side of screen
    time_win = create_newwin(3,15,LINES- 37,COLS-15,5);
    mvwprintw(time_win,0,3,"TIME");
    wrefresh(time_win);

    // instantiate a sim time window which states the actual simlator time
    sim_time_win = create_newwin(3,15,LINES- 34,COLS-15,5);
    mvwprintw(sim_time_win,0,1,"SIM TIME");
    wrefresh(sim_time_win);

    // instantiate a window to show which clock edge this is
    clock_win = create_newwin(6,15,LINES- 37,COLS-30,5);
    mvwprintw(clock_win,0,5,"CLOCK");
    mvwprintw(clock_win,1,1,"cycle:");
    update_clock(0);
    wrefresh(clock_win);

    // instantiate window to visualize IF stage (including IF/ID)
    if_win = create_newwin((num_if_regs+2),30,LINES- 37,53,5);
    mvwprintw(if_win,0,10,"IF STAGE");
    wrefresh(if_win);

    // instantiate a window to visualize Reservation Station //changed

    int rs_starty = LINES - 30;  
    int rs_startx = 53;   
    rs_win = create_newwin(rs_height, rs_width, rs_starty, rs_startx, 1); 

    mvwprintw(rs_win, 0, (rs_width - 4) / 2, "RS");
    wrefresh(rs_win);  

    // instantiate a window to visualize CDB
    int cdb_width = 20; 
    int cdb_starty = LINES- 30; 
    int cdb_startx = 115;

    cdb_win = create_newwin(7, cdb_width, cdb_starty, cdb_startx, 5);
    mvwprintw(cdb_win, 0, (cdb_width - 4) / 2, "CDB");
    wrefresh(cdb_win);

    // instantiate a window to visualize ROB
    int rob_width = 50; 
    int rob_starty = LINES- 37; 
    int rob_startx = 0;

    rob_win = create_newwin(36, rob_width, rob_starty, rob_startx, 5);
    mvwprintw(rob_win, 0, (rob_width - 4) / 2, "ROB");
    wrefresh(rob_win);

    // instantiate a window to visualize Map Table
    int mt_width = 35; 
    int mt_starty = LINES- 17; 
    int mt_startx = 53;

    mt_win = create_newwin(10, mt_width, mt_starty, mt_startx, 5);
    mvwprintw(mt_win, 0, (mt_width - 8) / 2, "Map Table");
    wrefresh(mt_win);


    // instantiate an instructional window to help out the user some
    instr_win = create_newwin(7,30,LINES-17,COLS-30,5);
    mvwprintw(instr_win,0,9,"INSTRUCTIONS");
    wattron(instr_win,COLOR_PAIR(5));
    mvwaddstr(instr_win,1,1,"'n'   -> Next clock edge");
    mvwaddstr(instr_win,2,1,"'b'   -> Previous clock edge");
    mvwaddstr(instr_win,3,1,"'c/g' -> Goto specified time");
    mvwaddstr(instr_win,4,1,"'r'   -> Run to end of sim");
    mvwaddstr(instr_win,5,1,"'q'   -> Quit Simulator");
    wrefresh(instr_win);

    vtuber_win = create_newwin(10, 47, LINES-10, COLS-47, 8);
    mvwaddstr(vtuber_win, 2, 4, "__     _______ _   _ ____  _____ ____");
    mvwaddstr(vtuber_win, 3, 4, "\\ \\   / /_   _| | | | __ )| ____|  _ \\");
    mvwaddstr(vtuber_win, 4, 4, " \\ \\ / /  | | | | | |  _ \\|  _| | |_) |");
    mvwaddstr(vtuber_win, 5, 4, "  \\ V /   | | | |_| | |_) | |___|  _ <");
    mvwaddstr(vtuber_win, 6, 4, "   \\_/    |_|  \\___/|____/|_____|_| \\_\\");
    wrefresh(vtuber_win);

    refresh();
}

// This function updates all of the signals being displayed with the values
// from time history_num_in (this is the index into all of the data arrays).
// If the value changed from what was previously display, the signal has its
// display color inverted to make it pop out.
void parsedata(int history_num_in) {
    static int old_history_num_in=0;
    static int old_head_position=0;
    static int old_tail_position=0;
    int i=0;
    int data_counter=0;
    char *opcode;
    int tmp=0;
    int tmp_val=0;
    char tmp_buf[32];
    int pipe_width = COLS/6;

    // Handle updating resets
    if (resets[history_num_in]) {
        wattron(title_win,A_REVERSE);
        mvwprintw(title_win,1,(COLS/2)-3,"RESET");
        wattroff(title_win,A_REVERSE);
    }
    else if (done_time != 0 && (history_num_in == done_time)) {
        wattron(title_win,A_REVERSE);
        mvwprintw(title_win,1,(COLS/2)-3,"DONE ");
        wattroff(title_win,A_REVERSE);
    }
    else
        mvwprintw(title_win,1,(COLS/2)-3,"     ");
    wrefresh(title_win);

    // Handle updating the pipeline window
    for (i=0; i < NUM_STAGES; i++) {
        strncpy(tmp_buf,inst_contents[history_num_in]+i*9,8);
        tmp_buf[9] = '\0';
        sscanf(tmp_buf,"%8x", &tmp_val);
        tmp = (int)inst_contents[history_num_in][8+(i*9)] - (int)'0';
        opcode = get_opcode_str(tmp_val, tmp);

        // clear string and overwrite
        mvwprintw(pipe_win,2,pipe_width*(i+1)-2-5,"          ");
        if (strncmp(tmp_buf,"xxxxxxxx",8) == 0)
            mvwaddnstr(pipe_win,2,pipe_width*(i+1)-2-4,tmp_buf,8);
        else
            mvwaddstr(pipe_win,2,pipe_width*(i+1)-2-(strlen(opcode)/2),opcode);
        if (tmp==0 || tmp==((int)'x'-(int)'0'))
            mvwprintw(pipe_win,3,pipe_width*(i+1)-2,"I");
        else
            mvwprintw(pipe_win,3,pipe_width*(i+1)-2,"V");

    }
    wrefresh(pipe_win);

    // Handle updating the IF window
    for (i=0;i<num_if_regs;i++) {
        if (strcmp(if_contents[history_num_in][i],
                if_contents[old_history_num_in][i]))
            wattron(if_win, A_REVERSE);
        else
            wattroff(if_win, A_REVERSE);
        mvwaddstr(if_win,i+1,strlen(if_reg_names[i])+3,if_contents[history_num_in][i]);
    }
    wrefresh(if_win);

    // update the time window
    mvwprintw(time_win, 1, 1, "%s", timebuffer[history_num_in]);
    wrefresh(time_win);
    
    // update the cycle count in the clock window
    mvwprintw(clock_win, 1, 1, "%s", cycles[history_num_in]);
    update_clock(clocks[history_num_in]);
    wrefresh(clock_win);
        
    // save the old history index to check for changes later
    old_history_num_in = history_num_in;
}

// Parse a line of data output from the testbench
int processinput() {
    static int byte_num = 0;
    static int if_reg_num = 0;

    int tmp_len;
    char name_buf[32];
    char val_buf[32];

    // get rid of newline character
    readbuffer[strlen(readbuffer)-1] = 0;

    
    if (strncmp(readbuffer, "bCDB_valid", 10) == 0) {
        char valid_val[8];
        sscanf(readbuffer, "bCDB_valid %s", valid_val);
        mvwprintw(cdb_win, 1, 1, "Valid: %s", valid_val);
        wrefresh(cdb_win);
        return 0;
    } else if (strncmp(readbuffer, "bCDB_T", 6) == 0) {
        char t_val[32];
        sscanf(readbuffer, "bCDB_T %s", t_val);
        mvwprintw(cdb_win, 2, 1, "Tag: %s", t_val);
        wrefresh(cdb_win);
        return 0;
    } else if (strncmp(readbuffer, "bCDB_V", 6) == 0) {
        char v_val[32];
        sscanf(readbuffer, "bCDB_V %s", v_val);
        mvwprintw(cdb_win, 3, 1, "Value: %s", v_val);
        wrefresh(cdb_win);
        return 0;
    } else if (strncmp(readbuffer, "tMT_out_dbg", 11) == 0) {
        // Process Map Table signals: here we assume you print either the entire table or individual fields.
        char mt_out[256];
        int index, tag, plus, valid;

        sscanf(readbuffer, "tMT_out_dbg %s", mt_out);
        mvwprintw(mt_win, 1, 1, "MT: %.32s", mt_out);
        mvwprintw(mt_win, 2, 1, "    %.32s", mt_out + 32);
        wrefresh(mt_win);
        return 0;
    } else if (strncmp(readbuffer, "rRS", 3) == 0) {
        // Process Reservation Station data
        int rs_index;
        char field[8];
        char value[32];
    
        // Check if it's the busy status first
        if (strncmp(readbuffer, "rRS_busy", 8) == 0) {
            int scanned = sscanf(readbuffer, "rRS_busy %*d:%s", value);
            if (scanned == 1) {
                // Display the busy status at the top of the RS window
                mvwprintw(rs_win, 0, 5, "Busy: %s", value);
                wrefresh(rs_win);
            } else {
                printf("Error parsing busy input: %s\n", readbuffer);
            }
        } 
        // Otherwise parse individual RS entries
        else {
            // Format is rRS0_T 2:02, rRS0_T1 2:00, etc.
            int scanned = sscanf(readbuffer, "rRS%d_%[^' '] %*d:%s", &rs_index, field, value);
            if (scanned == 3) {
                // Calculate row based on RS index (one entry per row)
                int row = rs_index + 2;  // Start at row 1 (row 0 is for headers/busy status)
                
                // Format with proper column positioning based on field type
                if (strcmp(field, "T") == 0) {
                    mvwprintw(rs_win, row, 2, "RS%d: T=%-4s", rs_index, value);
                } else if (strcmp(field, "T1") == 0) {
                    mvwprintw(rs_win, row, 12, "T1=%-4s", value);
                } else if (strcmp(field, "T2") == 0) {
                    mvwprintw(rs_win, row, 22, "T2=%-4s", value);
                } else if (strcmp(field, "ready") == 0) {
                    mvwprintw(rs_win, row, 32, "Ready=%-4s", value);
                }
            } else {
                printf("Error parsing RS entry: %s\n", readbuffer);
            }
        }
        wrefresh(rs_win);
    } else if (strncmp(readbuffer,"t",1) == 0) {

        // We are getting the timestamp
        strcpy(timebuffer[history_num],readbuffer+1);
        return 0;
    } else if (strncmp(readbuffer,"c",1) == 0) {

        // We have a clock edge/cycle count signal
        if (strncmp(readbuffer+1,"0",1) == 0)
            clocks[history_num] = 0;
        else
            clocks[history_num] = 1;

        // grab clock count (for some reason, first clock count sent is
        // too many digits, so check for this)
        strncpy(cycles[history_num],readbuffer+2,7);
        if (strncmp(cycles[history_num],"       ",7) == 0)
            cycles[history_num][6] = '0';

    } else if (strncmp(readbuffer,"z",1) == 0) {

        // we have a reset signal
        if (strncmp(readbuffer+1,"0",1) == 0)
            resets[history_num] = 0;
        else
            resets[history_num] = 1;
    } else if (strncmp(readbuffer,"p",1) == 0) {
        // We are getting information about which instructions are in each stage
        strcpy(inst_contents[history_num], readbuffer+1);

    } else if (strncmp(readbuffer,"f",1) == 0) {
        // We are getting an IF register

        // If this is the first time we've seen the register,
        // add name and data to arrays
        if (!setup_registers) {
            parse_register(readbuffer, if_reg_num, if_contents, if_reg_names);
            mvwaddstr(if_win,if_reg_num+1,1,if_reg_names[if_reg_num]);
            waddstr(if_win, ": ");
            wrefresh(if_win);
        } else {
            sscanf(readbuffer,"%*c%s %d:%s",name_buf,&tmp_len,val_buf);
            strcpy(if_contents[history_num][if_reg_num],val_buf);
        }

        if_reg_num++;
    } else if (strncmp(readbuffer, "ohead", 5) == 0) {
            char head_val[32];
            sscanf(readbuffer, "ohead %s", head_val);
            // Update ROB window header for head pointer (for example, row 1)
            mvwprintw(rob_win, 1, 1, "Head: %s", head_val);
            wrefresh(rob_win);
            return 0;
    } else if (strncmp(readbuffer, "otail", 5) == 0) {
            char tail_val[32];
            sscanf(readbuffer, "otail %s", tail_val);
            // Update ROB window header for tail pointer (for example, row 2)
            mvwprintw(rob_win, 2, 1, "Tail: %s", tail_val);
            wrefresh(rob_win);
            return 0;
    } else if (strncmp(readbuffer, "oROB", 4) == 0) {
            int idx;
            char rob_entry[64];
            sscanf(readbuffer, "oROB[%d] %s", &idx, rob_entry);
            // Assume row offset 3 for entries (row = idx+3)
            mvwprintw(rob_win, idx + 3, 1, "Entry %d: %s", idx, rob_entry);
            wrefresh(rob_win);
            return 0;
    } else if (strncmp(readbuffer,"break",4) == 0) {
        // If this is the first time through, indicate that we've setup all of
        // the register arrays.
        setup_registers = 1;

        // we've received our last data segment, now go process it
        byte_num = 0;
        if_reg_num = 0;

        // update the simulator time, this won't change with 'b's
        mvwaddstr(sim_time_win,1,1,timebuffer[history_num]);
        wrefresh(sim_time_win);

        // tell the parent application we're ready to move on
        return(1);
    }
    return(0);
}

// extern "C" void initcurses(int if_regs, int if_id_regs, int id_regs, int id_ex_regs, int ex_regs,
//     int ex_mem_regs, int mem_regs, int mem_wb_regs, int wb_regs,
//     int misc_regs, int rs_regs, int cdb_regs, int mt_regs, int rob_regs) { // count =14

// this initializes a ncurses window and sets up the arrays for exchanging reg information
extern "C" void initcurses(int if_regs, int rs_regs, int cdb_regs, int mt_regs, int rob_regs) { // count = 5
    int nbytes;
    int ready_val;

    done_state = 0;
    echo_data = 1;
    num_if_regs = if_regs;

    num_rs_regs = rs_regs;
    num_cdb_regs = cdb_regs;
    num_mt_regs = mt_regs;
    num_rob_regs = rob_regs;

    pid_t childpid;
    pipe(readpipe);
    pipe(writepipe);
    stdout_save = dup(1);
    childpid = fork();
    if (childpid == 0) {
        close(PARENT_WRITE);
        close(PARENT_READ);
        fp = fdopen(CHILD_READ, "r");
        fp2 = fopen("program.out","w");

        // allocate room on the heap for the reg data
        inst_contents     = (char**) malloc(NUM_HISTORY*sizeof(char*));
        // arf_contents      = (char**) malloc(NUM_HISTORY*sizeof(char*));
        int i=0;
        if_contents       = (char***) malloc(NUM_HISTORY*sizeof(char**));
  
        rs_contents = (char***)malloc(NUM_HISTORY * sizeof(char**));
        cdb_contents = (char***)malloc(NUM_HISTORY * sizeof(char**));
        mt_contents = (char***)malloc(NUM_HISTORY * sizeof(char**));
        rob_contents = (char***)malloc(NUM_HISTORY * sizeof(char**));

        timebuffer        = (char**) malloc(NUM_HISTORY*sizeof(char*));
        cycles            = (char**) malloc(NUM_HISTORY*sizeof(char*));
        clocks            = (char*) malloc(NUM_HISTORY*sizeof(char));
        resets            = (char*) malloc(NUM_HISTORY*sizeof(char));

        // allocate room for the register names (what is displayed)
        if_reg_names      = (char**) malloc(num_if_regs*sizeof(char*));
        rs_reg_names = (char**) malloc(num_rs_regs*sizeof(char*));
        cdb_reg_names = (char**) malloc(num_cdb_regs*sizeof(char*));
        mt_reg_names = (char**) malloc(num_mt_regs*sizeof(char*));
        rob_reg_names =  (char**) malloc(num_rob_regs*sizeof(char*));

        int j=0;
        for (;i<NUM_HISTORY;i++) {
            timebuffer[i]       = (char*) malloc(8);
            cycles[i]           = (char*) malloc(7);
            inst_contents[i]    = (char*) malloc(NUM_STAGES*10);
            if_contents[i]      = (char**) malloc(num_if_regs*sizeof(char*));
            rs_contents[i]   = (char**) malloc(rs_regs * sizeof(char*));
            cdb_contents[i]  = (char**) malloc(cdb_regs * sizeof(char*));
            mt_contents[i]   = (char**) malloc(mt_regs * sizeof(char*));
            rob_contents[i]  = (char**) malloc(rob_regs * sizeof(char*));
        }
        setup_gui(fp, rs_regs);

        // Main loop for retrieving data and taking commands from user
        char quit_flag = 0;
        char resp=0;
        char running=0;
        int mem_addr=0;
        char goto_flag = 0;
        char cycle_flag = 0;
        char done_received = 0;
        memset(readbuffer,'\0',sizeof(readbuffer));
        while (!quit_flag) {
            if (!done_received) {
                fgets(readbuffer, sizeof(readbuffer), fp);
                ready_val = processinput();
            }
            if (strcmp(readbuffer,"DONE") == 0) {
                done_received = 1;
                done_time = history_num - 1;
            }
            if (ready_val == 1 || done_received == 1) {
                if (echo_data == 0 && done_received == 1) {
                    running = 0;
                    timeout(-1);
                    echo_data = 1;
                    history_num--;
                    history_num%=NUM_HISTORY;
                }
                if (echo_data != 0) {
                    parsedata(history_num);
                }
                history_num++;
                // keep track of whether time wrapped around yet
                if (history_num == NUM_HISTORY)
                    time_wrapped = 1;
                history_num%=NUM_HISTORY;

                // we're done reading the reg values for this iteration
                if (done_received != 1) {
                    write(CHILD_WRITE, "n", 1);
                    write(CHILD_WRITE, &mem_addr, 2);
                }
                char continue_flag = 0;
                int hist_num_temp = (history_num-1)%NUM_HISTORY;
                if (history_num==0) hist_num_temp = NUM_HISTORY-1;
                char echo_data_tmp,continue_flag_tmp;

                while (continue_flag == 0) {
                    resp=getch();
                    if (running == 1) {
                        continue_flag = 1;
                    }
                    if (running == 0 || resp == 'p') {
                        if (resp == 'n' && hist_num_temp == (history_num-1)%NUM_HISTORY) {
                            if (!done_received)
                                continue_flag = 1;
                        } else if (resp == 'n') {
                            // forward in time, but not up to present yet
                            hist_num_temp++;
                            hist_num_temp%=NUM_HISTORY;
                            parsedata(hist_num_temp);
                        } else if (resp == 'r') {
                            echo_data = 0;
                            running = 1;
                            timeout(0);
                            continue_flag = 1;
                        } else if (resp == 'p') {
                            echo_data = 1;
                            timeout(-1);
                            running = 0;
                            parsedata(hist_num_temp);
                        } else if (resp == 'q') {
                            // quit
                            continue_flag = 1;
                            quit_flag = 1;
                        } else if (resp == 'b') {
                            // We're goin BACK IN TIME, woohoo!
                            // Make sure not to wrap around to NUM_HISTORY-1 if we don't have valid
                            // data there (time_wrapped set to 1 when we wrap around to history 0)
                            if (hist_num_temp > 0) {
                                hist_num_temp--;
                                parsedata(hist_num_temp);
                            } else if (time_wrapped == 1) {
                                hist_num_temp = NUM_HISTORY-1;
                                parsedata(hist_num_temp);
                            }
                        } else if (resp == 'g' || resp == 'c') {
                            // See if user wants to jump to clock cycle instead of sim time
                            cycle_flag = (resp == 'c');

                            // go to specified simulation time (either in history or
                            // forward in simulation time).
                            stop_time = get_time();

                            // see if we already have that time in history
                            int tmp_time;
                            int cur_time;
                            int delta;
                            if (cycle_flag)
                                sscanf(cycles[hist_num_temp], "%u", &cur_time);
                            else
                                sscanf(timebuffer[hist_num_temp], "%u", &cur_time);
                            delta = (stop_time > cur_time) ? 1 : -1;
                            if ((hist_num_temp+delta)%NUM_HISTORY != history_num) {
                                tmp_time=hist_num_temp;
                                i= (hist_num_temp+delta >= 0) ? (hist_num_temp+delta)%NUM_HISTORY : NUM_HISTORY-1;
                                while (i!=history_num) {
                                    if (cycle_flag)
                                        sscanf(cycles[i], "%u", &cur_time);
                                    else
                                        sscanf(timebuffer[i], "%u", &cur_time);
                                    if ((delta == 1 && cur_time >= stop_time) ||
                                            (delta == -1 && cur_time <= stop_time)) {
                                        hist_num_temp = i;
                                        parsedata(hist_num_temp);
                                        stop_time = 0;
                                        break;
                                    }

                                    if ((i+delta) >=0)
                                        i = (i+delta)%NUM_HISTORY;
                                    else {
                                        if (time_wrapped == 1)
                                            i = NUM_HISTORY - 1;
                                        else {
                                            parsedata(hist_num_temp);
                                            stop_time = 0;
                                            break;
                                        }
                                    }
                                }
                            }

                            // If we looked backwards in history and didn't find stop_time
                            // then give up
                            if (i==history_num && (delta == -1 || done_received == 1))
                                stop_time = 0;

                            // Set flags so that we run forward in the simulation until
                            // it either ends, or we hit the desired time
                            if (stop_time > 0) {
                                // grab current values
                                echo_data = 0;
                                running = 1;
                                timeout(0);
                                continue_flag = 1;
                                goto_flag = 1;
                            }
                        }
                    }
                }
                // if we're instructed to goto specific time, see if we're there
                int cur_time=0;
                if (goto_flag==1) {
                    if (cycle_flag)
                        sscanf(cycles[hist_num_temp], "%u", &cur_time);
                    else
                        sscanf(timebuffer[hist_num_temp], "%u", &cur_time);
                    if ((cur_time >= stop_time) ||
                            (strcmp(readbuffer,"DONE")==0) ) {
                        goto_flag = 0;
                        echo_data = 1;
                        running = 0;
                        timeout(-1);
                        continue_flag = 0;
                        // parsedata(hist_num_temp);
                    }
                }
            }
        }
        refresh();
        delwin(title_win);
        endwin();
        fflush(stdout);
        if (resp == 'q') {
            fclose(fp2);
            write(CHILD_WRITE, "Z", 1);
            exit(0);
        }
        readbuffer[0] = 0;
        while (strncmp(readbuffer,"DONE",4) != 0) {
            if (fgets(readbuffer, sizeof(readbuffer), fp) != NULL)
                fputs(readbuffer, fp2);
        }
        fclose(fp2);
        fflush(stdout);
        write(CHILD_WRITE, "Z", 1);
        printf("Child Done Execution\n");
        exit(0);
    } else {
        close(CHILD_READ);
        close(CHILD_WRITE);
        dup2(PARENT_WRITE, 1);
        close(PARENT_WRITE);

    }
}


// Function to make testbench block until debugger is ready to proceed
extern "C" int waitforresponse() {
    static int mem_start = 0;
    char c=0;
    while (c!='n' && c!='Z') read(PARENT_READ,&c,1);
    if (c=='Z') exit(0);
    mem_start = read(PARENT_READ,&c,1);
    mem_start = mem_start << 8 + read(PARENT_READ,&c,1);
    return(mem_start);
}

extern "C" void flushpipe() {
    char c=0;
    read(PARENT_READ, &c, 1);
}

// Function to return string representation of opcode given inst encoding
char *get_opcode_str(int inst, int valid_inst)
{
    int opcode, check;
    char *str;

    if (valid_inst == ((int)'x' - (int)'0'))
        str = "-";
    else if (!valid_inst)
        str = "-";
    else if (inst==NOOP_INST)
        str = "nop";
    else {
        inst_t dummy_inst;
        dummy_inst.decode(inst);
        str = const_cast<char*>(dummy_inst.str); // due to legacy code..
    }

    return str;
}

// Function to parse register $display() from testbench and add to
// names/contents arrays
void parse_register(char *readbuf, int reg_num, char*** contents, char** reg_names) {
    char name_buf[32];
    char val_buf[32];
    int tmp_len;

    sscanf(readbuf,"%*c%s %d:%s",name_buf,&tmp_len,val_buf);
    int i=0;
    for (;i<NUM_HISTORY;i++) {
        contents[i][reg_num] = (char*) malloc((tmp_len+1)*sizeof(char));
    }
    strcpy(contents[history_num][reg_num],val_buf);
    reg_names[reg_num] = (char*) malloc((strlen(name_buf)+1)*sizeof(char));
    strncpy(reg_names[reg_num], readbuf+1, strlen(name_buf));
    reg_names[reg_num][strlen(name_buf)] = '\0';
}

// Ask user for simulation time to stop at
// Since the enter key isn't detected, user must press 'g' key
//  when finished entering a number.
int get_time() {
    int col = COLS/2-6;
    wattron(title_win,A_REVERSE);
    mvwprintw(title_win,1,col,"goto time: ");
    wrefresh(title_win);
    int resp=0;
    int ptr = 0;
    char buf[32];
    int i;

    resp=wgetch(title_win);
    while (resp != 'g' && resp != KEY_ENTER && resp != ERR && ptr < 6) {
        if (isdigit((char)resp)) {
            waddch(title_win,(char)resp);
            wrefresh(title_win);
            buf[ptr++] = (char)resp;
        }
        resp=wgetch(title_win);
    }

    // Clean up title window
    wattroff(title_win,A_REVERSE);
    mvwprintw(title_win,1,col,"           ");
    for (i=0;i<ptr;i++)
        waddch(title_win,' ');

    wrefresh(title_win);

    buf[ptr] = '\0';
    return atoi(buf);
}
