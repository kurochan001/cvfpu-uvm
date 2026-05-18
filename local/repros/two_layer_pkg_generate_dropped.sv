// Minimal reproducer for sukimasim#282:
//   "CVFPU two-layer package config generate-if branch is not elaborated
//    at runtime."
//
// Mirrors the OpenHW chain used in cvfpu-uvm:
//   pkg_user_cfg::user_cfg          (typed struct literal, like cva6_config_pkg::cva6_cfg)
//     -> build_cfg::build(user_cfg)  (automatic function, separate package,
//                                      called from a localparam initialiser)
//          -> pkg_common::CFG        (consumer-side localparam, separate package
//                                      again, this is the one tb modules import)
//             -> dut #(.CFG_P(CFG))  (CFG is passed through a parameter port)
//                if (CFG_P.FpPresent) begin : g  ... drive `out_o`
//
// Expected (any conforming SV simulator, including the single-package
// version filed earlier as #279):
//   - g is elaborated
//   - dut.g.<assign> drives out_o = 1
//   - $finish prints "out_o=1 / FpPresent=1"
//
// Observed in the CVFPU UVM smoke: `fpu_ready_o = X` for 9000+ clock
// edges (matching this shape) — please confirm this minimal version
// reproduces the same elaboration drop. If yes, it is a smaller test
// vehicle than running the full cvfpu-uvm bringup.

// --- layer 1: input config -------------------------------------------------
package pkg_user_cfg;
  typedef struct packed {
    bit RVF;
    bit RVD;
    bit XF16;
  } user_cfg_t;

  // Same shape as cv64a60ax_config_pkg_cvfpu-uvm.sv's cva6_cfg literal.
  localparam user_cfg_t user_cfg = '{
      RVF:  1'b1,
      RVD:  1'b1,
      XF16: 1'b1
  };
endpackage

// --- layer 2: derived config + automatic function --------------------------
package build_cfg;
  // Independent struct definition (NOT pkg_user_cfg::user_cfg_t) so we
  // exercise the "field rewrite + add a derived field" pattern, like
  // CVA6 going from cva6_user_cfg_t to cva6_cfg_t.
  typedef struct packed {
    bit FpPresent;
    bit RVF;
    bit RVD;
    bit XF16;
  } cfg_t;

  function automatic cfg_t build(pkg_user_cfg::user_cfg_t in_cfg);
    cfg_t out_cfg;
    out_cfg.RVF       = in_cfg.RVF;
    out_cfg.RVD       = in_cfg.RVD;
    out_cfg.XF16      = in_cfg.XF16;
    out_cfg.FpPresent = in_cfg.RVF | in_cfg.RVD | in_cfg.XF16;
    return out_cfg;
  endfunction
endpackage

// --- layer 3: tb-side consumer package -------------------------------------
// This is the package that the testbench `import`s, mirroring
// fpu_common_pkg's:
//   localparam CVA6Cfg = build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);
package pkg_common;
  localparam build_cfg::cfg_t CFG =
      build_cfg::build(pkg_user_cfg::user_cfg);
endpackage

// --- DUT with parameter-port + generate-if --------------------------------
module dut #(
    parameter build_cfg::cfg_t CFG_P = '{default: 1'b0}
) (
    output logic out_o
);
  if (CFG_P.FpPresent) begin : g
    assign out_o = 1'b1;
  end
endmodule

// --- top -------------------------------------------------------------------
module top;
  import pkg_common::*;

  logic w;
  dut #(.CFG_P(CFG)) d (.out_o(w));

  initial begin
    #1ns;
    $display("[REPRO282] CFG.FpPresent=%0b  out_o=%0b  (both should be 1)",
             CFG.FpPresent, w);
    $finish;
  end
endmodule
