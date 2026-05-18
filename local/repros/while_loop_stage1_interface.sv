// Stage 1: move the always+while into an interface, drive enable
// from a module initial. No class, no virtual interface, no UVM.

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
        $display("[STAGE1 OK] count=%0d at %0t", count, $time);
        $finish;
      end
    end
  end
endinterface

module top;
  bit clk;
  clk_if cif (.clock(clk));
  initial begin
    #1ns;
    cif.enable = 1'b1;
  end
endmodule
