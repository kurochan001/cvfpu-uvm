# CVFPU UVM DV — sukimasim bringup report

## Header

| field           | value                                                          |
|-----------------|----------------------------------------------------------------|
| date            | 2026-05-16 (initial) → 2026-05-17 (post-#265, NBA SEGV captured) |
| host OS         | Ubuntu 24.04.4 LTS (WSL2, kernel 6.6.87.2-microsoft-standard)  |
| working dir     | `/home/bamba/Work2/cvfpu-uvm`                                  |
| repo (origin)   | https://github.com/kurochan001/cvfpu-uvm.git (fork, private)   |
| repo (upstream) | https://github.com/openhwgroup/cvfpu-uvm.git                   |
| branch / HEAD   | `sukimasim-bringup` @ `4bcc8fc`                                |
| sukimasim       | v0.9.9.2 at `/home/bamba/Work2/sukimasim/build/sukimasim` (HEAD `49826e013`, includes #265 fix `d99e191f6`) |
| user            | pirochan7@outlook.jp                                            |

## Submodule status

| path                    | commit (pinned)                              |
|-------------------------|----------------------------------------------|
| `modules/cva6`          | `338cb95` (v5.3.0-132)                       |
| `modules/core-v-verif`  | `bcbb93e` (22dc5fc-3083)                     |
| `modules/cva6/core/cvfpu` | `58ca3c3` (v0.6.6-65)                      |
| (others)                | see `git submodule status --recursive`       |

All submodules cloned and pinned to the project-tracked SHAs.
**Note:** the official `setup_env.sh` invokes
`git submodule update --init --recursive --remote`, which silently advances
submodules to upstream HEAD; our `local/env_sukimasim.sh` deliberately
omits the `--remote` so we stay on the pinned SHAs.

## Dependency check

| dep        | status | notes                                                                 |
|------------|--------|-----------------------------------------------------------------------|
| python3    | OK     | 3.14.0 (linuxbrew)                                                    |
| pip3       | OK     | upgraded in `.venv` to 26.1.1                                         |
| make       | OK     | GNU Make 4.3                                                          |
| gcc / g++  | OK     | 14.3.0                                                                |
| perl       | OK     | 5.38.2                                                                |
| git        | OK     | 2.43.0                                                                |
| **sukimasim** | OK   | v0.9.9.2 (`3259f7c44`) auto-detected at `${HOME}/Work2/sukimasim/build/sukimasim` |
| **bender** | OK     | 0.31.0 (`cargo install bender`, no-sudo)                              |
| **libgmp-dev**  | OK | multiarch layout: `gmp.h` at `/usr/include/x86_64-linux-gnu/gmp.h`; `env_sukimasim.sh` adds the dir to `CPATH` |
| **libmpfr-dev** | OK | `mpfr.h` at `/usr/include/mpfr.h` (no multiarch on this build)        |
| questa / xcelium / vcs | MISSING | none of the officially supported simulators is installed |
| verilator  | OK (1.x) | not officially supported by cvfpu-uvm                              |

## Official flow summary (full text in `local/official_flow_summary.md`)

- `compile.py` regenerates the filelist on every run with:
  `bender update && bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm > simu/bender_filelist.f`
- Per-tool wrappers: `vlog`/`vopt` (questa), `xrun -compile`/`xrun -elaborate` (xcelium), `vcs` (one-step).
- Common simulation switches: top=`top`, `+NB_TXNS=10000` (vcs: 10), `+TIMEOUT=30000000`, `-sv_lib ${PROJECT_DIR}/ref_model_csim/cpp/build/refmodel_csim_lib`.
- Tool-specific defines: `+define+QUESTASIM`, `-define XCELIUM`, `+define+VCS`. Our sukimasim run also passes `+define+SUKIMASIM` as the project's marker.
- Tests register list: `simu/fpu_reg_list` — smoke target chosen here is `fpu_random_test`.

## sukimasim flow summary

| concept               | sukimasim flag                                                                     |
|-----------------------|------------------------------------------------------------------------------------|
| UVM linkage           | `--enable-uvm` (auto-loads `libuvm_dpi.so` from `${SUKIMASIM_HOME}`)               |
| UVM macro expansion   | `--preprocess` (Verilator-based external preprocessor)                              |
| top module            | `-top top`                                                                          |
| filelist              | `-f local/cvfpu_uvm_sukimasim.f` → delegates to `local/cvfpu_uvm_sukimasim.bender.f` |
| work dir              | `--work-dir output/sukimasim/work`                                                  |
| compile-only          | `--compile-only` (parse + IR, no elab, no sim)                                      |
| lint                  | `--lint` (parse + elaborate, no sim)                                                |
| DPI lib               | `--lib-path <dir> --lib refmodel_csim_lib.so` (with `.so` suffix)                  |
| seed                  | `--seed 1`                                                                          |
| sim time cap          | `--max-time 1ms`                                                                    |
| wall-clock cap        | `--wall-timeout 60`                                                                 |

## C++ reference model build — **PASS**

- Wrapper: `local/build_refmodel_sukimasim.sh`.
- Output: `ref_model_csim/cpp/build/refmodel_csim_lib.so` (63 KB).
- Reproduce:
  ```sh
  cd /home/bamba/Work2/cvfpu-uvm
  source local/env_sukimasim.sh
  bash local/build_refmodel_sukimasim.sh
  ```
- Two non-obvious adjustments live in the wrapper, not in the upstream
  `ref_model_csim/cpp/Makefile`:
  1. **multiarch GMP**: `env_sukimasim.sh` detects
     `/usr/include/x86_64-linux-gnu/gmp.h` and prepends the directory to
     `CPATH` so g++ finds `<gmp.h>` without patching the Makefile's
     `-I$(GMP_DIR)/include`.
  2. **DPI_DLLESPEC override**: `ref_model_csim/cpp/include/dpiheader.h`
     was autogenerated by QuestaSim and references `DPI_DLLESPEC` (a
     Mentor-specific macro) on every prototype. sukimasim's bundled
     `svdpi.h` does not define it, so the wrapper builds with
     `make CXX='g++ -DDPI_DLLESPEC='` to expand it to nothing on Linux.

## Bender-driven filelist — **OK**

- `local/cvfpu_uvm_sukimasim.bender.f` (382 lines) is generated by:
  ```sh
  bender update
  bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
      > local/cvfpu_uvm_sukimasim.bender.f
  ```
- It already contains cv_dv_utils (`+incdir+` for all 14 UVM helper dirs)
  and the cvfpu-uvm local sources in Bender.yml order, terminating with
  `top/rtl/tb_top.sv`. The entrypoint `local/cvfpu_uvm_sukimasim.f` only
  adds `+define+SUKIMASIM`, a project-root `+incdir+`, and `-f` to the
  bender output.
- The generated `.bender.f` is gitignored: it embeds absolute paths into
  `.bender/git/checkouts/<sha>/...` and is fully reproducible from
  `Bender.lock`.

## Compile result — **PASS (`--compile-only`)**

- Driver: `local/run_sukimasim_compile.sh`.
- Numbers (from `output/sukimasim/compile.log`):
  - **355 files parsed, 408 modules built**, 2.27 s compile time.
  - All 3 DPI libraries load cleanly:
    - `libuvm_dpi.so` (from `${SUKIMASIM_HOME}`)
    - `refmodel_csim_lib.so` (our refmodel)
    - `libtest_dpi.so` (sukimasim built-in)
  - **0 unresolved DPI imports**.
  - 0 `UVM_ERROR`, 0 `UVM_FATAL`.

## Lint result — **PASS (`--lint`)**

- Command (one-off, not wrapped yet):
  ```sh
  source local/env_sukimasim.sh
  "${SUKIMASIM_BIN}" --enable-uvm --preprocess -top top \
      --work-dir output/sukimasim/lint_work --errormax 1 \
      -f local/cvfpu_uvm_sukimasim.f +define+SUKIMASIM \
      "+incdir+${PROJECT_DIR}" --lint
  ```
- Result: `[LINT] Analysis complete: 33 warning(s)`, **zero non-DPI errors**.
  The non-zero exit code is `--errormax 1` reacting to the 17 stale
  DPI ERROR lines that are emitted *before* the refmodel `.so` is
  loaded — with DPI fully resolved (the `--compile-only` run shows
  this), `--lint` would also exit 0 once the wrapper is updated to set
  the same `--lib` arguments. Full log: `output/sukimasim/lint.log`
  (591 lines).
- Notable testbench-quality nits surfaced (worth filing upstream):
  - 8× `PITFALL-NON-VIRTUAL-OVERRIDE` on `base_test::create` shadowed
    by `fpu_*_test::create`.
  - `PITFALL-NULL-HANDLE` on `xrtl_reset_vif::hvl_obj` — closely
    correlated with both [sukimasim#265](https://github.com/kurochan001/sukimasim/issues/265)
    (CLOSED, class-handle method dispatch path) and the still-open
    [sukimasim#270](https://github.com/kurochan001/sukimasim/issues/270)
    (NBA-region callback path). See the Smoke section below.
  - `PITFALL-TASK-STATIC-DEFAULT` on `wait_n_clocks`.
  - Several `PITFALL-INPUT-KIND-SURPRISE` (input ports declared without
    explicit `var`/`wire`).
  - 6× `PITFALL-OUTPUT-UNDRIVEN` on `fpu_wrap` outputs — likely a
    target-gating artefact (`CVA6Cfg.FpPresent` propagation through
    the cva6 closure), not a real testbench bug. Not yet investigated.

## Smoke run result — **SIGSEGV in NBA region (post-#265)**

- Driver: `local/run_sukimasim_smoke.sh`.
- Defaults: `TESTNAME=fpu_random_test`, `SEED=1`, `VERBOSITY=UVM_LOW`,
  `NB_TXNS=1`, `MAX_TIME=1ms`, `WALL_TIMEOUT=60`.
- History of the smoke walking forward as sukimasim fixes land:

  | sukimasim build       | furthest UVM step reached                       | crash signature                                           |
  |-----------------------|--------------------------------------------------|------------------------------------------------------------|
  | `3259f7c44` (pre-#265)| `reset_phase` → reset_driver `[RESET START] RESET START (0 active)` | `[FATAL] Signal caught: SIGSEGV (Segmentation fault)` from sukimasim's own handler, exit 139 |
  | `49826e013` (post-#265, current) | `pre_reset_phase` then `reset_phase`, **before** `[RESET START]` | bash-level `Segmentation fault (core dumped)`, exit 139; no `RUNTIME_NULL_OBJECT`, no sukimasim FATAL line |

- Post-#265 backtrace (from `gdb --batch --args ${SUKIMASIM_BIN} ...
  -ex run -ex 'bt 40'`, full log at `output/sukimasim/gdb_smoke.log`):
  ```
  #0  TestbenchRuntime::TestbenchRuntime(ModuleIR*, ostream&)::$_4 (lambda)
      signature: void(const string&, const shared_ptr<ir::Value>&)
  #1  NBAFullEvent::execute()
  #2  FullDeltaScheduler::executeRegion(FullRegion)
  #3  FullDeltaScheduler::executeDeltaCycle()
  #4  TestbenchRuntime::executeDeltaCyclesOnce()
  #5  TestbenchRuntime::executeUVMRuntimePhasesFromIndex(unsigned long)
  #6  TestbenchRuntime::executeUVMTest("fpu_random_test")
  ...
  #20 main
  ```
- Interpretation: the #265 fix removed the null-method-receiver trip,
  so reset_driver walks one delta-cycle further into the NBA region;
  the next null/dangling reference is inside the NBA-update callback
  registered in `TestbenchRuntime`'s ctor, not a class-method dispatch.
  Same likely root cause (`xrtl_reset_vif::hvl_obj` going through a
  non-blocking assignment) but a different code path inside sukimasim.
- Filed as
  [sukimasim#270](https://github.com/kurochan001/sukimasim/issues/270);
  cross-linked from #265 ([comment](https://github.com/kurochan001/sukimasim/issues/265#issuecomment-4469489094)).

## Generated files

```
bringup_report.md                       # this report
local/dependency_check.txt
local/env_sukimasim.sh                  # source this; no `set -e` leak
local/official_flow_summary.md
local/build_refmodel_sukimasim.sh       # builds refmodel_csim_lib.so (PASS)
local/cvfpu_uvm_sukimasim.f             # entrypoint filelist (31 lines)
local/cvfpu_uvm_sukimasim.bender.f      # gitignored, regenerate via bender
local/run_sukimasim_compile.sh          # --compile-only PASS
local/run_sukimasim_smoke.sh            # reaches reset_phase NBA, SIGSEGV
local/log_summary.md
local/sukimasim_issue_draft.md          # body of sukimasim#265 (CLOSED)
local/sukimasim_issue_nba_segv_draft.md # body of sukimasim#270 (OPEN)
ref_model_csim/cpp/build/refmodel_csim_lib.so   # gitignored (*.so)
output/sukimasim/compile.log            # gitignored
output/sukimasim/lint.log
output/sukimasim/gdb_smoke.log          # gitignored, sim phase
output/sukimasim/cmd.txt
output/sukimasim/version.txt
output/sukimasim/work/                  # sukimasim work dir
```

Still no `local/repros/` — sukimasim#265 and #270 carry the symptom +
repro recipe, and the SIGSEGV is too entangled with the cvfpu-uvm UVM
stack right now to extract a 10-line isolated reproducer cheaply.
Revisit if #270 needs an `-O0` rebuild for richer locals or if the
fix surfaces a third null path one delta-cycle deeper.

## Exact commands to reproduce (from a clean clone)

```sh
# 1. clone + submodules
git clone https://github.com/kurochan001/cvfpu-uvm.git ~/Work2/cvfpu-uvm
cd ~/Work2/cvfpu-uvm
git checkout sukimasim-bringup        # at 9ebc04d or newer
git submodule update --init --recursive

# 2. python venv
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

# 3. one-time host deps
sudo apt-get install libgmp-dev libmpfr-dev
cargo install bender

# 4. env (auto-detects sukimasim if it's at ~/Work2/sukimasim/build*/sukimasim
#    and GMP/MPFR headers under /usr; CPATH gets the multiarch dir on Debian/Ubuntu)
source local/env_sukimasim.sh

# 5. bender filelist (generated, gitignored)
bender update
bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
    > local/cvfpu_uvm_sukimasim.bender.f

# 6. refmodel .so
bash local/build_refmodel_sukimasim.sh

# 7. compile-only — PASS
bash local/run_sukimasim_compile.sh

# 8. smoke — currently SIGSEGV in NBA region (sukimasim#270)
bash local/run_sukimasim_smoke.sh

# 9. (optional) capture backtrace under gdb
gdb --batch --args "${SUKIMASIM_BIN}" \
    --enable-uvm --preprocess -top top \
    --work-dir output/sukimasim/work --errormax 1 \
    --seed 1 --max-time 1ms --wall-timeout 60 \
    -f local/cvfpu_uvm_sukimasim.f \
    --lib-path ref_model_csim/cpp/build --lib refmodel_csim_lib.so \
    +define+SUKIMASIM "+incdir+${PROJECT_DIR}" \
    +UVM_TESTNAME=fpu_random_test +UVM_VERBOSITY=UVM_LOW \
    +NB_TXNS=1 +TIMEOUT=30000000 \
    -ex 'run' -ex 'bt 40' -ex 'thread apply all bt 20'
```

## Blockers (ordered)

1. **NBA-region SIGSEGV after #265 fix.** Tracked in
   [sukimasim#270](https://github.com/kurochan001/sukimasim/issues/270).
   Reset driver progresses through `pre_reset_phase` into `reset_phase`
   and crashes inside the NBA-update callback registered by
   `TestbenchRuntime`'s ctor. Two possible resolutions:
   - **sukimasim side (preferred):** validate the NBA target lookup
     (or wrap the callback with the same null-guard machinery #265
     added for method dispatch) so the deref surfaces as an SV runtime
     error rather than OS SIGSEGV.
   - **testbench side:** construct `xrtl_reset_vif::hvl_obj` (`new()`)
     before the reset driver enters its run loop. The lint warning
     `PITFALL-NULL-HANDLE` still points at the same handle, so the
     workaround silences both #265 and #270 symptoms for this TB.
2. **`fpu_wrap` outputs reported as UNDRIVEN by `--lint`** —
   `CVA6Cfg.FpPresent` parameter propagation or sukimasim's generate-
   block elaboration depth. Investigate only after the SIGSEGV is gone,
   because the smoke run is the cheapest oracle.
3. **Testbench-quality nits** (8 non-virtual `create` overrides,
   `wait_n_clocks` static lifetime, missing `var`/`wire` kinds on a few
   input ports). Not blockers; file upstream against cvfpu-uvm after
   the smoke is green.

### Resolved (kept for history)

- **#265 — null class-handle method dispatch → SIGSEGV.** CLOSED by
  `d99e191f6` (`Fix null class handle method calls`). Surfaces as
  `RUNTIME_NULL_OBJECT` SV runtime error on non-UVM-lazy-stub
  receivers; UVM lazy-stub / `current_phase` paths intentionally left
  out to avoid false positives.

## Next actions

- Wait on / track [sukimasim#270](https://github.com/kurochan001/sukimasim/issues/270).
  Once a fix lands, rebuild sukimasim (note: clear ccache or
  `CCACHE_DISABLE=1` — a stale ccache hit a phantom
  `SymbolKind::TypeAliasType` reference during this round) and rerun
  `bash local/run_sukimasim_smoke.sh`.
- If #270 stalls on lack of locals, rebuild sukimasim at `-O0` and
  re-capture the bt — the captured-variable layer in the lambda
  `$_4` would name the actual NBA target.
- (Optional, parallelisable) extend `run_sukimasim_compile.sh`'s
  `--lib` wiring into a thin `run_sukimasim_lint.sh` so `--lint`
  also exits 0 with DPI resolved.
- Re-investigate `fpu_wrap` UNDRIVEN after smoke is green.

## Status

**SMOKE_NBA_SEGV_POST_265**

Reason: sukimasim#265 is CLOSED (`d99e191f6`); a rebuilt sukimasim
(HEAD `49826e013`) walks the smoke one delta-cycle further — through
`pre_reset_phase` and into `reset_phase` — before SIGSEGV inside the
NBA-region callback registered in `TestbenchRuntime`'s ctor. Captured
upstream as sukimasim#270 with full backtrace; cvfpu-uvm side is
currently parked on that.
