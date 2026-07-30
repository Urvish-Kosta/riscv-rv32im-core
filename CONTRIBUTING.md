# Contributing

This is a personal portfolio project, but issues, questions, and patches are
welcome — particularly bug reports against the RTL, since a genuine
counter-example is the most valuable thing anyone can send.

## Ground rules

The project has one non-negotiable rule that predates every other convention
here:

> **Never state a result that was not produced by a committed, re-runnable
> script.** No estimated performance numbers, no benchmark scores from
> approximated benchmarks, no claims about hardware this has never run on.

If a change adds a claim to the documentation, it must also add the script or
test that produces it.

## Before opening a pull request

```sh
make -C sim/verilator both        # both cores must build with zero warnings
make -C sim/verilator mdu_tb      # MDU vs. behavioural spec
make -C sw/tests run              # ISA suite on the reference core
bash scripts/run_pipe_diff.sh        # differential, all predictor modes
bash scripts/run_lockstep.sh         # retire-trace lockstep comparison
bash scripts/run_benchmarks.sh       # self-checking benchmarks
```

All of these run in CI. The Verilator build treats warnings as errors: if a
signal is only partially used on purpose, add a narrow `lint_off/lint_on`
waiver with a comment saying why, rather than relaxing the flags globally.

## Reporting an RTL bug

The most useful report is a program that diverges. If you have one:

1. Run it on both cores with `+trace_file=`.
2. Run `python3 tools/trace_compare.py ref.trace pipe.trace`.
3. Paste the localized divergence — it names the exact retired instruction.

Small self-checking assembly programs are ideal;
`tools/gen_pipe_test.py <seed> <n> --hazard` will also generate them.

## Style

- SystemVerilog: `always_ff` / `always_comb`, explicit types, one module per
  file, package-level types instead of magic numbers.
- Commit messages: Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`,
  `refactor:`, `perf:`, `build:`, `ci:`, `chore:`), one logical change each.
- Design decisions with a trade-off worth defending go in
  `docs/design-decisions.md` as a numbered entry — choice, why, trade-off.
- When code and documentation disagree, the code is right and the documentation
  is a bug.
