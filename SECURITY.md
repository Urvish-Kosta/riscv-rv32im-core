# Security policy

## Scope

This repository contains a RISC-V CPU core intended for **simulation and
education**. It is not a security-hardened design and has never been run on
hardware. It implements no privileged modes, no memory protection, no
isolation boundaries, and no side-channel countermeasures. Do not use it where
any of those matter.

Known and deliberate gaps, all documented in `docs/isa-support.md`:

- no privileged spec, traps, or interrupts;
- no virtual memory or PMP;
- CSR writes have no effect (every implemented CSR is a read-only counter);
- unimplemented CSRs read as zero rather than raising an illegal-instruction
  exception;
- `FENCE`, `ECALL`, and `EBREAK` decode as NOPs.

## Reporting a vulnerability

For a defect in the RTL, tooling, or build scripts, please open a GitHub issue
with a reproducer. If you would rather not report publicly, contact the author
through the address on the GitHub profile.

Because this is a simulation-only project, the practical severity of most
findings is low; correctness bugs are nonetheless taken seriously and are what
this project most wants to hear about.

## Supply chain

The build depends on Verilator, an LLVM or GNU RISC-V cross-toolchain, Python 3
with matplotlib/pandas, and GNU Make. No dependency is vendored into this
repository, and no build step downloads code at compile time. CI installs
toolchain packages from the runner's distribution repositories.
