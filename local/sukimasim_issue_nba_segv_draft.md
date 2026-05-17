# SIGSEGV in NBA-region callback during UVM reset_phase (post-#265)

## Summary

After the #265 fix landed (commit `d99e191f6`, "Fix null class handle
method calls"), the same CVFPU UVM smoke now progresses further into
`reset_phase` but still crashes with SIGSEGV — this time **not** routed
through the SystemVerilog `RUNTIME_NULL_OBJECT` runtime error, and not
caught by sukimasim's own SIGSEGV handler. The bash job-control reports

> `Segmentation fault (core dumped)`
> `[INFO] sukimasim exit = 139`

with no `[FATAL] Signal caught` line from sukimasim itself. The
backtrace points to a lambda registered in `TestbenchRuntime`'s
constructor, called from inside `NBAFullEvent::execute()`.

## Relation to #265

| | before #265 fix | after #265 fix (this issue) |
|---|---|---|
| sukimasim handler trips | yes — `[FATAL] Signal caught: SIGSEGV` | **no** (silent SIGSEGV) |
| `RUNTIME_NULL_OBJECT` | no | no |
| furthest UVM phase reached | `reset_phase`, mid `reset_driver_c [RESET START]` | `pre_reset_phase` + `reset_phase`, NBA region |
| crashing path | (class-handle method call, root cause of #265) | NBA-region callback |

So #265 widened the path that the testbench can walk before crashing;
the next null/dangling reference shows up one delta-cycle later, inside
the NBA scheduling region instead of the class-method dispatch.

## sukimasim

- repo: `kurochan001/sukimasim`
- HEAD: `49826e013` (Improve parameterized class expression forwarding)
- fix for #265 is in tree: `d99e191f6` is reachable from HEAD
- build: `cmake --build build --target sukimasim` (debug, `-g`, ccache
  cleared / disabled — stale ccache hit a phantom `SymbolKind::TypeAliasType`
  reference unrelated to this issue)
- self-reported version: `v0.9.9.2`

## Repro

```sh
# cvfpu-uvm side
git clone https://github.com/kurochan001/cvfpu-uvm.git
cd cvfpu-uvm
git checkout sukimasim-bringup     # at 9ebc04d
git submodule update --init --recursive

# host deps (one-time)
sudo apt-get install libgmp-dev libmpfr-dev
cargo install bender

# bringup
source local/env_sukimasim.sh
bender update
bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
    > local/cvfpu_uvm_sukimasim.bender.f
bash local/build_refmodel_sukimasim.sh
bash local/run_sukimasim_compile.sh    # PASS, all 3 DPI libs load
bash local/run_sukimasim_smoke.sh      # SIGSEGV (this issue)
```

## Last UVM lines before the crash

```
[UVM_INFO] @ 0: clock_driver_c [CLOCK_DRIVER_C] START clock period = 1000 ps, duty = 50
[UVM_INFO] @ 0: fpu_random_test [TEST] run_phase
[UVM_INFO] @ 0: watchdog_c [WD START] Global Watchog Timer set to 30000000 ns
[UVM_INFO] @ 0: fpu_random_test [TEST] pre_reset_phase
[UVM_INFO] @ 0: fpu_random_test [TEST] reset_phase
<Segmentation fault — no further sukimasim output>
```

## Backtrace (from `gdb --args ${SUKIMASIM_BIN} ... -ex run -ex bt`)

```
Program received signal SIGSEGV, Segmentation fault.

#0  std::_Function_handler<
      void(const std::string&, const std::shared_ptr<sukimasim::ir::Value>&),
      sukimasim::eval::TestbenchRuntime::TestbenchRuntime(
        sukimasim::ir::ModuleIR*, std::basic_ostream<char>&)::$_4>::_M_invoke(...)
#1  sukimasim::scheduler::NBAFullEvent::execute()
#2  sukimasim::scheduler::FullDeltaScheduler::executeRegion(FullRegion)
#3  sukimasim::scheduler::FullDeltaScheduler::executeDeltaCycle()
#4  sukimasim::eval::TestbenchRuntime::executeDeltaCyclesOnce()
#5  sukimasim::eval::TestbenchRuntime::executeUVMRuntimePhasesFromIndex(unsigned long)
#6  sukimasim::eval::TestbenchRuntime::executeUVMTest("fpu_random_test")
#7  sukimasim::eval::TestbenchRuntime::handleRunTestTask(...)
#8  std::_Function_handler<...,
      TestbenchRuntime::setupBuiltinSystemTasks()::$_44>::_M_invoke(...)
#9  sukimasim::eval::TestbenchRuntime::executeSystemTask(SystemTaskCall, EvaluationContext&)
#10 sukimasim::eval::StatementExecutor::execute(Statement*)
#11 ...
#13 TestbenchRuntime::scheduleInitialBlocks()::$_8
#14 FullDeltaScheduler::executeRegion(FullRegion)
#15 FullDeltaScheduler::executeDeltaCycle()
#16 TimingScheduler::processDeltaCycle()
#17 TimingScheduler::processTimeSlot(unsigned long)
#18 TimingScheduler::run(unsigned long)
#19 TestbenchRuntime::run(unsigned long)
#20 main
```

Only one thread; build is `-g` but not `-O0`, so locals are not
recoverable from a release build without rebuilding at `-O0`.

## Suspected source

- The crashing frame is a lambda captured in `TestbenchRuntime`'s ctor,
  whose signature `void(const std::string&, shared_ptr<ir::Value>&)`
  matches an NBA-update sink: `(target name, new value)`. NBA region
  callbacks are dispatched from `NBAFullEvent::execute()` per
  scheduler turn.
- One plausible shape: the lambda derefs a captured raw pointer (or
  weak pointer / iterator) into a per-target map that has been
  invalidated, rather than the SV-level `shared_ptr<Value>` argument
  (which the callsite holds live).
- This is **not** a class-method dispatch on a null receiver, so the
  #265 guard correctly stays out of the way; the bug is one layer
  deeper, inside the NBA delivery path itself.

## Expected behaviour

- Detect the null/dangling case before delivering it to the NBA
  callback (e.g. validate the target lookup, or wrap the lambda with
  the same null-guard machinery #265 added for method dispatch).
- Or, if the captured state is genuinely supposed to outlive the
  scheduler turn, capture by `weak_ptr` / `shared_ptr` and report a
  clean SV runtime error (or sukimasim-internal assertion) on the
  miss instead of letting the host see SIGSEGV.

## Notes

- The cvfpu-uvm `--lint` warning `PITFALL-NULL-HANDLE` on
  `xrtl_reset_vif::hvl_obj` may still be relevant: the reset driver
  reaches that point through a non-blocking assignment, so a
  null-handle write going through NBA could explain why the trip
  point moved from "class method dispatch" (#265) to "NBA callback"
  (this issue). Worth correlating during the fix.
- An `-O0` rebuild of `sukimasim` would let us name the captured
  variables and the exact NBA target — happy to repro under that
  build if useful.
