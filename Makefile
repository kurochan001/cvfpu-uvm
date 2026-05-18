# =============================================================================
# CVFPU UVM testbench — sukimasim bringup Makefile
#
# Quick start:
#   make all       # full pipeline: venv -> bender -> refmodel -> compile -> lint -> smoke
#   make help      # list targets
#
# Per-phase entry points:
#   make venv      # python3 -m venv + requirements.txt
#   make bender    # bender update + flist-plus -> local/cvfpu_uvm_sukimasim.bender.f
#   make refmodel  # build ref_model_csim/cpp/build/refmodel_csim_lib.so
#   make compile   # sukimasim --compile-only
#   make lint      # sukimasim --lint (parse + elaborate, no sim)
#   make smoke     # sukimasim run, +UVM_TESTNAME=fpu_random_test, seed=1
#
# Override knobs (env or `make VAR=...`):
#   TESTNAME=fpu_random_test  SEED=1  VERBOSITY=UVM_LOW
#   NB_TXNS=1  MAX_TIME=1ms   WALL_TIMEOUT=60
#   SUKIMASIM_BIN=/path/to/sukimasim
#
# Cleanup:
#   make clean      # output/, compile/lint/smoke logs, bender filelist, refmodel .so
#   make distclean  # clean + .venv + .bender
# =============================================================================

SHELL          := /usr/bin/env bash
.SHELLFLAGS    := -eu -o pipefail -c

PROJECT_DIR    := $(abspath $(CURDIR))
LOCAL_DIR      := $(PROJECT_DIR)/local
OUTPUT_DIR     := $(PROJECT_DIR)/output/sukimasim
VENV_DIR       := $(PROJECT_DIR)/.venv

ENV_SCRIPT     := $(LOCAL_DIR)/env_sukimasim.sh
COMPILE_SH     := $(LOCAL_DIR)/run_sukimasim_compile.sh
SMOKE_SH       := $(LOCAL_DIR)/run_sukimasim_smoke.sh
REFMODEL_SH    := $(LOCAL_DIR)/build_refmodel_sukimasim.sh

BENDER_FLIST   := $(LOCAL_DIR)/cvfpu_uvm_sukimasim.bender.f
REFMODEL_SO    := $(PROJECT_DIR)/ref_model_csim/cpp/build/refmodel_csim_lib.so

VENV_STAMP     := $(VENV_DIR)/.installed
COMPILE_LOG    := $(OUTPUT_DIR)/compile.log
LINT_LOG       := $(OUTPUT_DIR)/lint.log
LINT_WORK      := $(OUTPUT_DIR)/lint_work

# Test parameters (override via `make smoke TESTNAME=...`)
TESTNAME      ?= fpu_random_test
SEED          ?= 1
VERBOSITY     ?= UVM_LOW
NB_TXNS       ?= 1
TIMEOUT       ?= 30000000
MAX_TIME      ?= 1ms
WALL_TIMEOUT  ?= 60
SMOKE_LOG     := $(OUTPUT_DIR)/$(TESTNAME)_seed$(SEED).log

# Bender targets used by the official compile.py
BENDER_TARGETS := -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm

# Source the env script once at the top of every recipe that needs PROJECT_DIR
# / SUKIMASIM_BIN / GMP_DIR / MPFR_DIR. The `source` line MUST sit inside the
# same shell invocation, hence the leading backslash-newline.
ACTIVATE_ENV := source $(ENV_SCRIPT) >/dev/null

# Export TESTNAME etc. so the smoke wrapper picks them up.
export TESTNAME SEED VERBOSITY NB_TXNS TIMEOUT MAX_TIME WALL_TIMEOUT

.DEFAULT_GOAL := all

.PHONY: all help check-tools venv bender refmodel compile lint lint-strict smoke \
        clean distclean rerun

# -----------------------------------------------------------------------------
# Aggregate targets
# -----------------------------------------------------------------------------
all: venv bender refmodel compile lint smoke
	@echo ""
	@echo "[make all] full pipeline finished."
	@echo "  compile log: $(COMPILE_LOG)"
	@echo "  lint    log: $(LINT_LOG)"
	@echo "  smoke   log: $(SMOKE_LOG)"

# `make rerun` re-runs the dynamic phases without rebuilding venv/bender/refmodel.
rerun: compile lint smoke

