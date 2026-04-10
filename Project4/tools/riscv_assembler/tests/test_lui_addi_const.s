# test_lui_addi_const.s
# ----------------------------------------------------------------------------
# The standard "build a 32-bit constant" idiom in RISC-V: lui sets the upper
# 20 bits, addi adds a 12-bit signed extension. This test sticks to positive
# lower halves so it doesn't need the +1 correction that the negative-lower
# case requires.
#
# Constants built (decimal -> hex):
#   x1 = 4096        = 0x00001000
#   x2 = 74565       = 0x00012345  (lui 18 -> 73728, addi 837)
#   x3 = 268431360   = 0x0FFFF000  (lui 65535 -> upper 20 bits all ones)

main:
    lui  x1, 1               # x1 = 1 << 12 = 4096
    addi x1, x1, 0           # +0 (kept for symmetry; the addi is a no-op)

    lui  x2, 18              # x2 = 18 << 12 = 73728
    addi x2, x2, 837         # x2 = 73728 + 837 = 74565

    lui  x3, 65535           # x3 = 65535 << 12 = 0x0FFFF000
    addi x3, x3, 0

halt:
    jal  x0, halt
