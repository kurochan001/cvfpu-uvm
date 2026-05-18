// Stage 8: Stage 6 with constant-literal RHS — does the drop survive
// when the RHS is a plain int literal (no real arithmetic)?

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
  function new(virtual clk2_if v); this.vif = v; endfunction
  task apply();
    vif.hi = 500;  // literal, same write order as Stage 6
    vif.lo = 500;
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;
  initial begin
    w = new(c); w.apply();
    $display("[STAGE8] hi=%0d lo=%0d", c.hi, c.lo);
    $finish;
  end
endmodule
