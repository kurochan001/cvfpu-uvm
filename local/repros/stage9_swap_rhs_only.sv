// Stage 9: Stage 6 with the two RHS *expressions* swapped (LHS order
// unchanged: hi first, lo second). If the bug is RHS-shape-sensitive,
// the drop should follow the (period*(duty/100.0)*1000000) shape and
// move from `hi` to `lo`.

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
    // RHS expressions swapped vs Stage 6 (LHS order unchanged)
    vif.hi = (period) * (1.0 - (duty / 100.0)) * 1000000;
    vif.lo = (period) * (duty / 100.0) * 1000000;
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;
  initial begin
    w = new(c); w.apply();
    $display("[STAGE9] hi=%0d lo=%0d", c.hi, c.lo);
    $finish;
  end
endmodule
