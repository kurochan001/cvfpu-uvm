#!/usr/bin/env bash
#
# Build the C++ reference model shared library for sukimasim.
#
# The official Makefile (ref_model_csim/cpp/Makefile) is parameterised by:
#   TOOL  -> {questa, xcelium, vcs}    (controls -DUSE_QUESTA / -DUSE_XCELIUM / -DUSE_VCS)
#   GEN_PATH -> simulator install root (used for -I$(GEN_PATH)/include to find svdpi.h)
#   GMP_DIR  -> -I$(GMP_DIR)/include   -L$(GMP_DIR)/lib   -lgmp
#   MPFR_DIR -> -I$(MPFR_DIR)/include  -L$(MPFR_DIR)/lib  -lmpfr
#
# For sukimasim we do not have an official TOOL define. The wrapper here:
#   - defaults TOOL=questa (the -DUSE_QUESTA path is the closest match for a
#     generic DPI-C library that any simulator with svdpi.h should be able to load)
#   - lets the caller override TOOL via the SUKIMASIM_REFMODEL_TOOL env var
#   - lets the caller override GEN_PATH via SUKIMASIM_GEN_PATH, otherwise expects
#     sukimasim to ship its own svdpi.h under $(dirname $SUKIMASIM_BIN)/../include
#
# Output: ref_model_csim/cpp/build/refmodel_csim_lib.so

set -euo pipefail

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${_THIS_DIR}/.." && pwd)"

# Source env if not already loaded.
if [ -z "${PROJECT_DIR:-}" ] || [ -z "${SCRIPTS_DIR:-}" ]; then
  # shellcheck disable=SC1091
  source "${_THIS_DIR}/env_sukimasim.sh"
fi

TOOL="${SUKIMASIM_REFMODEL_TOOL:-questa}"

# --- GMP / MPFR sanity ---
need_dev_pkg=0
if [ -z "${GMP_DIR:-}" ] || [ ! -e "${GMP_DIR}/include/gmp.h" ]; then
  echo "[ERROR] gmp.h not found. Set GMP_DIR to a prefix that has include/gmp.h." >&2
  echo "        Debian/Ubuntu: install libgmp-dev (sudo apt-get install libgmp-dev), then GMP_DIR=/usr" >&2
  need_dev_pkg=1
fi
if [ -z "${MPFR_DIR:-}" ] || [ ! -e "${MPFR_DIR}/include/mpfr.h" ]; then
  echo "[ERROR] mpfr.h not found. Set MPFR_DIR to a prefix that has include/mpfr.h." >&2
  echo "        Debian/Ubuntu: install libmpfr-dev (sudo apt-get install libmpfr-dev), then MPFR_DIR=/usr" >&2
  need_dev_pkg=1
fi

# --- GEN_PATH (where svdpi.h lives) ---
if [ -z "${GEN_PATH:-}" ]; then
  if [ -n "${SUKIMASIM_GEN_PATH:-}" ]; then
    export GEN_PATH="${SUKIMASIM_GEN_PATH}"
  elif [ -n "${SUKIMASIM_BIN:-}" ] && [ -x "${SUKIMASIM_BIN}" ]; then
    _root="$(cd "$(dirname "${SUKIMASIM_BIN}")/.." && pwd)"
    if [ -e "${_root}/include/svdpi.h" ]; then
      export GEN_PATH="${_root}"
    fi
  fi
fi

if [ -z "${GEN_PATH:-}" ] || [ ! -e "${GEN_PATH}/include/svdpi.h" ]; then
  echo "[ERROR] svdpi.h not found. Set GEN_PATH (or SUKIMASIM_GEN_PATH) to a prefix" >&2
  echo "        that contains include/svdpi.h (typically the simulator install root)." >&2
  need_dev_pkg=1
fi

if [ "${need_dev_pkg}" -ne 0 ]; then
  echo "[BLOCKED] Cannot build refmodel; see errors above." >&2
  exit 2
fi

echo "[INFO] TOOL=${TOOL}"
echo "[INFO] GEN_PATH=${GEN_PATH}"
echo "[INFO] GMP_DIR=${GMP_DIR}"
echo "[INFO] MPFR_DIR=${MPFR_DIR}"

cd "${PROJECT_DIR}/ref_model_csim/cpp"
make TOOL="${TOOL}" GEN_PATH="${GEN_PATH}" GMP_DIR="${GMP_DIR}" MPFR_DIR="${MPFR_DIR}" 2>&1 | tee "${PROJECT_DIR}/local/refmodel_build.log"

if [ -e "${PROJECT_DIR}/ref_model_csim/cpp/build/refmodel_csim_lib.so" ]; then
  echo "[OK] built: ref_model_csim/cpp/build/refmodel_csim_lib.so"
else
  echo "[ERROR] refmodel_csim_lib.so not produced; see local/refmodel_build.log" >&2
  exit 3
fi
