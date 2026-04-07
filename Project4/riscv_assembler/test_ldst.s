# test_ldst.s
# Store a word to memory, load it back, add to itself
# Expected: x1=42  x2=42  x3=84

    addi x1, x0, 42     # x1 = 42
    sw   x0, x1, 0      # mem[0] = 42   (base=x0, src=x1, offset=0)
    lw   x2, 0(x0)      # x2 = mem[0] = 42
    add  x3, x2, x1     # x3 = 42 + 42 = 84

halt:
    jal  x0, halt
