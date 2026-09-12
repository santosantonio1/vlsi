// ============================================================================
//  tb_receptor_padrao.sv
//  Directed testbench for "Trabalho 3 - Receptor de Padrao"
//  Projeto de Sistemas Integrados - 98G07-04
//
//  Frame: | ALIGN (0xA5) | 5 payload bytes | ALIGN | 5 payload bytes | ...
//  Serial order: MSB first (bit 7 is the first bit on the wire).
//  sync rises only after 3 consecutive ALIGN words at the correct spacing.
// ============================================================================
`timescale 1ns/1ps

module tb_receptor_padrao;

  // ------------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------------
  localparam time        CLK_PERIOD    = 10ns;   // 100 MHz
  localparam logic [7:0] ALIGN         = 8'hA5;
  localparam int         PAYLOAD_BYTES = 5;
  localparam int         SYNC_FRAMES   = 3;

  // Assumption: sync rises at the end of the 3rd ALIGN word, so the payload
  // that immediately follows it IS considered valid and emitted.
  // If your design only emits from the 4th frame onward, set this to 0.
  localparam bit LOCK_FRAME_PAYLOAD_IS_VALID = 1'b1;

  // ------------------------------------------------------------------
  // DUT signals
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
  // Bookkeeping
  // ------------------------------------------------------------------
  int         errors    = 0;
  int         checks    = 0;
  string      test_name = "init";
  logic [7:0] captured [$];   // bytes seen on data_pl when data_pl_en pulsed
  logic [7:0] expected [$];   // bytes the stimulus says should be emitted

  task automatic chk(input bit cond, input string msg);
    checks++;
    if (!cond) begin
      errors++;
      $error("[%0t] [%s] %s", $time, test_name, msg);
    end
  endtask

  // ------------------------------------------------------------------
  // Monitor: capture every data_pl_en pulse and police its legality
  // ------------------------------------------------------------------
  logic dpe_q;

  always @(posedge clk) begin
    if (rst) begin
      dpe_q <= 1'b0;
    end else begin
      if (data_pl_en) begin
        captured.push_back(data_pl);
        chk(sync === 1'b1,
            $sformatf("data_pl_en asserted while sync is low (data=0x%02h)", data_pl));
        chk(dpe_q !== 1'b1, "data_pl_en stayed high for more than one clock cycle");
      end
      dpe_q <= data_pl_en;
    end
  end

  // ------------------------------------------------------------------
  // Stimulus helpers
  // ------------------------------------------------------------------
  // One bit per clock. Driven on the falling edge so the DUT samples a
  // stable value on the rising edge.
  task automatic send_bit(input logic b);
    @(negedge clk);
    data_sr = b;
  endtask

  task automatic send_byte(input logic [7:0] d);
    for (int i = 7; i >= 0; i--) send_bit(d[i]);   // MSB first
  endtask

  task automatic idle_cycles(input int n);
    repeat (n) @(negedge clk);
  endtask

  // Sends ALIGN + 5 payload bytes. If expect_valid, the payload bytes are
  // added to the expected-output queue.
  task automatic send_frame(input logic [7:0] align_word,
                            input logic [7:0] pay [PAYLOAD_BYTES],
                            input bit         expect_valid);
    send_byte(align_word);
    foreach (pay[i]) begin
      send_byte(pay[i]);
      if (expect_valid) expected.push_back(pay[i]);
    end
  endtask

  // Builds a payload where every byte is base + index, for easy waveform ID.
  function automatic void make_payload(input logic [7:0] base,
                                       output logic [7:0] pay [PAYLOAD_BYTES]);
    for (int i = 0; i < PAYLOAD_BYTES; i++) pay[i] = base + i[7:0];
  endfunction

  // ------------------------------------------------------------------
  // Scoreboard
  // ------------------------------------------------------------------
  task automatic compare_payloads();
    idle_cycles(4);   // let the final data_pl_en land in the monitor

    chk(captured.size() == expected.size(),
        $sformatf("payload count mismatch: expected %0d bytes, captured %0d",
                  expected.size(), captured.size()));

    for (int i = 0; i < expected.size(); i++) begin
      if (i < captured.size())
        chk(captured[i] === expected[i],
            $sformatf("payload byte %0d mismatch: expected 0x%02h, got 0x%02h",
                      i, expected[i], captured[i]));
    end

    captured.delete();
    expected.delete();
  endtask

  task automatic do_reset();
    rst     = 1'b1;
    data_sr = 1'b0;
    repeat (3) @(negedge clk);
    rst = 1'b0;
    captured.delete();
    expected.delete();
    @(negedge clk);
  endtask

  // ------------------------------------------------------------------
  // Tests
  // ------------------------------------------------------------------
  logic [7:0] pay_a [PAYLOAD_BYTES];
  logic [7:0] pay_b [PAYLOAD_BYTES];
  logic [7:0] pay_c [PAYLOAD_BYTES];
  logic [7:0] pay_d [PAYLOAD_BYTES];

  // T1: reset drives the outputs to a known, unsynced state.
  task automatic t1_reset();
    test_name = "T1_reset";
    rst     = 1'b1;
    data_sr = 1'b0;
    repeat (3) @(negedge clk);
    chk(sync       === 1'b0, "sync must be low during reset");
    chk(data_pl_en === 1'b0, "data_pl_en must be low during reset");
    rst = 1'b0;
    @(negedge clk);
    chk(sync === 1'b0, "sync must still be low right after reset release");
  endtask

  // T2: three consecutive ALIGN words acquire sync; earlier payloads discarded.
  task automatic t2_acquire_sync();
    test_name = "T2_acquire_sync";
    do_reset();

    make_payload(8'h10, pay_a);
    make_payload(8'h20, pay_b);
    make_payload(8'h30, pay_c);
    make_payload(8'h40, pay_d);

    send_frame(ALIGN, pay_a, 1'b0);
    chk(sync === 1'b0, "sync must stay low after only 1 alignment word");

    send_frame(ALIGN, pay_b, 1'b0);
    chk(sync === 1'b0, "sync must stay low after only 2 alignment words");

    // 3rd ALIGN completes the lock. Check right after the alignment word,
    // before its payload, with one cycle of slack for the output register.
    send_byte(ALIGN);
    idle_cycles(1);
    chk(sync === 1'b1, "sync must be high after 3 consecutive alignment words");

    for (int i = 0; i < PAYLOAD_BYTES; i++) begin
      send_byte(pay_c[i]);
      if (LOCK_FRAME_PAYLOAD_IS_VALID) expected.push_back(pay_c[i]);
    end

    send_frame(ALIGN, pay_d, 1'b1);
    chk(sync === 1'b1, "sync must remain high while frames keep arriving");

    compare_payloads();
  endtask

  // T3: a corrupted alignment word after lock must drop sync and restart.
  task automatic t3_lose_sync();
    test_name = "T3_lose_sync";

    make_payload(8'h50, pay_a);
    send_frame(8'h5A, pay_a, 1'b0);   // wrong alignment word

    chk(sync === 1'b0, "sync must drop when the alignment word is wrong");
    chk(captured.size() == 0,
        $sformatf("payload after a bad alignment word must be discarded, got %0d bytes",
                  captured.size()));

    // One good frame is not enough to relock: the count restarts from zero.
    make_payload(8'h60, pay_b);
    send_frame(ALIGN, pay_b, 1'b0);
    chk(sync === 1'b0, "a single alignment word must not restore sync");

    captured.delete();
    expected.delete();
  endtask

  // T4: after a loss, three fresh frames re-acquire sync.
  task automatic t4_reacquire();
    test_name = "T4_reacquire";
    do_reset();

    make_payload(8'h70, pay_a);
    make_payload(8'h80, pay_b);
    make_payload(8'h90, pay_c);

    send_frame(ALIGN, pay_a, 1'b0);
    send_frame(ALIGN, pay_b, 1'b0);

    send_byte(ALIGN);
    idle_cycles(1);
    chk(sync === 1'b1, "sync must be re-acquired after 3 new alignment words");

    for (int i = 0; i < PAYLOAD_BYTES; i++) begin
      send_byte(pay_c[i]);
      if (LOCK_FRAME_PAYLOAD_IS_VALID) expected.push_back(pay_c[i]);
    end

    compare_payloads();
  endtask

  // T5: asynchronous reset asserted mid-frame clears sync immediately.
  task automatic t5_async_reset();
    test_name = "T5_async_reset";
    do_reset();

    make_payload(8'hA0, pay_a);
    make_payload(8'hB0, pay_b);
    make_payload(8'hC0, pay_c);
    send_frame(ALIGN, pay_a, 1'b0);
    send_frame(ALIGN, pay_b, 1'b0);
    send_byte(ALIGN);
    idle_cycles(1);
    chk(sync === 1'b1, "precondition: DUT should be locked before the async reset");

    // Assert reset off the clock edge; sync must react without waiting for clk.
    send_bit(pay_c[0][7]);
    #(CLK_PERIOD/4);
    rst = 1'b1;
    #1ns;
    chk(sync === 1'b0, "async reset must clear sync without a rising clock edge");

    repeat (2) @(negedge clk);
    rst = 1'b0;
    captured.delete();
    expected.delete();

    // Reception logic restarted: one frame must not be enough to relock.
    make_payload(8'hD0, pay_c);
    send_frame(ALIGN, pay_c, 1'b0);
    chk(sync === 1'b0, "sync must stay low until 3 alignment words after reset");
    chk(captured.size() == 0, "no payload should be emitted before sync");

    captured.delete();
    expected.delete();
  endtask

  // ------------------------------------------------------------------
  // Main
  // ------------------------------------------------------------------
  initial begin
    `ifdef WAVES
      $dumpfile("tb_receptor_padrao.vcd");
      $dumpvars(0, tb_receptor_padrao);
    `endif

    rst     = 1'b1;
    data_sr = 1'b0;

    t1_reset();
    t2_acquire_sync();
    t3_lose_sync();
    t4_reacquire();
    t5_async_reset();

    $display("--------------------------------------------------");
    if (errors == 0)
      $display("PASS - %0d checks, 0 errors", checks);
    else
      $display("FAIL - %0d checks, %0d errors", checks, errors);
    $display("--------------------------------------------------");
    $finish;
  end

  // Watchdog
  initial begin
    #200us;
    $display("FAIL - simulation timeout during test '%s'", test_name);
    $fatal(1);
  end

endmodule