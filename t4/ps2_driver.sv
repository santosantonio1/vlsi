module ps2_driver #(
    parameter FILTER = 8    // clock_ps2 glitch filter, in clock_in cycles
) (
    input  logic       clock_in,
    input  logic       reset_in,
    input  logic       clock_ps2,
    input  logic       data_ps2,
    output logic [7:0] data_p,
    output logic       data_p_en
);

    typedef enum logic [1:0] {IDLE, DATA, PARITY, STOP} state_t;

    state_t            state;
    logic [1:0]        clk_s;
    logic [1:0]        dat_s;
    logic [FILTER-1:0] clk_h;
    logic              clk_f;
    logic              clk_f_q;
    logic              data;
    logic              fall;
    logic [2:0]        cnt;
    logic [7:0]        sr;
    logic              par_ok;
    logic              brk;
    logic              valid;
    logic [7:0]        ascii;

    assign data = dat_s[1];
    assign fall = clk_f_q & ~clk_f;

    // 2-FF synchronizer, glitch filter and falling edge detect
    always_ff @(posedge clock_in or posedge reset_in) begin
        if (reset_in) begin
            clk_s   <= '1;
            dat_s   <= '1;
            clk_h   <= '1;
            clk_f   <= 1;
            clk_f_q <= 1;
        end
        else begin
            clk_s   <= {clk_s[0], clock_ps2};
            dat_s   <= {dat_s[0], data_ps2};
            clk_h   <= {clk_h[FILTER-2:0], clk_s[1]};
            clk_f_q <= clk_f;
            if (&clk_h) begin
                clk_f <= 1;
            end
            else if (~|clk_h) begin
                clk_f <= 0;
            end
        end
    end

    // ponytail: no frame timeout, a cut frame mis-frames until reset; add a ~200 us watchdog if needed
    always_ff @(posedge clock_in or posedge reset_in) begin
        if (reset_in) begin
            state     <= IDLE;
            cnt       <= 0;
            sr        <= 0;
            par_ok    <= 0;
            brk       <= 0;
            data_p    <= 0;
            data_p_en <= 0;
        end
        else begin
            data_p_en <= 0;
            if (fall) begin
                case (state)
                    IDLE: begin
                        if (!data) begin
                            state <= DATA;
                        end
                    end
                    DATA: begin
                        sr  <= {data, sr[7:1]};
                        cnt <= cnt + 1;
                        if (cnt == 7) begin
                            state <= PARITY;
                        end
                    end
                    PARITY: begin
                        par_ok <= ^{sr, data};  // odd parity
                        state  <= STOP;
                    end
                    STOP: begin
                        if (data && par_ok) begin
                            if (sr == 8'hF0) begin
                                brk <= 1;
                            end
                            else if (brk) begin
                                brk <= 0;   // key release, drop it
                            end
                            else if (valid) begin
                                data_p    <= ascii;
                                data_p_en <= 1;
                            end
                        end
                        state <= IDLE;
                    end
                endcase
            end
        end
    end

    // scancode -> ASCII
    // ponytail: no Shift/Caps/E0 handling, letters always uppercase, symbols unshifted
    always_comb begin
        valid = 1;
        case (sr)
            8'h1C: ascii = "A";
            8'h32: ascii = "B";
            8'h21: ascii = "C";
            8'h23: ascii = "D";
            8'h24: ascii = "E";
            8'h2B: ascii = "F";
            8'h34: ascii = "G";
            8'h33: ascii = "H";
            8'h43: ascii = "I";
            8'h3B: ascii = "J";
            8'h42: ascii = "K";
            8'h4B: ascii = "L";
            8'h3A: ascii = "M";
            8'h31: ascii = "N";
            8'h44: ascii = "O";
            8'h4D: ascii = "P";
            8'h15: ascii = "Q";
            8'h2D: ascii = "R";
            8'h1B: ascii = "S";
            8'h2C: ascii = "T";
            8'h3C: ascii = "U";
            8'h2A: ascii = "V";
            8'h1D: ascii = "W";
            8'h22: ascii = "X";
            8'h35: ascii = "Y";
            8'h1A: ascii = "Z";
            8'h45: ascii = "0";
            8'h16: ascii = "1";
            8'h1E: ascii = "2";
            8'h26: ascii = "3";
            8'h25: ascii = "4";
            8'h2E: ascii = "5";
            8'h36: ascii = "6";
            8'h3D: ascii = "7";
            8'h3E: ascii = "8";
            8'h46: ascii = "9";
            8'h29: ascii = " ";
            8'h0E: ascii = "`";
            8'h4E: ascii = "-";
            8'h55: ascii = "=";
            8'h54: ascii = "[";
            8'h5B: ascii = "]";
            8'h5D: ascii = "\\";
            8'h4C: ascii = ";";
            8'h52: ascii = "'";
            8'h41: ascii = ",";
            8'h49: ascii = ".";
            8'h4A: ascii = "/";
            8'h5A: ascii = 8'h0D;   // Enter
            8'h66: ascii = 8'h08;   // Backspace
            8'h0D: ascii = 8'h09;   // Tab
            8'h76: ascii = 8'h1B;   // Esc
            default: begin
                valid = 0;
                ascii = 8'h00;
            end
        endcase
    end

endmodule
