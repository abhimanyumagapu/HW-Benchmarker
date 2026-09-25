#!/usr/bin/env python3
"""STEAD FAIL line for one failed openc910 ISA test.

usage: stead_line.py <test> <elf> <trace> <dump>

Every check in the ISA tests is a branch comparing a computed register with
an expected one, on a path that ends at crt0's __fail. The failing check is
the last conditional branch retired before __fail. The testbench trace
(`trace_file=`) gives its retire id, and the branch unit's operands for that
id: S is the branch unit's operand holding the computed value, T the time the
dump holds it, A that value, E the other operand's. The test is written
<test>:<section>, the section being the label before the check (XORI, REMW,
...), as scr1's per-instruction test names do; bake reruns the spec's test,
not this field.

The expected register is the one written last before the branch: the tests
compute a result, then load the value it should be. Only a check whose fail
condition is "not equal" has one expected value; any other prints a NOTE.
"""

import re
import subprocess
import sys
from pathlib import Path

BJU = (
    "TOP.top.x_soc.x_cpu_sub_system_axi.x_rv_integration_platform.x_cpu_top"
    ".x_ct_top_0.x_ct_core.x_ct_iu_top.x_ct_iu_bju.idu_iu_rf_pipe2_src"
)
TOOL = "riscv64-unknown-elf-"
BRANCH = {"beq", "bne", "blt", "bge", "bltu", "bgeu", "c.beqz", "c.bnez"}
NEGATE = {"eq": "ne", "ne": "eq", "lt": "ge", "ge": "lt", "ltu": "geu", "geu": "ltu"}
NO_RD = ("s", "c.s", "fs", "c.fs", "th.s", "th.fs", "b", "c.b", "fence", "ecall", "ebreak")
INSN = re.compile(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(\S+)\s*([^#<]*)")


def disassemble(elf):
    """pc -> (mnemonic, [operands]), canonical forms."""
    out = subprocess.run(
        [f"{TOOL}objdump", "-d", "-M", "numeric,no-aliases", elf],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    code = {}
    for line in out.splitlines():
        m = INSN.match(line)
        if m:
            ops = [o.strip() for o in m.group(3).split(",") if o.strip()]
            code[int(m.group(1), 16)] = (m.group(2), ops)
    return code


def symbols(elf):
    """Code labels: name -> address."""
    out = subprocess.run([f"{TOOL}nm", elf], capture_output=True, text=True, check=True).stdout
    return {
        f[2]: int(f[0], 16)
        for f in (line.split() for line in out.splitlines())
        if len(f) == 3 and f[1] in "tT"
    }


def section(labels, pc):
    """The last label at or before pc: the test's section holding that check."""
    return max(((a, n) for n, a in labels.items() if a <= pc), default=(0, "?"))[1]


def written(mnemonic, ops):
    """The x registers an instruction writes."""
    if mnemonic.startswith(NO_RD) or not ops:
        return set()
    regs = {ops[0]} if re.fullmatch(r"x\d+", ops[0]) else set()
    if mnemonic in ("th.ldd", "th.lwd", "th.lwud"):
        regs.add(ops[1])
    if mnemonic.startswith("th.l") and mnemonic[-2:] in ("ia", "ib"):
        regs.add(ops[1].strip("()"))
    return regs - {"x0"}


def trace(path):
    retired, bju = [], []
    for line in Path(path).read_text().splitlines():
        f = line.split()
        if f[0] == "R":
            retired.append((int(f[1]), int(f[2]), int(f[3], 16), int(f[4])))
        elif f[0] == "B":
            bju.append((int(f[1]), int(f[2]), int(f[3], 16), int(f[4], 16)))
    retired.sort(key=lambda r: (r[0], r[1]))  # program order
    return retired, bju


def note(test, why):
    print(f"NOTE  test={test}  no STEAD record: {why}")
    sys.exit(0)


def main():
    test, elf, trace_path, dump = sys.argv[1:5]
    code = disassemble(elf)
    labels = symbols(elf)
    fail = labels.get("__fail")
    retired, bju = trace(trace_path)
    pcs = [r[2] for r in retired]
    if fail not in pcs:
        note(test, "the run never reached __fail")
    end = pcs.index(fail)
    at = next((i for i in range(end - 1, -1, -1) if code.get(pcs[i], ("",))[0] in BRANCH), None)
    if at is None:
        note(test, "no conditional branch retired before __fail")
    mnemonic, ops = code[pcs[at]]
    check = section(labels, pcs[at])
    where = f"failed check in section {check} at 0x{pcs[at]:x}"
    rs1, rs2 = (ops[0], "x0") if mnemonic.startswith("c.") else (ops[0], ops[1])
    cond = mnemonic.removeprefix("c.").removeprefix("b").removesuffix("z")
    taken = int(ops[-1], 16) == pcs[at + 1]
    if not taken:  # an inverted branch skipping the jump to the fail label
        cond = NEGATE[cond]
    if cond != "ne":
        note(test, f"{where}, a {mnemonic} that wants no single value")
    last = {}
    for i in range(at):
        for reg in written(*code.get(pcs[i], ("", []))):
            last[reg] = i
    # x0 is never written: it is the expected side of a compare against zero
    expected_is_rs2 = last.get(rs2, -1 if rs2 != "x0" else at) >= last.get(rs1, -1)
    time, _slot, _pc, iid = retired[at]
    ops_at = [b for b in bju if b[1] == iid and b[0] <= time]
    if not ops_at:
        note(test, f"{where}: the branch unit never took iid {iid}")
    t, _iid, src0, src1 = ops_at[-1]
    actual, expected, n = (src0, src1, 0) if expected_is_rs2 else (src1, src0, 1)
    if rs2 == "x0":
        expected = 0
    print(
        f"FAIL  test={test}:{check}  signal={BJU}{n}  time={t}  "
        f"expected=0x{expected:016x}  actual=0x{actual:016x}  dump={dump}"
    )


if __name__ == "__main__":
    main()
