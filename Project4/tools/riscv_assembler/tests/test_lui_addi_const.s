# build 32-bit constants with lui+addi (positive lower halves only).
# expect: x1=4096  x2=74565  x3=268431360

main:
    lui  x1, 1               # 0x00001000
    addi x1, x1, 0

    lui  x2, 18              # 0x00012000
    addi x2, x2, 837         # + 0x345 = 0x00012345

    lui  x3, 65535           # 0x0FFFF000
    addi x3, x3, 0
halt:
    jal  x0, halt
