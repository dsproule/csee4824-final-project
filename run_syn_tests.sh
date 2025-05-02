#!/bin/bash

echo "Comparing ground truth outputs to new processor"

LOG_FILE="scoreboard.log"

# Extract CLOCK_PERIOD in picoseconds and convert to microseconds
CLOCK_PS=$(grep -oP 'export CLOCK_PERIOD\s*=\s*\K[0-9]+' Makefile)
CLOCK_US=$(echo "scale=6; $CLOCK_PS / 1000" | bc)

file_ext=""
while getopts "sc" opt; do
    case $opt in
        s) file_ext="s" ;;
        c) file_ext="c" ;;
        *) echo "Usage: $0 [-s] [-c]" >&2; exit 1 ;;
    esac
done
shift $((OPTIND -1))

# Decide which sources to gather
if [[ "$file_ext" == "s" ]]; then
    sources=(programs/*.s)
elif [[ "$file_ext" == "c" ]]; then
    sources=(programs/*.c)
else
    if [[ $# -gt 0 ]]; then
        sources=()
        for program in "$@"; do
            sources+=("programs/$program.s")
            sources+=("programs/$program.c")
        done
    else
        sources=(programs/*.{s,c})
    fi
fi

# Declare associative arrays
declare -A scoreboard_reg
declare -A scoreboard_mem
declare -A halt_messages
declare -A cpi_values
declare -A cycles
declare -A time_values

# Process each source file
for source_file in "${sources[@]}"; do
    [[ -f "$source_file" ]] || continue
    [[ "$source_file" == "programs/crt.s" ]] && continue

    program=$(basename "$source_file" | cut -d '.' -f1)
    echo -e "\nRunning $program"

    make simulate_all_syn -j$(nproc)

    # if ! timeout 36000000s make "$program.syn.out"; then
    #     echo -e "\033[33m⚠️  Skipping $program (INFINITE LOOP DETECTED)\033[0m"
    #     scoreboard_reg["$program"]="SKIPPED"
    #     scoreboard_mem["$program"]="SKIPPED"
    #     cpi_values["$program"]="N/A"
    #     halt_messages["$program"]="N/A"
    #     continue
    # fi

    ### REG CHECK
    diff -y --suppress-common-lines \
        <(grep 'REG\[' correct_out/"$program".wb | grep -v 'REG\[ *0\]' | sed -n 's/.*\(REG\[[^]]*\]=[0-9A-Fa-f]\{8\}\).*/\1/p') \
        <(grep 'REG\[' output/"$program".syn.wb | grep -v 'REG\[ *0\]' | sed -n 's/.*\(REG\[[^]]*\]=[0-9A-Fa-f]\{8\}\).*/\1/p') > /dev/null
    status_reg=$?

    ### MEM CHECK
    diff -y --suppress-common-lines \
      <(grep '@@@ mem' correct_out/"$program".out) \
      <(grep '@@@ mem' output/"$program".syn.out) > /dev/null
    status_mem=$?

    ### CPI EXTRACT
    cpi=$(grep -oP '@@.*=\s*\K[0-9.]+(?=\s*CPI)' output/"$program".syn.out)
    cpi_values["$program"]="${cpi:-N/A}"
    cycles=$(grep -oP '@@.*?(\d+)\s+cycles' output/"$program".syn.out | grep -oP '\d+')
    cycles["$program"]="${cycles:-N/A}"

    if [[ -n "$cycles" && -n "$CLOCK_US" ]]; then
        exec_time=$(echo "scale=3; $cycles * $CLOCK_US" | bc)
        time_values["$program"]=$(printf "%.1f" "$exec_time")
    else
        time_values["$program"]="N/A"
    fi

    ### SYSTEM HALT MESSAGE
    expected_halt=$(grep '@@@ System halted' correct_out/"$program".out | sed 's/@@@ System halted on //')
    actual_halt=$(grep '@@@ System halted' output/"$program".syn.out | sed 's/@@@ System halted on //')
    expected_halt=${expected_halt:-"Unknown"}
    actual_halt=${actual_halt:-"Unknown"}

    if [[ "$expected_halt" == "$actual_halt" ]]; then
        halt_messages["$program"]="\033[32m$actual_halt\033[0m"
    else
        halt_messages["$program"]="\033[31m$actual_halt (EXPECTED: $expected_halt)\033[0m"
    fi

    ### REGISTER RESULT
    if [[ $status_reg -eq 0 ]]; then
        scoreboard_reg["$program"]="\033[32mPASS\033[0m"
    else
        scoreboard_reg["$program"]="\033[31mFAIL\033[0m"
    fi

    ### MEMORY RESULT
    if [[ $status_mem -eq 0 ]]; then
        scoreboard_mem["$program"]="\033[32mPASS\033[0m"
    else
        scoreboard_mem["$program"]="\033[31mFAIL\033[0m"
    fi
done

# Start the log file with a timestamp
{
    echo -e "\n============================================== SCOREBOARD ============================================="
    echo "Test Run: $(date)                        Clock Period: $CLOCK_PS ps = $CLOCK_US µs"
    printf "%-20s | %-10s | %-10s | %-10s | %-10s | %-10s | %-30s\n" "Program" "RegCheck" "MemCheck" "Cycles" "Time (µs)" "CPI" "System Halt"
    echo "-------------------------------------------------------------------------------------------------------"
} | tee "$LOG_FILE"

cpi_sum=0
num_program=0

for program in "${!scoreboard_reg[@]}"; do

    # Terminal output with color
    printf "%-20s | " "$program"
    echo -ne "   ${scoreboard_reg[$program]}   "
    echo -n " | "
    echo -ne "   ${scoreboard_mem[$program]}   "
    echo -n " | "
    printf "%-10s | %-10s | %-10s | " "${cycles[$program]}" "${time_values[$program]}" "${cpi_values[$program]}"
    echo -ne "${halt_messages[$program]}"
    echo ""

    # Strip ANSI codes for log file
    reg_plain=$(echo -e "${scoreboard_reg[$program]}" | sed 's/\x1b\[[0-9;]*m//g')
    mem_plain=$(echo -e "${scoreboard_mem[$program]}" | sed 's/\x1b\[[0-9;]*m//g')
    halt_plain=$(echo -e "${halt_messages[$program]}" | sed 's/\x1b\[[0-9;]*m//g')


    # Log plain output aligned
    printf "%-20s | %-10s | %-10s | %-10s | %-10s | %-10s | %-30s\n" \
        "$program" "$reg_plain" "$mem_plain" "${cycles[$program]}" "${time_values[$program]}" "${cpi_values[$program]}" "$halt_plain" >> "$LOG_FILE"

    if [[ "${cpi_values[$program]}" != "N/A" ]]; then
        cpi_sum=$(echo "$cpi_sum + ${cpi_values[$program]}" | bc)
        ((num_program += 1))
    fi
done

if (( num_program > 0 )); then
    echo "Average CPI = $(echo "scale=2; $cpi_sum / $num_program" | bc)         Average Time = $(echo "scale=3; ($cpi_sum / $num_program) * $CLOCK_US" | bc) µs"
else
    echo "Average CPI = N/A         Average Time = N/A"
fi

echo "==========================================================================================" | tee -a "$LOG_FILE"
echo "Scoreboard saved to $LOG_FILE"
