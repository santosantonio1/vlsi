interface receptor_padrao_if 
(
    input logic clk
);

    logic rst;
    logic data_sr;
    logic [7:0] data_pl;
    logic data_pl_en;
    logic sync;

endinterface
