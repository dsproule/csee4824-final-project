# Compile the wrapper (top)
analyze -sv -incdir .. -incdir ../verilog ./top_branch_pred.sv

# Compile the DUT
analyze -sv -incdir .. -incdir ../verilog ../verilog/branch_pred.sv

# Elaborate top
elaborate -top top

# Declare clock & reset for formal
clock clock
reset reset

# Run proofs
prove -all


