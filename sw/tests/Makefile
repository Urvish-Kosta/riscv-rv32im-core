# -----------------------------------------------------------------------------
# sw/tests/Makefile -- build and run the self-checking ISA tests on the core.
#
#   make run          # build sim (if needed) + all tests, report pass/fail
#   make build        # just build the .hex images
#   make clean
#
# Toolchain autodetect: prefers a riscv*-unknown-elf- GNU toolchain if present,
# otherwise falls back to clang cross-compilation (+ lld + llvm-objcopy).
# -----------------------------------------------------------------------------
RISCV_PREFIX ?= $(shell for p in riscv32-unknown-elf- riscv64-unknown-elf- riscv-none-elf-; do \
                   command -v $${p}gcc >/dev/null 2>&1 && { echo $$p; break; }; done)

ifeq ($(RISCV_PREFIX),)
  CC      := clang --target=riscv32-unknown-elf -fuse-ld=lld
  OBJCOPY := llvm-objcopy
else
  CC      := $(RISCV_PREFIX)gcc
  OBJCOPY := $(RISCV_PREFIX)objcopy
endif

COMMON  := ../common
CFLAGS  := -march=rv32im_zicsr -mabi=ilp32 -mno-relax -nostdlib -nostartfiles \
           -ffreestanding -I$(COMMON) -Wl,-T,$(COMMON)/link.ld
SIM     ?= ../../sim/verilator/obj_dir/Vcore_top
BIN2HEX := ../../tools/bin2hex.py
MAXCYC  ?= 20000

BUILD   := build
TESTS   := $(patsubst isa/%.S,%,$(wildcard isa/*.S))
HEXES   := $(addprefix $(BUILD)/,$(addsuffix .hex,$(TESTS)))

.PHONY: run build clean sim
run: build
	@pass=0; fail=0; \
	for t in $(TESTS); do \
	  printf "  %-16s " $$t; \
	  if $(SIM) +hex=$(BUILD)/$$t.hex +max_cycles=$(MAXCYC) >$(BUILD)/$$t.log 2>&1; then \
	    echo "PASS"; pass=$$((pass+1)); \
	  else \
	    echo "FAIL"; sed 's/^/      /' $(BUILD)/$$t.log | tail -2; fail=$$((fail+1)); \
	  fi; \
	done; \
	echo "  ------------------------------"; \
	echo "  passed=$$pass  failed=$$fail"; \
	test $$fail -eq 0

build: $(HEXES)

$(BUILD)/%.elf: isa/%.S $(COMMON)/crt.S $(COMMON)/test.h $(COMMON)/link.ld
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(COMMON)/crt.S $< -o $@

$(BUILD)/%.hex: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $(BUILD)/$*.bin
	python3 $(BIN2HEX) $(BUILD)/$*.bin $@

clean:
	rm -rf $(BUILD)
