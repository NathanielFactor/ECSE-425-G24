# ============================================================================
# testbench_debug.tcl — Full test suite (11 tests)
# ============================================================================
# Usage: In ModelSim transcript:   do testbench_debug.tcl
#
# Tests run:
#   0  Factorial 5! = 120          (program.txt)
#   1  Summation 1+2+...+10 = 55   (test_sum.txt)
#   2  RAW hazard chain             (test_raw.txt)
#   3  Load/store word              (test_ldst.txt)
#   4  Forward branch               (test_fwd_branch.txt)
#   5  JAL/JALR call+return         (test_jalr.txt)
#   6  Negative arithmetic          (test_neg.txt)
#   7  All R+I ALU ops + mul        (test_alu.txt)
#   8  LUI / AUIPC / JAL / JALR     (test_upper_jump.txt)
#   9  All load/store widths        (test_mem.txt)
#  10  All 6 branch types           (test_branches.txt)
#  11  RAW chain + load-use hazard  (test_hazard_stall.txt)
#
# Outputs:
#   test_results.txt  — pass/fail summary for every test
#   pipeline_log.txt  — cycle-by-cycle pipeline trace for each test
# ============================================================================

vlib work
vcom -2008 memory.vhd
vcom -2008 regfile.vhd
vcom -2008 alu.vhd
vcom -2008 hazard_control.vhd
vcom -2008 processor.vhd
vcom -2008 processor_tb.vhd

# ============================================================================
# run_test: load a program, simulate, check registers, log pipeline state
#
# Arguments
#   test_name   human-readable label
#   prog_file   the .txt machine-code file to use as program.txt
#   run_cycles  how many ns to run after the 2000 ns reset phase
#   checks      flat list: reg_index expected_value  reg_index expected_value ...
#   result_fh   file handle for test_results.txt
#   log_fh      file handle for pipeline_log.txt
# ============================================================================
proc run_test {test_name prog_file run_cycles checks result_fh log_fh} {

    puts "================================================================"
    puts "TEST: $test_name"
    puts "================================================================"
    puts $result_fh "================================================================"
    puts $result_fh "TEST: $test_name  (program: $prog_file)"

    # Point program.txt at this test's machine code
    if {$prog_file ne "program.txt"} {
        file copy -force $prog_file program.txt
    }

    # Fresh simulation instance
    vsim -t 1ps work.processor_tb -quiet

    # Reset + program-load phase
    run 2000 ns

    # ------------------------------------------------------------------
    # Pipeline log: first 150 cycles (or fewer if run_cycles < 150)
    # ------------------------------------------------------------------
    set log_cycles 150
    if {$run_cycles < $log_cycles} { set log_cycles $run_cycles }

    puts $log_fh ""
    puts $log_fh "--- $test_name ---"
    puts $log_fh [format "%-4s  %-6s %-6s  %s %s %s  %-10s %-10s %-10s %-10s  %s %-4s %s" \
        "cyc" "pc" "pc_nxt" "fv" "st" "fl" \
        "IF/ID_ir" "ID/EX_ir" "EX/MEM_ir" "MEM/WB_ir" \
        "wb_en" "wb_rd" "wb_data"]

    for {set i 0} {$i < $log_cycles} {incr i} {
        run 1 ns
        set pc    [examine -radix unsigned /processor_tb/dut/pc]
        set pcn   [examine -radix unsigned /processor_tb/dut/pc_nxt]
        set fv    [examine /processor_tb/dut/fetch_valid]
        set st    [examine /processor_tb/dut/stall_sig]
        set fl    [examine /processor_tb/dut/flush_sig]
        set ifid  [examine -radix hex /processor_tb/dut/ifid_ir]
        set idex  [examine -radix hex /processor_tb/dut/idex_ir]
        set exmem [examine -radix hex /processor_tb/dut/exmem_ir]
        set memwb [examine -radix hex /processor_tb/dut/memwb_ir]
        set wben  [examine /processor_tb/dut/wb_wr_en]
        set wba   [examine -radix unsigned /processor_tb/dut/wb_rd_addr]
        set wbd   [examine -radix hex /processor_tb/dut/wb_rd_data]
        puts $log_fh [format "%4d  %6s %6s   %s  %s  %s  %-10s %-10s %-10s %-10s   %s  %-4s %s" \
            $i $pc $pcn $fv $st $fl $ifid $idex $exmem $memwb $wben $wba $wbd]
    }

    # Run remaining cycles without per-cycle logging (faster)
    set remaining [expr {$run_cycles - $log_cycles}]
    if {$remaining > 0} { run ${remaining} ns }

    # ------------------------------------------------------------------
    # Register checks
    # ------------------------------------------------------------------
    set pass    1
    set details ""

    foreach {reg expected} $checks {
        set raw [examine /processor_tb/dut/rf/regs($reg)]

        # Convert 32-bit binary string -> unsigned -> signed integer
        set uval 0
        set nbits [string length $raw]
        for {set b 0} {$b < $nbits} {incr b} {
            if {[string index $raw $b] eq "1"} {
                set uval [expr {$uval | (1 << ($nbits - 1 - $b))}]
            }
        }
        set sval [expr {$uval >= 2147483648 ? $uval - 4294967296 : $uval}]

        if {$sval == $expected} {
            append details "    x${reg} = ${sval}  (expected ${expected})  OK\n"
        } else {
            append details "    x${reg} = ${sval}  (expected ${expected})  *** FAIL ***\n"
            set pass 0
        }
    }

    if {$pass} {
        puts  "  RESULT: PASS"
        puts $result_fh "  RESULT: PASS"
    } else {
        puts  "  RESULT: *** FAIL ***"
        puts $result_fh "  RESULT: *** FAIL ***"
    }
    puts  $details
    puts $result_fh $details

    quit -sim
    return $pass
}

