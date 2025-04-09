simSetSimulator "-vcssv" -exec "./simv" -args \
           "+MEMORY=programs/ppl_test.mem +WRITEBACK=/dev/null +PIPELINE=/dev/null" \
           -uvmDebug on -simDelim
debImport "-i" "-simflow" "-dbdir" "./simv.daidir"
srcTBInvokeSim
verdiSetActWin -dock widgetDock_<Member>
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcHBSelect "testbench.memory" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.core" -win $_nTrace1
srcSetScope "testbench.core" -delim "." -win $_nTrace1
srcHBSelect "testbench.core" -win $_nTrace1
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcSignalView -on
verdiSetActWin -dock widgetDock_<Signal_List>
srcSignalViewSelect "testbench.core.clock"
verdiSetActWin -win $_InteractiveConsole_2
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcSetScope "testbench.core.func_unit_03" -delim "." -win $_nTrace1
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcSignalViewSelect "testbench.core.func_unit_03.clock"
verdiSetActWin -dock widgetDock_<Signal_List>
srcSignalViewSelect "testbench.core.func_unit_03.clock" \
           "testbench.core.func_unit_03.reset" \
           "testbench.core.func_unit_03.Dmem_gnt" \
           "testbench.core.func_unit_03.retired" \
           "testbench.core.func_unit_03.mem2proc_response\[3:0\]" \
           "testbench.core.func_unit_03.mem2proc_tag\[3:0\]" \
           "testbench.core.func_unit_03.Dmem2proc_data\[63:0\]" \
           "testbench.core.func_unit_03.S_X_reg" \
           "testbench.core.func_unit_03.mem_store_pend" \
           "testbench.core.func_unit_03.proc2Dmem_addr\[31:0\]" \
           "testbench.core.func_unit_03.proc2Dmem_data\[63:0\]" \
           "testbench.core.func_unit_03.proc2Dmem_command\[1:0\]" \
           "testbench.core.func_unit_03.X_packet" \
           "testbench.core.func_unit_03.rawDmem_addr\[31:0\]" \
           "testbench.core.func_unit_03.line_offset\[3:0\]" \
           "testbench.core.func_unit_03.nextDmem_tag\[3:0\]" \
           "testbench.core.func_unit_03.shift\[5:0\]" \
           "testbench.core.func_unit_03.size_offset\[5:0\]" \
           "testbench.core.func_unit_03.Dmem_data\[63:0\]" \
           "testbench.core.func_unit_03.rawDmem_data\[63:0\]" \
           "testbench.core.func_unit_03.fetchDmem_state\[1:0\]" \
           "testbench.core.func_unit_03.storeDmem_state\[1:0\]" \
           "testbench.core.func_unit_03.fetchDmem_valid" \
           "testbench.core.func_unit_03.load_pend" \
           "testbench.core.func_unit_03.store_pend" \
           "testbench.core.func_unit_03.store_valid"
