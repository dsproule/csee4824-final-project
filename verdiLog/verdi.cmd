simSetSimulator "-vcssv" -exec "./simv" -args \
           "+MEMORY=programs/fib.mem +WRITEBACK=/dev/null +PIPELINE=/dev/null" \
           -uvmDebug on -simDelim
debImport "-i" "-simflow" "-dbdir" "./simv.daidir"
srcTBInvokeSim
verdiWindowResize -win $_Verdi_1 "295" "56" "901" "700"
verdiSetActWin -dock widgetDock_<Member>
verdiWindowResize -win $_Verdi_1 "295" "56" "901" "700"
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
verdiWindowResize -win $_Verdi_1 "295" "56" "1166" "700"
verdiWindowResize -win $_Verdi_1 -10 "19" "1471" "737"
srcHBSelect "testbench.core" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.core" -win $_nTrace1
srcSetScope "testbench.core" -delim "." -win $_nTrace1
srcHBSelect "testbench.core" -win $_nTrace1
srcHBSelect "testbench.core.icache_0" -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "clock" -line 14 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcSelect -win $_nTrace1 -range {14 15 4 4 4 5}
srcDeselectAll -win $_nTrace1
srcSelect -signal "reset" -line 15 -pos 1 -win $_nTrace1
srcSelect -win $_nTrace1 -range {14 15 4 4 3 4} -backward
srcDeselectAll -win $_nTrace1
srcSelect -signal "clock" -line 14 -pos 1 -win $_nTrace1
wvCreateWindow
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
verdiSetActWin -win $_nWave3
srcDeselectAll -win $_nTrace1
srcSelect -signal "reset" -line 15 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcHBSelect "testbench.core.if_stage_0" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcHBSelect "testbench.core.icache_0" -win $_nTrace1
srcSetScope "testbench.core.icache_0" -delim "." -win $_nTrace1
srcHBSelect "testbench.core.icache_0" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcDeselectAll -win $_nTrace1
srcSelect -signal "Icache_data_out" -line 64 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcHBSelect "testbench.core.if_stage_0" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcDeselectAll -win $_nTrace1
srcSelect -signal "Icache_valid_out" -line 65 -pos 1 -win $_nTrace1
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcHBSelect "testbench.core.if_stage_0" -win $_nTrace1
srcSetScope "testbench.core.if_stage_0" -delim "." -win $_nTrace1
srcHBSelect "testbench.core.if_stage_0" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
srcDeselectAll -win $_nTrace1
srcSelect -signal "Imem2proc_data" -line 17 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "IF_packet" -line 70 -pos 1 -win $_nTrace1
srcDeselectAll -win $_nTrace1
srcSelect -signal "nextIF_packet" -line 70 -pos 1 -win $_nTrace1
srcAddSelectedToWave -clipboard -win $_nTrace1
wvDrop -win $_nWave3
srcTBRunSim
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
verdiSetActWin -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 3 )} 
wvSetCursor -win $_nWave3 3487872.816901 -snap {("G1" 4)}
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSearchPrev -win $_nWave3
wvSearchPrev -win $_nWave3
wvSearchPrev -win $_nWave3
wvSearchPrev -win $_nWave3
wvSearchPrev -win $_nWave3
wvSetCursor -win $_nWave3 5408.450704 -snap {("G1" 4)}
wvSearchNext -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvExpandBus -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
srcHBSelect "testbench.core.if_stage_0" -win $_nTrace1
srcSetScope "testbench.core.if_stage_0" -delim "." -win $_nTrace1
srcHBSelect "testbench.core.if_stage_0" -win $_nTrace1
verdiSetActWin -dock widgetDock_<Inst._Tree>
verdiSetActWin -dock widgetDock_MTB_SOURCE_TAB_1
verdiSetActWin -win $_nWave3
wvSelectSignal -win $_nWave3 {( "G1" 6 )} 
wvSetPosition -win $_nWave3 {("G1" 6)}
wvSetPosition -win $_nWave3 {("G1" 5)}
wvSetPosition -win $_nWave3 {("G1" 4)}
wvSetPosition -win $_nWave3 {("G1" 3)}
wvMoveSelected -win $_nWave3
wvSetPosition -win $_nWave3 {("G1" 3)}
wvSetPosition -win $_nWave3 {("G1" 4)}
wvSelectSignal -win $_nWave3 {( "G1" 6 )} 
wvSetPosition -win $_nWave3 {("G1" 6)}
wvCollapseBus -win $_nWave3
wvSetPosition -win $_nWave3 {("G1" 6)}
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSetPosition -win $_nWave3 {("G1" 4)}
wvExpandBus -win $_nWave3
wvSetPosition -win $_nWave3 {("G1" 13)}
wvScrollDown -win $_nWave3 3
wvScrollUp -win $_nWave3 1
wvScrollUp -win $_nWave3 3
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvSelectSignal -win $_nWave3 {( "G1" 6 )} 
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
wvScrollDown -win $_nWave3 1
wvSelectSignal -win $_nWave3 {( "G1" 7 )} 
wvSelectSignal -win $_nWave3 {( "G1" 10 )} 
wvScrollDown -win $_nWave3 0
wvSelectSignal -win $_nWave3 {( "G1" 11 )} 
wvScrollDown -win $_nWave3 0
wvSelectSignal -win $_nWave3 {( "G1" 12 )} 
wvSelectSignal -win $_nWave3 {( "G1" 9 )} 
wvScrollUp -win $_nWave3 4
wvSelectSignal -win $_nWave3 {( "G1" 4 )} 
wvSelectSignal -win $_nWave3 {( "G1" 5 )} 
debExit
