# `--lint` reports OUTPUT-UNDRIVEN for ports driven inside a `generate if`
# whose condition reads a parameter-struct field (false positive)

## Summary

`sukimasim --lint` emits `PITFALL-OUTPUT-UNDRIVEN` against ports that
**are** driven, when the driver lives inside a `generate if` whose
condition reads a field of a parameter of struct type, and that field
was computed by an `automatic function` called from a `localparam`
initialiser.

**Importantly the simulator itself elaborates the body correctly** —
running the same source without `--lint` shows the generate block is
active and the port carries the expected value. So this is a **lint
pass false positive**: the driver-trace inside the lint pass does not
descend into the generate scope, even though elaboration does.

The shape is widely used across OpenHW Group RTL (every CVA6
`build_config_pkg::build_config(...)` call hits it), so a fresh user
running `make lint` on the CVFPU UVM bringup sees six loud UNDRIVEN
warnings on the only DUT they care about (`fpu_wrap`).

## Minimal repro (50 lines, single file)

`undriven_in_generate.sv`:

```systemverilog
package cfg_pkg;
  typedef struct packed {
    bit FpPresent;
    bit RVF;
    bit RVD;
  } cfg_t;

  function automatic cfg_t build_config(cfg_t in_cfg);
    cfg_t out_cfg;
    out_cfg.RVF       = in_cfg.RVF;
    out_cfg.RVD       = in_cfg.RVD;
    out_cfg.FpPresent = in_cfg.RVF | in_cfg.RVD;
    return out_cfg;
  endfunction

  localparam cfg_t USER_CFG = '{FpPresent: 1'b0, RVF: 1'b1, RVD: 1'b1};
  localparam cfg_t CVA6Cfg  = build_config(USER_CFG);
endpackage

module dut #(
    parameter cfg_pkg::cfg_t CFG = '{default: 1'b0}
) (
    output logic out_o
);
  if (CFG.FpPresent) begin : g
    assign out_o = 1'b1;
  end
endmodule

module top;
  import cfg_pkg::*;
  logic w;
  dut #(.CFG(CVA6Cfg)) d (.out_o(w));

  initial begin
    #1ns;
    $display("[REPRO] CVA6Cfg.FpPresent=%0b  out_o=%0b (expect 1 / 1)",
             CVA6Cfg.FpPresent, w);
    $finish;
  end
endmodule
```

### Run 1: simulation (correct — elaboration works)

```
$ sukimasim --max-time 1us undriven_in_generate.sv
...
[REPRO] CVA6Cfg.FpPresent=1  out_o=1 (expect 1 / 1)
$finish called at simulation time 1000
TEST PASSED
```

### Run 2: lint (false positive)

```
$ sukimasim --lint undriven_in_generate.sv
...
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'out_o' of module 'dut'
          has no driver (Verilator UNDRIVEN). ... Add a driver or remove
          the output declaration.
[LINT] Analysis complete: 1 warning(s)
```

`out_o` is plainly driven by `assign out_o = 1'b1;` inside
`if (CFG.FpPresent) begin : g`, and the same simulator agrees so when
it actually elaborates and runs.

## Impact on real designs

Surfaced on the OpenHW CVFPU UVM testbench (`fpu_wrap`), where all
six DUT outputs are driven inside `if (CVA6Cfg.FpPresent) begin : fpu_gen`:

```
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'fpu_ready_o'        of module 'fpu_wrap'
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'fpu_trans_id_o'     of module 'fpu_wrap'
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'result_o'           of module 'fpu_wrap'
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'fpu_valid_o'        of module 'fpu_wrap'
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'fpu_exception_o'    of module 'fpu_wrap'
[WARNING] PITFALL-OUTPUT-UNDRIVEN: output port 'fpu_early_valid_o'  of module 'fpu_wrap'
```

That is six false positives per real-world DUT instance, on the first
`make lint` a user sees, on a checkbox-friendly diagnostic — high
noise / low signal at the worst possible moment.

## sukimasim

- self-reported version: `v0.9.9.2`
- binary used: `~/Work2/sukimasim/build/sukimasim`
- HEAD known to include the #265 null-handle fix (commit `d99e191f6`).

## Suggested fix area

The lint pass that emits `PITFALL-OUTPUT-UNDRIVEN` needs to walk into
generate scopes (named `g : ...` blocks created from `if`/`for`/`case`
inside a module body) when looking for drivers of the enclosing
module's output ports. The fact that the simulator's elaborator does
descend correctly proves the structural information is present — only
the lint walker is missing the recursion.

## Reproduction (full UVM bringup, for context)

```sh
git clone https://github.com/kurochan001/cvfpu-uvm.git
cd cvfpu-uvm
git checkout sukimasim-bringup     # at 4bcc8fc
git submodule update --init --recursive
sudo apt-get install libgmp-dev libmpfr-dev

make lint
grep PITFALL-OUTPUT-UNDRIVEN output/sukimasim/lint.log
```

`local/repros/undriven_in_generate.sv` in this repository is the
50-line standalone shown above.