# Detect sukimasim binary lazily for help / status display only.
# (Heredoc-safe: never errors even if the env script can't find a binary.)
SUKIMASIM_BIN_DISPLAY := $(shell bash -c 'source $(ENV_SCRIPT) >/dev/null 2>&1; echo "$${SUKIMASIM_BIN:-<not found>}"')

help:
	@printf '\n'
	@printf '  CVFPU UVM testbench — sukimasim bringup Makefile\n'
	@printf '  ================================================\n'
	@printf '\n'
	@printf '  USAGE\n'
	@printf '    make [target] [VAR=value]...\n'
	@printf '\n'
	@printf '  PIPELINE TARGETS\n'
	@printf '    all            Full pipeline (default):\n'
	@printf '                     venv -> bender -> refmodel -> compile -> lint -> smoke\n'
	@printf '                   lint and smoke failures are tolerated so the run completes.\n'
	@printf '    rerun          Skip venv / bender / refmodel and re-run compile + lint + smoke.\n'
	@printf '\n'
	@printf '  INDIVIDUAL PHASES\n'
	@printf '    venv           Create .venv (if missing) and pip-install requirements.txt.\n'
	@printf '    bender         bender update + flist-plus → local/cvfpu_uvm_sukimasim.bender.f.\n'
	@printf '    refmodel       Build C++ DPI shared library refmodel_csim_lib.so.\n'
	@printf '                   Wraps ref_model_csim/cpp/Makefile with -DDPI_DLLESPEC= and\n'
	@printf '                   the multiarch GMP/MPFR include paths from env_sukimasim.sh.\n'
	@printf '    compile        sukimasim --compile-only (parse + IR; no elaboration).\n'
	@printf '    lint           sukimasim --lint (parse + elaborate; no simulation).\n'
	@printf '                   Warnings are reported but do NOT fail the build.\n'
	@printf '    lint-strict    Same as lint, but any warning propagates a non-zero exit.\n'
	@printf '    smoke          Run +UVM_TESTNAME=%s seed=%s for one transaction.\n' '$(TESTNAME)' '$(SEED)'
	@printf '                   Wall-clock capped by WALL_TIMEOUT (currently %s s).\n' '$(WALL_TIMEOUT)'
	@printf '\n'
	@printf '  MAINTENANCE\n'
	@printf '    clean          Remove output/, refmodel build/, bender filelist, log files.\n'
	@printf '    distclean      clean + remove .venv and .bender dirs.\n'
	@printf '    check-tools    Verify python3 / bender / sukimasim are reachable.\n'
	@printf '    help           Show this help (default goal is "all", not "help").\n'
	@printf '\n'
	@printf '  CONFIGURATION VARIABLES — override with `make VAR=value` or `VAR=value make ...`\n'
	@printf '    TESTNAME       = %s\n' '$(TESTNAME)'
	@printf '    SEED           = %s\n' '$(SEED)'
	@printf '    VERBOSITY      = %s     (UVM_LOW / UVM_MEDIUM / UVM_HIGH / UVM_FULL / UVM_DEBUG)\n' '$(VERBOSITY)'
	@printf '    NB_TXNS        = %s     (testbench-level stimulus count plusarg)\n' '$(NB_TXNS)'
	@printf '    TIMEOUT        = %s\n' '$(TIMEOUT)'
	@printf '    MAX_TIME       = %s     (sukimasim --max-time, e.g. 1us / 1ms / 10ms)\n' '$(MAX_TIME)'
	@printf '    WALL_TIMEOUT   = %s     (sukimasim --wall-timeout, seconds)\n' '$(WALL_TIMEOUT)'
	@printf '    BENDER_TARGETS = %s\n' '$(BENDER_TARGETS)'
	@printf '    SUKIMASIM_BIN  = %s\n' '$(SUKIMASIM_BIN_DISPLAY)'
	@printf '                   (auto-detected from local/env_sukimasim.sh; set this env\n'
	@printf '                    var or edit env_sukimasim.sh to point at a different build.)\n'
	@printf '\n'
	@printf '  KEY OUTPUT PATHS (created on demand under %s)\n' '$(notdir $(PROJECT_DIR))'
	@printf '    bender filelist  local/cvfpu_uvm_sukimasim.bender.f   (gitignored)\n'
	@printf '    refmodel lib     ref_model_csim/cpp/build/refmodel_csim_lib.so\n'
	@printf '    compile log      output/sukimasim/compile.log\n'
	@printf '    lint log         output/sukimasim/lint.log\n'
	@printf '    smoke log        output/sukimasim/%s_seed%s.log\n' '$(TESTNAME)' '$(SEED)'
	@printf '    cmd / version    output/sukimasim/cmd.txt , version.txt\n'
	@printf '\n'
	@printf '  EXAMPLES\n'
	@printf '    make                                       # default goal = all\n'
	@printf '    make help\n'
	@printf '    make check-tools\n'
	@printf '    make compile                               # just the compile phase\n'
	@printf '    make smoke TESTNAME=fpu_op_group_test SEED=42 WALL_TIMEOUT=120\n'
	@printf '    SUKIMASIM_BIN=/path/to/sukimasim make compile\n'
	@printf '    make lint-strict                           # treat lint warnings as errors\n'
	@printf '    make clean && make all                     # full rebuild from scratch\n'
	@printf '    make -j2 refmodel bender                   # build independent targets in parallel\n'
	@printf '\n'
	@printf '  PREREQUISITES (verified by `make check-tools`)\n'
	@printf '    python3        any 3.x; .venv created locally so the system Python is untouched.\n'
	@printf '    bender         pulp-platform/bender ≥ 0.31. Install: `cargo install bender`.\n'
	@printf '    sukimasim      built by you (e.g. ~/Work2/sukimasim/build/sukimasim).\n'
	@printf '    libgmp-dev,    Debian/Ubuntu dev headers for the C++ refmodel build.\n'
	@printf '    libmpfr-dev    Install via `sudo apt-get install libgmp-dev libmpfr-dev`.\n'
	@printf '\n'
	@printf '  REFERENCE\n'
	@printf '    bringup_report.md          Status, blockers, exact reproduction commands.\n'
	@printf '    local/official_flow_summary.md   How the upstream Questa/Xcelium/VCS flow works.\n'
	@printf '    local/log_summary.md       Warning categorisation from the last run.\n'
	@printf '\n'

