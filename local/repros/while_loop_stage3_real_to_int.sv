// Stage 3: write `clk_high` from a real-typed expression (real → int
// implicit conversion). This is exactly what cv_dv_utils'
// clock_driver_c does in its start_of_simulation_phase:
//
//   m_v_clock_vif.clk_high = (period) * (duty/100.0) * 1000000;  // ps
//
// where period and duty are real.

interface clk_if (output bit clock);
  timeunit 1ns;
  timeprecision 1ps;

  bit enable = 1'b0;
  int clk_high = 10;
  int clk_low  = 10;
  int count    = 0;

  always begin
    wait(enable);
    while (enable) begin
      clock = 1'b0;
      #(clk_high * 1ps);
      clock = 1'b1;
      #(clk_low  * 1ps);
      count++;
      if (count >= 5) begin
        $display("[STAGE3 OK] count=%0d at %0t", count, $time);
        $finish;
      end
    end
  end
endinterface

class clock_driver;
  virtual clk_if vif;

  real m_clock_period;   // ns
  real m_duty_cycle;     // %

  function new(virtual clk_if v);
    this.vif         = v;
    this.m_clock_period = 0.001;   // mirrors cv_dv_utils real arithmetic
    this.m_duty_cycle   = 50.0;
  endfunction

  task start_clock();
    // exact shape from cv_dv_utils clock_driver_c.svh:80-81
    vif.clk_high = (m_clock_period) * (m_duty_cycle / 100.0) * 1000000;  // ps
    vif.clk_low  = (m_clock_period) * (1.0 - (m_duty_cycle / 100.0)) * 1000000;
    $display("[STAGE3] clk_high=%0d clk_low=%0d", vif.clk_high, vif.clk_low);
    vif.enable   = 1'b1;
  endtask
endclass

module top;
  bit clk;
  clk_if cif (.clock(clk));

  clock_driver drv;

  initial begin
    drv = new(cif);
    #1ns;
    drv.start_clock();
  end
endmodule
