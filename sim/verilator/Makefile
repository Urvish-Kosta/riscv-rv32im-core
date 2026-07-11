# -----------------------------------------------------------------------------
# sim/verilator/Makefile  --  build the single-cycle core simulator (M1)
#
#   make                       # build ./obj_dir/Vcore_top
#   make run HEX=path.hex      # build + run a program image
#   make clean
# -----------------------------------------------------------------------------
VERILATOR ?= verilator
TOP       := core_top
HEX       ?=
MAXCYC    ?= 100000

RTL := ../../rtl/include/riscv_pkg.sv \
       ../../rtl/core/regfile.sv \
       ../../rtl/core/alu.sv \
       ../../rtl/core/imm_gen.sv \
       ../../rtl/core/control.sv \
       ../../rtl/core/core_top.sv \
       ../../rtl/mem/imem.sv \
       ../../rtl/mem/dmem.sv

VFLAGS := --cc --exe --build -j 0 --trace -Wall \
          --top-module $(TOP) \
          -I../../rtl/include

EXE := obj_dir/V$(TOP)

.PHONY: default run clean
default: $(EXE)

$(EXE): $(RTL) main.cpp
	$(VERILATOR) $(VFLAGS) $(RTL) main.cpp -o V$(TOP)

run: $(EXE)
	@test -n "$(HEX)" || { echo "usage: make run HEX=<image.hex> [MAXCYC=n]"; exit 2; }
	$(EXE) +hex=$(HEX) +max_cycles=$(MAXCYC)

clean:
	rm -rf obj_dir wave.vcd
