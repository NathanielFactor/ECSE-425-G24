# ECSE 425 P4 run script. Usage: vsim -do testbench.tcl
#
# Reads program.txt, writes register_file.txt and memory.txt next to this
# script. Outputs the dumps after the processor has run for 10000 cycles.

# work from this script's own directory so relative paths resolve
cd [file dirname [file normalize [info script]]]

vlib work

vcom -2008 src/memory.vhd
vcom -2008 src/regfile.vhd
vcom -2008 src/alu.vhd
vcom -2008 src/hazard_control.vhd
vcom -2008 src/processor.vhd
vcom -2008 sim/processor_tb.vhd

vsim -t 1ps work.processor_tb
run -all
quit -f