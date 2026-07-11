/* ---------------------------------------------------------------------------
 * link.ld  --  minimal bare-metal linker script for Spike
 *
 * Places code at Spike's default reset vector (0x80000000) and exposes the
 * HTIF `tohost` / `fromhost` symbols that Spike looks up by name to implement
 * program exit. This is the same signalling mechanism riscv-tests uses, so the
 * M0 "hello" already exercises the exit protocol the real test harness relies
 * on at M1+.
 * ------------------------------------------------------------------------- */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;

  .text.init : { *(.text.init) }
  .text      : { *(.text) *(.text.*) }

  .rodata    : { *(.rodata) *(.rodata.*) }
  .data      : { *(.data) *(.data.*) }
  .bss       : { *(.bss)  *(.bss.*) *(COMMON) }

  /* HTIF mailbox. Spike resolves these symbols to drive host <-> target I/O. */
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
}
