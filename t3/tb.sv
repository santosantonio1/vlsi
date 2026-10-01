`timescale 1ns/1ps

module tb ();

    logic clk;
    receptor_padrao_if vif (
        .clk(clk)
    );

    receptor_padrao dut (
        .clk        (vif.clk        ),
        .rst        (vif.rst        ),
        .data_sr    (vif.data_sr    ),
        .data_pl    (vif.data_pl    ),
        .data_pl_en (vif.data_pl_en ),
        .sync       (vif.sync       )
    );

    localparam CLK_PERIOD = 10ns;   // 100 MHz
    localparam K_RELOCK   = 6;      // frames allowed to re-lock after a desync (§3.2, generous)

    initial begin
        clk = 0;

        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    logic [7:0]  align     = 8'hA5;
    logic [39:0] payload_1 = 40'h0DEADBEEF0;

    typedef enum {ALIGN_FLIP, PAYLOAD_FLIP, HOLD0, HOLD1, SLIP_INS, SLIP_DEL} perturb_t;

    // ------------------------------------------------------------------
    // stimulus-side state: the TB knows what it drove
    // ------------------------------------------------------------------

    int         aligns_seen;            // consecutive clean alignment words driven
    int         bit_pos;                // bits driven since the last alignment word started
    logic       align_corrupted = 0;    // the last alignment word driven was corrupted
    logic       directed        = 1;    // phase 1: sync timing is checked exactly
    logic [7:0] expected [$];           // payload bytes the DUT must emit
    int         last_offset     = -1;   // where gen_payload() embedded 0xA5 last frame

    // ------------------------------------------------------------------
    // coverage (§5)
    //
    // covergroups need a verification license the Starter edition lacks:
    // compile with +define+COVERAGE where one is available (lab machine)
    // ------------------------------------------------------------------

`ifdef COVERAGE
    `define SAMPLE(cg, args) cg.sample args;
    covergroup cg_leadin with function sample(int n);
        leadin_mod8: coverpoint n % 8 {
            bins phase[] = {[1:7]};
        }
    endgroup

    covergroup cg_perturb with function sample(perturb_t cause, int pos);
        desync_cause: coverpoint cause;

        flip_bit: coverpoint pos iff (cause == ALIGN_FLIP) {
            bins b[] = {[0:7]};
        }

        hold_start: coverpoint pos iff (cause inside {HOLD0, HOLD1}) {
            bins payload_byte[] = {[1:5]};
        }
    endgroup

    covergroup cg_a5 with function sample(int offset);
        a5_form: coverpoint offset % 8 {
            bins aligned     = {0};
            bins straddle[]  = {[1:7]};
        }

        a5_byte: coverpoint offset / 8 {
            bins payload_byte[] = {[0:4]};
        }

        form_x_byte: cross a5_form, a5_byte {
            // a pattern straddling out of the first payload byte overlaps the align word
            ignore_bins into_align = binsof(a5_form) intersect {[1:7]} &&
                                     binsof(a5_byte) intersect {4};
        }
    endgroup

    covergroup cg_rst with function sample(int pos, logic synced);
        rst_phase: coverpoint pos {
            bins in_align      = {[1:7]};
            bins byte_boundary = {0, 8, 16, 24, 32, 40};
            bins mid_byte      = {[9:15], [17:23], [25:31], [33:39], [41:47]};
        }

        rst_state: coverpoint synced {
            bins hunting = {0};
            bins synced  = {1};
        }

        phase_x_state: cross rst_phase, rst_state;
    endgroup

    cg_leadin  cov_leadin  = new();
    cg_perturb cov_perturb = new();
    cg_a5      cov_a5      = new();
    cg_rst     cov_rst     = new();
`else
    `define SAMPLE(cg, args)
`endif

    // ------------------------------------------------------------------
    // stimulus
    // ------------------------------------------------------------------

    task send_bit(logic b);
        vif.data_sr <= b;
        bit_pos++;
        @(posedge vif.clk);
    endtask

    task send_byte(logic [7:0] b);
        foreach (b[i]) begin
            send_bit(b[i]);
        end
    endtask

    // payload byte: the DUT must emit it if synced
    task send_data(logic [7:0] b);
        send_byte(b);
        expected.push_back(b);
    endtask

    // alignment word, possibly corrupted on purpose
    task send_align(logic [7:0] word);
        bit_pos         = 0;
        align_corrupted = (word !== align);

        if (align_corrupted) begin
            aligns_seen = 0;    // before sending: the DUT may notice at the first wrong bit
        end

        send_byte(word);

        if (!align_corrupted && vif.rst !== 1'b1) begin
            aligns_seen++;
        end
    endtask

    // {align word, payload}
    task drive(logic [47:0] data);
        send_align(data[47:40]);

        for (int i = 4; i >= 0; i--) begin
            send_data(data[8*i+:8]);
        end
    endtask

    // transmitter goes quiet from payload byte first_byte (1..5) through the next frame
    task suspend(logic level, int first_byte);
        send_align(align);

        for (int i = 1; i < first_byte; i++) begin
            send_data(payload_1[8*(5-i)+:8]);
        end

        for (int i = first_byte; i <= 5; i++) begin
            send_data({8{level}});      // still locked: these bytes come out
        end

        send_align({8{level}});         // the held line fails the alignment check

        repeat (5) begin
            send_byte({8{level}});      // unsynced: discarded
        end
    endtask

    // off the edge, so only an asynchronous reset passes the A3 checker (§6.1)
    task reset(realtime width = 3*CLK_PERIOD);
        @(posedge vif.clk);
        #(CLK_PERIOD/4);

        `SAMPLE(cov_rst, (bit_pos, vif.sync))
        vif.rst     = 1'b1;
        aligns_seen = 0;

        #(width);
        vif.rst = 1'b0;
    endtask

    // biased payload: often embeds 0xA5 at a random bit offset, never at the
    // previous frame's offset, so a false phase can't collect three matches
    function automatic logic [39:0] gen_payload();
        logic [39:0] p      = {$urandom, $urandom};
        int          offset = -1;

        if ($urandom_range(1)) begin
            do begin
                offset = $urandom_range(32);
            end while (offset == last_offset);

            p[offset+:8] = align;
            `SAMPLE(cov_a5, (offset))
        end

        last_offset = offset;
        return p;
    endfunction

    // ------------------------------------------------------------------
    // scoreboard: nothing is expected while the DUT is not synced
    // ------------------------------------------------------------------

    always @(posedge vif.clk or posedge vif.rst) begin
        if (vif.rst || !vif.sync) begin
            expected.delete();
        end
        else if (vif.data_pl_en) begin
            assert (vif.data_pl === expected.pop_front())
            else $error("[FAIL] data_pl differs from the driven payload");
        end
    end

    // ------------------------------------------------------------------
    // assertions (§6)
    // ------------------------------------------------------------------

    // A1 - data_pl_en is a one-cycle pulse
    property p_en_pulse;
        @(posedge vif.clk) disable iff (vif.rst)
        vif.data_pl_en |=> !vif.data_pl_en;
    endproperty

    assert property (p_en_pulse)
    else $error("[FAIL] A1: data_pl_en high for more than one cycle");

    // A2 - no payload output while unsynced
    property p_en_implies_sync;
        @(posedge vif.clk) disable iff (vif.rst)
        vif.data_pl_en |-> vif.sync;
    endproperty

    assert property (p_en_implies_sync)
    else $error("[FAIL] A2: data_pl_en while not synced");

    // A3 - reset takes effect without a clock edge (§6.1)
    always @(posedge vif.rst) begin
        #1ps;

        assert (vif.sync === 1'b0 && vif.data_pl_en === 1'b0)
        else $error("[FAIL] A3: reset did not take effect without a clock edge");
    end

    // A3 - reset is level-sensitive: outputs stay cleared while rst is high
    property p_rst_level;
        @(posedge vif.clk)
        vif.rst |-> !vif.sync && !vif.data_pl_en;
    endproperty

    assert property (p_rst_level)
    else $error("[FAIL] A3: outputs active while rst is high");

    // A4, A7 - sync only falls after the TB broke the stream (bad align, hold, slip)
    property p_sync_holds;
        @(posedge vif.clk) disable iff (vif.rst)
        $fell(vif.sync) |-> aligns_seen == 0;
    endproperty

    assert property (p_sync_holds)
    else $error("[FAIL] A4: sync dropped on a clean stream");

    // A5 - byte cadence while locked: 8 cycles inside a payload, 16 across the align word
    property p_en_cadence;
        @(posedge vif.clk) disable iff (vif.rst || !vif.sync)
        vif.data_pl_en |=> (!vif.data_pl_en [*7]  ##1 vif.data_pl_en)
                        or (!vif.data_pl_en [*15] ##1 vif.data_pl_en);
    endproperty

    assert property (p_en_cadence)
    else $error("[FAIL] A5: data_pl_en cadence is not 8/16 cycles");

    // A6 - sync never rises without three clean alignment words behind it
    property p_sync_needs_three;
        @(posedge vif.clk) disable iff (vif.rst)
        $rose(vif.sync) |-> aligns_seen >= 3;
    endproperty

    assert property (p_sync_needs_three)
    else $error("[FAIL] A6: sync rose without three consecutive alignment words");

    // A6 - directed tests: sync rises exactly one cycle after the 3rd alignment word
    property p_sync_exact;
        @(posedge vif.clk) disable iff (vif.rst || !directed)
        $rose(aligns_seen == 3) |=> $rose(vif.sync);
    endproperty

    assert property (p_sync_exact)
    else $error("[FAIL] A6: sync did not rise 1 cycle after the 3rd alignment word");

    // R10 - a corrupted alignment word drops sync by 1 cycle after it ends
    property p_drop_on_bad_align;
        @(posedge vif.clk) disable iff (vif.rst)
        $rose(align_corrupted) |-> ##[0:9] !vif.sync;
    endproperty

    assert property (p_drop_on_bad_align)
    else $error("[FAIL] R10: sync held through a corrupted alignment word");

    // ------------------------------------------------------------------
    // tests (§4)
    // ------------------------------------------------------------------

    task sync_up();
        repeat (3) drive({align, payload_1});

        assert (vif.sync === 1'b1)
        else $error("[FAIL] sync low after 3 alignment words");
    endtask

    // let the last byte come out, then check none is missing
    task finish_test();
        repeat (3) @(posedge vif.clk);

        assert (expected.size() == 0)
        else $error("[FAIL] %0d payload byte(s) never came out", expected.size());
    endtask

    // T02, T03 - reset acts without a clock edge, even as a sub-period pulse
    task test_rst_async();
        reset();
        sync_up();
        reset();

        sync_up();
        reset(CLK_PERIOD/2);

        assert (vif.sync === 1'b0)
        else $error("[FAIL] T03: narrow reset pulse did not clear sync");
    endtask

    // T04 - reset held high ignores a full sync sequence
    task test_rst_level();
        fork
            reset(5 * 48 * CLK_PERIOD);
            repeat (4) drive({align, payload_1});
        join

        assert (vif.sync === 1'b0)
        else $error("[FAIL] T04: sync high after a held reset");
    endtask

    // T05 - reset from anywhere in the frame clears the sync state: no resume
    task automatic test_rst_state();
        int offsets [3] = '{3, 11, 14};     // rst rises at bit 5 (align), 13 (mid-byte), 16 (boundary)

        foreach (offsets[i]) begin
            for (int synced = 0; synced <= 1; synced++) begin
                reset();

                if (synced) begin
                    sync_up();
                end
                else begin
                    drive({align, payload_1});
                end

                fork
                    drive({align, payload_1});
                    begin
                        repeat (offsets[i]) @(posedge vif.clk);
                        reset();
                    end
                join

                repeat (2) drive({align, payload_1});

                assert (vif.sync === 1'b0)
                else $error("[FAIL] T05: sync resumed after reset with 2 fresh alignment words");

                drive({align, payload_1});  // 3rd: p_sync_exact checks the rise
                finish_test();
            end
        end
    endtask

    // T06, T07 - three alignment words lock; two are not enough
    task test_sync();
        reset();
        sync_up();
        finish_test();

        reset();
        repeat (2) drive({align, payload_1});
        drive({align ^ 8'h01, payload_1});
        drive({align, payload_1});

        assert (vif.sync === 1'b0)
        else $error("[FAIL] T07: sync rose with only 2 consecutive alignment words");
        finish_test();
    endtask

    // T08, T09 - payload bytes come out in order, MSB first, constant payloads included
    task test_data();
        reset();
        sync_up();

        drive({align, 40'h01_23_45_67_89});
        drive({align, 40'h00_00_00_00_00});
        drive({align, 40'hFF_FF_FF_FF_FF});
        finish_test();
    endtask

    // T10 - a corrupted alignment word drops sync, then it re-locks
    task test_desync_align();
        reset();
        sync_up();

        for (int b = 0; b < 8; b++) begin
            drive({align ^ (8'h01 << b), payload_1});
            `SAMPLE(cov_perturb, (ALIGN_FLIP, b))
            sync_up();
        end

        finish_test();
    endtask

    // T11 - a suspended transmitter drops sync, from the 1st and the 5th payload byte
    task test_desync_hold();
        reset();
        sync_up();

        for (int level = 0; level <= 1; level++) begin
            for (int first = 1; first <= 5; first += 4) begin
                suspend(level, first);
                `SAMPLE(cov_perturb, (level ? HOLD1 : HOLD0, first))
                sync_up();
            end
        end

        finish_test();
    endtask

    // T20 - clean random traffic from a random stream phase (§3.2 2a)
    task automatic test_rand_clean(int frames);
        int leadin = 8 * $urandom_range(5) + $urandom_range(7, 1);

        reset();
        `SAMPLE(cov_leadin, (leadin))

        repeat (leadin) begin
            send_bit($urandom);
        end

        repeat (frames) begin
            drive({align, gen_payload()});
        end

        assert (vif.sync === 1'b1)
        else $error("[FAIL] T20: not synced on clean random traffic");
        finish_test();
    endtask

    // T21 - random perturbations, each followed by a bounded re-lock (§3.2 2b)
    task automatic test_rand_perturb(int rounds);
        reset();

        repeat (rounds) begin
            perturb_t    cause = perturb_t'($urandom_range(SLIP_DEL));
            int          pos   = $urandom_range(7);
            logic [39:0] p;

            repeat (K_RELOCK) begin
                drive({align, gen_payload()});
            end

            p = gen_payload();

            assert (vif.sync === 1'b1)
            else $error("[FAIL] T21: no re-lock within %0d frames", K_RELOCK);

            case (cause)
                ALIGN_FLIP: begin
                    drive({align ^ (8'h01 << pos), p});
                end

                PAYLOAD_FLIP: begin
                    drive({align, p ^ (40'h1 << $urandom_range(39))});
                end

                HOLD0, HOLD1: begin
                    pos = pos % 5 + 1;
                    suspend(cause == HOLD1, pos);
                end

                SLIP_INS: begin
                    aligns_seen = 0;
                    send_bit($urandom);
                    drive({align, p});
                end

                SLIP_DEL: begin
                    aligns_seen = 0;

                    for (int i = 6; i >= 0; i--) begin
                        send_bit(align[i]);
                    end

                    for (int i = 4; i >= 0; i--) begin
                        send_data(p[8*i+:8]);
                    end
                end
            endcase

            `SAMPLE(cov_perturb, (cause, pos))

            // only a payload flip keeps the lock
            assert (vif.sync === (cause == PAYLOAD_FLIP))
            else $error("[FAIL] T21: wrong sync response to %s", cause.name());
        end

        finish_test();
    endtask

    initial begin
        vif.rst     = 1'b0;
        vif.data_sr = 1'b0;

        // phase 1 - directed
        test_rst_async();
        test_rst_level();
        test_rst_state();
        test_sync();
        test_data();
        test_desync_align();
        test_desync_hold();

        // phase 2 - randomized
        directed = 0;
        test_rand_clean(200);
        test_rand_perturb(100);

        $finish;
    end

endmodule
