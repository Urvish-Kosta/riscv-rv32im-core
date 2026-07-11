#!/usr/bin/env python3
"""Plot CPI/IPC comparison across predictors from measured perf reports.

M0 stub: argument interface is defined so the tool contract is stable, but the
implementation lands at milestone M6. It intentionally does nothing yet rather
than emit placeholder/fabricated output.
"""
import argparse
import sys


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Plot CPI/IPC comparison across predictors from measured perf reports.")
    p.add_argument("reports", nargs="+", help="one or more perf_report outputs to plot")
    p.add_argument("--out", default="cpi.png", help="output image path")
    return p


def main() -> int:
    args = build_parser().parse_args()
    print("plot_cpi: would render the CPI comparison plot.", file=sys.stderr)
    print("Not implemented yet — arrives at milestone M6.", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