wvCreateWindow
srcSignalViewAddSelectedToWave -win $_nTrace1 -clipboard
wvDrop -win $_nWave3
srcTBRunSim
srcSignalView -off
verdiDockWidgetMaximize -dock windowDock_nWave_3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSetCursor -win $_nWave3 117281.782750 -snap {("G1" 4)}
wvSetCursor -win $_nWave3 120662.456143 -snap {("G1" 3)}
wvSelectSignal -win $_nWave3 {( "G1" 22 )} 
srcSignalView -on
srcSignalView -off
srcSignalView -on
verdiDockWidgetRestore -dock windowDock_nWave_3
srcSignalView -off
verdiDockWidgetMaximize -dock windowDock_nWave_3
wvSetCursor -win $_nWave3 116981.884304 -snap {("G1" 21)}
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvSetCursor -win $_nWave3 120498.875172 -snap {("G1" 22)}
wvSetCursor -win $_nWave3 124206.710506 -snap {("G1" 22)}
wvSetCursor -win $_nWave3 106649.019659 -snap {("G1" 22)}
wvSetCursor -win $_nWave3 117227.255760 -snap {("G1" 21)}
srcSignalView -on
srcSignalView -off
srcSignalView -on
verdiDockWidgetRestore -dock windowDock_nWave_3
debReload
srcHBSelect "testbench.core" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.core" -win $_nTrace1
srcSetScope "testbench.core" -delim "." -win $_nTrace1
srcHBSelect "testbench.core" -win $_nTrace1
srcDeselectAll -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcSetScope "testbench.core.func_unit_03" -delim "." -win $_nTrace1
srcHBSelect "testbench.core.func_unit_03" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "fetchDmem_valid" -line 70 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcDeselectAll -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcTBInvokeSim
srcTBRunSim
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
verdiSetActWin -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
srcSignalView -off
verdiDockWidgetMaximize -dock windowDock_nWave_3
wvSetCursor -win $_nWave3 113892.619956 -snap {("G1" 3)}
wvSetCursor -win $_nWave3 117242.106162 -snap {("G1" 4)}
wvSelectSignal -win $_nWave3 {( "G1" 11 )} 
wvSetPosition -win $_nWave3 {("G1" 11)}
wvExpandBus -win $_nWave3
wvSetPosition -win $_nWave3 {("G1" 90)}
wvScrollUp -win $_nWave3 19
wvSelectSignal -win $_nWave3 {( "G1" 11 )} 
wvSetPosition -win $_nWave3 {("G1" 11)}
wvCollapseBus -win $_nWave3
wvSetPosition -win $_nWave3 {("G1" 11)}
wvSetPosition -win $_nWave3 {("G1" 26)}
srcSignalView -on
srcSignalView -off
srcSignalView -on
verdiDockWidgetRestore -dock windowDock_nWave_3
srcHBSelect "testbench.memory" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.unnamed\$\$_0" -win $_nTrace1
srcSetScope "testbench.unnamed\$\$_0" -delim "." -win $_nTrace1
srcHBSelect "testbench.unnamed\$\$_0" -win $_nTrace1
srcHBSelect "testbench.memory" -win $_nTrace1
srcSetScope "testbench.memory" -delim "." -win $_nTrace1
srcHBSelect "testbench.memory" -win $_nTrace1
srcSignalViewSelect "testbench.memory.clk"
verdiSetActWin -dock widgetDock_<Signal_List>
srcSignalViewSelect "testbench.memory.clk" \
           "testbench.memory.proc2mem_addr\[31:0\]" \
           "testbench.memory.proc2mem_data\[63:0\]" \
           "testbench.memory.proc2mem_command\[1:0\]" \
           "testbench.memory.mem2proc_response\[3:0\]" \
           "testbench.memory.mem2proc_data\[63:0\]" \
           "testbench.memory.mem2proc_tag\[3:0\]" \
           "testbench.memory.next_mem2proc_data\[63:0\]" \
           "testbench.memory.next_mem2proc_response\[3:0\]" \
           "testbench.memory.next_mem2proc_tag\[3:0\]" \
           "testbench.memory.unified_memory\[8191:0\]" \
           "testbench.memory.loaded_data\[15:1\]" \
           "testbench.memory.cycles_left\[15:1\]" \
           "testbench.memory.waiting_for_bus\[15:1\]" \
           "testbench.memory.acquire_tag" "testbench.memory.bus_filled" \
           "testbench.memory.valid_address"
wvCreateWindow
wvSetPosition -win $_nWave4 {("G1" 0)}
wvOpenFile -win $_nWave4 {/workdir/yd2770_csee4824/p4.fsdb}
srcSignalViewAddSelectedToWave -win $_nTrace1 -clipboard
wvDrop -win $_nWave4
debReload
verdiDockWidgetSetCurTab -dock windowDock_nWave_3
verdiSetActWin -win $_nWave3
verdiDockWidgetSetCurTab -dock windowDock_nWave_4
verdiSetActWin -win $_nWave4
srcTBInvokeSim
srcTBRunSim
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvSelectSignal -win $_nWave4 {( "G1" 3 )} 
wvZoomOut -win $_nWave4
wvZoomIn -win $_nWave4
wvSelectSignal -win $_nWave4 {( "G1" 3 )} 
wvSelectSignal -win $_nWave4 {( "G1" 4 )} 
wvSelectSignal -win $_nWave4 {( "G1" 3 )} 
debReload
srcTBInvokeSim
srcTBRunSim
srcSignalView -off
verdiDockWidgetMaximize -dock windowDock_nWave_4
srcSignalView -on
srcSignalView -off
srcSignalView -on
verdiDockWidgetRestore -dock windowDock_nWave_4
srcSignalView -off
verdiDockWidgetMaximize -dock windowDock_nWave_4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvZoomOut -win $_nWave4
wvSetCursor -win $_nWave4 103227.286871 -snap {("G1" 3)}
wvSelectSignal -win $_nWave4 {( "G1" 2 )} 
wvSelectSignal -win $_nWave4 {( "G1" 3 )} 
wvSetCursor -win $_nWave4 117266.094373 -snap {("G1" 4)}
