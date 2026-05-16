#!/usr/bin/env bash
#
# Environment setup for running the CVFPU UVM testbench with sukimasim.
# Mirrors the variables that the official setup_env.sh exports for
# questa/xcelium/vcs, but without invoking commercial-simulator paths.
#
# Source this file (do NOT execute) from the repository root:
#   source local/env_sukimasim.sh
#
# Note: keep this script side-effect-free except for environment exports.
# In particular it does NOT call `git submodule update --remote`
# (the official setup_env.sh does, which can silently advance submodules).
#
# We deliberately do NOT `set -euo pipefail` here: source-time `set -u` leaks
# into the caller's interactive shell and breaks the prompt / snapshot
# restore on common setups (e.g. anything that probes ZSH_VERSION
# unconditionally). Each driver in local/run_*.sh sets its own strict flags.

# Resolve the project directory as the parent of local/.
_THIS_FILE="${BASH_SOURCE[0]}"
_THIS_DIR="$(cd "$(dirname "${_THIS_FILE}")" && pwd)"
export PROJECT_DIR="$(cd "${_THIS_DIR}/.." && pwd)"

# --- mirror of setup_env.sh "Project-specific environment variables" ---
export TARGET_CFG="cv64a60ax"
export CVA6_REPO_DIR="${PROJECT_DIR}/modules/cva6"
export CORE_V_VERIF="${PROJECT_DIR}/modules/core-v-verif"
export DV_UTILS_DIR="${CORE_V_VERIF}/lib/cv_dv_utils"
export SCRIPTS_DIR="${DV_UTILS_DIR}/python/sim_cmd"

# Perl lib for scan_logs.pl
if [ -n "${PERL5LIB:-}" ]; then
  export PERL5LIB="${PERL5LIB}:${PROJECT_DIR}/scripts/perl5"
else
  export PERL5LIB="${PROJECT_DIR}/scripts/perl5"
fi

# Project scripts on PATH
export SCRIPTS="${PROJECT_DIR}/scripts"
export PATH="${SCRIPTS}:${PATH}"

# --- sukimasim-specific ---
# Search order:
#   1. caller-provided SUKIMASIM_BIN
#   2. ${HOME}/Work2/sukimasim/build/sukimasim  (canonical for this bringup)
#   3. `sukimasim` on PATH
#   4. other known build outputs under ${HOME}/Work2/sukimasim
if [ -n "${SUKIMASIM_BIN:-}" ]; then
  export SUKIMASIM_BIN
else
  _maybe=""
  for _cand in \
      "${HOME}/Work2/sukimasim/build/sukimasim" \
      "${HOME}/Work2/sukimasim/build-release/sukimasim" \
      "${HOME}/Work2/sukimasim/build-relwithdeb/sukimasim" \
      "${HOME}/Work2/sukimasim/build-fast/sukimasim" ; do
    if [ -x "${_cand}" ]; then
      _maybe="${_cand}"
      break
    fi
  done
  if [ -z "${_maybe}" ]; then
    _maybe="$(command -v sukimasim 2>/dev/null || true)"
  fi
  export SUKIMASIM_BIN="${_maybe:-}"
fi

# SUKIMASIM_HOME (used by sukimasim to find libuvm_dpi.so etc).
if [ -n "${SUKIMASIM_BIN:-}" ] && [ -z "${SUKIMASIM_HOME:-}" ]; then
  _suki_root="$(cd "$(dirname "${SUKIMASIM_BIN}")/.." 2>/dev/null && pwd)"
  if [ -n "${_suki_root}" ] && [ -d "${_suki_root}" ]; then
    export SUKIMASIM_HOME="${_suki_root}"
  fi
fi

# --- GMP / MPFR hints for refmodel build ---
# ref_model_csim/cpp/Makefile expects $(GMP_DIR)/include and $(GMP_DIR)/lib.
# Debian/Ubuntu /usr layout does NOT match that prefix exactly, but it works
# because gmp.h ends up at /usr/include and libgmp.so at /usr/lib/...
# Only export if the user has not set them already.
if [ -z "${GMP_DIR:-}" ]; then
  for d in /usr /usr/local /opt/homebrew /home/linuxbrew/.linuxbrew; do
    if [ -e "${d}/include/gmp.h" ]; then
      export GMP_DIR="${d}"
      break
    fi
    # Debian/Ubuntu multiarch layout: header lives at
    # ${d}/include/<triplet>/gmp.h. The Makefile only passes
    # -I${GMP_DIR}/include, so add the multiarch dir to CPATH so g++
    # can still find <gmp.h> via the standard search path.
    _multiarch_h=$(ls "${d}/include/"*"-linux-gnu/gmp.h" 2>/dev/null | head -1)
    if [ -n "${_multiarch_h}" ]; then
      export GMP_DIR="${d}"
      _multiarch_incdir="$(dirname "${_multiarch_h}")"
      export CPATH="${_multiarch_incdir}${CPATH:+:${CPATH}}"
      break
    fi
  done
fi
if [ -z "${MPFR_DIR:-}" ]; then
  for d in /usr /usr/local /opt/homebrew /home/linuxbrew/.linuxbrew; do
    if [ -e "${d}/include/mpfr.h" ]; then
      export MPFR_DIR="${d}"
      break
    fi
    _multiarch_h=$(ls "${d}/include/"*"-linux-gnu/mpfr.h" 2>/dev/null | head -1)
    if [ -n "${_multiarch_h}" ]; then
      export MPFR_DIR="${d}"
      _multiarch_incdir="$(dirname "${_multiarch_h}")"
      export CPATH="${_multiarch_incdir}${CPATH:+:${CPATH}}"
      break
    fi
  done
fi

# venv if present
if [ -f "${PROJECT_DIR}/.venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  . "${PROJECT_DIR}/.venv/bin/activate"
fi

echo "PROJECT_DIR    = ${PROJECT_DIR}"
echo "TARGET_CFG     = ${TARGET_CFG}"
echo "CVA6_REPO_DIR  = ${CVA6_REPO_DIR}"
echo "CORE_V_VERIF   = ${CORE_V_VERIF}"
echo "DV_UTILS_DIR   = ${DV_UTILS_DIR}"
echo "SCRIPTS_DIR    = ${SCRIPTS_DIR}"
echo "GMP_DIR        = ${GMP_DIR:-<unset: gmp.h not found>}"
echo "MPFR_DIR       = ${MPFR_DIR:-<unset: mpfr.h not found>}"
echo "SUKIMASIM_BIN  = ${SUKIMASIM_BIN:-<not found>}"
echo "SUKIMASIM_HOME = ${SUKIMASIM_HOME:-<unset>}"
