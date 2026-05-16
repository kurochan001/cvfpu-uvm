#!/usr/bin/env bash
#
# Smoke test runner for the CVFPU UVM testbench under sukimasim
# (sukimasim v0.9.9.x, IEEE 1800-2023).
#
# Default run:
#   +UVM_TESTNAME=fpu_random_test
#   seed = 1                    (--seed)
#   +UVM_VERBOSITY=UVM_LOW
#   +NB_TXNS=1                  (minimum stimulus)
#   --max-time 1ms              (cap simulation time)
#   --wall-timeout 60           (CI safety: kill if hung)
#
# Unlike commercial flows, sukimasim does not have a separate "elaborate then
# run later" mode usable across invocations — it goes parse → elab → simulate
# in one call. We rely on the build cache (parse cache) for incremental speed.

set -euo pipefail

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_THIS_DIR}/env_sukimasim.sh"

OUTDIR="${PROJECT_DIR}/output/sukimasim"
mkdir -p "${OUTDIR}"
mkdir -p "${OUTDIR}/work"

TESTNAME="${TESTNAME:-fpu_random_test}"
SEED="${SEED:-1}"
VERBOSITY="${VERBOSITY:-UVM_LOW}"
NB_TXNS="${NB_TXNS:-1}"
TIMEOUT="${TIMEOUT:-30000000}"
MAX_TIME="${MAX_TIME:-1ms}"
WALL_TIMEOUT="${WALL_TIMEOUT:-60}"

LOGFILE="${OUTDIR}/${TESTNAME}_seed${SEED}.log"

if [ -z "${SUKIMASIM_BIN:-}" ] || [ ! -x "${SUKIMASIM_BIN}" ]; then
  echo "[BLOCKED] sukimasim not found (SUKIMASIM_BIN unset and no 'sukimasim' on PATH)." | tee "${LOGFILE}"
  exit 2
fi

FLIST="${PROJECT_DIR}/local/cvfpu_uvm_sukimasim.f"
if [ ! -f "${FLIST}" ]; then
  echo "[ERROR] filelist missing: ${FLIST}" | tee "${LOGFILE}"
  exit 3
fi

# --- DPI library (refmodel) ---
DPILIB="${PROJECT_DIR}/ref_model_csim/cpp/build/refmodel_csim_lib.so"
DPI_OPTS=()
if [ -e "${DPILIB}" ]; then
  # See run_sukimasim_compile.sh for the rationale: keep the .so suffix so
  # sukimasim's dlopen does not synthesise an extra `lib` prefix.
  DPI_OPTS+=( --lib-path "$(dirname "${DPILIB}")" --lib "$(basename "${DPILIB}")" )
  export LD_LIBRARY_PATH="$(dirname "${DPILIB}"):${LD_LIBRARY_PATH:-}"
else
  echo "[WARN] DPI shared lib not built; refmodel DPI calls will fail to bind." >&2
fi

SUKI_OPTS=(
  --enable-uvm
  --preprocess
  -top top
  --work-dir   "${OUTDIR}/work"
  --logfile    "${LOGFILE}"
  --seed       "${SEED}"
  --max-time   "${MAX_TIME}"
  --wall-timeout "${WALL_TIMEOUT}"
  -f "${FLIST}"
)
if [ "${#DPI_OPTS[@]}" -gt 0 ]; then
  SUKI_OPTS+=( "${DPI_OPTS[@]}" )
fi
SUKI_OPTS+=(
  +define+SUKIMASIM
  +incdir+"${PROJECT_DIR}"
  "+UVM_TESTNAME=${TESTNAME}"
  "+UVM_VERBOSITY=${VERBOSITY}"
  "+NB_TXNS=${NB_TXNS}"
  "+TIMEOUT=${TIMEOUT}"
)

echo "[INFO] Command: ${SUKIMASIM_BIN} ${SUKI_OPTS[*]}"

set +e
"${SUKIMASIM_BIN}" "${SUKI_OPTS[@]}"
rc=$?
set -e

echo "[INFO] sukimasim exit = ${rc}"
echo "[INFO] sukimasim exit = ${rc}" >> "${LOGFILE}"
exit "${rc}"
