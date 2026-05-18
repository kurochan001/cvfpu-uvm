// Stage 6: interface with TWO `int` variables driving #delay inside an
// always; both are written from a class via virtual interface with a
// real → int expression. This is structurally identical to
// xrtl_clock_vif.sv + clock_driver_c.svh (cv_dv_utils).
//
// Expected: hi = lo = 500
// Observed under sukimasim v0.9.9.2: TBM

interface clk2_if (output bit clk_out);
  int hi = 10;
  int lo = 10;
  bit enable = 1'b0;

  always begin
    wait(enable);
    while (enable) begin
      clk_out = 1'b1;
      #(hi * 1ps);
      clk_out = 1'b0;
      #(lo * 1ps);
    end
  end
endinterface

class clk_writer;
  virtual clk2_if vif;
  real period = 0.001;
  real duty   = 50.0;

  function new(virtual clk2_if v); this.vif = v; endfunction

  task apply();
    // exact shape from cv_dv_utils clock_driver_c.svh:80-81
    vif.hi = (period) * (duty / 100.0) * 1000000;
    vif.lo = (period) * (1.0 - (duty / 100.0)) * 1000000;
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;

  initial begin
    w = new(c);
    w.apply();
    $display("[STAGE6] hi=%0d lo=%0d (both expected = 500)", c.hi, c.lo);
    $finish;
  end
endmodule
