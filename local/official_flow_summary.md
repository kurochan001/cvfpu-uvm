# Official cvfpu-uvm compile/run flow — summary

Captured from:
- `simu/sim_questa.yaml`, `simu/sim_xcelium.yaml`, `simu/sim_vcs.yaml`
- `modules/core-v-verif/lib/cv_dv_utils/python/sim_cmd/compile.py`
- `modules/core-v-verif/lib/cv_dv_utils/python/sim_cmd/run_test.py`
- `setup_env.sh`
- `Bender.yml`

## 1. Environment

`source setup_env.sh <tool>` (or `setup_env.csh`) sets:

| variable        | value                                                              |
|-----------------|---------------------------------------------------------------------|
| `PROJECT_DIR`   | `$(pwd)` at the time of sourcing                                    |
| `PERL5LIB`      | `${PERL5LIB}:${PROJECT_DIR}/scripts/perl5`                          |
| `TARGET_CFG`    | `cv64a60ax`                                                         |
| `CVA6_REPO_DIR` | `${PROJECT_DIR}/modules/cva6`                                       |
| `CORE_V_VERIF`  | `${PROJECT_DIR}/modules/core-v-verif`                               |
| `DV_UTILS_DIR`  | `${CORE_V_VERIF}/lib/cv_dv_utils`                                   |
| `SCRIPTS_DIR`   | `${DV_UTILS_DIR}/python/sim_cmd`                                    |
| `SCRIPTS`       | `${PROJECT_DIR}/scripts` (also prepended to `PATH`)                 |
| `GEN_PATH`/`PATH` | tool-specific (`QUESTA_PATH`, `XLM_PATH`, `VCS_PATH`)             |

The script *also* runs `git submodule update --init --recursive --remote`,
which silently advances submodules — we deliberately do NOT do this in
`local/env_sukimasim.sh`.

## 2. Filelist

`compile.py` ignores the static `filelist:` value in the YAML and
*regenerates* it from Bender every run:

```sh
bender update
bender script flist-plus -t cv64a60ax_cvfpu_uvm -t cvfpu_uvm > ${PROJECT_DIR}/simu/bender_filelist.f
```

So the filelist path declared in the YAML (`${PROJECT_DIR}/simu/bender_filelist.f`)
only exists after a successful Bender invocation. The two `-t` flags select
the cv64a60ax_cvfpu_uvm + cvfpu_uvm targets. `flist-plus` emits a sukimasim-compatible
`.f` file with `+incdir+` / `+define+` lines plus an ordered list of sources.

## 3. Compile options (per tool)

| tool     | compile command (constructed by compile.py)                                                                                       |
|----------|------------------------------------------------------------------------------------------------------------------------------------|
| questa   | `vlog -sv +define+QUESTASIM +incdir+${PROJECT_DIR} -L $QUESTA_PATH/uvm-1.1d -f bender_filelist.f -work work`                       |
| xcelium  | `xrun -compile -64bit -errormax 1 -nowarn UEXPSC -nowarn SPDUSD -nowarn NOINUF -nowarn FUNTSK +incdir+${PROJECT_DIR} -uvm -define XCELIUM -f bender_filelist.f -work work` |
| vcs      | `vcs -Mdir=work -sverilog -timescale=1ns/1ps -full64 -debug_access+r -kdb +define+VCS +incdir+${PROJECT_DIR} -ntb_opts uvm -f bender_filelist.f` |

Common to all:
- `+incdir+${PROJECT_DIR}` so any `\`include "..."` finds the local `fpu_*` headers.
- UVM is pulled in by the tool's built-in switch (`-L $QUESTA_PATH/uvm-1.1d`, `-uvm`, `-ntb_opts uvm`).
- A per-tool `+define+QUESTASIM` / `-define XCELIUM` / `+define+VCS` is set; the
  SV source uses these to gate tool-specific bits.

## 4. Elaboration

| tool     | elab command                                                                                                                                |
|----------|----------------------------------------------------------------------------------------------------------------------------------------------|
| questa   | `vopt -debug -designfile design.bin -access=rw+/. -64 -suppress 2583,13314 -lint=full -L $QUESTA_PATH/uvm-1.1d -work work top -o opt`        |
| xcelium  | `xrun -elaborate -64bit -access +rwc -errormax 1 -timescale 1ns/1ps -nowarn CUVUKP +incdir+${PROJECT_DIR} -uvm -work work -top top`          |
| vcs      | (single-step, no separate elab)                                                                                                              |

