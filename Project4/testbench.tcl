# ============================================================================
# ECSE 425 Project 4: testbench.tcl
# ============================================================================
# Usage: vsim -do testbench.tcl
#
# Prerequisites:
#   - program.txt must be in the simulation working directory
#   - All .vhd files must be in the same directory as this script
# ============================================================================

# Create fresh work library
vlib work

# Compile in dependency order:
#   1-4: sub-components (no inter-dependencies)
#   5:   processor (depends on 1-4)
#   6:   testbench (depends on 5)
vcom -2008 memory.vhd
vcom -2008 regfile.vhd
vcom -2008 alu.vhd
vcom -2008 hazard_control.vhd
vcom -2008 processor.vhd
vcom -2008 processor_tb.vhd

# Load and run
vsim -t 1ps work.processor_tb

# Run until the testbench stops itself
run -all

# Done
quit -f