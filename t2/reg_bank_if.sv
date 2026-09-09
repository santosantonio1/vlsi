interface regbank_if #(
) (
    input logic clk
);

    logic rst, rd_en, wr_en;
    logic [3:0] rd_address;
    logic [7:0] wr_data;
    logic [3:0] wr_address;

    logic [7:0] rd_data;
endinterface