// Stage 11: single write only. Does the Stage 6 RHS still drop when
// it is the only statement in the task?

interface clk2_if (output bit clk_out);
  int hi = 10;
  int lo = 10;
  bit enable = 1'b0;
  always begin
    wait(enable);
    while (enable) begin
      clk_out = 1'b1; #(hi * 1ps);
      clk_out = 1'b0; #(lo * 1ps);
    end
  end
endinterface

class clk_writer;
  virtual clk2_if vif;
  real period = 0.001;
  real duty   = 50.0;
  function new(virtual clk2_if v); this.vif = v; endfunction
  task apply();
    vif.hi = (period) * (duty / 100.0) * 1000000;   // only statement
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;
  initial begin
    w = new(c); w.apply();
    $display("[STAGE11] hi=%0d (expected 500), lo=%0d (untouched, expected 10)", c.hi, c.lo);
    $finish;
  end
endmodule
