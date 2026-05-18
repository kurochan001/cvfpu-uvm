// Stage 5 (revised): three near-identical interfaces, each written
// to by a class through a virtual-interface handle. The only structural
// differences are:
//
//   (a) no always
//   (b) always reading `x`, but no interface port
//   (c) always reading `x`, AND the interface has an `output` port
//       (mirrors xrtl_clock_vif.sv: `interface clk_if(output bit clock);`)
//
// Expected (any conforming SV simulator):
//   a.x = b.x = c.x = 500
//
// Observed under sukimasim v0.9.9.2: to be measured.

interface if_no_always;
  int x = 10;
endinterface

interface if_always_no_port;
  int x = 10;
  bit enable = 1'b0;
  always begin
    wait(enable);
    while (enable) begin
      #(x * 1ps);
    end
  end
endinterface

interface if_always_with_output_port (output bit clk_out);
  int x = 10;
  bit enable = 1'b0;
  always begin
    wait(enable);
    while (enable) begin
      clk_out = 1'b1;
      #(x * 1ps);
      clk_out = 1'b0;
      #(x * 1ps);
    end
  end
endinterface

class writer_a;
  virtual if_no_always vif;
  real period = 0.001;
  real duty   = 50.0;
  function new(virtual if_no_always v); this.vif = v; endfunction
  task do_write(); vif.x = (period) * (duty / 100.0) * 1000000; endtask
endclass

class writer_b;
  virtual if_always_no_port vif;
  real period = 0.001;
  real duty   = 50.0;
  function new(virtual if_always_no_port v); this.vif = v; endfunction
  task do_write(); vif.x = (period) * (duty / 100.0) * 1000000; endtask
endclass

class writer_c;
  virtual if_always_with_output_port vif;
  real period = 0.001;
  real duty   = 50.0;
  function new(virtual if_always_with_output_port v); this.vif = v; endfunction
  task do_write(); vif.x = (period) * (duty / 100.0) * 1000000; endtask
endclass

module top;
  bit clk_c;

  if_no_always                   a();
  if_always_no_port              b();
  if_always_with_output_port     c (.clk_out(clk_c));

  writer_a wa;
  writer_b wb;
  writer_c wc;

  initial begin
    wa = new(a);
    wb = new(b);
    wc = new(c);
    wa.do_write();
    wb.do_write();
    wc.do_write();
    $display("[STAGE5] a.x = %0d  (no always               , expect 500)", a.x);
    $display("[STAGE5] b.x = %0d  (always, no port         , expect 500)", b.x);
    $display("[STAGE5] c.x = %0d  (always + output port    , expect 500)", c.x);
    $finish;
  end
endmodule
