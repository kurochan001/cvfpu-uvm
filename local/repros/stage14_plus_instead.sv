// Stage 14: same shared sub-expr but use `1.0 + ...` instead of
// `1.0 - ...`. If the trigger is specifically the subtraction, this
// should NOT drop. If the trigger is just "shared sub-expression",
// it should still drop.

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
    vif.hi = (duty / 100.0);
    vif.lo = 1.0 + (duty / 100.0);   // 1.0 + instead of 1.0 -
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;
  initial begin
    w = new(c); w.apply();
    $display("[STAGE14] hi=%0d, lo=%0d", c.hi, c.lo);
    $finish;
  end
endmodule
