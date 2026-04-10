# test_fwd_branch.s
# BEQ taken: skip over the addi x10=99, land on addi x10=42
# Expected: x1=5  x2=5  x10=42

    addi x1, x0, 5      # x1 = 5
    addi x2, x0, 5      # x2 = 5
    beq  x1, x2, skip   # x1 == x2, so jump to skip
    addi x10, x0, 99    # SKIPPED

halt:
    jal  x0, halt

skip:
    addi x10, x0, 42    # x10 = 42

end:
    jal  x0, end
