module mag_uart_streamer #(
    parameter integer CLOCK_HZ = 50_000_000,
    parameter integer BAUD_RATE = 115_200,
    parameter integer FRAME_HZ = 80
) (
    input  wire               clk,
    input  wire               rst_n,

    input  wire signed [15:0] s1_x,
    input  wire signed [15:0] s1_y,
    input  wire signed [15:0] s1_z,
    input  wire signed [15:0] s2_x,
    input  wire signed [15:0] s2_y,
    input  wire signed [15:0] s2_z,
    input  wire signed [15:0] s3_x,
    input  wire signed [15:0] s3_y,
    input  wire signed [15:0] s3_z,
    input  wire signed [15:0] s4_x,
    input  wire signed [15:0] s4_y,
    input  wire signed [15:0] s4_z,

    output wire               uart_txd
);

    localparam integer FRAME_PERIOD = CLOCK_HZ / FRAME_HZ;
    localparam [1:0]
        S_WAIT      = 2'd0,
        S_SEND      = 2'd1,
        S_WAIT_DONE = 2'd2;

    reg [22:0] frame_counter;
    reg [1:0]  state;
    reg [2:0]  sensor_index;
    reg [4:0]  char_index;
    reg        tx_start;
    reg [7:0]  tx_data;

    reg signed [15:0] snap_s1_x, snap_s1_y, snap_s1_z;
    reg signed [15:0] snap_s2_x, snap_s2_y, snap_s2_z;
    reg signed [15:0] snap_s3_x, snap_s3_y, snap_s3_z;
    reg signed [15:0] snap_s4_x, snap_s4_y, snap_s4_z;

    wire tx_busy;
    wire tx_done;
    wire frame_counter_done = (frame_counter == FRAME_PERIOD - 1);

    uart_tx #(
        .CLOCK_HZ  (CLOCK_HZ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .start (tx_start),
        .data  (tx_data),
        .txd   (uart_txd),
        .busy  (tx_busy),
        .done  (tx_done)
    );

    function automatic [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 4'd10)
                hex_to_ascii = "0" + hex;
            else
                hex_to_ascii = "A" + (hex - 4'd10);
        end
    endfunction

    function automatic [15:0] signed_magnitude;
        input signed [15:0] value;
        begin
            if (value < 0)
                signed_magnitude = (~value) + 1'b1;
            else
                signed_magnitude = value;
        end
    endfunction

    function automatic [7:0] signed_word_char;
        input signed [15:0] value;
        input [2:0]         index;
        reg [15:0]          magnitude;
        begin
            magnitude = signed_magnitude(value);

            case (index)
                3'd0: signed_word_char = value < 0 ? "-" : "+";
                3'd1: signed_word_char = hex_to_ascii(magnitude[15:12]);
                3'd2: signed_word_char = hex_to_ascii(magnitude[11:8]);
                3'd3: signed_word_char = hex_to_ascii(magnitude[7:4]);
                3'd4: signed_word_char = hex_to_ascii(magnitude[3:0]);
                default: signed_word_char = " ";
            endcase
        end
    endfunction

    function automatic [7:0] sensor_line_char;
        input [2:0] sensor;
        input [4:0] index;
        reg signed [15:0] x_value;
        reg signed [15:0] y_value;
        reg signed [15:0] z_value;
        begin
            case (sensor)
                3'd0: begin
                    x_value = snap_s1_x;
                    y_value = snap_s1_y;
                    z_value = snap_s1_z;
                end
                3'd1: begin
                    x_value = snap_s2_x;
                    y_value = snap_s2_y;
                    z_value = snap_s2_z;
                end
                3'd2: begin
                    x_value = snap_s3_x;
                    y_value = snap_s3_y;
                    z_value = snap_s3_z;
                end
                default: begin
                    x_value = snap_s4_x;
                    y_value = snap_s4_y;
                    z_value = snap_s4_z;
                end
            endcase

            case (index)
                5'd0:  sensor_line_char = "S";
                5'd1:  sensor_line_char = "1" + sensor[1:0];
                5'd2:  sensor_line_char = " ";
                5'd3:  sensor_line_char = "X";
                5'd4:  sensor_line_char = "=";
                5'd5:  sensor_line_char = signed_word_char(x_value, 3'd0);
                5'd6:  sensor_line_char = signed_word_char(x_value, 3'd1);
                5'd7:  sensor_line_char = signed_word_char(x_value, 3'd2);
                5'd8:  sensor_line_char = signed_word_char(x_value, 3'd3);
                5'd9:  sensor_line_char = signed_word_char(x_value, 3'd4);
                5'd10: sensor_line_char = " ";
                5'd11: sensor_line_char = "Y";
                5'd12: sensor_line_char = "=";
                5'd13: sensor_line_char = signed_word_char(y_value, 3'd0);
                5'd14: sensor_line_char = signed_word_char(y_value, 3'd1);
                5'd15: sensor_line_char = signed_word_char(y_value, 3'd2);
                5'd16: sensor_line_char = signed_word_char(y_value, 3'd3);
                5'd17: sensor_line_char = signed_word_char(y_value, 3'd4);
                5'd18: sensor_line_char = " ";
                5'd19: sensor_line_char = "Z";
                5'd20: sensor_line_char = "=";
                5'd21: sensor_line_char = signed_word_char(z_value, 3'd0);
                5'd22: sensor_line_char = signed_word_char(z_value, 3'd1);
                5'd23: sensor_line_char = signed_word_char(z_value, 3'd2);
                5'd24: sensor_line_char = signed_word_char(z_value, 3'd3);
                5'd25: sensor_line_char = signed_word_char(z_value, 3'd4);
                5'd26: sensor_line_char = 8'h0D;
                default: sensor_line_char = 8'h0A;
            endcase
        end
    endfunction

    wire [4:0] current_line_length =
        (sensor_index < 3'd4) ? 5'd28 : 5'd2;
    wire [7:0] current_character =
        (sensor_index < 3'd4)
            ? sensor_line_char(sensor_index, char_index)
            : ((char_index == 5'd0) ? 8'h0D : 8'h0A);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_counter <= 23'd0;
            state         <= S_WAIT;
            sensor_index  <= 3'd0;
            char_index    <= 5'd0;
            tx_start      <= 1'b0;
            tx_data       <= 8'd0;
            snap_s1_x     <= 16'sd0;
            snap_s1_y     <= 16'sd0;
            snap_s1_z     <= 16'sd0;
            snap_s2_x     <= 16'sd0;
            snap_s2_y     <= 16'sd0;
            snap_s2_z     <= 16'sd0;
            snap_s3_x     <= 16'sd0;
            snap_s3_y     <= 16'sd0;
            snap_s3_z     <= 16'sd0;
            snap_s4_x     <= 16'sd0;
            snap_s4_y     <= 16'sd0;
            snap_s4_z     <= 16'sd0;
        end else begin
            tx_start <= 1'b0;

            case (state)
                S_WAIT: begin
                    if (frame_counter_done) begin
                        frame_counter <= 23'd0;
                        sensor_index  <= 3'd0;
                        char_index    <= 5'd0;
                        snap_s1_x     <= s1_x;
                        snap_s1_y     <= s1_y;
                        snap_s1_z     <= s1_z;
                        snap_s2_x     <= s2_x;
                        snap_s2_y     <= s2_y;
                        snap_s2_z     <= s2_z;
                        snap_s3_x     <= s3_x;
                        snap_s3_y     <= s3_y;
                        snap_s3_z     <= s3_z;
                        snap_s4_x     <= s4_x;
                        snap_s4_y     <= s4_y;
                        snap_s4_z     <= s4_z;
                        state         <= S_SEND;
                    end else begin
                        frame_counter <= frame_counter + 1'b1;
                    end
                end

                S_SEND: begin
                    if (!tx_busy) begin
                        tx_data  <= current_character;
                        tx_start <= 1'b1;
                        state    <= S_WAIT_DONE;
                    end
                end

                S_WAIT_DONE: begin
                    if (tx_done) begin
                        if (char_index == current_line_length - 1'b1) begin
                            char_index <= 5'd0;

                            if (sensor_index == 3'd4) begin
                                state <= S_WAIT;
                            end else begin
                                sensor_index <= sensor_index + 1'b1;
                                state <= S_SEND;
                            end
                        end else begin
                            char_index <= char_index + 1'b1;
                            state <= S_SEND;
                        end
                    end
                end

                default: state <= S_WAIT;
            endcase
        end
    end

endmodule
