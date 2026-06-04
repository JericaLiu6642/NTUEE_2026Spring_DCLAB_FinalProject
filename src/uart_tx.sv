module uart_tx #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer BAUD_RATE = 115_200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] data,
    output reg        txd,
    output reg        busy,
    output reg        done
);

    localparam integer BAUD_DIV = CLOCK_HZ / BAUD_RATE;

    localparam [1:0]
        S_IDLE  = 2'd0,
        S_START = 2'd1,
        S_DATA  = 2'd2,
        S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] baud_count;
    reg [2:0]  bit_index;
    reg [7:0]  shift_data;

    wire bit_period_done = (baud_count == BAUD_DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            baud_count <= 16'd0;
            bit_index  <= 3'd0;
            shift_data <= 8'd0;
            txd        <= 1'b1;
            busy       <= 1'b0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    txd        <= 1'b1;
                    busy       <= 1'b0;
                    baud_count <= 16'd0;
                    bit_index  <= 3'd0;

                    if (start) begin
                        shift_data <= data;
                        txd        <= 1'b0;
                        busy       <= 1'b1;
                        state      <= S_START;
                    end
                end

                S_START: begin
                    busy <= 1'b1;

                    if (bit_period_done) begin
                        baud_count <= 16'd0;
                        txd        <= shift_data[0];
                        state      <= S_DATA;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                S_DATA: begin
                    busy <= 1'b1;

                    if (bit_period_done) begin
                        baud_count <= 16'd0;

                        if (bit_index == 3'd7) begin
                            txd   <= 1'b1;
                            state <= S_STOP;
                        end else begin
                            bit_index <= bit_index + 1'b1;
                            txd       <= shift_data[bit_index + 1'b1];
                        end
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                S_STOP: begin
                    busy <= 1'b1;

                    if (bit_period_done) begin
                        baud_count <= 16'd0;
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        state      <= S_IDLE;
                    end else begin
                        baud_count <= baud_count + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
