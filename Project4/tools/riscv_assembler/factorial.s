main:
    addi  a0, x0, 5       # set n = 5
    jal   fact              # jump and link

stop: 
    j     stop              # infinite loop



fact:
    add   t0, x0, a0      # move argument to temporary
    addi  a0, x0, 1       # initialize return value to 1

fact_l:
    slti  t1, t0, 2         # t1 = t0<2 ? 1 : 0
    bne   t1, x0, done    # if i<2, we're done!
    mul   a0, a0, t0        
    addi  t0, t0, -1        # i--
    jal   x0, fact_l      # jump to loop

done:
    jalr  x0, ra, 0       # return
