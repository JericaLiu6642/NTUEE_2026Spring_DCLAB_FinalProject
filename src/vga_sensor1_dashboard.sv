module vga_sensor1_dashboard (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               frame_start,
    input  wire               active_video,
    input  wire [9:0]         pixel_x,
    input  wire [9:0]         pixel_y,

    input  wire signed [15:0] sensor_x,
    input  wire signed [15:0] sensor_y,
    input  wire signed [15:0] sensor_z,
    input  wire        [31:0] magnitude_squared_gauss_q16,
    input  wire               calibrated_mode,
    input  wire               calibration_collecting,
    input  wire               calibration_calculating,
    input  wire               calibration_done,

    output wire               text_pixel_on,
    output wire               graph_axis_pixel_on,
    output wire               graph_plot_pixel_on
);

    localparam [9:0] GRAPH_LEFT   = 10'd96;
    localparam [9:0] GRAPH_RIGHT  = 10'd607;
    localparam [9:0] GRAPH_TOP    = 10'd272;
    localparam [9:0] GRAPH_BOTTOM = 10'd447;
    localparam [31:0] GRAPH_FULL_SCALE_Q16 = 32'd1_048_576; // 16 Gauss^2

    reg signed [15:0] snapshot_x;
    reg signed [15:0] snapshot_y;
    reg signed [15:0] snapshot_z;
    reg        [31:0] snapshot_magnitude_squared_gauss_q16;
    reg               snapshot_calibrated_mode;
    reg               snapshot_collecting;
    reg               snapshot_calculating;
    reg               snapshot_done;
    reg        [7:0]  plot_history [0:511];
    reg        [8:0]  history_write_index;
    reg        [9:0]  history_valid_count;

    wire [5:0] text_column = pixel_x[9:4];
    wire [4:0] text_row    = pixel_y[8:4];
    wire [2:0] glyph_column = pixel_x[3:1];
    wire [2:0] glyph_row    = pixel_y[3:1];

    reg  [7:0]   character;
    reg  [255:0] line_text;
    reg  [87:0]  status_text;
    wire [7:0]   font_pixels;
    wire [9:0]   graph_x = pixel_x - GRAPH_LEFT;
    wire         graph_area = (pixel_x >= GRAPH_LEFT) &&
                              (pixel_x <= GRAPH_RIGHT) &&
                              (pixel_y >= GRAPH_TOP) &&
                              (pixel_y <= GRAPH_BOTTOM);
    wire         history_full = (history_valid_count == 10'd512);
    wire [9:0]   empty_history_columns = 10'd512 - history_valid_count;
    wire         graph_history_valid =
        history_full || (graph_x >= empty_history_columns);
    wire [8:0]   graph_history_index =
        history_full
            ? history_write_index + graph_x[8:0]
            : graph_x[8:0] - empty_history_columns[8:0];
    wire [9:0]   graph_plot_y =
        GRAPH_BOTTOM - {2'd0, plot_history[graph_history_index]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snapshot_x               <= 16'sd0;
            snapshot_y               <= 16'sd0;
            snapshot_z               <= 16'sd0;
            snapshot_magnitude_squared_gauss_q16 <= 32'd0;
            snapshot_calibrated_mode <= 1'b0;
            snapshot_collecting      <= 1'b0;
            snapshot_calculating     <= 1'b0;
            snapshot_done            <= 1'b0;
            history_write_index       <= 9'd0;
            history_valid_count       <= 10'd0;
        end else if (frame_start) begin
            snapshot_x               <= sensor_x;
            snapshot_y               <= sensor_y;
            snapshot_z               <= sensor_z;
            snapshot_magnitude_squared_gauss_q16 <=
                magnitude_squared_gauss_q16;
            snapshot_calibrated_mode <= calibrated_mode;
            snapshot_collecting      <= calibration_collecting;
            snapshot_calculating     <= calibration_calculating;
            snapshot_done            <= calibration_done;
            plot_history[history_write_index] <=
                magnitude_to_plot_level(magnitude_squared_gauss_q16);
            history_write_index <= history_write_index + 1'b1;

            if (!history_full)
                history_valid_count <= history_valid_count + 1'b1;
        end
    end

    function automatic [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 4'd10)
                hex_to_ascii = "0" + hex;
            else
                hex_to_ascii = "A" + (hex - 4'd10);
        end
    endfunction

    function automatic [71:0] q16_to_hex_ascii;
        input [31:0] value;
        begin
            q16_to_hex_ascii = {
                hex_to_ascii(value[31:28]),
                hex_to_ascii(value[27:24]),
                hex_to_ascii(value[23:20]),
                hex_to_ascii(value[19:16]),
                ".",
                hex_to_ascii(value[15:12]),
                hex_to_ascii(value[11:8]),
                hex_to_ascii(value[7:4]),
                hex_to_ascii(value[3:0])
            };
        end
    endfunction

    function automatic [7:0] magnitude_to_plot_level;
        input [31:0] magnitude_q16;
        reg [39:0] scaled_magnitude;
        begin
            if (magnitude_q16 >= GRAPH_FULL_SCALE_Q16) begin
                magnitude_to_plot_level = 8'd175;
            end else begin
                scaled_magnitude = magnitude_q16 * 8'd175;
                magnitude_to_plot_level = scaled_magnitude >> 20;
            end
        end
    endfunction

    function automatic [39:0] signed_word_to_hex_ascii;
        input signed [15:0] value;
        reg [15:0] magnitude;
        begin
            if (value < 0) begin
                magnitude = (~value) + 1'b1;
                signed_word_to_hex_ascii = {
                    "-",
                    hex_to_ascii(magnitude[15:12]),
                    hex_to_ascii(magnitude[11:8]),
                    hex_to_ascii(magnitude[7:4]),
                    hex_to_ascii(magnitude[3:0])
                };
            end else begin
                magnitude = value;
                signed_word_to_hex_ascii = {
                    "+",
                    hex_to_ascii(magnitude[15:12]),
                    hex_to_ascii(magnitude[11:8]),
                    hex_to_ascii(magnitude[7:4]),
                    hex_to_ascii(magnitude[3:0])
                };
            end
        end
    endfunction

    function automatic [7:0] string_character;
        input [255:0] text;
        input [5:0]   index;
        begin
            if (index < 6'd32)
                string_character = text[255 - (index * 8) -: 8];
            else
                string_character = " ";
        end
    endfunction

    always @* begin
        if (snapshot_collecting)
            status_text = "COLLECTING ";
        else if (snapshot_calculating)
            status_text = "CALCULATING";
        else if (snapshot_done)
            status_text = "DONE       ";
        else
            status_text = "READY      ";

        line_text = {32{" "}};

        case (text_row)
            5'd2:  line_text = {"MAGNETOMETER MONITOR", {12{" "}}};
            5'd4:  line_text = {
                "MODE: ",
                snapshot_calibrated_mode ? "CALIBRATED" : "RAW       ",
                {16{" "}}
            };
            5'd6:  line_text = {"SENSOR 1", {24{" "}}};
            5'd8:  line_text = {
                "X = ", signed_word_to_hex_ascii(snapshot_x), {23{" "}}
            };
            5'd9:  line_text = {
                "Y = ", signed_word_to_hex_ascii(snapshot_y), {23{" "}}
            };
            5'd10: line_text = {
                "Z = ", signed_word_to_hex_ascii(snapshot_z), {23{" "}}
            };
            5'd11: line_text = {
                "H2 = ",
                q16_to_hex_ascii(snapshot_magnitude_squared_gauss_q16),
                " G2",
                {15{" "}}
            };
            5'd13: line_text = {
                "CALIBRATION: ", status_text, {8{" "}}
            };
            5'd15: line_text = {"H2 GRAPH: 0 TO 16 G2", {11{" "}}};
            5'd28: line_text = {"TIME: 8.6 SECONDS", {15{" "}}};
            default: line_text = {32{" "}};
        endcase

        character = string_character(line_text, text_column);
    end

    vga_font_rom u_font (
        .character (character),
        .glyph_row (glyph_row),
        .pixels    (font_pixels)
    );

    assign text_pixel_on = active_video &&
                           font_pixels[3'd7 - glyph_column];
    assign graph_axis_pixel_on = active_video && graph_area &&
                                 ((pixel_x == GRAPH_LEFT) ||
                                  (pixel_y == GRAPH_BOTTOM));
    assign graph_plot_pixel_on = active_video && graph_area &&
                                 graph_history_valid &&
                                 ((pixel_y == graph_plot_y) ||
                                  (pixel_y == graph_plot_y + 1'b1));

endmodule
