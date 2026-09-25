#!/usr/bin/env python3
"""srec2vmem.py <srec> <vmem>: the tests' Srec2vmem, which ships only as an x86-64 binary.

Four 32-bit words to a line, each word four bytes in address order, the line prefixed with its
word offset from the file's lowest address. Gaps are zero.
"""

import sys

data = {}
for line in open(sys.argv[1]):
    kind = line[:2]
    if kind not in ("S1", "S2", "S3"):
        continue
    width = {"S1": 4, "S2": 6, "S3": 8}[kind]
    count = int(line[2:4], 16)
    addr = int(line[4 : 4 + width], 16)
    body = bytes.fromhex(line[4 + width : 4 + 2 * count - 2])
    for i, b in enumerate(body):
        data[addr + i] = b
with open(sys.argv[2], "w") as out:
    if data:
        base, end = min(data), max(data) + 1
        for row in range(0, end - base, 16):
            words = (
                "".join(f"{data.get(base + row + w * 4 + k, 0):02x}" for k in range(4)) for w in range(4)
            )
            out.write(f"@{row // 4:08x}  " + "".join(f"{w}  " for w in words) + "\n")
