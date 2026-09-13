interface receptor_padrao_if 
(
    input logic clk
);

    logic rst;
    logic data_sr;
    logic [7:0] data_pl;
    logic data_pl_en;
    logic sync;

    clocking cb @(posedge clk);
        default input #1step output #1ns;
        input data_pl, data_pl_en, sync;
        output data_sr;        
    endclocking

endinterface
