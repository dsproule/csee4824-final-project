# ----------------------------------------
# Jasper Version Info
# tool      : Jasper 2024.06
# platform  : Linux 4.18.0-553.89.1.el8_10.x86_64
# version   : 2024.06p002 64 bits
# build date: 2024.09.02 16:28:38 UTC
# ----------------------------------------
# started   : 2025-12-15 18:59:57 EST
# hostname  : cadpc39.(none)
# pid       : 2203805
# arguments : '-label' 'session_0' '-console' '//127.0.0.1:42399' '-style' 'windows' '-data' 'AAAAmnicY2RgYLCp////PwMYMD6A0Aw2jAyoAMRnQhUJbEChGRhYYZphSkAaOBh0GdIYChjKgGw1IKuMQZ8hkyGZIRGIMxhSGeKBuJChFChWxqDHUAIUzQHrBQBmCg/L' '-proj' '/homes/user/stud/fall23/das2313/csee4824/csee4824-final-project/jgproject/sessionLogs/session_0' '-init' '-hidden' '/homes/user/stud/fall23/das2313/csee4824/csee4824-final-project/jgproject/.tmp/.initCmds.tcl' 'fv/icache_equiv.tcl'
set ROOT_PATH .
set RTL_PATH ${ROOT_PATH}/verilog

set CLOCK_PERIOD 1300

analyze -sv \
    +define+CLOCK_PERIOD=${CLOCK_PERIOD} \
    +define+FORMAL \
    -incdir ${ROOT_PATH} \
    ${RTL_PATH}/sys_defs.svh \
    ${RTL_PATH}/icache.sv \
    ${ROOT_PATH}/test/mem.sv \
    ${ROOT_PATH}/fv/icache_check.sv

elaborate -top icache_check
clock clock -both_edges
reset reset

get_design_info
prove -all
report


visualize -violation -property <embedded>::icache_check.icache_0._assert_1 -new_window
reset -all
