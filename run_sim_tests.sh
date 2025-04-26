#!/bin/bash

echo "Comparing ground truth outputs to new processor"

LOG_FILE="scoreboard.log"



# Gather source programs
if [[ $# -gt 0 ]]; then
    sources=()
    for program in "$@"; do
        sources+=("programs/$program.s")
        sources+=("programs/$program.c")
    done
else
    sources=(programs/*.{s,c})
fi

# Declare associative arrays
declare -A scoreboard_reg
declare -A scoreboard_mem
declare -A halt_messages
declare -A cpi_values

# Process each source file
for source_file in "${sources[@]}"; do
    [[ -f "$source_file" ]] || continue
    [[ "$source_file" == "programs/crt.s" ]] && continue

    program=$(basename "$source_file" | cut -d '.' -f1)
    echo -e "\nRunning $program"

    if ! timeout 360s make "$program.out"; then
        echo -e "\033[33m⚠️  Skipping $program (INFINITE LOOP DETECTED)\033[0m"
        scoreboard_reg["$program"]="SKIPPED"
        scoreboard_mem["$program"]="SKIPPED"
        cpi_values["$program"]="N/A"
        halt_messages["$program"]="N/A"
        continue
    fi

    ### REG CHECK
    diff -y --suppress-common-lines \
      <(grep 'REG\[' correct_out/"$program".wb | grep -v 'REG\[ *0\]' | awk -F', ' '{print $2}') \
      <(grep 'REG\[' output/"$program".wb | grep -v 'REG\[ *0\]' | awk -F', ' '{print $2}') > /dev/null
    status_reg=$?

    ### MEM CHECK
    diff -y --suppress-common-lines \
      <(grep '@@@ mem' correct_out/"$program".out) \
      <(grep '@@@ mem' output/"$program".out) > /dev/null
    status_mem=$?

    ### CPI EXTRACT
    cpi=$(grep -oP '@@.*=\s*\K[0-9.]+(?=\s*CPI)' output/"$program".out)
    cpi_values["$program"]="${cpi:-N/A}"

    ### SYSTEM HALT MESSAGE
    expected_halt=$(grep '@@@ System halted' correct_out/"$program".out | sed 's/@@@ System halted on //')
    actual_halt=$(grep '@@@ System halted' output/"$program".out | sed 's/@@@ System halted on //')
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
    echo -e "\n================== SCOREBOARD =================="
    echo "Test Run: $(date)"
    printf "%-20s | %-10s | %-10s | %-10s | %-30s\n" "Program" "RegCheck" "MemCheck" "CPI" "System Halt"
    echo "------------------------------------------------------------------------------------------"
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
    printf "%-10s | " "${cpi_values[$program]}"
    echo -ne "${halt_messages[$program]}"
    echo ""    

    cpi_sum=$(echo "$cpi_sum + ${cpi_values[$program]}" | bc)
    ((num_program += 1))

    # Strip ANSI codes for log file
    reg_plain=$(echo -e "${scoreboard_reg[$program]}" | sed 's/\x1b\[[0-9;]*m//g')
    mem_plain=$(echo -e "${scoreboard_mem[$program]}" | sed 's/\x1b\[[0-9;]*m//g')
    halt_plain=$(echo -e "${halt_messages[$program]}" | sed 's/\x1b\[[0-9;]*m//g')

    # Log plain output aligned
    printf "%-20s | %-10s | %-10s | %-10s | %-30s\n" \
        "$program" "$reg_plain" "$mem_plain" "${cpi_values[$program]}" "$halt_plain" >> "$LOG_FILE"
    
    cpi_sum=$(echo "$cpi_sum + ${cpi_values[$program]}" | bc)
    ((num_program += 1))
done

echo "Average CPI = $(echo "scale=2; $cpi_sum / $num_program" | bc)"
echo "==========================================================================================" | tee -a "$LOG_FILE"
echo "Scoreboard saved to $LOG_FILE"
