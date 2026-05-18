// Stage-up of two_layer_pkg_generate_dropped.sv:
// the inner driver of out_o is no longer `assign out_o = 1'b1` but a
// proceduralised mini-FSM modelled on fpu_wrap's `p_inputFSM` /
// `fp_hold_reg`:
//
//   always_ff @(posedge clk_i or negedge rst_ni) begin
//     if (~rst_ni) state_q <= READY;
//     else         state_q <= state_d;
//   end
//
//   always_comb begin
//     out_o = 1'b0;
//     case (state_q)
//       READY: out_o = 1'b1;
//       ...
//     endcase
//   end
//
// Expected: after reset deasserts, state_q=READY → out_o=1.
// Observation we want to check: does sukimasim drive out_o here, or
// does it stay X like fpu_ready_o does in the CVFPU smoke?

package pkg_user_cfg;
  typedef struct packed { bit RVF; bit RVD; bit XF16; } user_cfg_t;
  localparam user_cfg_t user_cfg = '{RVF: 1'b1, RVD: 1'b1, XF16: 1'b1};
endpackage

package build_cfg;
  typedef struct packed { bit FpPresent; bit RVF; bit RVD; bit XF16; } cfg_t;
  function automatic cfg_t build(pkg_user_cfg::user_cfg_t in_cfg);
    cfg_t o;
    o.RVF = in_cfg.RVF; o.RVD = in_cfg.RVD; o.XF16 = in_cfg.XF16;
    o.FpPresent = in_cfg.RVF | in_cfg.RVD | in_cfg.XF16;
    return o;
  endfunction
endpackage

package pkg_common;
  localparam build_cfg::cfg_t CFG = build_cfg::build(pkg_user_cfg::user_cfg);
endpackage

module dut #(
    parameter build_cfg::cfg_t CFG_P = '{default: 1'b0}
) (
    input  logic clk_i,
    input  logic rst_ni,
    output logic out_o
);
  if (CFG_P.FpPresent) begin : g
    typedef enum logic { READY, STALL } state_e;
    state_e state_q, state_d;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) state_q <= READY;
      else         state_q <= state_d;
    end

    always_comb begin : p_fsm
      out_o   = 1'b0;
      state_d = state_q;
      unique case (state_q)
        READY: out_o = 1'b1;
        STALL: out_o = 1'b0;
      endcase
    end
  end
endmodule

module top;
  import pkg_common::*;

  bit clk;
  bit rst_n;
  logic w;

  // simple 1-ns half-period clock generator
  initial clk = 0;
  always #500ps clk = ~clk;

  // active-low reset, pulse low for 5 ns
  initial begin
    rst_n = 1'b0;
    #5ns;
    rst_n = 1'b1;
  end

  dut #(.CFG_P(CFG)) d (.clk_i(clk), .rst_ni(rst_n), .out_o(w));

  initial begin
    #20ns;
    $display("[REPRO282-FSM] CFG.FpPresent=%0b  w=%0b at %0t  (expect FpPresent=1, w=1)",
             CFG.FpPresent, w, $time);
    $finish;
  end
endmodule
