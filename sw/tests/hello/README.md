# M0 toolchain smoke test (`hello`)

A tiny bare-metal program that confirms the RISC-V toolchain and Spike work
end-to-end, **before any RTL exists**. It computes `2 + 3`, checks the result is
`5`, and reports pass/fail to the host via the HTIF `tohost` mailbox.

This is deliberately not a "print hello" program: it uses the exact `tohost`
exit-signature mechanism that `riscv-tests` and this project's own self-checking
tests use from M1 onward, so getting it green de-risks the real test flow.

## Build

```sh
riscv64-unknown-elf-gcc \
    -march=rv32im -mabi=ilp32 \
    -nostdlib -nostartfiles \
    -T ../../common/link.ld \
    hello.S -o hello.elf
```

> If your packaged toolchain is named `riscv32-unknown-elf-gcc`, use that and
> drop `-march/-mabi` (or keep them; they are still valid). If neither is
> present, run `scripts/build_toolchain.sh` first.

## Run on Spike (golden model)

```sh
spike --isa=rv32im hello.elf
echo "exit code = $?"
```

## What "passing" looks like

- Spike runs and **terminates on its own** (because of the `tohost` write).
- `exit code = 0`.

An exit code of `1` means the internal `2 + 3 == 5` check failed (which would
indicate a broken toolchain/assembler, not a logic bug — the math is trivial).

## Inspect the disassembly (optional sanity check)

```sh
riscv64-unknown-elf-objdump -d hello.elf | less
```
