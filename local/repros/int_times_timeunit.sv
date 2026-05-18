// Minimal reproducer for:
//   "WhileLoop with timing exceeded maximum iterations"
//   caused by `#(<int> * 1ps)` style delay being evaluated as if the
//   integer operand had no value (sukimasim renders it internally as
//   `unknown'(<id>) * 0.001000`).
//
// Expected: the always-loop ticks `count` once every 10 ps and `$finish`
//           after 5 ticks (~50 ps simulated).
// Observed under sukimasim: the inner while loop spins without advancing
//           simulation time, hits the iteration cap, and the wall-clock
//           timeout fires.
//
// Run:
//   sukimasim --max-time 1us int_times_timeunit.sv
//
// (mirrors xrtl_clock_vif.sv from core-v-verif cv_dv_utils/uvm/clock_gen/)

module top;
  timeunit 1ns;
  timeprecision 1ps;

  bit clk = 0;
  bit enable = 1'b1;
  int clk_high = 10;     // intentionally `int`, default value 10
  int clk_low  = 10;
  int count    = 0;

  always begin
    wait(enable);
    while (enable) begin
      clk = 1'b0;
      #(clk_high * 1ps);    // 10 ps high
      clk = 1'b1;
      #(clk_low  * 1ps);    // 10 ps low
      count++;
      if (count >= 5) begin
        $display("[OK] count=%0d at %0t", count, $time);
        $finish;
      end
    end
  end
endmodule
