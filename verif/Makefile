# -------------------------------------------------------------
# Makefile – Verilator simulation for rv32i_core + tb_top
# -------------------------------------------------------------
# Usage:
#   make REPO_ROOT=..  -> compile design & run sim
#   make run           -> run simulation again (skip compilation)
#   make clean         -> remove obj_dir and binary
# -------------------------------------------------------------

# Repo root must be set (contains rtl.f)
REPO_ROOT    ?= ..

# Top-level testbench
TB_TOP       ?= tb_top

# Verilator options (compatible with 5.006+)
VERILATOR_FLAGS = \
  --binary --timing \
  --top-module $(TB_TOP) \
  -Wall --Wno-fatal \
  --trace \
  -CFLAGS "-std=c++17" \
  -I$(REPO_ROOT) \
  -f $(REPO_ROOT)/rtl.f \
  -f tb_files.f \
  +define+VIVADO_SIM +define+USE_SRAM +define+tracer

SIM     = obj_dir/V$(TB_TOP)
TARGET  = $(SIM)

# Collect all RTL and TB source files for dependency tracking
RTL_SRCS := $(shell cat $(REPO_ROOT)/rtl.f 2>/dev/null | sed 's|^|$(REPO_ROOT)/|')
TB_SRCS  := $(shell cat tb_files.f 2>/dev/null)

.PHONY: all clean run build_verilator_sim

all: $(TARGET) run

$(TARGET): $(REPO_ROOT)/rtl.f tb_files.f $(RTL_SRCS) $(TB_SRCS)
	verilator $(VERILATOR_FLAGS)
	$(MAKE) -C obj_dir -j -f V$(TB_TOP).mk

build_verilator_sim: $(TARGET)

run: $(TARGET)
	$(SIM)

clean:
	rm -rf obj_dir V$(TB_TOP) trace_core_*.log
