#!/usr/bin/env bash
#
# Mirror our submodule edits into bender's independent checkouts.
#
# Background: `bender update` clones each dependency from the SHA pinned
# in Bender.lock into .bender/git/checkouts/<name>-<hash>/, ignoring
# whatever we have in `modules/<name>` (those are git submodules under a
# *different* worktree). Compile.py + sukimasim then read sources from
# the .bender/ tree, so any fix we make in modules/ is invisible to the
# tool flow until we sync it across.
#
# This script overwrites the relevant files in .bender/git/checkouts/
# with the matching files from modules/. We only sync files we actually
# patched — listed in PAIRS below. Anything else stays at the
# Bender.lock-pinned content.

set -euo pipefail

_THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${_THIS_DIR}/.." && pwd)"
BENDER_DIR="${PROJECT_DIR}/.bender/git/checkouts"

if [ ! -d "${BENDER_DIR}" ]; then
  echo "[sync] no bender checkouts at ${BENDER_DIR}; nothing to do"
  exit 0
fi

# Each row:  <submodule>  <relative path inside the submodule>
PAIRS=(
  "core-v-verif lib/cv_dv_utils/uvm/reset_gen/xrtl_reset_vif.sv"
  "core-v-verif lib/cv_dv_utils/uvm/pulse_gen/pulse_if.sv"
  "core-v-verif lib/cv_dv_utils/uvm/unix_utils/md5sum_file_check.svh"
  "cva6         core/fpu_wrap.sv"
)

count_copied=0
for pair in "${PAIRS[@]}"; do
  # shellcheck disable=SC2086
  set -- $pair
  proj="$1"
  rel="$2"

  src="${PROJECT_DIR}/modules/${proj}/${rel}"
  if [ ! -f "${src}" ]; then
    echo "[sync][WARN] source missing, skipping: ${src}" >&2
    continue
  fi

  matched=0
  for dst_dir in "${BENDER_DIR}/${proj}"-*; do
    [ -d "${dst_dir}" ] || continue
    dst="${dst_dir}/${rel}"
    if [ ! -f "${dst}" ]; then
      echo "[sync][WARN] target missing under ${dst_dir}, skipping: ${rel}" >&2
      continue
    fi
    if ! cmp -s "${src}" "${dst}"; then
      cp "${src}" "${dst}"
      echo "[sync] updated ${dst#${PROJECT_DIR}/}"
      count_copied=$((count_copied + 1))
    fi
    matched=$((matched + 1))
  done

  if [ "${matched}" -eq 0 ]; then
    echo "[sync][WARN] no .bender checkout matched ${proj}-* for ${rel}" >&2
  fi
done

echo "[sync] ${count_copied} file(s) copied into .bender/git/checkouts/"
