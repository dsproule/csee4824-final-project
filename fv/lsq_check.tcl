set ROOT_PATH .
set RTL_PATH ${ROOT_PATH}/verilog
set FV_PATH ${ROOT_PATH}/fv

set CLOCK_PERIOD 1300

analyze -sv \
    +define+CLOCK_PERIOD=${CLOCK_PERIOD} \
    +define+FORMAL \
    -incdir ${ROOT_PATH} \
    ${RTL_PATH}/sys_defs.svh \
    ${RTL_PATH}/lsq.sv \

elaborate -top lsq
clock clock -both_edges
reset reset

get_design_info
prove -all
report


