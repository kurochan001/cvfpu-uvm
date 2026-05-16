// ---------------------------------------------------------------------------
// CVFPU UVM testbench filelist for sukimasim.
//
// This file is the entrypoint that local/run_sukimasim_*.sh pass to sukimasim
// as `-f`. The bulk of the work is delegated to the bender-generated filelist
// `local/cvfpu_uvm_sukimasim.bender.f`, which is produced by:
//
//   source local/env_sukimasim.sh
//   bender update
//   bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
//       > local/cvfpu_uvm_sukimasim.bender.f
//
// The generated filelist already contains:
//   - all cva6 / cvfpu (fpnew) / common_cells / axi / tech_cells_generic /
//     hpdcache RTL under .bender/git/checkouts/
//   - core-v-verif cv_dv_utils UVM helpers (clock_gen, reset_gen, pulse_gen,
//     watchdog, generic_agent, memory_*, etc.) + their +incdir lines
//   - cvfpu-uvm local sources in Bender.yml order, terminating with
//     top/rtl/tb_top.sv
//
// So this file only needs the project-local extras that bender does not
// emit on its own: the SUKIMASIM marker define and a project-root incdir
// for anything that includes via paths relative to ${PROJECT_DIR}.
// ---------------------------------------------------------------------------

// Compile-time gating define for any sukimasim-specific bits.
+define+SUKIMASIM

// Project root incdir (mirrors what setup_env.sh + sim_<tool>.yaml export
// for the official flows).
+incdir+${PROJECT_DIR}

// Pull in the bender-generated closure.
-f ${PROJECT_DIR}/local/cvfpu_uvm_sukimasim.bender.f
