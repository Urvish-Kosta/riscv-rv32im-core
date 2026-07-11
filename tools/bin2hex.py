#!/usr/bin/env python3
"""bin2hex.py -- convert a flat binary image to a Verilog $readmemh file.

Emits one little-endian 32-bit word per line (8 hex digits). Word 0 corresponds
to the image's lowest load address (RESET_PC). Used to load imem/dmem in sim.

    python3 bin2hex.py program.bin program.hex
"""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: bin2hex.py <in.bin> <out.hex>", file=sys.stderr)
        return 2
    data = open(sys.argv[1], "rb").read()
    if len(data) % 4:
        data += b"\x00" * (4 - len(data) % 4)
    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            word = data[i] | (data[i + 1] << 8) | (data[i + 2] << 16) | (data[i + 3] << 24)
            f.write(f"{word:08x}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