## 5. Simulation

`run_test.py` adds: `+UVM_TESTNAME=<test>`, `-sv_seed <seed>` (questa) /
`-seed <seed>` (xcelium) / `+ntb_random_seed=<seed>` (vcs), `+UVM_VERBOSITY=<debug>`,
and a tool-specific dump TCL/do file.

Common simulation switches from the YAMLs:

| key            | value                                                                                          |
|----------------|------------------------------------------------------------------------------------------------|
| top entity     | `top`                                                                                          |
| plusargs       | `+NB_TXNS=10000` (vcs: `+NB_TXNS=10`), `+TIMEOUT=30000000`                                     |
| DPI shared lib | `-sv_lib ${PROJECT_DIR}/ref_model_csim/cpp/build/refmodel_csim_lib`                            |
| UVM            | tool-native (`-uvm`, `-L .../uvm-1.1d`, `-ntb_opts uvm`)                                       |
| timescale      | 1ns/1ps                                                                                        |

Note the questa elab uses `-suppress 2583,13314` and xcelium suppresses
`UEXPSC`, `SPDUSD`, `NOINUF`, `FUNTSK`, `CUVUKP`. These are warnings the
official flow knowingly ignores; sukimasim probably emits different codes.

## 6. C++ reference model

`ref_model_csim/cpp/Makefile`:
- compiles `dpi_wrapper.cpp`, `memory.cpp`, `operations.cpp` into a shared lib
  `build/refmodel_csim_lib.so`.
- requires `GMP_DIR` and `MPFR_DIR` (each must contain `include/` and `lib/`).
- `GEN_PATH` must contain `include/svdpi.h` (taken from the simulator install).
- exits with an error unless `TOOL=questa|xcelium|vcs` so that one of
  `-DUSE_QUESTA / -DUSE_XCELIUM / -DUSE_VCS` is defined.
- final link: `g++ -m64 -shared -fPIC -Bsymbolic ... -lm -lgmp -lmpfr`.

The vendored `ref_model_csim/cpp/include/dpiheader.h` is the Mentor-flavoured
DPI header (marked "MTI_DPI"), but only uses the standard `svdpi.h` types,
so any simulator that ships its own `svdpi.h` should be able to load the
resulting `.so` as long as the `-DUSE_*` define matches its DPI conventions.

## 7. Tests / regression list

`simu/fpu_reg_list` (also reachable via `run_reg.py`):

```
fpu_single_op_test     20
fpu_random_test        20
fpu_op_group_test      20
fpu_fmt_single_op_test 20
fpu_fmt_random_test    20
fpu_fmt_op_group_test  20
```

Tests under `tests/`: `base_test.svh`, `bug_f2i_test.svh`,
`fpu_fmt_op_group_test.svh`, `fpu_fmt_random_test.svh`,
`fpu_fmt_single_op_test.svh`, `fpu_op_group_test.svh`,
`fpu_random_test.svh`, `fpu_single_op_test.svh`, `fpu_unit_test.svh`.
The README's smoke example is `fpu_random_test` with seed=1.

## 8. Bender.yml summary

```yaml
package:  cvfpu-uvm
dependencies:
  cva6        : { rev: 3868a61 }       # openhwgroup/cva6, master
  core-v-verif: { rev: master  }       # openhwgroup/core-v-verif
sources:
  include_dirs: [fpu_common, fpu_agent, ref_model_csim/rtl, env, tests]
  files:
    - fpu_common/fpu_common_pkg.sv
    - fpu_agent/fpu_agent_pkg.sv
    - fpu_agent/fpu_if.sv
    - ref_model_csim/rtl/fpu_refmodel_pkg.sv
    - env/fpu_env_pkg.sv
    - tests/fpu_test_pkg.sv
    - top/rtl/tb_top.sv
```

So the *local* file order is fixed and small. All the heavy lifting
(cva6 RTL + cv_dv_utils + UVM helpers) is pulled in through Bender's
dependency closure on `cva6` and `core-v-verif`.
