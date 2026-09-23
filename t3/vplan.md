# Verification Plan — `receptor_padrao`

| | |
|---|---|
| **DUT** | `receptor_padrao` |
| **Spec** | `t3/spec.pdf` — Trabalho 3, Receptor de Padrão (Turma 310) |
| **Author** | *<your name>* |
| **Date** | *<date>* |
| **Status** | Draft |

---

## 1. Design Under Test

Serial-to-parallel pattern receiver. An FSM locks onto a repeating serial frame,
then deserializes the payload into 8-bit words.

### 1.1 Pinout

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Master clock, 100 MHz |
| `rst` | in | 1 | Global reset, asynchronous, active high |
| `data_sr` | in | 1 | Serial data in |
| `data_pl` | out | 8 | Parallel data out (MSB left) |
| `data_pl_en` | out | 1 | Output data valid, 1 cycle pulse |
| `sync` | out | 1 | Synchronization status |

### 1.2 Frame format

```
| ALIGN (0xA5) | payload #1..#5 (40 bits) | ALIGN (0xA5) | payload #1..#5 | ...
```

Bit order: MSB first — bit 7 of each byte is received first.
`0xA5` = `1 0 1 0 0 1 0 1` on the wire, left to right.

### 1.3 Decisions and open questions

Things the spec leaves undefined that change how the DUT is built or verified.
A decision recorded here binds both the RTL and the testbench.

| # | Question | Decision |
|---|---|---|
| D1 | Spec prose says `data_en`, Tabela 1 says `data_pl_en` | Use `data_pl_en` (Tabela 1 is normative) |
| D2 | How does the receiver search for the alignment word? | **Single-candidate hunt**: lock onto the first `0xA5`, verify it repeats at 48-bit spacing, restart the hunt on any mismatch |
| D3 | Are `sync` / `data_pl` / `data_pl_en` registered or combinational? | **Registered.** Outputs update on the clock edge after the condition is met |
| D4 | *...* | *open* |

D3 lets the timing properties in §6 be exact (`|=>`) instead of a `##[0:1]` window.
The spec does not say which, but R15 calls for a synthesizable FSM and R2 for an
asynchronous reset, both of which point at registered outputs. A tolerance window
would silently accept `sync` arriving a cycle early or late, which is exactly the
shape of an off-by-one in the alignment counter.

D2 matters because `0xA5` can occur inside a payload, so the hunt can lock onto a
false phase. Single-candidate is the simpler implementation; the cost is that
recovery from a false lock can take an extra frame, so re-lock timing is bounded
generously rather than predicted exactly (§3.2).

---

## 2. Requirements

Extracted from the spec. Each requirement must be covered by at least one test in §4.

| ID | Requirement | Priority |
|---|---|---|
| R1 | Top level named `receptor_padrao`; pinout follows Tabela 1 names/types/directions | must |
| R2 | Reset is asynchronous and level-sensitive, active high | must |
| R3 | On reset, the receive synchronization logic is reinitialized | must |
| R4 | Frame = alignment word followed by 5-byte payload, repeating | must |
| R5 | Alignment word is `0xA5` | must |
| R6 | Payload is 5 bytes (40 bits) | must |
| R7 | Bits are received MSB first (bit 7 first) | must |
| R8 | After 3 consecutive alignment words in the correct position, `sync` goes high and stays high | must |
| R9 | While not aligned, payload is discarded and `sync` is low | must |
| R10 | Once synced, a missing/misplaced alignment word **or** suspended data drops `sync` and restarts the whole reception process | must |
| R11 | `data_pl` is 8 bits, leftmost bit most significant | must |
| R12 | `data_pl_en` indicates a payload byte has finished parallelizing | must |
| R13 | `data_pl_en` is high for exactly one `clk` cycle | must |
| R14 | `clk` modeled at 100 MHz | must |
| R15 | Circuit is synthesizable, FSM style | must |

---

## 3. Verification Strategy

Two phases, deliberately ordered. Phase 1 proves the DUT is functionally correct with
directed tests that are cheap to debug. Phase 2 adds randomization and perturbation to
stress the parts directed tests reach badly — above all the desynchronization
mechanism.

