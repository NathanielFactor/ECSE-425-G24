#!/usr/bin/env python3
# assemble the test programs in this directory
#
# usage:
#   python3 build_all.py                  assemble everything, print summary
#   python3 build_all.py NAME             just NAME (with or without .s)
#   python3 build_all.py --install NAME   also drop result in Project4/program.txt

import contextlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASM = os.path.dirname(HERE)
PROJ = os.path.dirname(os.path.dirname(ASM))

sys.path.insert(0, ASM)
from convert import AssemblyConverter as AC


def assemble(path):
    # the assembler prints a line per parsed instruction; mute it
    with open(os.devnull, "w") as null, contextlib.redirect_stdout(null):
        return AC(output_mode="a")(path)


def install(words):
    with open(os.path.join(PROJ, "program.txt"), "w") as f:
        for w in words:
            f.write(w + "\n")


def main(argv):
    args = argv[1:]
    do_install = False
    if args and args[0] == "--install":
        do_install = True
        args = args[1:]

    if not args:
        ok = fail = 0
        for name in sorted(f for f in os.listdir(HERE) if f.endswith(".s")):
            try:
                words = assemble(os.path.join(HERE, name))
                print(f"  ok    {name:30} {len(words):3} words")
                ok += 1
            except Exception as e:
                print(f"  fail  {name:30} {str(e).splitlines()[0]}")
                fail += 1
        print(f"\n{ok} ok, {fail} fail")
        return 0 if fail == 0 else 1

    name = args[0]
    if not name.endswith(".s"):
        name += ".s"
    path = os.path.join(HERE, name)
    if not os.path.exists(path):
        print(f"no such test: {name}", file=sys.stderr)
        return 2

    try:
        words = assemble(path)
    except Exception as e:
        print(f"fail {name}: {e}", file=sys.stderr)
        return 1

    print(f"ok {name} ({len(words)} words)")
    if do_install:
        install(words)
        print(f"installed -> {os.path.join(PROJ, 'program.txt')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
