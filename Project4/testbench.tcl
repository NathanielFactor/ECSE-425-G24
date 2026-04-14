# ECSE 425 P4 run script.
# Run from Project4/: vsim -do testbench.tcl

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