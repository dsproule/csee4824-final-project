# ----------------------------------------
# Jasper Version Info
# tool      : Jasper 2024.06
# platform  : Linux 4.18.0-553.89.1.el8_10.x86_64
# version   : 2024.06p002 64 bits
# build date: 2024.09.02 16:28:38 UTC
# ----------------------------------------
# started   : 2025-12-16 12:48:52 EST
# hostname  : cadpc05.(none)
# pid       : 2398835
# arguments : '-label' 'session_0' '-console' '//127.0.0.1:33333' '-nowindow' '-style' 'windows' '-exitonerror' '-data' 'AAAAqnicY2RgYLCp////PwMYMD6A0Aw2jAyoAMRnQhUJbEChGRhYYZphSpiBmIdBlyGJIZGhhCGZIQPI5wDy0xgKGMqAbDUgq4xBnyETKJcIlk9liIfSyQzZDHpgXTlgswBfnRHb' '-proj' '/homes/user/stud/fall23/das2313/csee4824/csee4824-final-project/jgproject/sessionLogs/session_0' '-init' '-hidden' '/homes/user/stud/fall23/das2313/csee4824/csee4824-final-project/jgproject/.tmp/.initCmds.tcl' 'fv/icache_check.tcl' '-hidden' '/homes/user/stud/fall23/das2313/csee4824/csee4824-final-project/jgproject/.tmp/.postCmds.tcl'
set ROOT_PATH .
set RTL_PATH ${ROOT_PATH}/verilog
set FV_PATH ${ROOT_PATH}/fv

set CLOCK_PERIOD 1300

analyze -sv \
    +define+CLOCK_PERIOD=${CLOCK_PERIOD} \
    +define+FORMAL \
    -incdir ${ROOT_PATH} \
    ${RTL_PATH}/sys_defs.svh \
    ${RTL_PATH}/icache.sv \
    ${FV_PATH}/fv_mem.sv \
    ${FV_PATH}/icache_check.sv

elaborate -top icache_check
clock clock -both_edges
reset reset

get_design_info
prove -all
report


exit -force