# ============================================================================
# MAIN
# ============================================================================
set result_fh [open "test_results.txt"  w]
set log_fh    [open "pipeline_log.txt"  w]
set total  0
set passed 0

# Keep original program.txt safe
if {[file exists program.txt]} {
    file copy -force program.txt program_original_backup.txt
}

# --------------------------------------------------------------------------
# Test 0 — Factorial  5! = 120
# x5=1  x6=1  x10=120
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "Factorial (5! = 120)" \
    "program.txt" \
    300 \
    {5 1  6 1  10 120} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 1 — Summation 1+2+...+10 = 55
# x1=0  x2=55
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "Summation 1+2+...+10 = 55" \
    "test_sum.txt" \
    500 \
    {1 0  2 55} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 2 — Back-to-back RAW hazard chain
# x1=1 x2=2 x3=3 x4=4 x5=5 x6=6 x7=30 x8=26
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "Back-to-back RAW dependencies" \
    "test_raw.txt" \
    200 \
    {1 1  2 2  3 3  4 4  5 5  6 6  7 30  8 26} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 3 — Load / Store  (sw + lw)
# x1=42  x2=42  x3=84
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "Load/Store word (sw+lw)" \
    "test_ldst.txt" \
    200 \
    {1 42  2 42  3 84} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 4 — Forward branch  (beq taken, skip poison)
# x10=42
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "Forward branch (beq skip)" \
    "test_fwd_branch.txt" \
    200 \
    {10 42} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 5 — JAL / JALR  subroutine call + return
# x10=107  x1=8
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "JAL/JALR call+return" \
    "test_jalr.txt" \
    200 \
    {10 107  1 8} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 6 — Negative arithmetic  (sub, sra, slt)
# x1=-1  x3=-101  x4=1  x5=1  x6=-100
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "Negative number arithmetic" \
    "test_neg.txt" \
    200 \
    {1 -1  3 -101  4 1  5 1  6 -100} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 7 — All R-type + I-type ALU ops + mul
# x3=13 x4=7 x5=2 x6=11 x7=9 x8=8 x9=2
# x11=-1 x12=1 x13=1 x14=30 x15=7 x16=10
# x17=15 x18=5 x19=12 x20=5 x21=-4 x22=1 x23=1
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "All R+I ALU ops + mul" \
    "test_alu.txt" \
    200 \
    {3 13  4 7  5 2  6 11  7 9  8 8  9 2  11 -1  12 1  13 1  14 30  15 7  16 10  17 15  18 5  19 12  20 5  21 -4  22 1  23 1} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 8 — LUI / AUIPC / JAL / JALR
# x1=305418240  x2=4100  x3=12  x4=42  x5=32  x6=28  x7=99
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "LUI / AUIPC / JAL / JALR" \
    "test_upper_jump.txt" \
    200 \
    {1 305418240  2 4100  3 12  4 42  5 32  6 28  7 99} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 9 — All load/store widths + sign/zero extension
# x3=-1  x4=255  x6=-1  x7=65535  x9=2047
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "All load/store widths (lb lbu lh lhu lw sb sh sw)" \
    "test_mem.txt" \
    200 \
    {3 -1  4 255  6 -1  7 65535  9 2047} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 10 — All 6 branch types (beq bne blt bge bltu bgeu), all taken
# x5=1  x6=1  x7=1  x8=1  x10=1  x11=1
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "All 6 branch types taken" \
    "test_branches.txt" \
    300 \
    {5 1  6 1  7 1  8 1  10 1  11 1} \
    $result_fh $log_fh]

# --------------------------------------------------------------------------
# Test 11 — RAW chain + load-use hazard
# x1=1  x2=2  x3=3  x4=4  x5=5  x8=100  x9=105
# --------------------------------------------------------------------------
incr total
incr passed [run_test \
    "RAW chain + load-use hazard" \
    "test_hazard_stall.txt" \
    300 \
    {1 1  2 2  3 3  4 4  5 5  8 100  9 105} \
    $result_fh $log_fh]

# ============================================================================
# Summary
# ============================================================================
set failed [expr {$total - $passed}]

puts  "================================================================"
puts  "SUMMARY: $passed / $total tests passed"
puts  "================================================================"
puts $result_fh "================================================================"
puts $result_fh "SUMMARY: $passed / $total tests passed"
puts $result_fh "================================================================"

close $result_fh
close $log_fh

# Restore original program.txt
if {[file exists program_original_backup.txt]} {
    file copy -force program_original_backup.txt program.txt
}

puts "Results  -> test_results.txt"
puts "Pipeline -> pipeline_log.txt"

if {$failed == 0} {
    puts "ALL $total TESTS PASSED — processor is ready for submission."
} else {
    puts "WARNING: $failed test(s) FAILED — check pipeline_log.txt for details."
}

quit -f