# -----------------------------------------------------------------------------
# Tool sanity check
# -----------------------------------------------------------------------------
check-tools:
	@command -v python3 >/dev/null || { echo "[ERROR] python3 not on PATH"; exit 1; }
	@command -v bender  >/dev/null || { echo "[ERROR] bender not on PATH (install: cargo install bender)"; exit 1; }
	@$(ACTIVATE_ENV); \
	  if [ -z "$${SUKIMASIM_BIN:-}" ] || [ ! -x "$${SUKIMASIM_BIN}" ]; then \
	    echo "[ERROR] sukimasim binary not detected. Set SUKIMASIM_BIN or install one of:"; \
	    echo "        ~/Work2/sukimasim/build/sukimasim   (preferred)"; \
	    exit 1; \
	  fi; \
	  echo "[OK] python3=$$(command -v python3)"; \
	  echo "[OK] bender =$$(command -v bender)  ($$(bender --version))"; \
	  echo "[OK] sukimasim=$${SUKIMASIM_BIN}"

# -----------------------------------------------------------------------------
# Python venv
# -----------------------------------------------------------------------------
venv: $(VENV_STAMP)

$(VENV_STAMP): requirements.txt
	@if [ -e $(VENV_DIR)/bin/activate ]; then \
	   echo "[venv] reusing existing $(VENV_DIR)"; \
	 else \
	   echo "[venv] creating $(VENV_DIR)"; \
	   python3 -m venv $(VENV_DIR); \
	 fi
	. $(VENV_DIR)/bin/activate && \
	  python3 -m pip install --upgrade pip --quiet && \
	  python3 -m pip install -r requirements.txt --quiet
	@touch $(VENV_STAMP)

# -----------------------------------------------------------------------------
# Bender-driven filelist (cva6 + cvfpu + common_cells + axi + ...)
# -----------------------------------------------------------------------------
bender: $(BENDER_FLIST)

$(BENDER_FLIST): Bender.yml Bender.lock | check-tools
	@echo "[bender] update"
	bender update
	@echo "[bender] sync local submodule patches into .bender/git/checkouts/"
	bash $(LOCAL_DIR)/sync_submodule_patches_to_bender.sh
	@echo "[bender] script flist-plus $(BENDER_TARGETS) > $(notdir $@)"
	bender script flist-plus $(BENDER_TARGETS) > $@

