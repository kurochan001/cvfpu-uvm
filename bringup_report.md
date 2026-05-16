# CVFPU UVM DV — sukimasim bringup report

## Header

| field           | value                                                          |
|-----------------|----------------------------------------------------------------|
| date            | 2026-05-16                                                     |
| host OS         | Ubuntu 24.04.4 LTS (WSL2, kernel 6.6.87.2-microsoft-standard)  |
| working dir     | `/home/bamba/Work2/cvfpu-uvm`                                  |
| repo            | https://github.com/openhwgroup/cvfpu-uvm.git                   |
| commit (HEAD)   | `080581d0c254fe1d2673e74db3098eb7e38d12ba` (main)              |
| sukimasim       | v0.9.9.2 at `/home/bamba/Work2/sukimasim/build-release/sukimasim` |
| user            | pirochan7@outlook.jp                                            |

## Submodule status

| path                    | commit (pinned)                              |
|-------------------------|----------------------------------------------|
| `modules/cva6`          | `338cb950035af2498cbced52094329315dda27a5` (v5.3.0-132) |
| `modules/core-v-verif`  | `bcbb93e1976256e7c47a094e879d29354303fa9c` (22dc5fc-3083) |
| `modules/cva6/core/cvfpu` | `58ca3c376beb914b2b80b811d4b270c063d4e6f7` (v0.6.6-65)  |
| (others)                | see `git submodule status --recursive`        |

All submodules cloned and pinned to the project-tracked SHAs.
**Note:** the official `setup_env.sh` invokes
`git submodule update --init --recursive --remote`, which silently advances
submodules to upstream HEAD; our `local/env_sukimasim.sh` deliberately
omits the `--remote` so we stay on the pinned SHAs.

## Dependency check (full text in `local/dependency_check.txt`)

| dep        | status | notes                                                                 |
|------------|--------|-----------------------------------------------------------------------|
| python3    | OK     | 3.14.0 (linuxbrew)                                                    |
| pip3       | OK     | upgraded in `.venv` to 26.1.1                                         |
| make       | OK     | GNU Make 4.3                                                          |
| gcc / g++  | OK     | 14.3.0                                                                |
| perl       | OK     | 5.38.2                                                                |
| git        | OK     | 2.43.0                                                                |
| **sukimasim** | OK   | v0.9.9.2, auto-detected at `${HOME}/Work2/sukimasim/build-release/sukimasim` |
| **bender** | MISSING | needed by `compile.py` for filelist generation; install: `cargo install bender` (no sudo) or download static binary from pulp-platform releases |
| **libgmp-dev**  | MISSING (headers) | runtime libgmp present; need `libgmp.h`. Package: `libgmp-dev` (apt, requires sudo — not executed) |
| **libmpfr-dev** | MISSING (headers) | runtime libmpfr present; need `mpfr.h`. Package: `libmpfr-dev` (apt, requires sudo — not executed) |
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
| filelist              | `-f local/cvfpu_uvm_sukimasim.f`                                                    |
| work dir              | `--work-dir output/sukimasim/work`                                                  |
| compile-only          | `--compile-only` (parse + IR, no elab, no sim)                                      |
| lint                  | `--lint` (parse + elaborate, no sim)                                                |
| DPI lib               | `--lib-path <dir> --lib refmodel_csim_lib`                                          |
| seed                  | `--seed 1`                                                                          |
| sim time cap          | `--max-time 1ms`                                                                    |
| wall-clock cap        | `--wall-timeout 60`                                                                 |
| log                   | `--logfile <file>` (sim only; compile-mode output goes to stdout — wrapper tees it) |

## C++ reference model build

- Wrapper: `local/build_refmodel_sukimasim.sh`.
- Status: **BLOCKED** — needs `gmp.h` + `mpfr.h` (dev headers). `svdpi.h` is
  shipped under `${SUKIMASIM_HOME}/include` so once `SUKIMASIM_BIN` is set
  the wrapper picks it up as `GEN_PATH`.
- Classification of failures:
  - `GMP_DIR missing` (no `gmp.h`).
  - `MPFR_DIR missing` (no `mpfr.h`).
- Reproduce:
  ```sh
  cd /home/bamba/Work2/cvfpu-uvm
  source local/env_sukimasim.sh
  bash local/build_refmodel_sukimasim.sh    # exits 2 today
  ```
- After `sudo apt-get install libgmp-dev libmpfr-dev`, set
  `GMP_DIR=/usr MPFR_DIR=/usr`; `local/env_sukimasim.sh` auto-detects
  both prefixes once the headers exist.

## sukimasim detection result

- Auto-detected at `/home/bamba/Work2/sukimasim/build-release/sukimasim`
  (v0.9.9.2, IEEE 1800-2023 SV simulator).
- `SUKIMASIM_HOME` derived as `/home/bamba/Work2/sukimasim` (the build root
  contains `libuvm_dpi.so` and the `include/` headers that the refmodel
  build wrapper consumes as `GEN_PATH`).

## Compile result — **PASS (compile-only)**

- Driver: `local/run_sukimasim_compile.sh`.
- Status: **PASS** in `--compile-only` mode (parse + IR conversion only).
- Numbers (from `output/sukimasim/compile.log`, full breakdown in
  `local/log_summary.md`):
  - 32 files parsed, 10 modules built, 2.58s.
  - 313 `[WARNING]` (288 width-mismatch in UVM macro expansions; rest are
    real testbench-quality nits: non-virtual `create()` overrides, missing
    `automatic` on `wait_n_clocks`, null-handle on `xrtl_reset_vif::hvl_obj`,
    `input` ports without explicit `var`/`wire`).
  - 0 `UVM_ERROR`, 0 `UVM_FATAL`.
  - 17 `DPIExecutor: Symbol not found: dpi_*` (refmodel `.so` not built;
    sukimasim treats unresolved DPI as a warning, not a compile failure).
