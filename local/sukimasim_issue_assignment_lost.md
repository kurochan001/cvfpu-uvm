# Class-scope `vif.var = real-expr` assignment silently dropped when
# the same `var` is read by an interface-scope `#delay` expression

## Summary

When a class writes a real-valued RHS into an `int` member of an
interface through a `virtual` interface handle, **and** that interface
also has an `always` block that uses the same member inside a
`#(var * 1ps)` style delay expression, sukimasim silently **drops** the
assignment for the *first* of two such writes in the same task. The
variable keeps its declaration-time initial value, the print right
after the write sees the initial value, and any downstream code
(including the `#delay` itself) uses the stale value.

A neighbouring assignment to a different variable in the same
interface, with the same shape of RHS, completes correctly. So the
bug is sensitive to **which** variable, not to the assignment
mechanism itself.

This is a correctness bug, not a diagnostic — there is no warning at
elaboration time and no warning at run time. The first symptom is a
clock that ticks at the wrong period.

## Minimal repro (~50 lines, no UVM)

`assignment_lost_two_vars.sv`:

```systemverilog
interface clk2_if (output bit clk_out);
  int hi = 10;
  int lo = 10;
  bit enable = 1'b0;

  always begin
    wait(enable);
    while (enable) begin
      clk_out = 1'b1;
      #(hi * 1ps);
      clk_out = 1'b0;
      #(lo * 1ps);
    end
  end
endinterface

class clk_writer;
  virtual clk2_if vif;
  real period = 0.001;
  real duty   = 50.0;

  function new(virtual clk2_if v); this.vif = v; endfunction

  task apply();
    // shape from cv_dv_utils clock_driver_c.svh:80-81
    vif.hi = (period) * (duty / 100.0) * 1000000;
    vif.lo = (period) * (1.0 - (duty / 100.0)) * 1000000;
  endtask
endclass

module top;
  bit clk;
  clk2_if c (.clk_out(clk));
  clk_writer w;

  initial begin
    w = new(c);
    w.apply();
    $display("[REPRO] hi=%0d lo=%0d (both expected = 500)", c.hi, c.lo);
    $finish;
  end
endmodule
```

### Run

```
$ sukimasim --max-time 1us assignment_lost_two_vars.sv
...
[REPRO] hi=10 lo=500 (both expected = 500)
$finish called at simulation time 0
TEST PASSED
```

- `c.lo` = 500 → assignment took effect.
- `c.hi` = 10  → **assignment was silently dropped** (initial value).

Both writes are real-typed RHS being assigned to `int`, both happen in
the same `task`, both go through the same `virtual clk2_if`. The only
structural difference is the RHS shape (`(period)*(duty/100.0)*1000000`
vs `(period)*(1.0 - (duty/100.0))*1000000`) and the LHS variable name.

### What the repro is **not** sensitive to

- not the keyword `program` — that just collides with SV's program
  construct, the task is named `apply` here.
- not the always-block running — it never starts (`enable` stays 0).
- not the interface having an `output` port alone — Stage 5 in
  `local/repros/assignment_lost_with_alwaysreader.sv` shows that the
  port + always combination on a single-variable interface assigns
  correctly.
- not the `real → int` conversion alone — Stage 4 in
  `local/repros/while_loop_stage4_assignment_lost.sv` shows four
  near-identical real-to-int writes to a single interface
  (no always, no port) all succeed.

The combination required for the drop, as far as I have narrowed it:

1. interface has a non-empty `always` whose body contains
   `#(var * 1ps)` referencing the `int` member,
2. interface has **two** `int` members both used the same way in the
   always (`hi` and `lo`),
3. the class assigns real RHS to both inside the same task.

Remove any one of those (drop the second `int`, or remove the
always, or assign only one) and both writes go through.

## Relation to other issues

This is almost certainly the root cause of #280
(`WhileLoop iteration cap fires during interface-scope clock generator`),
because the cv_dv_utils `clock_driver_c.svh:80-81` is exactly the
shape above — it writes `m_v_clock_vif.clk_high` then
`m_v_clock_vif.clk_low` from a real expression. If `clk_high` is
dropped to the initial seed but the always block uses the new
`clk_low`, the rendered AST and runtime behaviour around the
delay expression diverge in ways that match #280's observation.

Suggest fixing this issue first; #280 likely closes naturally once
the assignment is no longer dropped.

## sukimasim

- self-reported version: `v0.9.9.2`
- binary used: `~/Work2/sukimasim/build/sukimasim`
- HEAD known to include the #265 null-handle fix (commit `d99e191f6`).

## Suggested investigation area

Whatever stage maps the class-scope `vif.<member> = real-expr;`
LHS through the virtual-interface handle into a hierarchical reference
write — when the target member is *also* live as an operand in a
sibling `always` block's delay expression, the first such write per
task is being dropped. Possibilities:

- the virtual-interface write is being routed to a stale shadow copy
  of the variable (one used by the delay-expression rewrite that
  produced the `unknown'(...)` form mentioned in #280),
- the elaborator is folding the variable into the delay AST as a
  constant (initial value), and the runtime write does not update the
  folded copy.

If pointers to the virtual-interface write path would help me reduce
this further (or split it into "two writes in one task" vs "two
interface members used in same `always`"), happy to keep narrowing.
