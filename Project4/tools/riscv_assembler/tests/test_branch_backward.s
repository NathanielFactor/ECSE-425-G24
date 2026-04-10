# test_branch_backward.s
# ----------------------------------------------------------------------------
# Tight backward-branch loop -- the canonical "sum 1..N" example. Each
# iteration of the loop costs one taken branch, so this is also a stress
# test for the flush-and-refetch path (10 taken branches in a row).
#
#   counter = 10
#   acc = 0
#   while (counter != 0) { acc += counter; counter -= 1 }
#
# Expected when the loop falls through:
#   x1 = 0           (counter at exit)
#   x2 = 55          (1+2+...+10)

main:
    addi x1, x0, 10      # counter
    addi x2, x0, 0       # accumulator
loop:
    add  x2, x2, x1      # acc += counter
    addi x1, x1, -1      # counter--
    bne  x1, x0, loop    # while counter != 0
halt:
    jal  x0, halt
