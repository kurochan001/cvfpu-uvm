# Catch null class-handle dereference instead of crashing with SIGSEGV

## Summary

When a UVM testbench dereferences a `class` handle that was declared but
never assigned (i.e. left at its default `null`), sukimasim faults with
SIGSEGV (exit 139) and prints

> `[FATAL] Signal caught: SIGSEGV (Segmentation fault)`
> `This is likely due to a serious error in the simulation.`
> `Please report this issue with a minimal test case.`

IEEE 1800-2023 §8.6 specifies the default value of an uninitialised
class handle as `null`, and accessing a member through such a handle is
a runtime error — not undefined behaviour. Commercial simulators
(QuestaSim, Xcelium, VCS) surface this as a recoverable runtime error
("attempt to use null object handle" / equivalent) and let the
test continue, typically resulting in a clean `UVM_FATAL` and a non-zero
exit code instead of crashing the simulator process.

It would be ideal if sukimasim:

1. Caught null-handle member access before the host OS sees a fault, and
2. Reported it as an SV runtime error (with source location), so users
   debug the **testbench**, not the simulator.

## Repro

Surfaced while bringing up the CVFPU UVM testbench under sukimasim.
Reproducible from a clean clone of the fork that hosts the bringup
scaffolding:

```sh
git clone https://github.com/kurochan001/cvfpu-uvm.git
cd cvfpu-uvm
git checkout sukimasim-bringup     # at 4bcc8fc
git submodule update --init --recursive

# one-time: install deps
sudo apt-get install libgmp-dev libmpfr-dev   # multiarch headers
cargo install bender

# build refmodel + bender filelist + sukimasim runs
source local/env_sukimasim.sh
bender update
bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
    > local/cvfpu_uvm_sukimasim.bender.f
bash local/build_refmodel_sukimasim.sh
bash local/run_sukimasim_compile.sh    # PASS
bash local/run_sukimasim_smoke.sh      # SIGSEGV
```

## sukimasim

- commit: `3259f7c44`
- self-reported version: `v0.9.9.2`
- invocation (full command line is in `output/sukimasim/cmd.txt`):
  ```
  sukimasim --enable-uvm --preprocess -top top \
    --work-dir output/sukimasim/work --errormax 1 \
    --seed 1 --max-time 1ms --wall-timeout 60 \
    -f local/cvfpu_uvm_sukimasim.f \
    --lib-path .../ref_model_csim/cpp/build --lib refmodel_csim_lib.so \
    +define+SUKIMASIM +incdir+/.../cvfpu-uvm \
    +UVM_TESTNAME=fpu_random_test +UVM_VERBOSITY=UVM_LOW \
    +NB_TXNS=1 +TIMEOUT=30000000
  ```

## Last lines before the crash

```
[UVM_INFO] @ 0: reset_driver_c#(1'b1,50,0) [RESET CONNECT] Reset driver now connected
[UVM_INFO] @ 0: clock_driver_c [CLOCK_DRIVER_C] START clock period = 1000 ps, duty = 50
[UVM_INFO] @ 0: watchdog_c [WD START] Global Watchog Timer set to 30000000 ns
[UVM_INFO] @ 0: fpu_random_test [TEST] reset_phase
[UVM_INFO] @ 0: fpu_driver [driver] Reset stage complete.
[UVM_INFO] @ 0: fpu_sb [SCOREBOARD] Reset stage complete.
[UVM_INFO] @ 0: reset_driver_c#(1'b1,50,0) [RESET START] RESET START (0 active)
[FATAL] Signal caught: SIGSEGV (Segmentation fault)
```

## Suspected source

`sukimasim --lint` on the same testbench already flags the likely
culprit (one entry among the 33 lint warnings):

> `[WARNING] PITFALL-NULL-HANDLE: class handle 'hvl_obj' declared`
> `without new() and never assigned in module 'xrtl_reset_vif' —`
> `any member access will null-deref at runtime. IEEE 1800-2023 §8.6:`
> `class handles default to null; construct the object explicitly`
> `(e.g. hvl_obj = new();) before use.`

`xrtl_reset_vif::hvl_obj` is touched by the reset driver immediately
after `[RESET START]`, which is exactly where the SIGSEGV strikes.

## Expected behaviour

- Either: a clean SV runtime error such as
  > `Error: null object access at <file>:<line> (handle 'hvl_obj' in xrtl_reset_vif)`
  followed by a non-zero exit, **without** raising SIGSEGV from the
  simulator process itself.
- Or: a UVM_FATAL routed through `uvm_report_fatal`, equivalent to
  what commercial simulators emit, so user-level CI keeps working.

## Notes

- The lint subsystem already detects this case statically — closing the
  loop at runtime (turning the static `PITFALL-NULL-HANDLE` into a
  runtime guard around field/method access through possibly-null
  handles) seems within scope of the existing analyser.
- `SUKIMASIM_DPI_STUB=1` was not set; refmodel `.so` resolves cleanly
  (`[INFO] DPILibraryLoader: Successfully loaded library: ...
  refmodel_csim_lib.so`), so the SIGSEGV is not a DPI binding issue.
