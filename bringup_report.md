# CVFPU UVM DV — sukimasim bringup report

## Header

| field           | value                                                          |
|-----------------|----------------------------------------------------------------|
| date            | 2026-05-16 (initial) → 2026-05-17 (post-#265, NBA SEGV captured) → 2026-05-18 (post-#281 fix, smoke advances 16 ms but txn=0) |
| host OS         | Ubuntu 24.04.4 LTS (WSL2, kernel 6.6.87.2-microsoft-standard)  |
| working dir     | `/home/bamba/Work2/cvfpu-uvm`                                  |
| repo (origin)   | https://github.com/kurochan001/cvfpu-uvm.git (fork, private)   |
| repo (upstream) | https://github.com/openhwgroup/cvfpu-uvm.git                   |
| branch / HEAD   | `sukimasim-bringup` @ `46ff70e`                                |
| sukimasim       | v0.9.9.2 at `/home/bamba/Work2/sukimasim/build/sukimasim` (HEAD `2c475fe1f`, includes #265 / #281 / #280-part-1 fixes) |
| reported issues | [#279](https://github.com/kurochan001/sukimasim/issues/279) CLOSED (accepted lint cosmetic), [#280](https://github.com/kurochan001/sukimasim/issues/280) OPEN (iteration-cap FIXED, scoped to sequencer↔driver handshake), [#281](https://github.com/kurochan001/sukimasim/issues/281) CLOSED (`2c475fe1f`), [#282](https://github.com/kurochan001/sukimasim/issues/282) OPEN (CVFPU two-layer package generate-if not elaborated at runtime → `fpu_ready_o = X`) |
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

## Lint result — **PASS (`--lint`, PITFALL=off by default)**

- Driver: `make lint` (wrapped, default `PITFALL=off`).
- Result: `[LINT] Analysis complete: 33 warning(s)`, **0 PITFALL, 0 DPI errors**.
  The 33 lines are `[LINT] Warning: Internal signal '...' is never read`
  on UVM `virtual interface` signals — inherent to UVM driver/monitor
  patterns where access is dynamic via `uvm_config_db` and outside
  the static analyser's reach. Informational only.
- `make lint PITFALL=on` re-enables the full audit (514 PITFALL lines).
- Testbench-quality items observed earlier and now resolved:
  - **FIXED in cvfpu-uvm / submodule patches** (commit `4d582ac`):
    - `fpu_if.sv` `wait_n_clocks` → `task automatic` (PITFALL-TASK-STATIC-DEFAULT)
    - `fpu_if.sv` `clk_i, rst_ni` → `input wire bit` (PITFALL-INPUT-KIND-SURPRISE ×2)
    - `core-v-verif/.../xrtl_reset_vif` — `input wire`, `hvl_obj = new()` in
      `initial` (was the PITFALL-NULL-HANDLE source)
    - `core-v-verif/.../pulse_if` — `input wire bit`
    - `core-v-verif/.../md5sum_file_check` — `task automatic`
    - `cva6/core/fpu_wrap.sv` — all 9 input ports `input wire ...` +
      module-local `timeunit/timeprecision`
  - **NOT fixable in tb** (UVM-1.2 macro byproducts):
    - 8× `PITFALL-NON-VIRTUAL-OVERRIDE` on `base_test::create` shadowed
      by `fpu_*_test::create` — generated by `uvm_component_utils*` macros.
    - 477 `PITFALL-WIDTH-MISMATCH` / 21 `PITFALL-SIGNED-MIX` / 2
      `PITFALL-RANDOMIZE-VOID-DROP` — all inside macro expansions.
  - **FIXED upstream in sukimasim**:
    - 6× `PITFALL-OUTPUT-UNDRIVEN` on `fpu_wrap` outputs → tracked as
      [sukimasim#279](https://github.com/kurochan001/sukimasim/issues/279),
      CLOSED as accepted-limitation (lint pass cosmetic, simulator
      elaborates correctly).

## Smoke run result — **walks main_phase, 0 txn (sukimasim #280 perf follow-up)**

- Driver: `make smoke` (or `local/run_sukimasim_smoke.sh`).
- Defaults: `TESTNAME=fpu_random_test`, `SEED=1`, `VERBOSITY=UVM_LOW`,
  `NB_TXNS=1`, `MAX_TIME=1ms`, `WALL_TIMEOUT=60` (raise via
  `make smoke WALL_TIMEOUT=120`).
- History of the smoke walking forward as sukimasim fixes land:

  | sukimasim build       | furthest UVM step reached                       | failure signature                                          |
  |-----------------------|--------------------------------------------------|------------------------------------------------------------|
  | `3259f7c44` (pre-#265)| `reset_phase` → reset_driver `[RESET START] RESET START (0 active)` | `[FATAL] Signal caught: SIGSEGV` from sukimasim's own handler, exit 139 |
  | `49826e013` (post-#265)| `pre_reset_phase` then `reset_phase`, **before** `[RESET START]` | bash-level `Segmentation fault (core dumped)`, exit 139; no `RUNTIME_NULL_OBJECT`, no sukimasim FATAL line (sukimasim#270) |
  | `eff54ebfe` (post-#270) | `main_phase` (sim_time 50501 ps); always re-enters delay | `WhileLoop with timing exceeded maximum iterations time=10000001` + wall-time @ 60 s (sukimasim#280 first symptom, root cause #281) |
  | **`2c475fe1f` (current, post-#281)** | **`main_phase` advances sim_time 50501 ps → ~16 ms; 0 transactions complete** | wall-time @ 120 s during combinational evaluation; **no `WhileLoop` warning**, **no UVM_FATAL/ERROR/WARNING**, exit 2 |

- Status today: the iteration-cap correctness side of #280 is **fixed**
  (the timed-while guard now counts only consecutive same-time iterations,
  so valid clock-generator loops no longer trip it). `clock_driver_c.svh`
  programs `clk_high` correctly after #281, so the clock actually ticks.
- Residual: between `main_phase` start and the 120 s wall-time, sim_time
  advances ~16 ms (≈ 16 M clock cycles) but **no UVM_INFO from
  `fpu_driver` / `fpu_sb` is emitted** — the testbench is alive but
  transaction throughput is effectively zero. The wall-time falls inside
  `[TIMEOUT] ... during combinational evaluation (entry)`, so the
  bottleneck looks like combinational-region re-evaluation cost. Tracked
  as the residual on
  [sukimasim#280](https://github.com/kurochan001/sukimasim/issues/280#issuecomment-4474165817)
  (kept open pending decision to split into a dedicated perf issue).

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
local/run_sukimasim_smoke.sh            # main_phase + 16 ms + wall-time
local/sync_submodule_patches_to_bender.sh  # bender hook (post-update)
local/log_summary.md
Makefile                                # `make help` / `make all` driver
local/sukimasim_issue_draft.md          # body of sukimasim#265 (CLOSED)
local/sukimasim_issue_nba_segv_draft.md # body of sukimasim#270 (OPEN)
local/sukimasim_issue_undriven_in_generate.md  # body of sukimasim#279 (CLOSED accepted)
local/sukimasim_issue_while_loop_timing.md     # body of sukimasim#280 (OPEN, perf residual)
local/sukimasim_issue_assignment_lost.md       # body of sukimasim#281 (CLOSED `2c475fe1f`)
local/repros/                           # 19 SV repros (single-file, sub-second)
  ├── undriven_in_generate.sv          # #279 decisive
  ├── assignment_lost_two_vars.sv      # #281 decisive (Stage 6)
  ├── stage{7..14}_*.sv                # #281 sweep
  ├── assignment_lost_with_alwaysreader.sv
  ├── while_loop_stage{1..4}_*.sv
  ├── int_times_timeunit.sv
  ├── two_layer_pkg_generate_dropped.sv  # #282 stage 1 (PASS — does not repro)
  ├── two_layer_pkg_with_fsm.sv          # #282 stage 2 (PASS — does not repro)
  └── two_layer_pkg_via_interface.sv     # #282 stage 3 (PASS — does not repro)
ref_model_csim/cpp/build/refmodel_csim_lib.so   # gitignored (*.so)
output/sukimasim/compile.log            # gitignored
output/sukimasim/lint.log
output/sukimasim/cmd.txt
output/sukimasim/version.txt
output/sukimasim/work/                  # sukimasim work dir
```

## Exact commands to reproduce (from a clean clone)

```sh
# 1. clone + submodules
git clone https://github.com/kurochan001/cvfpu-uvm.git ~/Work2/cvfpu-uvm
cd ~/Work2/cvfpu-uvm
git checkout sukimasim-bringup        # 46ff70e or newer
git submodule update --init --recursive

# 2. one-time host deps
sudo apt-get install libgmp-dev libmpfr-dev
cargo install bender

# 3. one-shot bring-up (creates .venv, runs bender, builds refmodel,
#    compile-only, lint --no-pitfall-checks, smoke). Auto-detects
#    sukimasim at ~/Work2/sukimasim/build*/sukimasim; override with
#    SUKIMASIM_BIN=/path/to/sukimasim make all.
make all

# 4. opt-in full lint audit
make lint PITFALL=on

# 5. one-off smoke with a longer wall budget (current sukimasim still
#    wall-times during combinational evaluation; tracked as the residual
#    on sukimasim#280)
make smoke WALL_TIMEOUT=120

# 6. (optional) reproduce any individual sukimasim issue
source local/env_sukimasim.sh
"${SUKIMASIM_BIN}" --lint local/repros/undriven_in_generate.sv  # #279
"${SUKIMASIM_BIN}"        local/repros/assignment_lost_two_vars.sv  # #281
```

## Blockers (ordered)

1. **`fpu_ready_o = X` after RESET DONE — DUT does not drive.**
   Tracked as [sukimasim#282](https://github.com/kurochan001/sukimasim/issues/282).
   DBG ladder added to `fpu_monitor::collect_reqs` observed 9000+
   `@(posedge clk_i)` edges with `valid_i=0, ready_o=x` after
   `[RESET DONE]`. `fpu_wrap`'s `if (CVA6Cfg.FpPresent) begin : fpu_gen`
   block contains the `always_comb / always_ff` that initialises
   `state_q <= READY` and drives `fpu_ready_o = 1'b1`, so `ready_o = X`
   means the generate body is either not elaborated or its
   `always_ff` is not firing on reset.
   - `--dump-hierarchy` lists `fpu_wrap` but never `fpnew_top`,
     `i_fpnew_bulk`, or the `fpu_gen` label, even though
     `fpnew_top.sv` is on the bender filelist and
     `--list-unresolved` reports zero unresolved modules.
   - Three single-file repros in `local/repros/two_layer_pkg_*.sv`
     (2-pkg chain alone / + always_ff+always_comb FSM / + clock and
     reset from interface output ports) all elaborate cleanly and
     drive `out_o = 1`. So the trigger is *something* more than the
     CVA6-style two-layer package config; candidates being chased
     upstream are: `parameter type` ports (`fu_data_t`, `exception_t`),
     the 355-file build closure, and UVM-driven phase activity.
2. **`main_phase` objection never dropped → `wait (sb.all_done)` hang
   (downstream consequence of #1, plus a sequencer/driver handshake
   side).** Tracked as the residual on
   [sukimasim#280](https://github.com/kurochan001/sukimasim/issues/280#issuecomment-4474534418),
   now scoped to the `start_item` / `finish_item` ↔ `get_next_item`
   handoff.
   - `[UVM_PHASE_TRACE]`/`[UVM_OBJECTION_TRACE]`: phase=main `raise`
     fires, no `drop`.
   - DBG ladder in `base_test::main_phase`: `base_sequence.start()`
     *returns* (sequence body completes its
     `start_item; finish_item` loop), yet the driver's
     `seq_item_port.get_next_item()` never unblocks. So either
     `start_item` short-circuits without enqueuing into the
     sequencer arbiter, or the queue path `start_item` pushes into
     differs from the one `get_next_item` pops from in this
     sukimasim build.
   - Even with that handshake fixed, blocker #1 keeps `ready_o = x`,
     so `send_req`'s `do @(posedge clk_i); while (!ready_o)` would
     never exit. Both need to land.
3. **`+UVM_VERBOSITY=UVM_HIGH` plusarg ignored.** Both the plusarg
   form and `--uvm-verbosity UVM_HIGH` flag leave `uvm_info(..., UVM_HIGH)`
   messages unprinted, while `UVM_LOW` messages with the same id do
   print. Parked on the #280 follow-up; may warrant its own issue.
4. **`--profile` reports no data.** `--profile` outputs
   `[PROFILE] No profiling data collected.` after >60 s of
   UVM-driven simulation. Also parked on #280.

### Resolved (kept for history)

- **#265 — null class-handle method dispatch → SIGSEGV.** CLOSED by
  `d99e191f6` (`Fix null class handle method calls`).
- **#270 — NBA-region SIGSEGV after #265.** Walked one delta-cycle
  further into `reset_phase` and crashed in an NBA callback; resolved
  in a subsequent sukimasim revision (the smoke now walks past reset
  cleanly).
- **#279 — `PITFALL-OUTPUT-UNDRIVEN` lint false positive on `fpu_wrap`
  outputs inside `if (CVA6Cfg.FpPresent) begin : fpu_gen`.** CLOSED as
  *accepted limitation*: simulator elaborates correctly, only `--lint`
  is fooled. `make lint PITFALL=off` (the default) hides it; the
  50-line repro lives at `local/repros/undriven_in_generate.sv` so
  any future lint-walker fix can use it as a regression test.
- **#281 — class-scope `vif.var = expr;` silently dropped.** CLOSED in
  sukimasim `2c475fe1f`. Root cause: LHS recovery from slang's
  `NamedValue.syntax->toString()` used the raw text **including
  preceding `//` comments**, so any dotted identifier inside a comment
  (e.g. `clock_driver_c.svh:80-81`, or `(0.5)` in `// int trunc of 0.5`)
  was parsed as the LHS prefix and the intended `vif.<member>` write
  routed to the wrong hierarchical target. Fix strips SV comments
  from recovered syntax text before re-parsing. Regression test
  `BugFix.Issue281VifAssignmentCommentLhsRecovery`.
- **#280 — `WhileLoop with timing exceeded maximum iterations`
  during `main_phase` (correctness side).** The 10000-iteration guard
  now counts only *consecutive* iterations at the **same** sim time,
  so a normal clock-generator `while (enable) #delay;` loop no longer
  trips it. Regression test `BugFix.Issue280TimedWhileLoopProgress`.
  Issue **stays open** for the residual wall-time follow-up listed in
  Blockers above.
- **Testbench-quality lint nits** (input port kinds, `task automatic`,
  `xrtl_reset_vif::hvl_obj` null handle, fpu_wrap timescale) — fixed
  in cvfpu-uvm commit `4d582ac` plus matching commits on the
  `sukimasim-bringup-fixes` branch of each submodule. cvfpu-uvm side
  ships through the submodule pointer update; the submodule branches
  are local-only pending upstream PRs.

## Next actions

- Narrow the `main_phase` zero-transaction symptom (Blocker #1):
  rerun with `make smoke VERBOSITY=UVM_HIGH WALL_TIMEOUT=300`,
  then inspect whether the sequencer is producing items
  (`fpu_random_seq`) and whether the driver sees them.
- If the sequencer is producing but combinational evaluation eats
  the wall, file a sukimasim performance issue with sim_time vs
  wall-time and `--profile` output; this can split out of #280.
- After the residual is understood, close #280 (either fixed or
  split-and-closed) and update the status below.
- Sweep `local/repros/` against any future sukimasim builds via
  `for f in local/repros/*.sv; do "${SUKIMASIM_BIN}" --max-time 1us "$f"; done`
  as a small regression smoke for the issues already filed.

## Status

**SMOKE_DUT_NOT_DRIVEN_AND_HANDSHAKE_BYPASS**
(was `SMOKE_HANGS_IN_SB_ALL_DONE_WAIT`)

Reason:
- Compile + lint (PITFALL=off) PASS green, regression-tracked in `make all`.
- sukimasim #265 / #270 / #279 / #281 all closed; the iteration-cap
  side of #280 is closed (test added). `clk_high` programs correctly
  and the clock actually ticks (`fpu_monitor` observes 9000+
  `@(posedge clk_i)` edges).
- Two cleanly-separated remaining issues, both upstream of cvfpu-uvm:
  - **#282** — `fpu_ready_o = X` for the entire run after `[RESET DONE]`.
    `fpu_wrap`'s `if (CVA6Cfg.FpPresent) begin : fpu_gen` is either
    not elaborated or its `always_ff`/`always_comb` does not fire on
    reset. Three single-file repros tried in `local/repros/` all
    elaborate fine, so the trigger is in CVFPU-specific
    elaboration territory (type parameters / 355-file build / UVM
    activity).
  - **#280 (scoped)** — `start_item; finish_item` in the sequence
    body returns without ever waking the driver's
    `seq_item_port.get_next_item()`. Sequence body
    *runs to completion* but no item flows through the agent, so
    `monitor.ap_fpu_req.write()` is called 0 times and the test's
    main-phase objection is never dropped.

Both are necessary for `make smoke` to drive even a single
transaction. They are independent — fixing only one leaves the
smoke still hanging.
