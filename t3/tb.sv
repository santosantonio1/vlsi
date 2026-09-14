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

    logic [39:0] payload_1 = 40'h0DEADBEEF0;
    logic [39:0] payload_2 = 40'h0BEBACAFE0;

    task send_byte(logic [7:0] b);
        // $display("[INFO] sending %h", b);

        foreach (b[i]) begin
            vif.data_sr <= b[i];
            @(posedge vif.clk);
        end
    endtask

    // 6 bytes -> 6*8-1 = 47
    task drive(logic [47:0] data);
        for (int i = 5; i >= 0; i--) begin
            send_byte(data[8*i+:8]);
        end
    endtask

    // stream primitives: drive only, never wait or check, so they can be
    // chained without inserting stray bits into the bitstream
    task sync_up();
        automatic logic [47:0] x = {align, payload_1};
        repeat(3) drive(x);
    endtask

    task break_sync();
        automatic logic [47:0] x = {align, payload_2} >> 8;
        drive(x);
    endtask

    task reset();
        vif.rst <= 1'b1;
        repeat(3) @(posedge vif.clk);
        vif.rst <= 1'b0;
    endtask

    task test_rst();
        reset();
        assert (vif.data_pl === 8'h00 && vif.sync === 1'b0 && vif.data_pl_en === 1'b0) 
        else $error("[FAIL] wrong reset values");
    endtask

    task test_sync();
        sync_up();

        @(posedge vif.clk);

        assert (vif.sync === 1'b1)
        else $error("[FAIL] sync didn't lift after 3 consecutive matches");
    endtask

    task test_desync();
        sync_up();
        break_sync();

        @(posedge vif.clk);

        assert (vif.sync === 1'b0)
        else $error("[FAIL] didn't desync after misaligned data");
    endtask

    task test_resync();
        sync_up();
        break_sync();
        sync_up();

        @(posedge vif.clk);

        assert (vif.sync === 1'b1)
        else $error("[FAIL] didn't resync after realignment");
    endtask

    logic [7:0] captured [$];

    always @(posedge vif.clk or posedge vif.rst) begin
        if (vif.rst) 
            captured.delete();
        else if(vif.data_pl_en === 1'b1)
            captured.push_back(vif.data_pl);
    end

    task test_data_pl();
        automatic logic [47:0] x = {align, payload_1};

        sync_up();
        drive(x);

        @(posedge vif.clk);

        assert (vif.data_pl_en === 1'b1)
        else $error("[FAIL] data_pl_en didn't lift with synced dut");

        assert (captured.size() == 5)
        else $error ("[FAIL] lost data (the queue didn't capture all 5 bytes)");

        for (int i = 4; i >= 0; i--) begin
            assert (captured[0] === payload_1[i*8+:8])
            else $error("[FAIL] data_pl different from expected data");

            captured.pop_front();
        end

        @(posedge vif.clk);
        assert (vif.data_pl_en === 1'b0)
        else $error("[FAIL] data_pl_en stayed high after 1 cycle");
    endtask

    initial begin
        test_rst();

        reset();
        test_sync(); 

        reset();
        test_desync();

        reset();
        test_resync();

        reset();
        test_data_pl();

        $finish;
    end        

endmodule