### 3.1 Phase 1 — Frame-level functional verification

| | |
|---|---|
| **Level** | Block |
| **Methodology** | Directed tests; the frame is the unit of stimulus |
| **Stimulus** | A 48-bit frame `{0xA5, payload[39:0]}` shifted onto `data_sr`, MSB first |
| **Checking** | Inline assertions at the end of each scenario |
| **Reset policy** | Full reset between tests, so scenarios cannot contaminate each other |
| **Targets** | R1–R9, R11–R14 |

Rationale: a failure here names a specific spec bullet. Nothing random, nothing to
reproduce from a seed. This is the phase that establishes the DUT is worth stressing.

**Reset testing.** R2 says asynchronous *and* level-sensitive, and neither half is
provable by a test that asserts `rst` and then waits for a clock edge — a purely
synchronous reset passes that identically. Four distinct checks:

| Aspect | Method | Req |
|---|---|---|
| Asynchronous | Assert `rst` off the edge (e.g. `+CLK_PERIOD/4`), check outputs cleared **before** the next posedge | R2 |
| Narrow pulse | Pulse `rst` for less than one clock period, check it still resets | R2 |
| Level-sensitive | Hold `rst` high through a full valid sync sequence, check `sync` never rises | R2 |
| State cleared | Reset while synced mid-frame, check the DUT re-hunts from scratch and needs three fresh alignment words | R3 |

The last one is the one that catches a DUT that "remembers" it was synced. Drive reset
at several offsets within a frame — mid-byte, on a byte boundary, during the alignment
word — since a partially-filled shift register is different state from an empty one.

Tests: T01–Tnn in §4.

### 3.2 Phase 2 — Randomized stress

What changes from Phase 1 is **randomization and perturbation**, not bit precision.
Bit-level driving is needed only to inject perturbations; clean random traffic is
still driven frame by frame.

Two categories, with **different checkers**. Keeping them apart is what keeps the
testbench simple — see the note at the end of this section.

#### 2a — Clean random traffic

| | |
|---|---|
| **Stimulus** | Random payloads, many consecutive frames, no noise |
| **Checker** | Scoreboard queue: push the 5 payload bytes when a frame is driven, pop and compare on `data_pl_en` |
| **Catches** | Data-path bugs, byte order, bit order, dropped or duplicated bytes, `data_pl_en` cadence |

**Stream phase must be random.** Phase 1 resets and then immediately drives a frame
starting at the driver's bit 0, so the DUT leaves reset at the exact instant a clean
alignment word begins — the first 8 bits it ever sees are `0xA5`. Its hunt logic never
has to search. That is not how a receiver starts in practice: the transmitter is
already running when the receiver comes out of reset.

So every 2a run begins with **N random bits of lead-in, N not a multiple of 8**, before
the first frame. The DUT then has to slide its window and recover the boundary itself.
`sync` consequently rises at an unpredictable cycle, which is correct — do not assert
a fixed cycle count for it.

**Scoreboard start.** Because the lock frame is unpredictable, the queue cannot push
from frame 0. Start pushing at the first frame boundary after `sync` rises. This is
safe under D2: a false candidate cannot collect three consecutive alignment matches, so
`sync` high implies the phase is correct. After that the DUT stays locked and the queue
is exact for the rest of the run.

**Payload generator.** Do not leave payload content to uniform randomness. Byte
boundaries do not exist on the wire — the stream is continuous, and while hunting the
DUT compares its window against `0xA5` on every cycle, at every bit phase. So bias the
generator to produce `0xA5` patterns deliberately, in both forms:

| Form | Example | Why |
|---|---|---|
| Byte-aligned | payload byte = `0xA5` | Obvious case |
| Straddling two bytes | `0x0A 0x50` → `0000_1010 0101_0000`, pattern at bit offset 4 | Only reachable by content, not by driving granularity |

A locked DUT must ignore both: alignment is only checked at the frame-boundary phase.
RTL that re-hunts while locked will desync here, and 2a will catch it because the test
asserts `sync` stays high for the whole run. The same patterns during *hunting* can
cause a temporary false lock — that is the K-generous case in 2b, not a bug.

#### 2b — Perturbation

