// Stage 12: 2nd statement uses a literal that shares NO sub-expression
// with the 1st RHS. Tests the CSE-like hypothesis: if the 1st-statement
// drop is triggered by the 2nd statement "covering" its sub-expressions,
// removing that overlap should restore the 1st write.

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
    vif.hi = (period) * (duty / 100.0) * 1000000;   // same RHS as Stage 6
    vif.lo = 999;                                    // unrelated literal
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;
  initial begin
    w = new(c); w.apply();
    $display("[STAGE12] hi=%0d (expected 500), lo=%0d (expected 999)", c.hi, c.lo);
    $finish;
  end
endmodule
