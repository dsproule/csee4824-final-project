set ROOT_PATH ..
set RTL_PATH ${ROOT_PATH}/verilog

set hdlin_enable_sv true
set CLOCK_PERIOD 1300

analyze -sv \
    +define+CLOCK_PERIOD=${CLOCK_PERIOD} \
    +define+FORMAL \
  -incdir ${ROOT_PATH} \
  ${RTL_PATH}/pipeline.sv \
  ${RTL_PATH}/regfile.sv \
  ${RTL_PATH}/icache.sv \
  ${RTL_PATH}/d_stage.sv \
  ${RTL_PATH}/map_table.sv \
  ${RTL_PATH}/rs_stage.sv \
  ${RTL_PATH}/func_unit_0.sv \
  ${RTL_PATH}/func_unit_1.sv \
  ${RTL_PATH}/func_unit_2.sv \
  ${RTL_PATH}/func_unit_3.sv \
  ${RTL_PATH}/mult.sv \
  ${RTL_PATH}/mult_stage.sv \
  ${RTL_PATH}/rps.sv \
  ${RTL_PATH}/rob.sv \
  ${RTL_PATH}/if_stage.sv \
  ${RTL_PATH}/lsq.sv \
  ${RTL_PATH}/dcache_nb.sv \
  ${RTL_PATH}/two_bit_pred.sv \
  ${RTL_PATH}/branch_pred.sv \

elaborate -top pipeline 

clock clock -both_edges
reset reset

get_design_info
prove -all
report

