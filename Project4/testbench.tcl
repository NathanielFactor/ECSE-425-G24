# ============================================================================
# ECSE 425 Project 4 -- ModelSim/Questa run script
# ============================================================================
# Usage:  vsim -do testbench.tcl
#
# What this script does, in order:
#   1. Make a fresh `work` library so stale .qdb files from a previous
#      run can't poison the compile.
#   2. Compile every .vhd source in dependency order. The leaf modules
#      (memory, regfile, alu, hazard_control) have no inter-dependencies,
#      so their order between themselves doesn't matter -- but the
#      processor depends on all of them, and the testbench depends on
#      the processor, so those two must come last.
#   3. Elaborate the testbench with a 1 ps simulation resolution.
#      (Our clock period is 1 ns and we never need finer than that.)
#   4. `run -all` blocks until the testbench fires its terminating
#      `assert false`, at which point we quit cleanly.
#
# Prerequisites in the working directory at run time:
#   - program.txt   (one 32-bit binary word per line, MSB first)
#   - src/          (the five RTL files)
#   - sim/          (the testbench)
#
# Outputs land in the working directory (not in src/ or sim/):
#   - register_file.txt   (32 lines, x0 .. x31)
#   - memory.txt          (8192 lines, one word per data-mem slot)
# ============================================================================

# Fresh work library every run -- avoids stale qdb files
vlib work

# Compile order: leaves first, then processor, then testbench.
# Sources live under src/ (synthesisable RTL) and sim/ (testbench only).
# Everything is compiled into the default `work` library, so no extra
# library switches are needed at elaboration time.
vcom -2008 src/memory.vhd
vcom -2008 src/regfile.vhd
vcom -2008 src/alu.vhd
vcom -2008 src/hazard_control.vhd
vcom -2008 src/processor.vhd
vcom -2008 sim/processor_tb.vhd

# Elaborate at 1 ps resolution (clock is 1 ns)
vsim -t 1ps work.processor_tb

# Block here until processor_tb's terminating assert fires
run -all

# Clean exit -- no GUI window to leave hanging
quit -f