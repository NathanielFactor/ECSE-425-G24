# test_hazard_stall.s
# Tests RAW hazard stalling (5-deep chain) and load-use hazard
# Expected: x1=1 x2=2 x3=3 x4=4 x5=5  x7=100 x8=100 x9=105

    # RAW chain - each depends on the previous result
    addi x1, x0, 1       # x1 = 1
    addi x2, x1, 1       # x2 = x1 + 1 = 2   (RAW on x1)
    addi x3, x2, 1       # x3 = x2 + 1 = 3   (RAW on x2)
    addi x4, x3, 1       # x4 = x3 + 1 = 4   (RAW on x3)
    addi x5, x4, 1       # x5 = x4 + 1 = 5   (RAW on x4)

    # Load-use hazard - load then immediately use result
    addi x6, x0, 0       # x6 = 0  (base address)
    addi x7, x0, 100     # x7 = 100
    sw   x7, 0(x6)       # mem[0] = 100  (store x7 at address 0+x6)
    lw   x8, 0(x6)       # x8 = mem[0] = 100  (load)
    addi x9, x8, 5       # x9 = x8 + 5 = 105  (RAW load-use: stall required)

halt:
    jal  x0, halt
