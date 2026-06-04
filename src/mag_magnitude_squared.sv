module mag_magnitude_squared (
    input  wire signed [15:0] field_x_counts,
    input  wire signed [15:0] field_y_counts,
    input  wire signed [15:0] field_z_counts,
    output wire        [31:0] magnitude_squared_gauss_q16
);

    // QMC5883P +-2 G range: 15000 counts per Gauss.
    // Convert (X^2 + Y^2 + Z^2) from counts^2 to Q16.16 Gauss^2:
    //   counts_squared * 2^16 / 15000^2
    // The multiplier is round(2^48 / 15000^2), followed by a 32-bit shift.
    localparam [20:0] GAUSS_SQUARED_Q16_MULTIPLIER = 21'd1_251_000;

    wire signed [31:0] x_square_signed = field_x_counts * field_x_counts;
    wire signed [31:0] y_square_signed = field_y_counts * field_y_counts;
    wire signed [31:0] z_square_signed = field_z_counts * field_z_counts;

    wire [32:0] square_sum =
        {1'b0, x_square_signed} +
        {1'b0, y_square_signed} +
        {1'b0, z_square_signed};
    wire [53:0] scaled_square_sum =
        square_sum * GAUSS_SQUARED_Q16_MULTIPLIER;

    assign magnitude_squared_gauss_q16 = scaled_square_sum >> 32;

endmodule
