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
WINDOW *ds_win; //changed
WINDOW *vtuber_win;
WINDOW *rs_win; //changed
WINDOW *cdb_win; // changed
WINDOW *rob_win; // changed
WINDOW *mt_win; // changed

// arrays for register contents and names
int history_num=0;
int num_if_regs = 0;

int num_ds_regs = 0;
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

char ***ds_contents;   // D_S
char ***rs_contents;   // Reservation Station
char ***cdb_contents;  // Common Data Bus
char ***rob_contents;  // Reorder Buffer
char ***mt_contents;   // Map Table
char **if_reg_names;
char **ds_reg_names; //changed
char **rs_reg_names; //changed 
char **cdb_reg_names; // changed 
char **rob_reg_names; // changed 
char **mt_reg_names; // changed

char *get_opcode_str(int inst, int valid_inst);
void parse_register(char* readbuf, int reg_num, char*** contents, char** reg_names);
int get_time();

int rs_width = 63;               // Width of the RS window
int rs_height = 10;              // Height for the RS window 

char entry_text[80];


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

void setup_gui(FILE *fp, int rs_regs, int cdb_regs, int mt_regs, int rob_regs, int ds_regs) {
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

    int if_startx = 0;

    int ds_width = 40;
    int ds_height = ds_regs + 2;
    int ds_starty = LINES - 30;
    int ds_startx = 0;

    int rs_starty = ds_starty + ds_height + 2;  
    int rs_startx = 0;  

    int rob_width = 33; 
    int rob_height = rob_regs + 4;
    int rob_starty = LINES - 37; 
    int rob_startx = rs_startx + rs_width + 2;

    int cdb_width = 20; 
    int cdb_starty = LINES - 30; 
    int cdb_startx = rs_startx + rs_width - cdb_width -2;

    int mt_width = 30; 
    int mt_height = mt_regs + 4;
    int mt_starty = LINES - 37; 
    int mt_startx = rob_startx + rob_width + 2;

    // instantiate the title window at top of screen
    title_win = create_newwin(3,COLS,0,0,4);
    mvwprintw(title_win,1,1,"SIMULATION INTERFACE V1");
    mvwprintw(title_win,1,COLS-22,"BEN KEMPKE/JOSH SMITH");
    wrefresh(title_win);

    // instantiate time window at right hand side of screen
    time_win = create_newwin(3,15,LINES- 37,COLS-15,7);
    mvwprintw(time_win,0,3,"TIME");
    wrefresh(time_win);

    // instantiate a sim time window which states the actual simlator time
    sim_time_win = create_newwin(3,15,LINES- 34,COLS-15,7);
    mvwprintw(sim_time_win,0,1,"SIM TIME");
    wrefresh(sim_time_win);

    // instantiate a window to show which clock edge this is
    clock_win = create_newwin(6,15,LINES- 37,COLS-30,7);
    mvwprintw(clock_win,0,5,"CLOCK");
    mvwprintw(clock_win,1,1,"cycle:");
    update_clock(0);
    wrefresh(clock_win);

    // instantiate window to visualize IF stage (including IF/ID)
    if_win = create_newwin((num_if_regs+4),25,LINES- 37,if_startx, 3);
    mvwprintw(if_win,0,6,"IF STAGE");
    wrefresh(if_win);

    // instantiate window to visualize IF stage (including IF/ID)
    ds_win = create_newwin(ds_height,ds_width,ds_starty,ds_startx, 5);
    mvwprintw(ds_win, 0, (ds_width - 4) / 2, "D/S");
    wrefresh(ds_win);

    // instantiate a window to visualize Reservation Station //changed
    rs_win = create_newwin(rs_height, rs_width, rs_starty, rs_startx, 1); 
    mvwprintw(rs_win, 0, (rs_width - 4) / 2, "RS");
    wrefresh(rs_win);  

    // instantiate a window to visualize CDB
    cdb_win = create_newwin(7, cdb_width, cdb_starty, cdb_startx, 5);
    mvwprintw(cdb_win, 0, (cdb_width - 4) / 2, "CDB");
    wrefresh(cdb_win);

    // instantiate a window to visualize ROB
    rob_win = create_newwin(rob_height, rob_width, rob_starty, rob_startx, 1);
    mvwprintw(rob_win, 0, (rob_width - 4) / 2, "ROB");
    wrefresh(rob_win);

    // instantiate a window to visualize Map Table
    mt_win = create_newwin(mt_height, mt_width, mt_starty, mt_startx, 5);
    mvwprintw(mt_win, 0, (mt_width - 8) / 2, "Map Table");
    wrefresh(mt_win);

    // instantiate an instructional window to help out the user some
    instr_win = create_newwin(7,30,LINES-30,COLS-30,7);
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
    for (i = 0; i < num_if_regs; i++) {
        if (strcmp(if_contents[history_num_in][i], if_contents[old_history_num_in][i]))
            wattron(if_win, A_REVERSE);
        else
            wattroff(if_win, A_REVERSE);
    
        // Print "PC: " or "inst: " before the value depending on index
        if (i == 0) {
            mvwprintw(if_win, i + 1, 1, "PC:  %s", if_contents[history_num_in][i]);
        } else if (i == 1) {
            mvwprintw(if_win, i + 1, 1, "inst:  %s", if_contents[history_num_in][i]);
        } else {
            // fallback: print raw value if there's ever more
            mvwprintw(if_win, i + 1, 1, "%s", if_contents[history_num_in][i]);
        }
    }
    wattroff(if_win, A_REVERSE);  // safety: ensure reverse is offn
    wrefresh(if_win);

    // D_S window
    for (i = 0; i < num_ds_regs; i++) {
        if (strcmp(ds_contents[history_num_in][i],
                ds_contents[old_history_num_in][i]) != 0)
            wattron(ds_win, A_REVERSE);
        else
            wattroff(ds_win, A_REVERSE);

        if (i == 0) {
            mvwprintw(ds_win, i + 1, 1, "INST->  %s", ds_contents[history_num_in][i]);
        } else if (i == 1) {
            mvwprintw(ds_win, i + 1, 1, "PC->  %s", ds_contents[history_num_in][i]);
        } else if (i == 2) {
            mvwprintw(ds_win, i + 1, 1, "NPC->  %s", ds_contents[history_num_in][i]);
        } else if (i == 3) {
            mvwprintw(ds_win, i + 1, 1, "r->  %s", ds_contents[history_num_in][i]);
        } else if (i == 4) {
            mvwprintw(ds_win, i + 1, 1, "r1->  %s", ds_contents[history_num_in][i]);
        } else if (i == 5) {
            mvwprintw(ds_win, i + 1, 1, "r2->  %s", ds_contents[history_num_in][i]);
        } else if (i == 6) {
            mvwprintw(ds_win, i + 1, 1, "opA->  %s", ds_contents[history_num_in][i]);
        } else if (i == 7) {
            mvwprintw(ds_win, i + 1, 1, "opB->  %s", ds_contents[history_num_in][i]);
        } else if (i == 8) {
            mvwprintw(ds_win, i + 1, 1, "branch->  %s", ds_contents[history_num_in][i]);
        } else if (i == 9) {
            mvwprintw(ds_win, i + 1, 1, "ALU->  %s", ds_contents[history_num_in][i]);
        } else if (i == 10) {
            mvwprintw(ds_win, i + 1, 1, "rs_id_x->  %s", ds_contents[history_num_in][i]);
        } else if (i == 11) {
            mvwprintw(ds_win, i + 1, 1, "Flags->  %s", ds_contents[history_num_in][i]);
        } 
    }
    // wattroff(ds_win, A_REVERSE);
    wrefresh(ds_win);

    // update the time window
    mvwprintw(time_win, 1, 1, "%s", timebuffer[history_num_in]);
    wrefresh(time_win);
    
    // update the cycle count in the clock window
    mvwprintw(clock_win, 1, 1, "%s", cycles[history_num_in]);
    update_clock(clocks[history_num_in]);
    wrefresh(clock_win);

    // Update Reservation Station
    for (i = 0; i < num_rs_regs; i++) {
        char busy_cur = rs_contents[history_num_in][i][0];  
        char busy_old = rs_contents[old_history_num_in][i][0];
        if (busy_cur != busy_old) wattron(rs_win, A_REVERSE);
        else wattroff(rs_win, A_REVERSE);
        // print the Busy line once (only at i==0)
        if (i == 0) {
            mvwprintw(rs_win, 1, 5, "Busy: %s", busy_cur ? "1" : "0");
        }
        // now the fields T, T1, T2, V1, V2, ready
        int base = 1 + i*6;
        /* clear old contents, width = window_width-4 */
        mvwprintw(rs_win, i+3, 2, "%*s", getmaxx(rs_win)-4, "");
        mvwprintw(rs_win, i+3, 2,
            "RS%1d-> T:%-4s T1:%-4s T2:%-4s V1:%-4s V2:%-4s Ready:%-4s",
            i,
            rs_contents[history_num_in][base + 0],
            rs_contents[history_num_in][base + 1],
            rs_contents[history_num_in][base + 2],
            rs_contents[history_num_in][base + 3],
            rs_contents[history_num_in][base + 4],
            rs_contents[history_num_in][base + 5]
        );
    }
    wrefresh(rs_win);

    // CDB
    // We have three lines: valid, tag, value
    if (strcmp(cdb_contents[history_num_in][0], cdb_contents[old_history_num_in][0]) != 0)
        wattron(cdb_win, A_REVERSE);
    else wattroff(cdb_win, A_REVERSE);
    mvwprintw(cdb_win, 1, 1, "Valid: %s", cdb_contents[history_num_in][0]);

    if (strcmp(cdb_contents[history_num_in][1], cdb_contents[old_history_num_in][1]) != 0)
        wattron(cdb_win, A_REVERSE);
    else wattroff(cdb_win, A_REVERSE);
    mvwprintw(cdb_win, 2, 1, "Tag: %s", cdb_contents[history_num_in][1]);

    if (strcmp(cdb_contents[history_num_in][2], cdb_contents[old_history_num_in][2]) != 0)
        wattron(cdb_win, A_REVERSE);
    else wattroff(cdb_win, A_REVERSE);
    mvwprintw(cdb_win, 3, 1, "Value: %s", cdb_contents[history_num_in][2]);

    wrefresh(cdb_win);

    // Reorder Buffer
    // Head & tail
    if (old_head_position != atoi(rob_contents[history_num_in][0])) {
        wattron(rob_win, A_REVERSE);
    } else wattroff(rob_win, A_REVERSE);
    mvwprintw(rob_win, 1, 1, "Head: %s", rob_contents[history_num_in][0]);
    old_head_position = atoi(rob_contents[history_num_in][0]);

    if (old_tail_position != atoi(rob_contents[history_num_in][1])) {
        wattron(rob_win, A_REVERSE);
    } else wattroff(rob_win, A_REVERSE);
    mvwprintw(rob_win, 2, 1, "Tail: %s", rob_contents[history_num_in][1]);
    old_tail_position = atoi(rob_contents[history_num_in][1]);

    // Retire signal    
    char *retire_str = rob_contents[history_num_in][2];
    char *old_retire_str = rob_contents[old_history_num_in][2];
    if (strcmp(retire_str, old_retire_str) != 0)
        wattron(rob_win, A_REVERSE);
    else
        wattroff(rob_win, A_REVERSE);

    mvwprintw(rob_win, 3, 1, "Retire: %s", retire_str);


    // Entries
    for (i = 0; i < num_rob_regs; i++) {
        char *entry_str = rob_contents[history_num_in][3 + i];
        char *old_str   = rob_contents[old_history_num_in][3 + i];
        if (strcmp(entry_str, old_str) != 0)
            wattron(rob_win, A_REVERSE);
        else
            wattroff(rob_win, A_REVERSE);
    
        // print the full SV‐display text
        mvwprintw(rob_win, i+4, 1, "%s", entry_str);
    }
    wrefresh(rob_win);

    // Map Table
    // Show one line per entry: "Idx  i: T=... plus=..."
    for (i = 0; i < num_mt_regs; i++) {
        // each mt_contents row should pack T and plus as two strings:
        char *T_str    = mt_contents[history_num_in][2*i + 0];
        char *plus_str = mt_contents[history_num_in][2*i + 1];
        char *T_old    = mt_contents[old_history_num_in][2*i + 0];
        char *p_old    = mt_contents[old_history_num_in][2*i + 1];

        if (strcmp(T_str, T_old) != 0 || strcmp(plus_str, p_old) != 0)
            wattron(mt_win, A_REVERSE);
        else wattroff(mt_win, A_REVERSE);

        mvwprintw(mt_win, i+1, 1, "%2d->   T:%3s  plus: %1s", i, T_str, plus_str);
    }
    wrefresh(mt_win);

        
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

    // CDB
    if (strncmp(readbuffer, "bCDB_valid", 10) == 0) {
        char v[8];
        sscanf(readbuffer, "bCDB_valid %s", v);
        strcpy(cdb_contents[history_num][0], v);
        return 0;
    } else if (strncmp(readbuffer, "bCDB_T", 6) == 0) {
            char v[32];
            sscanf(readbuffer, "bCDB_T %s", v);
            strcpy(cdb_contents[history_num][1], v);
            return 0;
    } else if (strncmp(readbuffer, "bCDB_V", 6) == 0) {
        char v[32];
        sscanf(readbuffer, "bCDB_V %s", v);
        strcpy(cdb_contents[history_num][2], v);
        return 0;

    // Map Table
    } else if (strncmp(readbuffer, "tMT_entry", 9) == 0) {
        int idx, T, plus;
        if (sscanf(readbuffer, "tMT_entry %d T:%d plus:%d", &idx, &T, &plus) == 3) {
            char bufT[8], bufP[4];
            sprintf(bufT, "%d", T);
            sprintf(bufP, "%d", plus);
            strcpy(mt_contents[history_num][2*idx+0], bufT);
            strcpy(mt_contents[history_num][2*idx+1], bufP);
        }
        return 0;

    // Reservation Station
    } else if (strncmp(readbuffer, "rRS_busy", 8) == 0) {
        char v[4];
        sscanf(readbuffer, "rRS_busy %*d:%s", v);
        strcpy(rs_contents[history_num][0], v);
        return 0;
    } else if (strncmp(readbuffer, "rRS", 3) == 0) {
        int idx; char field[8], val[32];
        if (sscanf(readbuffer, "rRS%d_%[^ ] %*d:%s", &idx, field, val) == 3) {
            int base = 1 + idx*6;
            if      (!strcmp(field,"T"))     strcpy(rs_contents[history_num][base+0], val);
            else if (!strcmp(field,"T1"))    strcpy(rs_contents[history_num][base+1], val);
            else if (!strcmp(field,"T2"))    strcpy(rs_contents[history_num][base+2], val);
            else if (!strcmp(field,"V1"))    strcpy(rs_contents[history_num][base+3], val);
            else if (!strcmp(field,"V2"))    strcpy(rs_contents[history_num][base+4], val);
            else if (!strcmp(field,"ready")) strcpy(rs_contents[history_num][base+5], val);
        }
        return 0;
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

        // IF/ID packet
    } else if (strncmp(readbuffer,"f",1) == 0) {
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

        // ROB
    } else if (strncmp(readbuffer, "oROB_entry", 10) == 0) {
        // We are getting ROB entries
        int slot, idx, r, V, ready;
        char buf[128];
        if (sscanf(readbuffer, "oROB_entry:%0d %4d->   r:%4d  V:%4d  ready:%1d", &slot, &idx, &r, &V, &ready) == 5) {
            sprintf(buf, "%2d->  r:%4d  V:%4d  ready: %1d", idx, r, V, ready);
            strcpy(rob_contents[history_num][2 + slot], buf);
        }
        return 0;    
    } else if (strncmp(readbuffer, "ohead", 5) == 0) {
        // We are getting ROB head
        char v[32];
        sscanf(readbuffer, "ohead %s", v);
        strcpy(rob_contents[history_num][0], v);
        return 0;
    }  else if (strncmp(readbuffer, "otail", 5) == 0) {
        // We are getting ROB head
        char v[32];
        sscanf(readbuffer, "otail %s", v);
        strcpy(rob_contents[history_num][1], v);
        return 0;
    } else if (strncmp(readbuffer, "oretire", 7) == 0) {
        // We are getting ROB retire
        char v[32];
        sscanf(readbuffer, "oretire %s", v);
        strcpy(rob_contents[history_num][2], v);
        return 0;
        
        // D/S
    } else if (strncmp(readbuffer, "dINST", 5) == 0) {
        char v[32];
        sscanf(readbuffer, "dINST %s", v);
        strcpy(ds_contents[history_num][0], v);
        return 0;
    } else if (strncmp(readbuffer, "dPC", 3) == 0) {
        char v[32];
        sscanf(readbuffer, "dPC %s", v);
        strcpy(ds_contents[history_num][1], v);
        return 0;
    } else if (strncmp(readbuffer, "dNPC", 4) == 0) {
        char v[32];
        sscanf(readbuffer, "dNPC %s", v);
        strcpy(ds_contents[history_num][2], v);
        return 0;
    } else if (strncmp(readbuffer, "dsr", 2) == 0) {
        char v[32];
        sscanf(readbuffer, "dsr %s", v);
        strcpy(ds_contents[history_num][3], v);
        return 0;
    } else if (strncmp(readbuffer, "dpr1", 4) == 0) {
        char v[32];
        sscanf(readbuffer, "dpr1 %s", v);
        strcpy(ds_contents[history_num][4], v);
        return 0;
    } else if (strncmp(readbuffer, "dqr2", 4) == 0) {
        char v[32];
        sscanf(readbuffer, "dqr2 %s", v);
        strcpy(ds_contents[history_num][5], v);
        return 0;
    } else if (strncmp(readbuffer, "dopa", 4) == 0) {
        char v[32];
        sscanf(readbuffer, "dopa %s", v);
        strcpy(ds_contents[history_num][6], v);
        return 0;
    } else if (strncmp(readbuffer, "dopb", 4) == 0) {
        char v[32];
        sscanf(readbuffer, "dopb %s", v);
        strcpy(ds_contents[history_num][7], v);
        return 0;
    } else if (strncmp(readbuffer, "dbranch", 7) == 0) {
        char buf[64];
        char v[32], v1[32], v2[32];
        sscanf(readbuffer, "dbranch %s %s", v1, v2);
        snprintf(buf, sizeof(buf), "cond: %s ucond: %s", v1, v2);
        strcpy(ds_contents[history_num][8], buf);
        return 0;
    } else if (strncmp(readbuffer, "dalu", 4) == 0) {
        char v[32];
        sscanf(readbuffer, "dalu %s", v);
        strcpy(ds_contents[history_num][9], v);
        return 0;
    } else if (strncmp(readbuffer, "drsidx", 6) == 0) {
        char v[32];
        sscanf(readbuffer, "drsidx %s", v);
        strcpy(ds_contents[history_num][10], v);
        return 0;
    } else if (strncmp(readbuffer, "dflags", 6) == 0) {
        char buf[64];
        char f1[8], f2[8], f3[8], f4[8];
        sscanf(readbuffer, "dflags %s %s %s %s", f1, f2, f3, f4);
        snprintf(buf,32,"f1: %s f2: %s f3: %s f4: %s",f1,f2,f3,f4);
        strcpy(ds_contents[history_num][11], buf);
        return 0;

        // Break
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
extern "C" void initcurses(int if_regs, int rs_regs, int cdb_regs, int mt_regs, int rob_regs, int ds_regs) { // count = 5
    int nbytes;
    int ready_val;

    done_state = 0;
    echo_data = 1;
    num_if_regs = if_regs;

    num_ds_regs = ds_regs;
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
        int i=0;
        if_contents       = (char***) malloc(NUM_HISTORY*sizeof(char**));
  
        ds_contents = (char***)malloc(NUM_HISTORY * sizeof(char**));
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

        for (int j = 0; j < num_if_regs; j++) {
            if_reg_names[j] = (char*)malloc(16);
            if_reg_names[j][0] = '\0';
        }

        ds_reg_names = (char**) malloc(num_ds_regs*sizeof(char*));

        rs_reg_names = (char**) malloc(num_rs_regs*sizeof(char*));
        cdb_reg_names = (char**) malloc(num_cdb_regs*sizeof(char*));
        mt_reg_names = (char**) malloc(num_mt_regs*sizeof(char*));
        rob_reg_names =  (char**) malloc(num_rob_regs*sizeof(char*));

        int j=0;

        for (int i = 0; i < NUM_HISTORY; i++) {
            timebuffer[i]    = (char*)malloc(8);  
            timebuffer[i][0] = '\0';
            cycles[i]        = (char*)malloc(7);  
            cycles[i][0]     = '\0';
            inst_contents[i] = (char*)malloc(NUM_STAGES*10);
            inst_contents[i][0] = '\0';
          
            // IF
            if_contents[i] = (char**)malloc(num_if_regs * sizeof(char*));
            for (int j = 0; j < num_if_regs; j++) {
              if_contents[i][j] = (char*)malloc(16);
              if_contents[i][j][0] = '\0';
            }

            // DS
            ds_contents[i] = (char**)malloc(num_ds_regs * sizeof(char*));
            for (int j = 0; j < num_ds_regs; j++) {
              ds_contents[i][j] = (char*)malloc(32);
              ds_contents[i][j][0] = '\0';
            }
          
            // RS
            int rs_ptrs = 1 + num_rs_regs*6;
            rs_contents[i] = (char**)malloc(rs_ptrs * sizeof(char*));
            // busy flag
            rs_contents[i][0] = (char*)malloc(4);
            strcpy(rs_contents[i][0], "0");
            // each RS field
            for (int j = 1; j < rs_ptrs; j++) {
              rs_contents[i][j] = (char*)malloc(32);
              rs_contents[i][j][0] = '\0';
            }
          
            // CDB
            cdb_contents[i] = (char**)malloc(3 * sizeof(char*));
            for (int j = 0; j < 3; j++) {
              cdb_contents[i][j] = (char*)malloc(32);
              cdb_contents[i][j][0] = '\0';
            }
          
            // ROB
            int rob_ptrs = 3 + num_rob_regs;
            rob_contents[i] = (char**)malloc(rob_ptrs * sizeof(char*));

            //head
            rob_contents[i][0] = (char*)malloc(32); 
            strcpy(rob_contents[i][0],"0");

            //tail
            rob_contents[i][1] = (char*)malloc(32); 
            strcpy(rob_contents[i][1],"0");

            //entries
            for (int j = 3; j < rob_ptrs; j++) {
              rob_contents[i][j] = (char*)malloc(64);
              rob_contents[i][j][0] = '\0';
            }

            // retire 
            rob_contents[i][2] = (char*)malloc(32);
            strcpy(rob_contents[i][2], "0");
          
            // MT
            int mt_ptrs = 2 * num_mt_regs;
            mt_contents[i] = (char**)malloc(mt_ptrs * sizeof(char*));
            for (int j = 0; j < mt_ptrs; j++) {
              mt_contents[i][j] = (char*)malloc(32);
              mt_contents[i][j][0] = '\0';
            }
          }
          
        setup_gui(fp, rs_regs, cdb_regs, mt_regs, rob_regs, ds_regs);

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
