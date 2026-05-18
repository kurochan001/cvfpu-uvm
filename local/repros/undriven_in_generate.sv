// Minimal reproducer for the UNDRIVEN-in-generate lint regression.
//
// Mirrors the fpu_wrap shape used by CVFPU UVM:
//   package + automatic function + localparam struct + parameter port +
//   generate-if on a parameter struct field + assign inside the generate.
//
// Expected (any conforming SV simulator):
//   - elaborate dut.g
//   - drive out_o = 1'b1
//   - no UNDRIVEN warning for out_o
//
// Observed on sukimasim v0.9.9.2 with --lint:
//   - PITFALL-OUTPUT-UNDRIVEN: output port 'out_o' of module 'dut'

package cfg_pkg;
  typedef struct packed {
    bit FpPresent;
    bit RVF;
    bit RVD;
  } cfg_t;

  // Mirrors openhw build_config_pkg::build_config — an `automatic`
  // function called from a `localparam` initialiser to fold derived
  // fields (FpPresent = RVF | RVD).
  function automatic cfg_t build_config(cfg_t in_cfg);
    cfg_t out_cfg;
    out_cfg.RVF       = in_cfg.RVF;
    out_cfg.RVD       = in_cfg.RVD;
    out_cfg.FpPresent = in_cfg.RVF | in_cfg.RVD;
    return out_cfg;
  endfunction

  localparam cfg_t USER_CFG = '{FpPresent: 1'b0, RVF: 1'b1, RVD: 1'b1};
  localparam cfg_t CVA6Cfg  = build_config(USER_CFG);
endpackage

module dut #(
    parameter cfg_pkg::cfg_t CFG = '{default: 1'b0}
) (
    output logic out_o
);
  if (CFG.FpPresent) begin : g
    assign out_o = 1'b1;
  end
endmodule

module top;
  import cfg_pkg::*;
  logic w;
  dut #(.CFG(CVA6Cfg)) d (.out_o(w));

  initial begin
    #1ns;
    $display("[REPRO] CVA6Cfg.FpPresent=%0b  out_o=%0b (expect 1 / 1)",
             CVA6Cfg.FpPresent, w);
    $finish;
  end
endmodule
