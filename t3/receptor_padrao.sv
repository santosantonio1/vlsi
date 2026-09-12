module receptor_padrao #(
    parameter logic [DATA_W-1:0] SYNC_VALUE = 8'hA5,
    parameter int DATA_W = 8,
    parameter int PAYLOAD_COUNT = 5,
    parameter int SYNC_COUNT = 3,
)
(
    input  logic        clk,
    input  logic        rst,
    input  logic        data_sr, 
    
    output logic [7:0]  data_pl,
    output logic        data_pl_en,
    output logic        sync
);


    typedef enum logic { 
        RESET,
        SYNC_FIRST,
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
    logic sync_full;

    always_comb begin 
        unique case(current_state):
            RESET: next_state = SYNC_FIRST;
            SYNC_FIRST: next_state = sync_lead ? SYNC : SYNC_FIRST;
            SYNC:       next_state = sync_fail ? SYNC_FIRST: 
                                     sync_full ? DATA : SYNC;
            DATA: next_state = (data_count == PAYLOAD_COUNT) ? SYNC_FIRST : DATA;
            default: next_state = RESET;
        endcase
    end

    logic [6:0]sr;

    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            sr <= '0;
        end else begin
            for(int i = 1; i < 6) begin
                sr[i] <= sr[i-1];
            end
            sr[0] <= data_sr;
        end
    end


    assign sync_lead = ({sr, data_sr} == SYNC_VALUE);

    logic [$clog2(DATA_W)-1:0] sr_count;
    logic last_sync;

    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            sr_count <= '0;
        end else begin
            if(current_state == SYNC)
                sr_count <= sr_count + 1'b1;
            else
                sr_count <= '0;
        end
    end
    
    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            last_sync <= '0;
        end else begin
            if((current_state == SYNC) && (sr_count == '1))
                last_sync <= 1'b1;
            else if (!(current_state inside {SYNC}))
                last_sync <= 1'b0;
        end
    end


    assign sync_fail = (current_state inside{SYNC} && data_sr != SYNC_VALUE[sr_count]);
    always_ff@(posedge clk or posedge rst) begin
        if(rst) begin
            sync_full <= '0;
        end else begin
            if(current_state == SYNC) begin
                if((last_sync) && (sr_count == '1))
            end
        end
    end
    

endmodule