| | |
|---|---|
| **Stimulus** | Bit-level: corrupt alignment words, hold `data_sr`, slip bits, embed `0xA5` in payloads |
| **Checker** | SVA on `sync` only. **Data is not compared.** |
| **Catches** | R10, the desync and recovery mechanism |

| Perturbation | Expected response | Req |
|---|---|---|
| Flip a bit inside an alignment word | `sync` drops, reception restarts | R10 |
| Flip a bit inside a payload byte | `sync` **holds**; one corrupted byte emitted | R10 (negative) |
| Hold `data_sr` constant for N cycles | `sync` drops | R10 |
| Insert/delete a bit (slip) | `sync` drops, then re-locks once framing repeats | R10 |
| Embed `0xA5` inside a payload | `sync` **holds**; no false re-lock while locked | R8 |

Properties:

- `sync` drops within one frame of a corrupted alignment word
- `sync` recovers within K frames of clean traffic resuming — K **generous**, since a
  payload `0xA5` can cause a temporary false lock under D2 and cost an extra frame
- `sync` never rises without three clean alignment words behind it

Rows 1 and 3 exercise the same detection mechanism (see R10 in §2): a suspended
transmitter leaves `data_sr` constant, and a constant line cannot match `0xA5`, so it
fails the alignment check like any other corruption. Two stimuli, one code path.

The payload-flip row is the one exception to "data is not compared" — it does not
desync, so the DUT stays locked and the 2a scoreboard stays valid. Push the **flipped**
byte as the expected value. This row is not about integrity checking, which the DUT
has none of by design; it guards against RTL that desyncs when it should not, e.g.
comparing the full 48-bit window instead of the alignment byte alone.

#### Why the checkers are split

Once the DUT desyncs, which frames produce output depends on when it re-locks — and
under D2 that is not a fixed number of frames. Predicting it means reimplementing the
hunt FSM in the testbench, which is the reference model this plan already rejected.
So 2b does not try: it checks sync behavior and ignores data. The data path is already
proven by 2a, and does not need proving twice.

### 3.3 Testbench architecture

```
  2a - clean random
                 +--------------+                      +-----+
     payloads -->| frame driver |--- data_sr --------->| DUT |
         |       +--------------+                      +-----+
         |                                          data_pl |
         |        +------------------+          data_pl_en  |
         +------->| scoreboard queue |<---------------------+
       expected   +------------------+

  2b - perturbation
                 +--------------+                      +-----+
     payloads -->|  bit driver  |--- data_sr --------->| DUT |
      + noise    +--------------+                      +-----+
                                                    sync |
                              +----------------+         |
                              | SVA properties |<--------+
                              +----------------+      (data ignored)
```

---

## 4. Test Plan

One row per test. Every requirement in §2 must appear in at least one row.

| Test ID | Req(s) | Name | Description | Stimulus | Checks | Status |
|---|---|---|---|---|---|---|
| T01 | | | | | | todo |
| T02 | | | | | | todo |
| T03 | | | | | | todo |
| T04 | | | | | | todo |
| T05 | | | | | | todo |

<!--
Example row:
| T01 | R2, R3 | reset_values | Assert rst mid-frame, check outputs return to idle | Drive partial frame, raise rst asynchronously off-edge | sync==0, data_pl_en==0, receiver restarts hunting | todo |
-->

### 4.1 Corner cases to consider

*Things worth a row above once you decide they matter.*

- [ ] Reset asserted off clock edge (proves asynchrony, R2)
- [ ] Reset pulse narrower than one clock period (R2)
- [ ] Reset held high across a full valid sync sequence — must not sync (R2, level-sensitive)
- [ ] Reset asserted mid-byte / mid-frame / during the alignment word (R3)
- [ ] After reset, DUT requires three fresh alignment words — no resume (R3)
- [ ] Random bit lead-in, length not a multiple of 8 (DUT joins a running stream)
- [ ] Alignment pattern appearing inside the payload (false lock)
- [ ] Exactly 2 alignment words then a break — must **not** sync
- [ ] Sync drop on the 1st vs 5th payload byte
- [ ] `data_sr` held constant (suspended data, R10)
- [ ] Payload of all `0x00` / all `0xFF`
- [ ] Back-to-back frames with no gap
- [ ] Re-sync after a drop
- [ ] *...*

