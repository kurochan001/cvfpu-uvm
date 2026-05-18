// Stage 13: minimise to "1.0 - shared_subexpr" trigger.
// 1st RHS = X / Y
// 2nd RHS = 1.0 - (X / Y)
// where (X / Y) is the common sub-expression.

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
  real duty = 50.0;
  function new(virtual clk2_if v); this.vif = v; endfunction
  task apply();
    vif.hi = (duty / 100.0);              // expect 0 (int trunc of 0.5)
    vif.lo = 1.0 - (duty / 100.0);        // expect 0 (int trunc of 0.5)
                                           // both should overwrite 10
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;
  initial begin
    w = new(c); w.apply();
    $display("[STAGE13] hi=%0d (overwritten? expect != 10), lo=%0d (overwritten? expect != 10)",
             c.hi, c.lo);
    $finish;
  end
endmodule
