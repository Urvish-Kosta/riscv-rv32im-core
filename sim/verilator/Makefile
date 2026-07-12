# -----------------------------------------------------------------------------
# sim/verilator/Makefile -- build the RV32I core simulators.
#
#   make            # build the single-cycle reference  -> obj_dir/Vcore_top
#   make pipe       # build the 5-stage pipeline (M2)    -> obj_dir_pipe/Vcore_pipe
#   make both       # build both
#   make run  HEX=path.hex   # build + run single-cycle
#   make runp HEX=path.hex   # build + run pipeline
#   make clean
# -----------------------------------------------------------------------------
VERILATOR ?= verilator
HEX       ?=
MAXCYC    ?= 100000

RTL_COMMON := ../../rtl/include/riscv_pkg.sv \
              ../../rtl/core/regfile.sv \
              ../../rtl/core/alu.sv \
              ../../rtl/core/imm_gen.sv \
              ../../rtl/core/control.sv \
              ../../rtl/mem/imem.sv \
              ../../rtl/mem/dmem.sv

RTL_CORE := $(RTL_COMMON) ../../rtl/core/core_top.sv
RTL_PIPE := $(RTL_COMMON) ../../rtl/core/core_pipe.sv

VFLAGS := --cc --exe --build -j 0 --trace -Wall -I../../rtl/include

CORE := obj_dir/Vcore_top
PIPE := obj_dir_pipe/Vcore_pipe

.PHONY: default pipe both run runp clean
default: $(CORE)
pipe:    $(PIPE)
both:    $(CORE) $(PIPE)

$(CORE): $(RTL_CORE) main.cpp
	$(VERILATOR) $(VFLAGS) --top-module core_top --Mdir obj_dir \
	    $(RTL_CORE) main.cpp -o Vcore_top

$(PIPE): $(RTL_PIPE) main.cpp
	$(VERILATOR) $(VFLAGS) --top-module core_pipe --Mdir obj_dir_pipe \
	    -CFLAGS -DDUT_PIPE $(RTL_PIPE) main.cpp -o Vcore_pipe

run: $(CORE)
	@test -n "$(HEX)" || { echo "usage: make run HEX=<image.hex>"; exit 2; }
	$(CORE) +hex=$(HEX) +max_cycles=$(MAXCYC)

runp: $(PIPE)
	@test -n "$(HEX)" || { echo "usage: make runp HEX=<image.hex>"; exit 2; }
	$(PIPE) +hex=$(HEX) +max_cycles=$(MAXCYC)

clean:
	rm -rf obj_dir obj_dir_pipe wave.vcd
