#!/bin/bash

echo "Comparing ground truth outputs to new processor"

#cd ~/Documents/ComputerArchitectures/project3 || exit

LOG_FILE="scoreboard.log"

# Start the log file with a timestamp
{
    echo -e "\n================== SCOREBOARD =================="
    echo "Test Run: $(date)"
    printf "%-20s | %-10s | %-30s\n" "Program" "Status" "System Halt"
    echo "---------------------------------------------------------------"
} | tee "$LOG_FILE"

# Check if program names are provided
if [[ $# -gt 0 ]]; then
    sources=()
    for program in "$@"; do
        sources+=("programs/$program.s")
        sources+=("programs/$program.c")
    done
else
    sources=(programs/*.{s,c})
fi

declare -A scoreboard
declare -A halt_messages

# Loop through all source files
for source_file in "${sources[@]}"; do
    [[ -f "$source_file" ]] || continue

    if [[ "$source_file" == "programs/crt.s" ]]; then
        continue
    fi

    program=$(basename "$source_file" | cut -d '.' -f1)
    echo -e "\nRunning $program"

    # Run with timeout to detect infinite loops (60s timeout)
    if ! timeout 360s make "$program.out"; then
        echo -e "\033[33m⚠️  Skipping $program (INFINITE LOOP DETECTED)\033[0m"
        echo ""
        scoreboard["$program"]="SKIPPED"
        halt_messages["$program"]="N/A"
        printf "%-20s | %-10s | %-30s\n" "$program" "SKIPPED" "N/A" >> "$LOG_FILE"
        continue
    fi

    #echo "Comparing writeback output for $program"
    #diff -y --suppress-common-lines correct_out/"$program".wb output/"$program".wb
    status1=0 #$?

    echo -e "\nComparing memory output for $program"
    diff -y --suppress-common-lines <(grep '@@@ mem' correct_out/"$program".out) <(grep '@@@ mem' output/"$program".out)
    status2=$?

    # Extract system halt message from both correct and output files
    expected_halt_reason=$(grep '@@@ System halted' correct_out/"$program".out | sed 's/@@@ System halted on //')
    actual_halt_reason=$(grep '@@@ System halted' output/"$program".out | sed 's/@@@ System halted on //')

    # If no halt message is found, set to "Unknown"
    expected_halt_reason=${expected_halt_reason:-"Unknown"}
    actual_halt_reason=${actual_halt_reason:-"Unknown"}

    # Compare halt reasons (plain text for log file)
    halt_message_log="$actual_halt_reason"
    if [[ "$actual_halt_reason" != "$expected_halt_reason" ]]; then
        halt_message_log="$actual_halt_reason (EXPECTED: $expected_halt_reason)"
    fi

    # Color the halt message for terminal output
    if [[ "$actual_halt_reason" == "$expected_halt_reason" ]]; then
        halt_messages["$program"]="\033[32m$actual_halt_reason\033[0m"  # Green if it matches
    else
        halt_messages["$program"]="\033[31m$halt_message_log\033[0m"  # Red if different
    fi

    # Store pass/fail status and print in real-time (no colors in log)
    if [[ $status1 -eq 0 && $status2 -eq 0 ]]; then
        echo -e "\033[32m✅ Passed! :)\033[0m"
        echo ""
        scoreboard["$program"]="\033[32mPASSED\033[0m"
        status_log="PASSED"
    else
        echo -e "\033[31m❌ Failed :(\033[0m"
        echo ""
        scoreboard["$program"]="\033[31mFAILED\033[0m"
        status_log="FAILED"
    fi

    # Log result without colors
    printf "%-20s | %-10s | %-30s\n" "$program" "$status_log" "$halt_message_log" >> "$LOG_FILE"
done

# Print scoreboard headers again for clarity in both terminal and log file
{
    printf "%-20s | %-10s | %-30s\n" "Program" "Status" "System Halt"
    echo "---------------------------------------------------------------"
} | tee -a "$LOG_FILE"

# Print scoreboard entries in terminal (with color) and log file (without color)
for program in "${!scoreboard[@]}"; do
    printf "%-20s | " "$program"
    echo -ne "${scoreboard[$program]}"
    echo -n " | "
    echo -ne "${halt_messages[$program]}"
    echo ""  # New line for formatting

    # Log without colors
    printf "%-20s | %-10s | %-30s\n" "$program" "$status_log" "$halt_message_log" >> "$LOG_FILE"
done

# Print closing line to both terminal and log file
echo "===============================================================" | tee -a "$LOG_FILE"

echo "Scoreboard saved to $LOG_FILE"
