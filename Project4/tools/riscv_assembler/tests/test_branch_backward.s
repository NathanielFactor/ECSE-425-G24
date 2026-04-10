# sum 1..10 with a backward branch loop.
# expect: x1=0  x2=55

main:
    addi x1, x0, 10      # counter
    addi x2, x0, 0       # acc
loop:
    add  x2, x2, x1
    addi x1, x1, -1
    bne  x1, x0, loop
halt:
    jal  x0, halt
