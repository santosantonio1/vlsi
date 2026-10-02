module receptor_padrao #(
    parameter int DATA_W = 8,
    parameter logic [DATA_W-1:0] SYNC_VALUE = 8'hA5,
    parameter int PAYLOAD_COUNT = 5,
    parameter int SYNC_COUNT = 3
)
(
    input  logic        clk,
    input  logic        rst,
    input  logic        data_sr,

    output logic [7:0]  data_pl,
    output logic        data_pl_en,
    output logic        sync
);

    typedef enum logic [1:0] {
        RESET,
        SYNC_LEAD,
        SYNC,
        DATA
    } states;

    states current_state, next_state;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            current_state <= RESET;
        end else begin
            current_state <= next_state;
        end
    end

    logic sync_lead;
    logic sync_fail;
    logic last_bit;
    logic [$clog2(SYNC_COUNT+1)-1:0] sync_counter;
    logic [$clog2(DATA_W)-1:0] sr_count;
    logic [$clog2(PAYLOAD_COUNT)-1:0] data_count;

    // SYNC_LEAD: hunting for the alignment word on every bit
    // SYNC:      checking the alignment word at its expected position
    // DATA:      payload, only sent out when synced
    always_comb begin
        unique case(current_state)
            RESET:     next_state = SYNC_LEAD;
            SYNC_LEAD: next_state = sync_lead ? DATA : SYNC_LEAD;
            SYNC:      next_state = sync_fail ? SYNC_LEAD :
                                    last_bit  ? DATA : SYNC;
            DATA:      next_state = (last_bit && (data_count == PAYLOAD_COUNT-1)) ? SYNC : DATA;
            default:   next_state = RESET;
        endcase
    end

    logic [DATA_W-1:0]sr_full;
    logic [DATA_W-2:0]sr;

    // a failed alignment word restarts the hunt from the failing bit,
    // older bits are dropped
    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            sr <= '0;
        end else begin
            if(sync_fail) begin
                sr <= '0;
            end else begin
                for(int i = 1; i < DATA_W-1; i++) begin
                    sr[i] <= sr[i-1];
                end
            end
            sr[0] <= data_sr;
        end
    end

    assign sr_full = {sr, data_sr};
    assign sync_lead = (sr_full == SYNC_VALUE);

    always_ff@(posedge clk or posedge rst)begin
        if(rst)begin
            sync_counter <= '0;
        end
        else begin
            case(current_state)
                SYNC_LEAD: begin
                    if(sync_lead)
                        sync_counter <= 1'b1;
                end
                SYNC: begin
                    if(sync_fail)
                        sync_counter <= '0;
                    else if(last_bit && (sync_counter != SYNC_COUNT))
                        sync_counter <= sync_counter + 1'b1;
                end
            endcase
        end
    end

    // bit inside the current byte, both for the alignment word and the payload
    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            sr_count <= '0;
        end else begin
            if((current_state inside{SYNC, DATA}) && !last_bit)
                sr_count <= sr_count + 1'b1;
            else
                sr_count <= '0;
        end
    end

    assign last_bit = (sr_count == DATA_W-1);

    // payload byte
    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            data_count <= '0;
        end else begin
            if(current_state == DATA) begin
                if(last_bit)
                    data_count <= (data_count == PAYLOAD_COUNT-1) ? '0 : data_count + 1'b1;
            end else
                data_count <= '0;
        end
    end

    // MSB first
    assign sync_fail = (current_state inside{SYNC} && data_sr != SYNC_VALUE[DATA_W-1-sr_count]);

    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            sync <= 1'b0;
        end else begin
            sync <= (sync_counter == SYNC_COUNT);
        end
    end

    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            data_pl    <= '0;
            data_pl_en <= 1'b0;
        end else begin
            data_pl_en <= 1'b0;
            if((current_state == DATA) && last_bit && sync) begin
                data_pl    <= sr_full;
                data_pl_en <= 1'b1;
            end
        end
    end

endmodule
