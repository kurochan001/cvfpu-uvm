// Stage 4: isolate the "assignment silently dropped" anomaly seen in
// Stage 3 — compare four nearly-identical real→int writes to the same
// interface variable. No always-block, no while loop, no UVM. Just
// print the values immediately after the writes.
//
// Expected (any conforming SV simulator): all four print 500.
// Observed on sukimasim v0.9.9.2: cases (a) and (c) print 10
// (the variable's default), the others print 500.

interface bus_if;
  int x_a = 10;
  int x_b = 10;
  int x_c = 10;
  int x_d = 10;
endinterface

class writer;
  virtual bus_if vif;
  real period = 0.001;
  real duty   = 50.0;

  function new(virtual bus_if v); this.vif = v; endfunction

  task write_all();
    // (a) shape from cv_dv_utils clock_driver_c:80 — `clk_high`
    vif.x_a = (period) * (duty / 100.0) * 1000000;

    // (b) shape from cv_dv_utils clock_driver_c:81 — `clk_low`
    vif.x_b = (period) * (1.0 - (duty / 100.0)) * 1000000;

    // (c) like (a) but drop the inner parentheses
    vif.x_c = period * (duty / 100.0) * 1000000;

    // (d) like (a) but split into two statements
    begin
      real tmp;
      tmp = (period) * (duty / 100.0) * 1000000;
      vif.x_d = tmp;
    end
  endtask
endclass

module top;
  bus_if bif();
  writer w;

  initial begin
    w = new(bif);
    w.write_all();
    $display("[STAGE4] x_a=%0d (expect 500)", bif.x_a);
    $display("[STAGE4] x_b=%0d (expect 500)", bif.x_b);
    $display("[STAGE4] x_c=%0d (expect 500)", bif.x_c);
    $display("[STAGE4] x_d=%0d (expect 500)", bif.x_d);
    $finish;
  end
endmodule
