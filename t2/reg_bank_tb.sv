class reg_bank_tr;
    logic rd_en;
    logic [3:0] rd_address;
    logic wr_en;
    logic [3:0] wr_address;
    logic [7:0] wr_data;
    
    function new();
        rd_en       = 0;
        rd_address  = 0;
        wr_en       = 0;
        wr_address  = 0;
        wr_data     = 0;
    endfunction
endclass

module reg_bank_tb();

    logic clk;
    regbank_if vif(.clk(clk));

    localparam CLK_PERIOD = 20ns; // 50 MHz clock
    initial begin
        #(200ns);
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    reg_bank cuv (
        // inputs
        .clk        (vif.clk       ), 
        .rst        (vif.rst       ), 
        .rd_en      (vif.rd_en     ), 
        .wr_en      (vif.wr_en     ), 
        .rd_address (vif.rd_address), 
        .wr_data    (vif.wr_data   ), 
        .wr_address (vif.wr_address), 

        // outputs
        .rd_data    (vif.rd_data   ) 

    );

    reg_bank_tr rst_tr = new();

    logic [7:0] reset_values[16] = '{
        8'h32,  // Read Only
        8'h30,  // Read Only
        8'h31,  // Read Only
        8'h37,  // Read Only
        8'h30,  // Read Only
        8'h39,  // Read Only

        8'h06,  // Read/Write
        8'h07,  // Read/Write
        8'h08,  // Read/Write
        8'h09,  // Read/Write
        8'h0A,  // Read/Write
        8'hFF,  // Read/Write
        8'hFF,  // Read/Write
        8'hFF,  // Read/Write
        8'hFF,  // Read/Write
        8'hFF   // Read/Write
    };

    logic [7:0] expected_data;

    initial begin
        $display("--- RESET TEST ---");        
        #(200ns);
        vif.rst = 1;

        vif.rd_en       = rst_tr.rd_en;
        vif.rd_address  = rst_tr.rd_address;
        vif.wr_en       = rst_tr.wr_en;
        vif.wr_address  = rst_tr.wr_address;
        vif.wr_data     = rst_tr.wr_data;

        #(200ns);
        vif.rst = 0;
        @(negedge clk);

        for (int i = 0; i < 16; i++) begin
            vif.rd_en       = 1;
            vif.rd_address  = i;
            @(negedge clk);
            assert(vif.rd_data == reset_values[i]) 
            else $display("Reset value mismatch at address %0d: expected %0h, got %0h", 
                            i, reset_values[i], vif.rd_data);
        end

        // ----------------------------------------------------------
        
        $display("--- WRITE READ-ONLY TEST ---");
        for (int i = 0; i < 7; i++) begin
            @(negedge clk);

            vif.rd_en       = 0;

            vif.wr_en       = 1;
            vif.wr_address  = i;
            vif.wr_data     = i + 8'h10;

            @(negedge clk);

            vif.rd_en       = 1;
            vif.rd_address  = i;
            
            @(negedge clk);

            assert(vif.rd_data == reset_values[i]) 
            else $display("Ready-Only mismatch at address %0d: expected %0h, got %0h", 
                            i, reset_values[i], vif.rd_data);
        end

        // ----------------------------------------------------------
        
        $display("--- WRITE READ-WRITE TEST ---");
        for (int i = 7; i < 16; i++) begin
            @(negedge clk);
            
            vif.rd_en       = 0;

            vif.wr_en       = 1;
            vif.wr_address  = i;
            vif.wr_data     = i + 8'h10;
            expected_data   = i + 8'h10;
            
            @(negedge clk);

            vif.rd_en       = 1;
            vif.rd_address  = i;
            
            @(negedge clk);

            assert(vif.rd_data == expected_data) 
            else $display("Read-Write value mismatch at address %0d: expected %0h, got %0h", 
                            i, expected_data, vif.rd_data);
        end

        $finish;
    end

endmodule