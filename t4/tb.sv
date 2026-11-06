`timescale 1ns/1ps

module tb;
    localparam CLK_PERIOD = 10ns;       // 100 MHz
    localparam CLK_PERIOD_MAX = 1us;    // 1 MHz
    localparam CLK_PERIOD_SLOW = 10us;  // 100 kHz

    logic clock_in;
    logic clock_ps2;

    ps2_driver_if vif (
        .clock_in  (clock_in ),
        .clock_ps2 (clock_ps2)
    );

    ps2_driver dut (
        .clock_in  (vif.clock_in ),
        .reset_in  (vif.reset_in ),
        .clock_ps2 (vif.clock_ps2),
        .data_ps2  (vif.data_ps2 ),
        .data_p    (vif.data_p   ),
        .data_p_en (vif.data_p_en)
    );

    initial begin
        clock_in = 0;
        forever #(CLK_PERIOD/2) clock_in = ~clock_in;
    end

    // scancode -> ASCII (spec Figura 3): letters, digits, space
    logic [7:0] ascii [logic [7:0]] = '{
        8'h1C: "A", 8'h32: "B", 8'h21: "C", 8'h23: "D", 8'h24: "E", 8'h2B: "F",
        8'h34: "G", 8'h33: "H", 8'h43: "I", 8'h3B: "J", 8'h42: "K", 8'h4B: "L",
        8'h3A: "M", 8'h31: "N", 8'h44: "O", 8'h4D: "P", 8'h15: "Q", 8'h2D: "R",
        8'h1B: "S", 8'h2C: "T", 8'h3C: "U", 8'h2A: "V", 8'h1D: "W", 8'h22: "X",
        8'h35: "Y", 8'h1A: "Z", 8'h45: "0", 8'h16: "1", 8'h1E: "2", 8'h26: "3",
        8'h25: "4", 8'h2E: "5", 8'h36: "6", 8'h3D: "7", 8'h3E: "8", 8'h46: "9",
        8'h29: " "
    };

    logic [7:0] exp_q [$];
    int         errors = 0;
    time        period = CLK_PERIOD_MAX;

    // start, 8 data bits LSB first, odd parity, stop; DUT samples on falling edge
    task automatic send(input logic [7:0] code, input logic bad_par = 0, input int nbits = 11);
        logic [10:0] frame;

        frame = {1'b1, ~^code ^ bad_par, code, 1'b0};
        for (int i = 0; i < nbits; i++) begin
            vif.data_ps2 = frame[i];
            #(period/2);
            clock_ps2 = 0;
            #(period/2);
            clock_ps2 = 1;
        end
        vif.data_ps2 = 1;
        #(period);
    endtask

    task automatic key(input logic [7:0] code);
        exp_q.push_back(ascii[code]);
        send(code);
    endtask

    always @(posedge clock_in) begin
        if (vif.data_p_en) begin
            assert (exp_q.size() > 0 && vif.data_p == exp_q.pop_front())
            else begin
                $error("unexpected data_p = %h", vif.data_p);
                errors++;
            end
        end
    end

    assert property (@(posedge clock_in) vif.data_p_en |=> !vif.data_p_en)
    else begin
        $error("data_p_en high for more than 1 cycle");
        errors++;
    end

    initial begin
        clock_ps2    = 1;
        vif.data_ps2 = 1;
        vif.reset_in = 1;
        #(3*CLK_PERIOD);
        vif.reset_in = 0;
        #(CLK_PERIOD_MAX);

        // every mapped key, at 1 MHz and at 100 kHz
        foreach (ascii[c]) begin
            key(c);
        end
        period = CLK_PERIOD_SLOW;
        foreach (ascii[c]) begin
            key(c);
        end
        period = CLK_PERIOD_MAX;

        // press + release 'A': only one 'A'
        key(8'h1C);
        send(8'hF0);
        send(8'h1C);

        // bad parity: no output
        send(8'h1C, 1);
        key(8'h32);

        // async reset: 2 ns pulse between clock_in edges, mid-frame
        send(8'h1C, 0, 5);
        #2;
        vif.reset_in = 1;
        #2;
        vif.reset_in = 0;
        #(CLK_PERIOD_MAX);
        key(8'h21);

        #(CLK_PERIOD_MAX);
        assert (exp_q.size() == 0)
        else begin
            $error("%0d expected outputs never arrived", exp_q.size());
            errors++;
        end

        if (errors == 0) begin
            $display("PASS");
        end
        else begin
            $display("FAIL: %0d errors", errors);
        end
        $finish;
    end
endmodule