---

## 5. Coverage

*What must be observed before you call this verified.*

### 5.1 Functional coverage

| Coverpoint | Bins | Rationale |
|---|---|---|
| | | |

### 5.2 Cross coverage

| Cross | Rationale |
|---|---|
| | |

### 5.3 Code coverage goals

| Metric | Target |
|---|---|
| Statement | |
| Branch | |
| FSM state | |
| FSM transition | |
| Toggle | |

---

## 6. Checkers and Assertions

Properties that hold at all times, independent of any single test. These run in both
phases and catch violations the end-of-test assertions would miss.

| ID | Property | Req |
|---|---|---|
| A1 | `data_pl_en` is never high two cycles in a row | R13 |
| A2 | `data_pl_en` implies `sync` | R9, R12 |
| A3 | Reset takes effect without a clock edge (see §6.1) | R2, R3 |
| A4 | Once `sync` is high it stays high until a desync event or reset | R8 |
| A5 | While locked, consecutive `data_pl_en` pulses are 8 or 16 cycles apart | R4, R6 |
| A6 | `sync` rises exactly one cycle after the third alignment word completes | R8, D3 |
| A7 | An `0xA5` inside a payload does not drop `sync` | R8 |

Sketches for the ones that are not obvious:

```systemverilog
// A1 - one-cycle pulse. The simplest useful property in the plan.
property p_en_pulse;
    @(posedge clk) disable iff (rst) data_pl_en |=> !data_pl_en;
endproperty

// A2 - no payload output while unsynced
property p_en_implies_sync;
    @(posedge clk) disable iff (rst) data_pl_en |-> sync;
endproperty

// A5 - byte cadence while locked: 8 cycles inside a payload,
// 16 across the alignment word. Vacuous if sync drops.
property p_en_cadence;
    @(posedge clk) disable iff (rst || !sync)
    data_pl_en |-> ##[8:16] (data_pl_en || !sync);
endproperty
```

### 6.1 Checking the asynchronous reset

A3 cannot be a clocked property. `@(posedge clk)` samples only at clock edges, and an
asynchronous reset acts between them — by the next posedge a *synchronous* reset has
taken effect too, so the two are indistinguishable. Proving R2 needs a checker driven
by `rst` itself, plus a stimulus rule.

**Checker** — triggers on `rst`, independent of the clock:

```systemverilog
always @(posedge rst) begin
    #1ps;   // let the asynchronous path settle past the delta cycle
    assert (sync === 1'b0 && data_pl_en === 1'b0)
    else $error("[FAIL] reset did not take effect without a clock edge");
end
```

The `#1ps` is required: at the instant `rst` rises the DUT outputs have not propagated
yet. It must stay far below one clock period (10 ns) so the check lands before any
posedge could rescue a synchronous implementation.

**Stimulus rule** — every reset in the reset tests is asserted *off* the edge:

```systemverilog
@(posedge clk);
#(CLK_PERIOD/4);    // 2.5 ns into the cycle, nowhere near an edge
rst = 1'b1;         // blocking: take effect now, not on the next edge
```

If `rst` is only ever asserted on a clock edge, the checker above cannot distinguish
the two implementations no matter how it is written. The stimulus rule is what gives
the checker something to see.

This same pair covers the narrow-pulse case in §3.1 — a pulse shorter than one clock
period never coincides with an edge, so a synchronous DUT ignores it entirely while
the checker still fires.

The remaining two aspects in §3.1 need no special mechanism: *level-sensitive* is a
directed test (hold `rst` high, drive a full valid sync sequence, assert `sync` never
rose), and *state cleared* is a directed test (reset while synced, then verify three
fresh alignment words are required).

---

## 7. Completion Criteria

The verification effort is done when:

- [ ] Every requirement in §2 maps to a passing test in §4
- [ ] All tests pass with zero `$error` / zero assertion failures
- [ ] Coverage goals in §5 are met
- [ ] *...*

---

## 8. Results

Fill in as tests are implemented and run.

| Test ID | Result | Date | Notes |
|---|---|---|---|
| | | | |
