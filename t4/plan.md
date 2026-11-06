# t4 — ps2_driver testbench (synthesis/SDC skipped)

## Context
T4 asks for a PS/2 keyboard reader (`ps2_driver`) that outputs ASCII. As on t3, you're the verification engineer and a colleague writes the RTL. So I'll deliver the TB, the interface, and the sim script. The DUT file will only be a port stub so things compile. Synthesis scripts, `.sdc` and reports are out of scope for now.

## What the spec pins down → TB checks
| # | Spec | Check |
|---|------|-------|
| 2-3 | entity `ps2_driver`, ports per Tabela 1 | the TB instantiates exactly those names |
| 4 | clock_in 100 MHz | 10 ns clock (already in tb.sv) |
| 6 | reset **async** (Tabela 1 says "síncrono"; item 6 wins) | pulse reset_in between clock_in edges in the middle of a frame. The partial frame must be dropped and the next full frame must decode correctly |
| 7 | clock_ps2 ≤ 1 MHz | run the stimulus at 1 MHz (the worst case) and at a slow rate, 100 kHz |
| 8 | data_p_en high for exactly 1 cycle | assertion: data_p_en is never high on two consecutive clock_in edges |
| 9 | odd parity | a frame with bad parity must produce **no** data_p_en |
| 10 | frame: start(0), 8 bits LSB first, P, stop(1), sampled on the falling edge of clock_ps2 | the TB task drives data while clock_ps2 is high and pulls clock low half a period later |
| 1, 11 | scancode → ASCII | send every scancode in the table and compare data_p against the expected ASCII |

## Assumptions (the spec doesn't say; correct me if you disagree)
- **Mapped set:** A–Z → uppercase `'A'..'Z'`, because the spec says key 'A' (0x1C) gives the character 'A'. 0–9 → `'0'..'9'` and SPACE → 0x20. Everything else (F-keys, shift, symbols, ESC/Enter) is left untested, because the expected ASCII for those is a design choice.
- **Break codes:** `F0 xx` (key release) must produce no output, either for the F0 or for the xx after it. The test is make 1C, then break F0 1C: exactly one 'A' comes out.
- E0-extended keys and Shift/Caps handling are not tested.

## Core sketch (scoreboard = expected-ASCII queue, no reference FSM)
```systemverilog
task automatic send(input logic [7:0] code, input logic bad_par = 0);
    logic [10:0] frame;

    frame = {1'b1, ~^code ^ bad_par, code, 1'b0};   // stop, P(odd), data, start
    foreach (frame[i]) begin
        vif.data_ps2 = frame[i];
        #(half);
        clock_ps2 = 0;
        #(half);
        clock_ps2 = 1;
    end
endtask

always @(posedge clock_in) begin
    if (vif.data_p_en) begin
        assert (exp_q.size() > 0 && vif.data_p == exp_q.pop_front())
            else $error("got %h", vif.data_p);
    end
end

assert property (@(posedge clock_in) vif.data_p_en |=> !vif.data_p_en)
    else $error("data_p_en longer than 1 cycle");
```
The stimulus pushes the expected ASCII into `exp_q` before each `send` of a mapped make code. At the end the TB checks `exp_q.size() == 0` and prints a pass/fail line.

A `byte ascii[byte]` associative array holds the 37 mapped entries. The main test does `foreach (ascii[c])` at both clock rates.

## Files
- [ps2_driver_if.sv](ps2_driver_if.sv): fix the name (`ps2_driver_if`, not `ps2_driver_if.sv`) and remove the empty `#()`, which is illegal. Everything else stays.
- [tb.sv](tb.sv): add clock_ps2 (idle high), the DUT instance, the `send` task, the scoreboard and the tests: reset, 37 codes at 1 MHz and 100 kHz, break code, bad parity, mid-frame async reset. Target is ~80 lines in the t3 `tb.sv` style.
- `ps2_driver.sv`: a port-only stub in SystemVerilog, to be replaced by your colleague's RTL.
- `sim.do`: copy of t3's, with t4 file names and `run -all`.

## Verification
`vsim -c -do sim.do` must compile, elaborate and run to `$finish` against the stub. Against the stub, the "missing outputs" check will fail as expected. That's the only meaning of "verified" until the real RTL arrives.
