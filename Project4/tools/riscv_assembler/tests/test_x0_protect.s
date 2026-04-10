# writes to x0 must be ignored.
# expect: x1=7  x2=0  x3=14  x4=0  x0=0

main:
    addi x0, x0, 99
    addi x1, x0, 7
    add  x0, x1, x1
    add  x2, x0, x0
    add  x3, x1, x1
    lui  x0, 12345
    add  x4, x0, x0
    jal  x0, halt        # rd=x0, link must vanish
halt:
    jal  x0, halt
