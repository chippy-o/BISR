#=============================================================================
# Icarus Verilog runs for the Shared BISR project
#
#   make all          every unit test + all system configurations
#   make unit         unit tests only
#   make shared       directed scenarios, proposed shared BISR
#   make dedicated    directed scenarios, dedicated baseline (1 local spare)
#   make equal        directed scenarios, dedicated with 2 local spares
#   make random       random campaign on all three (N=$(NRAND), SEED=$(SEED))
#   make clean
#
# Override sizes, e.g.  make shared ROWS=64 NMEM=4 FTD=16 NGLB=4
# (run `make clean` between different sizes)
#=============================================================================

IVERILOG = iverilog
VVP      = vvp
FLAGS    = -g2005 -Wall -DFAULT_INJECT -I../rtl/include
RTL      = $(wildcard ../rtl/*.v)
OUT      = build

ROWS  ?= 256
NMEM  ?= 2
FTD   ?= 8
NGLB  ?= 2
NRAND ?= 200
SEED  ?= 1

TOP_PARAMS = -Ptb_top_scenarios.ROWS=$(ROWS) -Ptb_top_scenarios.N_MEM=$(NMEM) \
             -Ptb_top_scenarios.FT_DEPTH=$(FTD) -Ptb_top_scenarios.N_GLOBAL=$(NGLB)

.PHONY: all unit shared dedicated equal random clean

all: unit shared dedicated equal random

$(OUT):
	mkdir -p $(OUT)

# ---------------- unit tests ----------------
unit: | $(OUT)
	@for tb in tb_sram_injector tb_march tb_logger tb_bira tb_remap; do \
	  $(IVERILOG) $(FLAGS) -s $$tb -o $(OUT)/$$tb.vvp $(RTL) ../tb/$$tb.v && \
	  $(VVP) -n $(OUT)/$$tb.vvp | grep -E "^(FAIL|TB_)" ; \
	done

# ---------------- system tests ----------------
$(OUT)/shared.vvp: $(RTL) ../tb/tb_top_scenarios.v | $(OUT)
	$(IVERILOG) $(FLAGS) -s tb_top_scenarios $(TOP_PARAMS) \
	  -Ptb_top_scenarios.ARCH=0 -o $@ $(RTL) ../tb/tb_top_scenarios.v

$(OUT)/dedicated.vvp: $(RTL) ../tb/tb_top_scenarios.v | $(OUT)
	$(IVERILOG) $(FLAGS) -s tb_top_scenarios $(TOP_PARAMS) \
	  -Ptb_top_scenarios.ARCH=1 -o $@ $(RTL) ../tb/tb_top_scenarios.v

$(OUT)/equal.vvp: $(RTL) ../tb/tb_top_scenarios.v | $(OUT)
	$(IVERILOG) $(FLAGS) -s tb_top_scenarios $(TOP_PARAMS) \
	  -Ptb_top_scenarios.ARCH=1 -Ptb_top_scenarios.N_LOCAL=2 -o $@ $(RTL) ../tb/tb_top_scenarios.v

shared: $(OUT)/shared.vvp
	$(VVP) -n $< | grep -v "^RESULT"

dedicated: $(OUT)/dedicated.vvp
	$(VVP) -n $< | grep -v "^RESULT"

equal: $(OUT)/equal.vvp
	$(VVP) -n $< | grep -v "^RESULT"

random: $(OUT)/shared.vvp $(OUT)/dedicated.vvp $(OUT)/equal.vvp
	@for cfg in shared dedicated equal; do \
	  echo "== $$cfg"; \
	  $(VVP) -n $(OUT)/$$cfg.vvp +RANDOM=$(NRAND) +SEED=$(SEED) | grep -v "^RESULT"; \
	done

clean:
	rm -rf $(OUT)
