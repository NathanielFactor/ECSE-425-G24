# test_auipc.s
# ----------------------------------------------------------------------------
# auipc rd, imm   ==>   rd = PC_of_this_instruction + (imm << 12)
#
# The interesting bit is that the result depends on the *address of the
# auipc itself*, so each instance produces a different value even with
# the same immediate. We line up four auipcs and check the math.
#
# Address layout (each instruction is 4 bytes, execution starts at 0):
#   0x00:  auipc x1, 0      ->  x1 = 0  + 0    = 0
#   0x04:  auipc x2, 1      ->  x2 = 4  + 4096 = 4100
#   0x08:  auipc x3, 2      ->  x3 = 8  + 8192 = 8200
#   0x0C:  auipc x4, 0      ->  x4 = 12 + 0    = 12
#   0x10:  jal x0, halt
#
# Expected:
#   x1=0  x2=4100  x3=8200  x4=12

main:
    auipc x1, 0
    auipc x2, 1
    auipc x3, 2
    auipc x4, 0
halt:
    jal   x0, halt
