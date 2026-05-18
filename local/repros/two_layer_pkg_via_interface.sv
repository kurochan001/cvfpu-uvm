// Final shape: clk and rst_n are produced INSIDE a SystemVerilog
// `interface` and exposed via output ports, then routed through top
// into the DUT — exactly mirroring how cvfpu-uvm wires
// xrtl_clock_vif.clock and xrtl_reset_vif.reset_n into fpu_wrap.

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

// --- clock interface ---  (mirrors xrtl_clock_vif's `output bit clock`)
interface clk_if (output bit clock);
  bit  enable     = 1'b1;
  int  clk_high   = 500;   // ps
  int  clk_low    = 500;   // ps
  always begin
    wait(enable);
    while (enable) begin
      clock = 1'b0;
      #(clk_high * 1ps);
      clock = 1'b1;
      #(clk_low  * 1ps);
    end
  end
endinterface

// --- reset interface --- (mirrors xrtl_reset_vif's `output bit reset_n`)
interface rst_if #( int unsigned assert_for = 5)
                 ( input  bit clk,
                   output bit reset,
                   output bit reset_n);
  initial reset = 1'b1;
  assign reset_n = ~reset;
  always @(posedge clk) begin
    static int cnt = 0;
    cnt++;
    if (cnt == assert_for) reset <= 1'b0;
  end
endinterface

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
  bit reset, rst_n;
  logic w;

  clk_if   cif (.clock(clk));
  rst_if #(.assert_for(5)) rif (.clk(clk), .reset(reset), .reset_n(rst_n));

  dut #(.CFG_P(CFG)) d (.clk_i(clk), .rst_ni(rst_n), .out_o(w));

  initial begin
    #20ns;
    $display("[REPRO282-VIF] CFG.FpPresent=%0b  w=%0b at %0t  (expect 1, 1)",
             CFG.FpPresent, w, $time);
    $finish;
  end
endmodule
