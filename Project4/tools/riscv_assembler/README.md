# RISC-V assembler

Small Python assembler for the RV32I subset the processor implements,
plus `mul` from RV32M. Output format is what the processor's loader
wants: one 32-bit word per line, MSB first, addresses ascending.

## Layout

```
riscv_assembler/
├── __init__.py        usage example
├── convert.py         AssemblyConverter (entry point)
├── parse.py           tokeniser, label resolver
├── instr_arr.py       instruction tables and encoders
├── data/
│   ├── instr_data.dat opcode/funct3/funct7 table
│   └── reg_map.dat    ABI name -> xN
├── factorial.s        the assignment's example program
└── tests/
    ├── build_all.py
    └── test_*.s       19 small test programs
```

## Quick start

From the project root:

```sh
cd Project4/tools/riscv_assembler
python3 -c "import sys; sys.path.insert(0,'.'); \
    from convert import AssemblyConverter as AC; \
    AC(output_mode='f')('factorial.s', '../../program.txt')"
```

Or use the test runner under `tests/`:

```sh
cd Project4/tools/riscv_assembler/tests
python3 build_all.py                          # assemble all
python3 build_all.py test_branches            # one
python3 build_all.py --install test_branches  # one + drop in ../../../program.txt
```

## Syntax

- `#` starts an end-of-line comment. Lines that *start* with `#` aren't
  allowed - the comment must follow some code, or the line must be blank.
- Blank lines and arbitrary whitespace are fine.
- Labels: `name:` on a line by itself.
- Registers: `x0`..`x31` and ABI names (`zero`, `ra`, `sp`, `t0`..`t6`,
  `s0`..`s11`, `a0`..`a7`, `fp`).
- Branches and jumps take label operands.
- Loads and stores are `lw rd, imm(rs1)` and `sw rs2, imm(rs1)`.
- Pseudos: `nop`, `mv`, `not`, `neg`, `j`, `li`. Note `li` only emits a
  `lui` and won't handle the lower 12 bits.

## Notes

A couple of things were broken upstream and got fixed in this fork:

- `slt`, `lh`, `srli` were missing from the I/R instruction tables in
  `instr_arr.py` even though their opcode rows were in `instr_data.dat`.
  `srli` was also spelled `slri` in the data file. Both fixed.
- The B-type and J-type immediate encoders packed the byte offset
  directly into the instruction field instead of using the standard
  scrambled encoding from the RV reference card. They now match the
  ALU's immediate generator.
- The I-type encoder ignored funct7, so `srai` silently encoded as
  `srli`. Fixed for `slli`/`srli`/`srai`.
