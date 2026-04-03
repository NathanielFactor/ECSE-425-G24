# ============================================================================
# ECSE 425 Project 4: testbench.tcl
# ============================================================================
# Usage: vsim -do testbench.tcl
#
# This script:
#   1. Creates a work library
#   2. Compiles all VHDL files (VHDL-2008)
#   3. Loads the testbench
#   4. Runs the simulation to completion
#   5. Output files (register_file.txt, memory.txt) are written by the
#      testbench into the simulation working directory.
#
# Prerequisites:
#   - program.txt must be in the simulation working directory
#   - All .vhd files must be in the same directory as this script
# ============================================================================

# Create fresh work library
vlib work

# Compile the memory component (PD3 model, modified)
vcom -2008 memory.vhd

# Compile the processor
vcom -2008 processor.vhd

# Compile the testbench
vcom -2008 processor_tb.vhd

# Load and run
vsim -t 1ps work.processor_tb

# Run until the testbench stops itself (after 10000 cycles + dump)
run -all

# Done
quit -f
