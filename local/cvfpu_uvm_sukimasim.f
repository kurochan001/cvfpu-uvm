// ---------------------------------------------------------------------------
// CVFPU UVM testbench filelist for sukimasim
//
// IMPORTANT: this is a TEMPLATE / SCAFFOLD, not a self-contained filelist.
// The official flow generates the *real* filelist with Bender:
//
//   bender update
//   bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
//       > ${PROJECT_DIR}/simu/bender_filelist.f
//
// That command pulls in:
//   - cva6 RTL (target-gated by `cv64a60ax_cvfpu_uvm`)
//   - cvfpu (a.k.a. fpnew)
//   - pulp common_cells, axi, tech_cells_generic
//   - hpdcache
//   - core-v-verif cv_dv_utils (UVM helpers)
//   - the cvfpu-uvm sources listed in this repo's Bender.yml
//
// Without bender we cannot reproduce that closure deterministically — the
// CVA6 Bender.yml has dozens of target-conditional blocks. Trying to
// hand-build the list here would silently miss / mis-order files.
//
// Recommended workflow once bender is available (`cargo install bender` works
// without sudo):
//
//   cd ${PROJECT_DIR}
//   bender update
//   bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
//       > local/cvfpu_uvm_sukimasim.bender.f
//   # then this file `-f local/cvfpu_uvm_sukimasim.f` plus
//   # the generated -f local/cvfpu_uvm_sukimasim.bender.f
//
// The lines below cover the parts that are stable (project-local sources +
// the cv_dv_utils filelist that the project also relies on). They are not
// enough on their own to elaborate `top`.
// ---------------------------------------------------------------------------

// Compile-time gating define for any sukimasim-specific bits.
+define+SUKIMASIM

// Top-level project include dirs (mirror Bender.yml `include_dirs`).
+incdir+${PROJECT_DIR}
+incdir+${PROJECT_DIR}/fpu_common
+incdir+${PROJECT_DIR}/fpu_agent
+incdir+${PROJECT_DIR}/ref_model_csim/rtl
+incdir+${PROJECT_DIR}/env
+incdir+${PROJECT_DIR}/tests

// cv_dv_utils (helper agents: clock_gen, reset_gen, pulse_gen, etc).
// This file does its own +incdir+ lines and lists package files in order.
-f ${CORE_V_VERIF}/lib/cv_dv_utils/uvm/Files.f

// === MISSING: cva6 + cvfpu + common_cells + axi + tech_cells_generic ===
// Re-emit via:
//   bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm > <output>.f
// and -f that file BEFORE the cvfpu-uvm sources below, so packages
// (riscv_pkg, ariane_pkg, fpnew_pkg, ...) elaborate first.

// cvfpu-uvm local sources, in Bender.yml order.
// fpu_common_pkg depends on ariane_pkg; fpu_refmodel_pkg depends on
// uvm_pkg + fpu_common_pkg + ariane_pkg.
${PROJECT_DIR}/fpu_common/fpu_common_pkg.sv
${PROJECT_DIR}/fpu_agent/fpu_agent_pkg.sv
${PROJECT_DIR}/fpu_agent/fpu_if.sv
${PROJECT_DIR}/ref_model_csim/rtl/fpu_refmodel_pkg.sv
${PROJECT_DIR}/env/fpu_env_pkg.sv
${PROJECT_DIR}/tests/fpu_test_pkg.sv
${PROJECT_DIR}/top/rtl/tb_top.sv
