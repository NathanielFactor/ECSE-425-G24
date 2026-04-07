Refer to `__init__.py` to see an example use of the assembler.
- Do not use lines that start with comments, or lines with only space(s) in your source assembly file. These are known to produce compiler error or incorrect PC offset for J-type instructions. Empty lines are fine.
- The assembler produces a log message for each instruction that's translated to binary encoding. Showing the `source`/`destination`/`imm`/`PC offset`/`label` of the parsed instruction, when applicable.
- Some register ABI names may not be supported, e.g. "**zero**" for x0. Replace them with original register names "x*n*" if necessary.
- The attached `factorial.s` is for your convienience.