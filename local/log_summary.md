# Log summary

Logs analysed: `output/sukimasim/compile.log` (329 lines, sukimasim v0.9.9.2).

## Headline

`--compile-only` (parse + IR conversion) **PASS**.

```
=== Compilation Summary ===
Files parsed  : 32
Top module    : top
Modules       : 10
Compile time  : 2.58s
Status        : PASS
```

Wrapper exit = 0. No `UVM_ERROR`, no `UVM_FATAL`. UVM auto-loaded via
`/home/bamba/Work2/sukimasim/build-release/libuvm_dpi.so`.

## Warning categories (313 total)

| count | category                        | meaning                                                                                          |
|------:|---------------------------------|--------------------------------------------------------------------------------------------------|
| 288   | `PITFALL-WIDTH-MISMATCH`         | LHS narrower than RHS in procedural assigns (silent truncation). Dominated by `uvm_*` macro expansions and a few `fpu_*` tests with `2'(...)` style casts missing. |
| 8     | `PITFALL-NON-VIRTUAL-OVERRIDE`   | `tests/*_test.svh` subclasses define `create()` that shadows the non-virtual `base_test.create()` (IEEE 1800-2023 §8.20). Real UVM bug-shaped pattern. |
| 7     | `PITFALL-SIGNED-MIX`             | Signed/unsigned mixed arithmetic.                                                                |
| 5     | `PITFALL-INPUT-KIND-SURPRISE`    | `xrtl_reset_vif`, `fpu_if`, `pulse_if` input ports without explicit `var`/`wire`. Affects net-collapse vs. variable semantics. |
| 2     | `PITFALL-TASK-STATIC-DEFAULT`    | `wait_n_clocks` declared without `automatic` — race hazard if forked. |
| 1     | `PITFALL-NULL-HANDLE`            | `xrtl_reset_vif::hvl_obj` never `new()`-ed; member access would null-deref. |

48 additional `DPIParser: Unknown type, defaulting to LogicVector` warnings
during DPI signature parsing — sukimasim could not map `mpfr_rnd_e` /
`env_t` to a built-in primitive and silently fell back to logic-vector.

## Errors

`DPIExecutor: Symbol not found: dpi_*` — **17** entries, one per imported
DPI function in `ref_model_csim/rtl/fpu_refmodel_pkg.sv`:

```
dpi_fcvt_f2f  dpi_fcvt_i2f  dpi_fcvt_f2i  dpi_fmv_f2x  dpi_fsgnj
dpi_fnms      dpi_fsqrt     dpi_fadd      dpi_fsub     dpi_fmul
dpi_fma       dpi_fnma      dpi_fclass    dpi_fms      dpi_fmin_max
dpi_fdiv      dpi_fcmp
```

These are **not** counted as parse/elab errors — sukimasim emits a final
`[WARNING] Some DPI bindings not resolved. Set SUKIMASIM_DPI_STUB=1 for
stub mode.` and still reports `Status: PASS`. Root cause: the C++ refmodel
`.so` is not built (blocked by missing `libgmp-dev`/`libmpfr-dev`).

## Classification

| bucket                                       | hits | example |
|----------------------------------------------|------|---------|
| 1. SystemVerilog parse / elaboration         | 0    | (parse OK; elab not attempted in `--compile-only`) |
| 2. UVM library                               | 0    | libuvm_dpi.so loaded cleanly |
| 3. constraint / randomize                    | 0    | n/a in compile-only |
| 4. DPI                                       | 17   | `dpi_f*` unresolved; refmodel .so missing |
| 5. package / import / compile order          | 0    | (cva6 packages not exercised in compile-only) |
| 6. interface / modport                       | 0    | (modports parsed clean; only input-kind warnings) |
| 7. fork / process / phase                    | 0    | n/a in compile-only |
| 8. DUT / reference-model mismatch            | 0    | refmodel not invoked |
| 9. environment / dependency                  | 2    | libgmp-dev / libmpfr-dev missing → refmodel not built; bender not installed → cva6 closure not in filelist |

## What `--compile-only` does **not** prove

- Does not elaborate `top`. Unresolved cells / packages from cva6 RTL
  (`fpu_wrap`, `ariane_pkg`, `riscv_pkg`, `fpnew_pkg`, `CVA6Cfg`,
  `fu_data_t`, `exception_t`) are silently skipped — sukimasim parses
  the tb_top instantiation but does not insist that the referenced
  types/modules exist.
- Does not run any simulation, so plusargs (`+NB_TXNS`, `+UVM_TESTNAME`)
  and DPI calls never fire.

## Next step

Run `--lint` (parse + elaborate, no simulation) once the cva6 closure is
merged into the filelist (`bender script flist-plus > ...`):

```sh
source local/env_sukimasim.sh
${SUKIMASIM_BIN} --enable-uvm --preprocess -top top \
    --work-dir output/sukimasim/work --errormax 1 \
    -f local/cvfpu_uvm_sukimasim.f --lint
```

That will surface the real cva6 import errors.

## Scan via `scripts/scan_logs.pl`

Not run — `scripts/patterns/sim_patterns.pat` is geared toward sim runs
(`UVM_INFO test PASSED` markers). On a compile-only log it would just
flag the DPI errors. Worth invoking after the first successful sim run.
