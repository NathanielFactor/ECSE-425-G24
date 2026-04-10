# test_x0_protect.s
# ----------------------------------------------------------------------------
# x0 must read as zero no matter what we try to write into it. The pipeline
# has three independent guards (regfile write enable mask, regfile read mux,
# regfile dump mux) so this exercises all of them.
#
# Expected register file after execution:
#   x0 = 0       (always)
#   x1 = 7       (proves x0 still reads as 0 after we tried to write 99 to it)
#   x2 = 0       (x0 + x0 = 0, even after the R-type write attempt)
#   x3 = 14      (x1 + x1; sanity check that ordinary writes still work)
#   x4 = 0       (jal with rd=x0 must discard PC+4)

main:
    addi x0, x0, 99      # try to clobber x0 via I-type
    addi x1, x0, 7       # x1 = 7  (would be 106 if x0 had taken the write)
    add  x0, x1, x1      # try to clobber x0 via R-type
    add  x2, x0, x0      # x2 = 0
    add  x3, x1, x1      # x3 = 14
    lui  x0, 12345       # try to clobber x0 via U-type
    add  x4, x0, x0      # x4 = 0
    jal  x0, halt        # jal with rd=x0 -- the link value must vanish
halt:
    jal  x0, halt
