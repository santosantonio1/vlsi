// ============================================================================
//  tb.sv - testbench for "Trabalho 3 - Receptor de Padrao"
//
//  Checks `sync`, and that every payload byte received while synced comes out
//  on data_pl with a one-cycle data_pl_en pulse (and nothing else does).
//
//  Frame: | ALIGN (0xA5) | 5 payload bytes | ALIGN | 5 payload bytes | ...
//  Serial order: MSB first. sync rises after 3 consecutive ALIGN words at the
//  correct spacing and drops when an ALIGN is missing/wrong.
// ============================================================================
`timescale 1ns/1ps

module tb;

  localparam time        CLK_PERIOD    = 10ns;   // 100 MHz
  localparam logic [7:0] ALIGN         = 8'hA5;
  localparam int         PAYLOAD_BYTES = 5;
  // Cycles of slack allowed between the last bit of an ALIGN word and the
  // sync edge (covers registered outputs).
  localparam int         SYNC_LATENCY  = 2;

  // ------------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------------
  logic       clk = 1'b0;
  logic       rst;
  logic       data_sr;
  logic [7:0] data_pl;
  logic       data_pl_en;
  logic       sync;

  receptor_padrao dut (
    .clk        (clk       ),
    .rst        (rst       ),
    .data_sr    (data_sr   ),
    .data_pl    (data_pl   ),
    .data_pl_en (data_pl_en),
    .sync       (sync      )
  );

  always #(CLK_PERIOD/2) clk = ~clk;

  // ------------------------------------------------------------------
  // Checking
  // ------------------------------------------------------------------
  int    errors    = 0;
  int    checks    = 0;
  string test_name = "init";

  task automatic chk(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $error("[%0t] [%s] %s", $time, test_name, msg);
    end
  endtask

  // Continuous sync checker. Set `sync_exp` to 0/1 to require that value on
  // every clock; set it to 'x while sync is allowed to change.
  logic sync_exp = 1'bx;

  always @(negedge clk) begin
    if (sync_exp !== 1'bx && sync !== sync_exp) begin
      errors++;
      $error("[%0t] [%s] sync = %b, expected %b", $time, test_name, sync, sync_exp);
    end
  end

  // Continuous data checker. A payload byte that ends while sync is high is
  // stored in `exp_byte`; the DUT must pulse data_pl_en with that byte on
  // data_pl before the next payload byte ends. Any other pulse is an error.
  logic [7:0] exp_byte;
  bit         exp_pending = 0;
  logic       en_prev     = 1'b0;

  always @(negedge clk) begin
    if (data_pl_en === 1'b1) begin
      chk(exp_pending, "data_pl_en high without a payload byte to output");
      chk(!en_prev, "data_pl_en high for more than one cycle");
      if (exp_pending)
        chk(data_pl === exp_byte,
            $sformatf("data_pl = %h, expected %h", data_pl, exp_byte));
      exp_pending = 0;
    end
    en_prev = data_pl_en;
  end

  // Polls sync for up to n cycles; fails if it never reaches `val`.
  task automatic wait_sync(input logic val, input int n, input string msg);
    bit ok = 0;
    for (int i = 0; i <= n; i++) begin
      if (sync === val) begin ok = 1; break; end
      @(negedge clk);
    end
    chk(ok, msg);
  endtask

  // ------------------------------------------------------------------
  // Stimulus
  // ------------------------------------------------------------------
  // Driven on the falling edge so the DUT samples a stable value.
  task automatic send_bit(input logic b);
    @(negedge clk);
    data_sr = b;
  endtask

  task automatic send_byte(input logic [7:0] d);
    for (int i = 7; i >= 0; i--) send_bit(d[i]);   // MSB first
  endtask

  // One payload byte. If the DUT is synced when it ends, it must come out on
  // data_pl (checked by the data checker).
  task automatic send_data(input logic [7:0] d);
    send_byte(d);
    chk(!exp_pending, "previous payload byte never came out on data_pl");
    if (sync === 1'b1) begin
      exp_byte    = d;
      exp_pending = 1;
    end
  endtask

  // n payload bytes of `fill` (0x00 by default: cannot form a false 0xA5
  // in any bit window next to an ALIGN word).
  task automatic send_payload(input int n = PAYLOAD_BYTES,
                              input logic [7:0] fill = 8'h00);
    repeat (n) send_data(fill);
  endtask

  // ALIGN + the 5 payload bytes in `pl`, first byte in pl[39:32].
  task automatic send_data_frame(input logic [39:0] pl);
    send_byte(ALIGN);
    for (int i = PAYLOAD_BYTES-1; i >= 0; i--) send_data(pl[8*i +: 8]);
  endtask

  task automatic send_frame(input logic [7:0] align_word = ALIGN);
    send_byte(align_word);
    send_payload();
  endtask

  // Sends the 3rd ALIGN, then checks sync rises within SYNC_LATENCY cycles
  // while the payload keeps flowing.
  task automatic send_lock_frame();
    sync_exp = 1'bx;
    send_byte(ALIGN);
    fork
      send_payload();
      begin
        wait_sync(1'b1, SYNC_LATENCY, "sync must rise after the 3rd ALIGN word");
        sync_exp = 1'b1;
      end
    join
  endtask

  // Reset, then send 3 good frames and require lock.
  task automatic acquire();
    do_reset();
    sync_exp = 1'b0;
    send_frame();
    send_frame();
    send_lock_frame();
  endtask

  // Waits for the last payload byte of a test to come out.
  task automatic drain_data();
    repeat (2) @(negedge clk);
    chk(!exp_pending, "last payload byte never came out on data_pl");
    exp_pending = 0;
  endtask

  task automatic do_reset();
    sync_exp = 1'bx;
    drain_data();
    rst      = 1'b1;
    data_sr  = 1'b0;
    repeat (3) @(negedge clk);
    chk(sync === 1'b0, "sync must be low during reset");
    rst = 1'b0;
    @(negedge clk);
  endtask

  // ------------------------------------------------------------------
  // Tests
  // ------------------------------------------------------------------

  // T1: 1 and 2 ALIGN words are not enough; the 3rd locks.
  task automatic t1_acquire();
    test_name = "T1_acquire";
    acquire();
  endtask

  // T2: once locked, sync stays high over many frames, even with 0xA5
  //     bytes inside the payload.
  task automatic t2_hold();
    test_name = "T2_hold";
    acquire();
    repeat (4) send_frame();
    send_byte(ALIGN);
    send_payload(PAYLOAD_BYTES, ALIGN);
    send_frame();
  endtask

  // T3: after lock, a wrong ALIGN word drops sync; 1 and 2 good frames are
  //     not enough to relock, the 3rd is.
  task automatic t3_lose_and_relock();
    test_name = "T3_lose_and_relock";
    acquire();
    send_frame();

    sync_exp = 1'bx;
    send_byte(8'h5A);                       // wrong alignment word
    wait_sync(1'b0, SYNC_LATENCY, "sync must drop on a wrong ALIGN word");
    sync_exp = 1'b0;
    send_payload();

    send_frame();
    send_frame();
    send_lock_frame();
  endtask

  // T4: ALIGN words at the wrong spacing (4-byte payload) never lock.
  task automatic t4_bad_spacing();
    test_name = "T4_bad_spacing";
    do_reset();
    sync_exp = 1'b0;
    send_frame();
    send_byte(ALIGN); send_payload(PAYLOAD_BYTES - 1);
    send_byte(ALIGN); send_payload(PAYLOAD_BYTES - 1);
    send_byte(ALIGN); send_payload();
  endtask

  // T5: a single bad ALIGN before the 3rd resets the count.
  task automatic t5_broken_sequence();
    test_name = "T5_broken_sequence";
    do_reset();
    sync_exp = 1'b0;
    send_frame();
    send_frame();
    send_frame(8'hA4);                      // 3rd one is corrupted
    send_payload(2);                        // gap so the next ALIGN is fresh
    send_frame();
    send_frame();
    send_lock_frame();
  endtask

  // T6: lock after junk bits that are not byte-aligned to the frame.
  task automatic t6_unaligned_start();
    test_name = "T6_unaligned_start";
    do_reset();
    sync_exp = 1'b0;
    send_bit(1'b1); send_bit(1'b1); send_bit(1'b0);
    send_frame();
    send_frame();
    send_lock_frame();
  endtask

  // T7: transmitter goes quiet (line stuck at 0) -> sync drops.
  task automatic t7_line_idle();
    test_name = "T7_line_idle";
    acquire();
    sync_exp = 1'bx;
    send_payload(1);                        // where the next ALIGN should be
    wait_sync(1'b0, SYNC_LATENCY, "sync must drop when the line goes idle");
    sync_exp = 1'b0;
    send_payload(10);
  endtask

  // T8: async reset while locked clears sync without a clock edge.
  task automatic t8_async_reset();
    test_name = "T8_async_reset";
    acquire();
    send_byte(ALIGN);
    sync_exp = 1'bx;
    #(CLK_PERIOD/4);
    rst = 1'b1;
    #1ns;
    chk(sync === 1'b0, "async reset must clear sync immediately");
    repeat (2) @(negedge clk);
    rst = 1'b0;
    sync_exp = 1'b0;
    send_frame();                           // count must restart from zero
    send_frame();
  endtask

  // T9: payload bytes come out in order, MSB first, one pulse per byte.
  task automatic t9_data();
    test_name = "T9_data";
    acquire();
    send_data_frame(40'h01_23_45_67_89);
    send_data_frame(40'h80_7E_C3_3C_FF);
    send_data_frame(40'hA5_5A_00_FF_A5);
  endtask

  // ------------------------------------------------------------------
  // Main
  // ------------------------------------------------------------------
  initial begin
    rst     = 1'b1;
    data_sr = 1'b0;

    t1_acquire();
    t2_hold();
    t3_lose_and_relock();
    t4_bad_spacing();
    t5_broken_sequence();
    t6_unaligned_start();
    t7_line_idle();
    t8_async_reset();
    t9_data();

    sync_exp = 1'bx;
    drain_data();
    $display("--------------------------------------------------");
    if (errors == 0) $display("PASS - %0d checks, 0 errors", checks);
    else             $display("FAIL - %0d checks, %0d errors", checks, errors);
    $display("--------------------------------------------------");
    $stop;
  end

  // Watchdog
  initial begin
    #200us;
    $fatal(1, "simulation timeout during test '%s'", test_name);
  end

endmodule
