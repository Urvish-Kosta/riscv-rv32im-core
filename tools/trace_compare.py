#!/usr/bin/env python3
"""Diff an RTL retire-trace against a Spike commit-log to prove instruction-level equivalence.

M0 stub: argument interface is defined so the tool contract is stable, but the
implementation lands at milestone M1. It intentionally does nothing yet rather
than emit placeholder/fabricated output.
"""
import argparse
import sys


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Diff an RTL retire-trace against a Spike commit-log to prove instruction-level equivalence.")
    p.add_argument("rtl_trace", help="path to the RTL retire-trace")
    p.add_argument("spike_log", help="path to the Spike -l commit log")
    return p


def main() -> int:
    args = build_parser().parse_args()
    print("trace_compare: would diff RTL trace vs Spike log and localize the first divergence.", file=sys.stderr)
    print("Not implemented yet — arrives at milestone M1.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
