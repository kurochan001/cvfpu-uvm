// Stage 2: drive `enable` from a class through a virtual-interface
// handle (same shape as cv_dv_utils' clock_driver_c). No UVM, no
// uvm_config_db — plain class instantiated from an initial block.

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
        $display("[STAGE2 OK] count=%0d at %0t", count, $time);
        $finish;
      end
    end
  end
endinterface

class clock_driver;
  virtual clk_if vif;

  function new(virtual clk_if v);
    this.vif = v;
  endfunction

  task start_clock(int high, int low);
    vif.clk_high = high;
    vif.clk_low  = low;
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
    drv.start_clock(.high(10), .low(10));
  end
endmodule
