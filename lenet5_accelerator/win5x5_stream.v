// win5x5_stream.v  (Pure Verilog-2001, no SystemVerilog features)
module win5x5_stream #(
    parameter IMG_WIDTH = 32,
    parameter PIX_BITS  = 8
)(
    input  wire                          clk,
    input  wire                          rst_n,      // synchronous, active-low
    input  wire                          valid_in,
    input  wire signed [PIX_BITS-1:0]    pix_in,

    output reg                           valid_out,
    output reg signed [PIX_BITS-1:0]     w00, w01, w02, w03, w04,
    output reg signed [PIX_BITS-1:0]     w10, w11, w12, w13, w14,
    output reg signed [PIX_BITS-1:0]     w20, w21, w22, w23, w24,
    output reg signed [PIX_BITS-1:0]     w30, w31, w32, w33, w34,
    output reg signed [PIX_BITS-1:0]     w40, w41, w42, w43, w44
);

    // -------- util: clog2 (Verilog-2001) --------
    function integer CLOG2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            CLOG2 = 0;
            while (v > 0) begin
                v = v >> 1;
                CLOG2 = CLOG2 + 1;
            end
        end
    endfunction

    // -------- five line buffers (shift-register style) --------
    reg signed [PIX_BITS-1:0] line0 [0:IMG_WIDTH-1];
    reg signed [PIX_BITS-1:0] line1 [0:IMG_WIDTH-1];
    reg signed [PIX_BITS-1:0] line2 [0:IMG_WIDTH-1];
    reg signed [PIX_BITS-1:0] line3 [0:IMG_WIDTH-1];
    reg signed [PIX_BITS-1:0] line4 [0:IMG_WIDTH-1];

    integer i;

    // column/row counters
    reg [CLOG2(IMG_WIDTH):0] col;
    reg [31:0]               row;

    // -------- main sequential logic --------
    always @(posedge clk) begin
        if (!rst_n) begin
            // clear line buffers
            for (i=0; i<IMG_WIDTH; i=i+1) begin
                line0[i] <= 0;
                line1[i] <= 0;
                line2[i] <= 0;
                line3[i] <= 0;
                line4[i] <= 0;
            end
            // reset counters
            col <= 0;
            row <= 0;
            // outputs
            valid_out <= 1'b0;
            w00 <= 0; w01 <= 0; w02 <= 0; w03 <= 0; w04 <= 0;
            w10 <= 0; w11 <= 0; w12 <= 0; w13 <= 0; w14 <= 0;
            w20 <= 0; w21 <= 0; w22 <= 0; w23 <= 0; w24 <= 0;
            w30 <= 0; w31 <= 0; w32 <= 0; w33 <= 0; w34 <= 0;
            w40 <= 0; w41 <= 0; w42 <= 0; w43 <= 0; w44 <= 0;
        end else begin
            // default
            valid_out <= 1'b0;

            // shift when input is valid
            if (valid_in) begin
                // right shift each line
                for (i=IMG_WIDTH-1; i>0; i=i-1) begin
                    line0[i] <= line0[i-1];
                    line1[i] <= line1[i-1];
                    line2[i] <= line2[i-1];
                    line3[i] <= line3[i-1];
                    line4[i] <= line4[i-1];
                end

                // insert new pixel and cascade line heads
                line0[0] <= pix_in;
                line1[0] <= line0[IMG_WIDTH-1];
                line2[0] <= line1[IMG_WIDTH-1];
                line3[0] <= line2[IMG_WIDTH-1];
                line4[0] <= line3[IMG_WIDTH-1];

                // advance counters
                if (col == IMG_WIDTH-1) begin
                    col <= 0;
                    row <= row + 1;
                end else begin
                    col <= col + 1;
                end
            end

            // output a 5x5 window when ready (row/col >= 4)
            if (valid_in && (col >= 4) && (row >= 4)) begin
                valid_out <= 1'b1;

                // row -4 .. 0 mapping across the five lines
                // top row (row-4)
                w00 <= line4[col-4];  w01 <= line4[col-3];  w02 <= line4[col-2];  w03 <= line4[col-1];  w04 <= line4[col-0];
                // row-3
                w10 <= line3[col-4];  w11 <= line3[col-3];  w12 <= line3[col-2];  w13 <= line3[col-1];  w14 <= line3[col-0];
                // row-2
                w20 <= line2[col-4];  w21 <= line2[col-3];  w22 <= line2[col-2];  w23 <= line2[col-1];  w24 <= line2[col-0];
                // row-1
                w30 <= line1[col-4];  w31 <= line1[col-3];  w32 <= line1[col-2];  w33 <= line1[col-1];  w34 <= line1[col-0];
                // current row (row)
                w40 <= line0[col-4];  w41 <= line0[col-3];  w42 <= line0[col-2];  w43 <= line0[col-1];  w44 <= line0[col-0];
            end
        end
    end
endmodule
