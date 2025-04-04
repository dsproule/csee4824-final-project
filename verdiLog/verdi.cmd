simSetSimulator "-vcssv" -exec "./func_unit_3.simv" -args " " -uvmDebug on
debImport "-i" "-simflow" "-dbdir" "./func_unit_3.simv.daidir"
srcTBInvokeSim
verdiSetActWin -dock widgetDock_<Member>
verdiSetActWin -dock widgetDock_<Inst._Tree>
srcHBSelect "testbench.memory" -win $_nTrace1
srcHBSelect "testbench.memory" -win $_nTrace1
srcHBSelect "testbench.memory" -win $_nTrace1
wvCreateWindow
srcHBAddObjectToWave -clipboard
wvDrop -win $_nWave3
verdiSetActWin -win $_nWave3
srcTBRunSim
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvZoomOut -win $_nWave3
wvSelectSignal -win $_nWave3 {( "memory" 4 )} 
debExit
