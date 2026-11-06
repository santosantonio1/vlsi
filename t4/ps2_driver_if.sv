interface ps2_driver_if (
    input logic clock_in,
    input logic clock_ps2
);

    // input
    logic       reset_in;
    logic       data_ps2;

    // output
    logic [7:0] data_p;
    logic       data_p_en;

endinterface