- **Caveat:** `--compile-only` does *not* elaborate, so unresolved cva6
  packages / module instances (`fpu_wrap`, `ariane_pkg`, `riscv_pkg`,
  `fpnew_pkg`, `CVA6Cfg`, `fu_data_t`, `exception_t`) are silently skipped.
  The first real elaboration check will need either `--lint` or a sim run,
  plus the bender-generated cva6 closure in the filelist.

## Smoke run result

- Driver: `local/run_sukimasim_smoke.sh`.
- Status: **NOT ATTEMPTED YET**. The compile-only PASS above does not
  exercise simulation. To attempt a smoke run, the filelist must be
  extended with the bender output (cva6 + cvfpu + common_cells + axi +
  tech_cells_generic + hpdcache) and the C++ refmodel `.so` must be
  built. Then:
  ```sh
  source local/env_sukimasim.sh
  bash local/run_sukimasim_smoke.sh
  ```
  Defaults: `TESTNAME=fpu_random_test`, `SEED=1`, `VERBOSITY=UVM_LOW`,
  `NB_TXNS=1`, `MAX_TIME=1ms`, `WALL_TIMEOUT=60`.

## Generated files

```
bringup_report.md
local/dependency_check.txt
local/env_sukimasim.sh           # source this, do NOT execute
local/official_flow_summary.md
local/build_refmodel_sukimasim.sh
local/cvfpu_uvm_sukimasim.f      # TEMPLATE; needs bender output appended
local/run_sukimasim_compile.sh   # PASS today in --compile-only mode
local/run_sukimasim_smoke.sh     # ready, blocked on refmodel .so + bender filelist
local/log_summary.md
output/sukimasim/compile.log
output/sukimasim/cmd.txt
output/sukimasim/version.txt
output/sukimasim/work/           # sukimasim work dir (empty today)
```

No `local/patches/`, `local/repros/` created — no need to patch anything,
and the only "failure" so far is environmental (refmodel .so missing /
bender missing), not a sukimasim-vs-DUT bug worth a minimal reproducer.

## Exact commands to reproduce

```sh
# 1. clone + submodules
git clone https://github.com/openhwgroup/cvfpu-uvm.git ~/Work2/cvfpu-uvm
cd ~/Work2/cvfpu-uvm
git submodule update --init --recursive

# 2. python venv
python3 -m venv .venv
. .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt

# 3. env (auto-detects sukimasim if it's at ~/Work2/sukimasim/build-release/sukimasim)
source local/env_sukimasim.sh

# 4. compile-only — passes today
bash local/run_sukimasim_compile.sh

# 5. (after libgmp-dev + libmpfr-dev installed, with sudo)
bash local/build_refmodel_sukimasim.sh   # builds ref_model_csim/cpp/build/refmodel_csim_lib.so

# 6. (after `cargo install bender`)
bender update
bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm \
    > local/cvfpu_uvm_sukimasim.bender.f
# then prepend `-f local/cvfpu_uvm_sukimasim.bender.f` inside local/cvfpu_uvm_sukimasim.f
# ahead of the cvfpu-uvm local sources block, so packages elaborate first.

# 7. real elaboration check, then smoke
${SUKIMASIM_BIN} --enable-uvm --preprocess -top top --errormax 1 \
    --work-dir output/sukimasim/work \
    -f local/cvfpu_uvm_sukimasim.f --lint
bash local/run_sukimasim_smoke.sh
```

## Blockers (ordered, must-fix-first)

1. **`bender` not installed.** Without it, the cva6+cvfpu+common_cells+axi+...
   closure cannot be turned into a filelist, so `--lint` and any sim
   attempt will fail with "package not found".
   → `cargo install bender` (no sudo) or grab a release binary from
   <https://github.com/pulp-platform/bender/releases>.
2. **`libgmp-dev` and `libmpfr-dev` development headers missing.** Required
   for `ref_model_csim/cpp/Makefile`. Without them no DPI reference model
   `.so` is built, so any actual fpu_*_test will see the 17 unresolved
   `dpi_*` imports observed today.
   → `sudo apt-get install libgmp-dev libmpfr-dev` (sudo not used in this run).
3. **Testbench quality nits surfaced by sukimasim** — *not blockers*,
   but worth filing upstream once bringup is green:
   - non-virtual `base_test::create` shadowed in 8 derived test classes
   - `xrtl_reset_vif::hvl_obj` declared but never `new()`-ed
   - `wait_n_clocks` task should be `automatic`

## Next actions

- **(no-sudo path)** `cargo install bender`, regenerate filelist, re-run
  `local/run_sukimasim_compile.sh` (still PASS) and then try `--lint`.
- **(needs sudo)** install `libgmp-dev`, `libmpfr-dev`, then
  `local/build_refmodel_sukimasim.sh` to produce
  `ref_model_csim/cpp/build/refmodel_csim_lib.so`.
- With both done, `bash local/run_sukimasim_smoke.sh` should attempt a
  real `fpu_random_test` run with `+NB_TXNS=1`. Whatever fails first is
  the actual "minimum interesting reproducer" — drop it into
  `local/repros/` and extend this report's Blockers section.

## Status

**PASS_SUKIMASIM_COMPILE**

Reason: `sukimasim --compile-only` PASSes (parse + IR, 0 errors, 313
warnings — none of them fatal). Smoke run remains blocked on (a) the
C++ refmodel `.so` (missing dev headers for GMP/MPFR) and (b) the
bender-generated cva6 closure that the template filelist replaces with
a TODO marker. All scaffolding (env / build / compile / smoke / log
scan) is ready and re-runnable; the next dependency to add will unblock
the next phase without further script changes.
