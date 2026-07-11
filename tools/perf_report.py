#!/usr/bin/env python3
"""Compute CPI/IPC, misprediction rate, and stall breakdown from committed performance counters.

M0 stub: argument interface is defined so the tool contract is stable, but the
implementation lands at milestone M5. It intentionally does nothing yet rather
than emit placeholder/fabricated output.
"""
import argparse
import sys


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Compute CPI/IPC, misprediction rate, and stall breakdown from committed performance counters.")
    p.add_argument("counters", help="path to the dumped performance-counter file")
    p.add_argument("--predictor", default=None, help="predictor label for the report")
    return p


def main() -> int:
    args = build_parser().parse_args()
    print("perf_report: would compute real, measured CPI/IPC from counter dumps.", file=sys.stderr)
    print("Not implemented yet — arrives at milestone M5.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
