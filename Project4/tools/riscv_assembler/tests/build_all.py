#!/usr/bin/env python3
"""
build_all.py -- assemble every .s file in this directory and report status.

Usage:
    python3 build_all.py            # assemble all, print pass/fail summary
    python3 build_all.py NAME       # assemble just NAME (with or without .s)
    python3 build_all.py --install NAME
                                    # assemble NAME and copy the result over
                                    # Project4/program.txt so the next vsim
                                    # run picks it up

The bundled assembler lives one directory up. We import it directly rather
than going through the package machinery so this script doesn't care about
how the user invokes it.
"""

import contextlib
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASM_DIR = os.path.dirname(HERE)
PROJECT4 = os.path.dirname(os.path.dirname(ASM_DIR))

sys.path.insert(0, ASM_DIR)
from convert import AssemblyConverter as AC  # noqa: E402


def assemble(src_path):
    """Run the assembler on `src_path` and return the list of binary words."""
    converter = AC(output_mode="a")
    # The assembler is chatty -- it logs every parse step to stdout. Swallow
    # that here so the build summary stays readable.
    with open(os.devnull, "w") as devnull, contextlib.redirect_stdout(devnull):
        return converter(src_path)


def write_program_txt(words, dest_path):
    """Write the assembled words out in the format the processor loader expects."""
    with open(dest_path, "w") as out:
        for w in words:
            out.write(w + "\n")


def main(argv):
    args = argv[1:]
    install = False
    if args and args[0] == "--install":
        install = True
        args = args[1:]

    # No name given -> assemble everything in this directory and tally results.
    if not args:
        sources = sorted(f for f in os.listdir(HERE) if f.endswith(".s"))
        ok = []
        fail = []
        for name in sources:
            try:
                words = assemble(os.path.join(HERE, name))
                ok.append((name, len(words)))
            except Exception as exc:
                fail.append((name, str(exc).splitlines()[0]))

        for name, n in ok:
            print(f"  OK    {name:30} {n:3} words")
        for name, msg in fail:
            print(f"  FAIL  {name:30} {msg}")
        print(f"\n{len(ok)} passed, {len(fail)} failed")
        return 0 if not fail else 1

    # Single-file mode: accept the .s suffix or not, doesn't matter.
    name = args[0]
    if not name.endswith(".s"):
        name = name + ".s"
    src = os.path.join(HERE, name)
    if not os.path.exists(src):
        print(f"no such test: {name}", file=sys.stderr)
        return 2

    try:
        words = assemble(src)
    except Exception as exc:
        print(f"FAIL {name}: {exc}", file=sys.stderr)
        return 1

    print(f"OK   {name}  ({len(words)} words)")

    if install:
        target = os.path.join(PROJECT4, "program.txt")
        write_program_txt(words, target)
        print(f"installed -> {target}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
