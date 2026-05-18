# `WhileLoop with timing exceeded maximum iterations` in interface-scoped
# clock generator stalls UVM simulation at `main_phase`

## Summary

The CVFPU UVM smoke (`+UVM_TESTNAME=fpu_random_test` seed=1) reaches
`main_phase` and then sukimasim prints

```
WARNING: WhileLoop with timing exceeded maximum iterations time=10000001
condition=clock_if.enable body=begin
  clock = starting_signal_level;
  clock_if.clock = clock_if.starting_signal_level;
  #(unknown'(clock_if.clk_high) * 0.001000) begin
end
  clock_if.clock...
[TIMEOUT] Wall-clock timeout reached (60s) during combinational evaluation
          (entry). Stopping simulation at time 12011501
Simulation completed with 1 error(s)
```

Then the wall-clock timeout (60 s) kills the run. No UVM transaction is
issued — the FPU `fpu_random_test` driver never gets to drive the first
`fu_data` because the clock is not progressing.

Two things stand out in the warning text:

1. `time=10000001` — exactly 10,000,001 iterations of the inner `while`
   loop. That matches sukimasim's internal iteration cap, which suggests
   the loop body **does not advance simulation time** even though the
   source body contains a `#delay`.

2. `#(unknown'(clock_if.clk_high) * 0.001000)` — the AST rendering of
   the delay uses `unknown'(...)` for the cast destination of `clk_high`.
   `clk_high` is declared as `int clk_high = 10;`, so the cast target
   should be `int` (or whatever time-numeric type sukimasim normalises
   to), never `unknown`. If the operand really is treated as `unknown`
   at runtime, multiplying by `0.001000` (the 1 ps → 1 ns scale factor)
   yields `unknown × 0.001 = unknown / 0`, which a sane time-evaluator
   should refuse, but it could plausibly come back as `0`, giving a
   zero-delay infinite loop — exactly what the iteration cap message
   describes.

## Source shape — interface with `always`

`modules/core-v-verif/lib/cv_dv_utils/uvm/clock_gen/xrtl_clock_vif.sv`:

```systemverilog
interface xrtl_clock_vif ( output bit clock);
  timeunit 1ns;
  timeprecision 1ps;

  bit enable = 1'b0;
  bit starting_signal_level = 1'b0;
  int clk_high = 10;
  int clk_low  = 10;

  always begin
    wait(enable);
    if ((clk_high == 0) || (clk_low == 0)) begin
      $display("[FATAL] %m Clock Period is zero : %0d %0d", clk_high, clk_low);
      $finish;
    end
    while (enable) begin
      clock = starting_signal_level;
      #(clk_high*1ps);              // <— rendered as `unknown'(clk_high) * 0.001`
      clock = ~starting_signal_level;
      #(clk_low*1ps);
    end
  end
endinterface
```

`enable`, `clk_high`, `clk_low` are written from a UVM `clock_driver_c`
component via the virtual-interface handle that `tb_top` puts into the
`uvm_config_db` — i.e. they are written from class scope at run time,
not parametrised at elaboration time.

## What the trace shows reaching the loop

```
[UVM_INFO] @ 0: clock_driver_c [CLOCK_DRIVER_C] START clock period = 1000.000000 ps,
            clock duty = 50, low_clock = 500000000 ps, high_clock = 500000000 ps
[UVM_INFO] @ 0: fpu_random_test [TEST] run_phase
[UVM_INFO] @ 0: fpu_random_test [TEST] reset_phase
[UVM_INFO] @ 50501: reset_driver_c [RESET DONE] (0 active)
[UVM_INFO] @ 50501: fpu_random_test [TEST] pre_main_phase
[UVM_INFO] @ 50501: fpu_random_test [TEST] main_phase
WARNING: WhileLoop with timing exceeded maximum iterations time=10000001 ...
```

Simulated time reaches 50501 ps (i.e. the clock *was* progressing
during `reset_phase`, ~50 ns of activity), so a constant-zero delay
cannot be the whole story — something flips state between the
post-reset wait and the start of `main_phase`. Possibly the UVM driver
re-writes `clk_high` at that point and the new value re-routes through
the same `unknown'(...)` AST node, but that is speculation until a
proper minimal repro is in hand.

## Single-file repros that **do not** reproduce

I tried four progressively closer single-file reproducers (under
`local/repros/while_loop_stage{1,2,3,4}_*.sv` in the bringup repo).
All four pass:

| stage | shape                                                              | result |
|------:|--------------------------------------------------------------------|:------:|
|   1   | interface scope `always`/`while`, module-`initial` writes `enable` | PASS   |
|   2   | + plain class with `virtual clk_if vif` writes `enable`/`clk_high` | PASS   |
|   3   | + the *exact* `clk_high = real-expr * 1_000_000` form from         | PASS (\*) |
|       | `cv_dv_utils/uvm/clock_gen/clock_driver_c.svh:80`                  |        |
|   4   | four variations of the real-to-int assignment, no `always`         | PASS   |

(\*) Stage 3 prints `clk_high=10` (i.e. the variable's initial value
rather than the `500` that the RHS evaluates to in Stage 4), yet still
runs to completion because `#(10*1ps)` is non-zero and the loop ticks.
That seeded-default vs. computed-value anomaly is a different bug
shape — likely an interaction between the interface-scope `always`
re-reading the variable and the class-scope write — but it is not on
the path to the `unknown'(...)` AST node observed in the full UVM run.

So this is *not* simply "sukimasim mishandles `int * 1ps`" — that case
works in isolation. Reaching the failure requires at least the full
UVM phase plumbing (`uvm_config_db`, `pre_reset_phase` fork-join_none
to `start_clock`, then a `main_phase` re-entry while the interface's
`always` is still re-evaluating the `while`-body delay expression).

Reduction toward a minimal repro is on-going; this issue is filed now
so the AST rendering hint (`#(unknown'(clock_if.clk_high) * 0.001000)`)
is on record, since that text is far more specific than anything I can
reduce without internal access to the time-expression code path.

## sukimasim

- self-reported version: `v0.9.9.2`
- binary: `~/Work2/sukimasim/build/sukimasim`

## Reproduction (full bringup)

```sh
git clone https://github.com/kurochan001/cvfpu-uvm.git
cd cvfpu-uvm
git checkout sukimasim-bringup
git submodule update --init --recursive
sudo apt-get install libgmp-dev libmpfr-dev

make smoke    # exits non-zero (2); log at output/sukimasim/fpu_random_test_seed1.log
              # plus the WhileLoop / TIMEOUT lines on stdout above.
```

## Suggested next step

I will keep narrowing the repro toward a single-file interface-scoped
clock generator driven from a class. The aspect that needs an internal
fix is whichever stage rewrites `clk_high` (an ordinary `int`
variable) into the AST node printed as `unknown'(clk_high)` — that
rendering should never appear for an `int` operand. Pointers to where
delay-expression cast destinations are inferred would help me reduce
the repro faster.
