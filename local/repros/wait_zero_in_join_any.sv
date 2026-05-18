// Repro candidate: `wait(0)` inside a `fork ... join_any` arm fires
// `join_any` immediately, leading to a zero-delay
// fork-join_any-disable-fork-while loop.
//
// Mirrors base_test::main_phase shape:
//   do begin
//     fork
//       MAIN_THREAD:  wait (some_flag);            // never set
//       OTHER_THREAD: if (cond) ... else wait(0);  // `else` branch hit
//     join_any
//     disable fork;
//   end while (!some_flag);
//
// Expected (any conforming SV simulator): all_done flag stays 0, all
// forked arms block forever, top.initial hits the hard 1us bail-out.
// Observed under sukimasim (in CVFPU smoke after #280-part-2 fix):
// the `wait(0)` arm returns the moment the fork starts, `join_any`
// fires, `disable fork` runs, the do-while iteration restarts —
// the simulator emits one `[DISABLE FORK]` line per iteration with
// no sim-time advance, the host CPU spins.
//
// (cvfpu-uvm side; debug ladder is reverted before commit.)

module top;
  bit some_flag = 1'b0;
  bit cond      = 1'b0;        // intentionally false to exercise the `else` arm
  int iterations = 0;

  initial begin
    fork
      // host-side bail-out so the loop cannot run forever even if it
      // is broken
      begin : BAIL_OUT
        #1us;
        $display("[BAILOUT] reached after %0d outer iterations (some_flag=%0b)",
                 iterations, some_flag);
        $finish;
      end

      // the loop under test
      begin : UNDER_TEST
        do begin
          iterations++;
          fork
            begin : MAIN_THREAD
              wait (some_flag);
            end
            begin : OTHER_THREAD
              if (cond) begin
                wait (some_flag);
              end else begin
                wait (0);   // expected: blocks forever
              end
            end
          join_any
          disable fork;
        end while (!some_flag);
      end
    join_any
  end
endmodule
