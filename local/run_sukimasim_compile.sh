#!/usr/bin/env bash
#
# Compile-only driver for the CVFPU UVM testbench under sukimasim
# (sukimasim v0.9.9.x, IEEE 1800-2023).
#
# Option mapping (from `sukimasim --help`):
#   -top <module>            : top module name
#   --enable-uvm             : enable UVM package + auto-include uvm_macros.svh
#   --preprocess             : Verilator-based external preprocessor for UVM
#                              macros (needed by `uvm_*` macros expansion)
#   -f <filelist>            : read switches/files from filelist
#   --work-dir <dir>         : working dir for temporary files
#   --compile-only           : parse + IR conversion, then stop (no elab, no sim)
#   --lint                   : alternative — parse + elaborate + diagnose
#   --lib / --lib-path       : DPI shared lib (also accepts -sv_lib alias)
#   --logfile <file>         : redirect simulation output (alias: -l)
#   --errormax <n>           : stop after n errors
#
# Output:
#   output/sukimasim/compile.log   - full sukimasim log
#   output/sukimasim/version.txt   - sukimasim --version capture
#   output/sukimasim/cmd.txt       - the exact command line

set -euo pipefail

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_THIS_DIR}/env_sukimasim.sh"

OUTDIR="${PROJECT_DIR}/output/sukimasim"
mkdir -p "${OUTDIR}"
mkdir -p "${OUTDIR}/work"
# truncate the log up-front so re-runs don't accumulate stale text
: > "${OUTDIR}/compile.log"

if [ -z "${SUKIMASIM_BIN:-}" ] || [ ! -x "${SUKIMASIM_BIN}" ]; then
  echo "[BLOCKED] sukimasim not found (SUKIMASIM_BIN unset and no 'sukimasim' on PATH)." | tee "${OUTDIR}/compile.log"
  echo "          Set SUKIMASIM_BIN=/path/to/sukimasim and re-run." | tee -a "${OUTDIR}/compile.log"
  exit 2
fi

{
  echo "host:          $(hostname)"
  echo "date:          $(date -Iseconds)"
  echo "PROJECT_DIR:   ${PROJECT_DIR}"
  echo "SUKIMASIM_BIN: ${SUKIMASIM_BIN}"
  echo "SUKIMASIM_HOME:${SUKIMASIM_HOME:-<unset>}"
  echo ""
  echo "--- sukimasim --version ---"
  "${SUKIMASIM_BIN}" --version 2>&1 || echo "(--version not supported)"
} > "${OUTDIR}/version.txt"

FLIST="${PROJECT_DIR}/local/cvfpu_uvm_sukimasim.f"
if [ ! -f "${FLIST}" ]; then
  echo "[ERROR] filelist missing: ${FLIST}" | tee "${OUTDIR}/compile.log"
  exit 3
fi

# Warn loudly if the filelist still has template placeholders for the cva6
# closure (bender output not merged yet).
if grep -q "MISSING: cva6 + cvfpu" "${FLIST}"; then
  cat >&2 <<'EOF'

[WARN] local/cvfpu_uvm_sukimasim.f still contains the template marker
       "MISSING: cva6 + cvfpu + ...". You almost certainly want to run

         bender update
         bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
             > local/cvfpu_uvm_sukimasim.bender.f

       and either include that file ahead of the local sources, or
       merge it into local/cvfpu_uvm_sukimasim.f. Continuing anyway, but
       elaboration will fail with "package not found" / undefined ids.

EOF
fi

# --- DPI library (refmodel) ---
DPILIB="${PROJECT_DIR}/ref_model_csim/cpp/build/refmodel_csim_lib.so"
DPI_OPTS=()
if [ -e "${DPILIB}" ]; then
  # `--lib NAME` looks up libNAME.so or NAME.so on lib-path. Easiest: pass
  # the containing dir on --lib-path and the basename (without .so) on --lib.
  DPI_OPTS+=( --lib-path "$(dirname "${DPILIB}")" --lib "$(basename "${DPILIB}" .so)" )
  export LD_LIBRARY_PATH="$(dirname "${DPILIB}"):${LD_LIBRARY_PATH:-}"
else
  echo "[WARN] DPI shared lib not built: ${DPILIB}" >&2
  echo "       Build with local/build_refmodel_sukimasim.sh after installing libgmp-dev + libmpfr-dev." >&2
fi

# --- sukimasim command ---
SUKI_OPTS=(
  --enable-uvm
  --preprocess
  -top top
  --work-dir "${OUTDIR}/work"
  --errormax 1
  -f "${FLIST}"
)
if [ "${#DPI_OPTS[@]}" -gt 0 ]; then
  SUKI_OPTS+=( "${DPI_OPTS[@]}" )
fi
SUKI_OPTS+=( --compile-only )

# Project-level defines mirroring the official yamls; SUKIMASIM is our marker.
SUKI_OPTS+=( +define+SUKIMASIM +incdir+"${PROJECT_DIR}" )

echo "[INFO] Command: ${SUKIMASIM_BIN} ${SUKI_OPTS[*]}" | tee "${OUTDIR}/cmd.txt"

# sukimasim's --logfile only captures simulation-phase output, not the
# parse/elab diagnostics that --compile-only emits — so we tee stdout/stderr
# directly into compile.log.
set +e
"${SUKIMASIM_BIN}" "${SUKI_OPTS[@]}" 2>&1 | tee -a "${OUTDIR}/compile.log"
rc=${PIPESTATUS[0]}
set -e

echo "[INFO] sukimasim exit = ${rc}" | tee -a "${OUTDIR}/compile.log"
exit "${rc}"