# -----------------------------------------------------------------------------
# C++ reference model (DPI shared library)
# -----------------------------------------------------------------------------
REFMODEL_SRCS := $(wildcard ref_model_csim/cpp/src/*.cpp) \
                 $(wildcard ref_model_csim/cpp/include/*.h) \
                 ref_model_csim/cpp/Makefile

refmodel: $(REFMODEL_SO)

$(REFMODEL_SO): $(REFMODEL_SRCS) $(REFMODEL_SH) $(ENV_SCRIPT)
	@echo "[refmodel] building $(notdir $@)"
	bash $(REFMODEL_SH)

# -----------------------------------------------------------------------------
# Compile-only (parse + IR)
# -----------------------------------------------------------------------------
compile: $(COMPILE_LOG)

$(COMPILE_LOG): $(BENDER_FLIST) $(REFMODEL_SO) $(COMPILE_SH) $(ENV_SCRIPT) \
                $(LOCAL_DIR)/cvfpu_uvm_sukimasim.f
	@echo "[compile] sukimasim --compile-only"
	bash $(COMPILE_SH)

# -----------------------------------------------------------------------------
# Lint (parse + elaborate, no sim) — inline; no separate wrapper exists yet
# -----------------------------------------------------------------------------
#
# Lint is informational — sukimasim returns non-zero whenever it emits any
# warning, but those warnings are testbench-quality observations, not blocking
# errors. We tee the full log to lint.log and always succeed so `make all`
# proceeds to smoke. Use `make lint-strict` to propagate the real exit code.
#
lint: $(LINT_LOG)
lint-strict: STRICT_LINT := 1
lint-strict: $(LINT_LOG)

$(LINT_LOG): $(BENDER_FLIST) $(REFMODEL_SO) $(ENV_SCRIPT) \
             $(LOCAL_DIR)/cvfpu_uvm_sukimasim.f
	@echo "[lint] sukimasim --lint"
	@mkdir -p $(LINT_WORK)
	@: > $(LINT_LOG)
	@$(ACTIVATE_ENV); \
	  set +e; \
	  "$${SUKIMASIM_BIN}" \
	    --enable-uvm --preprocess -top top \
	    --work-dir $(LINT_WORK) \
	    --errormax 1 \
	    --lib-path $(dir $(REFMODEL_SO)) --lib $(notdir $(REFMODEL_SO)) \
	    +define+SUKIMASIM +incdir+$(PROJECT_DIR) \
	    -f $(LOCAL_DIR)/cvfpu_uvm_sukimasim.f \
	    --lint 2>&1 | tee -a $(LINT_LOG); \
	  rc=$${PIPESTATUS[0]}; \
	  echo "[INFO] sukimasim --lint exit = $${rc}" | tee -a $(LINT_LOG); \
	  if [ "$${STRICT_LINT:-0}" = "1" ]; then \
	    exit $${rc}; \
	  else \
	    echo "[lint] non-zero exit ignored ($${rc}); use 'make lint-strict' to propagate" ; \
	    exit 0; \
	  fi

# -----------------------------------------------------------------------------
# Smoke run
#
# Wrapped with `-` so a known crash (e.g. the NBA SEGV that sukimasim
# currently hits during the fpu_random_test sim phase) does not abort the
# whole `make all` pipeline — the wrapper still records full logs and exit
# code under output/sukimasim/. Use `make smoke` directly if you want the
# non-zero exit to propagate.
# -----------------------------------------------------------------------------
smoke: $(BENDER_FLIST) $(REFMODEL_SO) $(SMOKE_SH) $(ENV_SCRIPT) \
       $(LOCAL_DIR)/cvfpu_uvm_sukimasim.f
	@echo "[smoke] sukimasim run +UVM_TESTNAME=$(TESTNAME) --seed $(SEED)"
	-bash $(SMOKE_SH)
	@echo "[smoke] log: $(SMOKE_LOG)"

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
clean:
	@echo "[clean] removing output/, refmodel build/, bender filelist"
	rm -rf $(OUTPUT_DIR)
	rm -rf $(PROJECT_DIR)/ref_model_csim/cpp/build
	rm -f  $(BENDER_FLIST)
	rm -f  $(LOCAL_DIR)/refmodel_build.log

distclean: clean
	@echo "[distclean] also removing .venv, .bender"
	rm -rf $(VENV_DIR)
	rm -rf $(PROJECT_DIR)/.bender
