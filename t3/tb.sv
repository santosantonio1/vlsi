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

    localparam CLK_PERIOD = 10ns; // 100 MHz

    initial begin
        clk = 0;

        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    logic [7:0] align = 8'hA5;

    initial begin

        $finish;
    end        

endmodule