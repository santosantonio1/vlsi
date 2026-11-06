# t4 — ps2_driver RTL

## Context
The testbench ([tb.sv](tb.sv)) is done. Run against the stub, it fails with 77 missing outputs. Now the stub [ps2_driver.sv](ps2_driver.sv) gets replaced by the real circuit. The TB was written from the spec before any RTL existed, and **it stays frozen**. If a test fails, I fix the RTL. I'd change the TB only if the spec proves the TB itself is wrong, and I'd tell you before doing it.

The RTL is in SystemVerilog, to match t3, and it's a single file. Synthesis and SDC are still out of scope, but the code stays synthesizable: no `#delays`, no `initial`, and everything runs on clock_in.

## Datapath (all on `posedge clock_in or posedge reset_in`; reset is async and active-high)

```
clock_ps2 ─┐
data_ps2  ─┴─> 2-FF sync ─> glitch filter ─> falling-edge detect ─> FSM (shift + parity) ─> F0 filter ─> scancode→ASCII ─> data_p / data_p_en
```

1. **Synchronizer.** clock_ps2 and data_ps2 come from outside, with no relation to clock_in, so each goes through 2 flip-flops. Reset value is 1, which is the PS/2 idle level.
2. **Glitch filter on clock_ps2.** The filtered clock only changes after `FILTER` = 8 equal samples in a row, which is 80 ns. That's well under the 500 ns half-period at 1 MHz. Real keyboard clocks have slow, ringing edges, and one glitch would add a fake bit. `FILTER` is a parameter, so it's the knob to adjust on real hardware. Data doesn't need a filter, because it's only read at the clock edge, while it's stable.
3. **Edge detect.** `fall = clk_f_q & ~clk_f`. It's a 1-cycle pulse, and the FSM only advances on it.
4. **FSM** (an `enum`, which is what the spec's "FSM" asks for):

   | State | On `fall` |
   |---|---|
   | IDLE | if data = 0 (start bit) → DATA, set cnt = 0 |
   | DATA | shift data in, LSB first (`sr = {data, sr[7:1]}`); after 8 bits → PARITY |
   | PARITY | `par_ok = ^{sr, data}` (odd parity means the 9 bits XOR to 1) → STOP |
   | STOP | if data = 1 and par_ok → emit; always → IDLE |

5. **Break-code filter.** A `brk` flag. On an emitted byte: if it's `F0`, set `brk`. Otherwise, if `brk` is set, clear it and drop the byte, because it's a key release. Otherwise, decode it.
6. **Decoder.** A combinational `case` from scancode to `{valid, ascii}`. An unmapped code gives valid = 0, which means no output.
   - Letters A–Z → uppercase. The spec example says 0x1C gives 'A'.
   - Digits 0–9 and SPACE (0x20).
   - Control keys with an obvious ASCII code: Enter 5A → 0x0D, Backspace 66 → 0x08, Tab 0D → 0x09, Esc 76 → 0x1B.
   - Unshifted symbols from Figura 3: `` ` - = [ ] \ ; ' , . / ``.
   - No ASCII, so no output: F1–F12, Shift, Ctrl, Alt, Caps.
7. **Output registers.** `data_p` holds the last character. `data_p_en` is 1 only in the cycle right after a valid decode, then goes back to 0, which is spec item 8.

## Simplifications on purpose (marked in the code with `ponytail:` comments)
- **No Shift/Caps handling.** Letters are always uppercase and symbols always unshifted. Adding it needs a shift flag and a second table.
- **No `E0` handling.** `E0` is unmapped, so it produces nothing. The byte after it decodes like a normal code; for example, keypad Enter `E0 5A` gives 0x0D.
- **No frame timeout.** If a frame is cut off mid-way, the next start bit will be mis-framed until reset. A watchdog counter would cover it if needed: about 200 µs, a 15-bit counter.

## Files
- [ps2_driver.sv](ps2_driver.sv): replaces the stub, with the same port list, about 100 lines.
- Nothing else changes. [sim.do](sim.do) already compiles this file.

## Verification
`vsim -c -do "do sim.do; quit -f"`, with `LM_LICENSE_FILE` and `SALT_LICENSE_SERVER` set as in `~/.bashrc`. Expected result: `PASS`. It needs:
- all 77 characters
- no extra `data_p_en` for the break code and the bad-parity frame
- the 2 ns async reset pulse, which also proves the reset is asynchronous
