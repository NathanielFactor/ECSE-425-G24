#%%
from convert import AssemblyConverter as AC
# instantiate object
# nibble mode means each 32 bit instruction will be devided into groups of 4 bits separated by space in output txt
convert = AC(output_mode = 'f', nibble_mode = False, hex_mode = False)

# Convert a whole .s file to text file
convert("factorial.s", "factorial_bin.txt")

# %%
