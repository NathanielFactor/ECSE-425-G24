# test_load_use_chain.s
# ----------------------------------------------------------------------------
# Stresses the load-use stall path: every load is consumed by the very next
# instruction, which is the worst case the hazard detector has to catch
# (one bubble each, since there is no forwarding).
#
# Setup:
#   mem[0..3]   = 11
#   mem[4..7]   = 22
#   mem[8..11]  = 33
#
# Expected:
#   x10 = 11
#   x11 = 22       (= 11 + 11, load-use stall on x10)
#   x12 = 22       (loaded)
#   x13 = 33       (= 22 + 11, load-use stall on x12)
#   x14 = 33       (loaded)
#   x15 = 66       (= 33 + 33, load-use stall on x14)

main:
    addi x1, x0, 11
    addi x2, x0, 22
    addi x3, x0, 33
    sw   x1, 0(x0)
    sw   x2, 4(x0)
    sw   x3, 8(x0)

    lw   x10, 0(x0)        # x10 = 11
    add  x11, x10, x10     # IMMEDIATE use of x10 (1 bubble)

    lw   x12, 4(x0)        # x12 = 22
    add  x13, x12, x10     # IMMEDIATE use of x12 (1 bubble)

    lw   x14, 8(x0)        # x14 = 33
    add  x15, x14, x13     # IMMEDIATE use of x14 (1 bubble)

halt:
    jal  x0, halt
