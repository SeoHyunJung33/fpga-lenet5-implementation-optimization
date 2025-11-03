`timescale 1ns/1ps
// ============================================================================
// lenet5_core (Pure Verilog-2001, external flat W/B buses)
//  - This is a readmemh-free variant of lenet5_top_all.
//  - All weights/biases are provided as *flat buses* from ROM IP loaders.
//  - Input stream: in_valid + signed pix (8b), ready-backpressure.
//  - Output: prob_valid + prob10_flat(10*16b), argmax(pred_digit/pred_valid).
// ============================================================================
module lenet5_core #(
    // widths
    parameter integer PIX_BITS   = 8,
    parameter integer WW_BITS    = 8,
    parameter integer OUT_BITS   = 16,
    // geometry/channels
    parameter integer IMG_W      = 32,
    parameter integer C1_OUT_CH  = 6,
    parameter integer C3_IN_CH   = 6,
    parameter integer C3_OUT_CH  = 16,
    parameter integer C5_IN_CH   = 16,
    parameter integer C5_OUT_CH  = 120,
    parameter integer FC120_OUT  = 84,
    parameter integer FC84_OUT   = 10,
    // internal headrooms
    parameter integer PROD1_BITS = PIX_BITS + WW_BITS,
    parameter integer SUM1_BITS  = PROD1_BITS + 5,
    parameter integer PROD3_BITS = OUT_BITS + WW_BITS,
    parameter integer SUM3_BITS  = PROD3_BITS + 5,
    parameter integer PROD5_BITS = OUT_BITS + WW_BITS,
    parameter integer SUM5_BITS  = PROD5_BITS + 9,
    // quant options
    parameter integer IN_ZP            = 0,
    parameter integer FC1_TO_FC2_SHIFT = 0,
    parameter integer FC2_SHIFT_R      = 10
)(
    input  wire                                 clk,
    input  wire                                 rst_n,

    // Pixel stream (TB/Preprocess)
    input  wire                                 in_valid,
    input  wire  signed [PIX_BITS-1:0]          in_pix,
    output wire                                 in_ready,

    // External flat Weights/Biases (ROM-loaded)
    input  wire [WW_BITS*(C1_OUT_CH*25)-1:0]            c1_w_flat,
    input  wire [16*C1_OUT_CH-1:0]                      c1_b_flat,

    input  wire [WW_BITS*(C3_OUT_CH*C3_IN_CH*25)-1:0]   c3_w_flat,
    input  wire [SUM3_BITS*C3_OUT_CH-1:0]               c3_b_flat,

    input  wire [WW_BITS*(C5_OUT_CH*C5_IN_CH*25)-1:0]   c5_w_flat,
    input  wire [SUM5_BITS*C5_OUT_CH-1:0]               c5_b_flat,

    input  wire [WW_BITS*(FC120_OUT*C5_OUT_CH)-1:0]     fc120_w_flat,
    input  wire [OUT_BITS*FC120_OUT-1:0]                fc120_b_flat,

    input  wire [WW_BITS*(FC84_OUT*FC120_OUT)-1:0]      fc84_w_flat,  // 8b sign-extend inside
    input  wire [OUT_BITS*FC84_OUT-1:0]                 fc84_b_flat,

    // Results
    output wire                                 prob_valid,
    output wire  signed [FC84_OUT*OUT_BITS-1:0] prob10_flat,
    output wire  [3:0]                          pred_digit,
    output wire                                 pred_valid
);

    // =========================================================================
    // 1) conv1
    // =========================================================================
    wire                       c1_valid;
    wire [15:0]                c1_ch;
    wire signed [OUT_BITS-1:0] c1_pix1,c1_pix2,c1_pix3,c1_pix4,c1_pix5,c1_pix6;
    wire                       c1_ready;

    wire signed [PIX_BITS-1:0] in_pix_adj = in_pix - IN_ZP[PIX_BITS-1:0];
    assign in_ready = c1_ready;

    conv1 #(
        .IMG_WIDTH (IMG_W),
        .PIX_BITS  (PIX_BITS),
        .WW_BITS   (WW_BITS),
        .PROD_BITS (PROD1_BITS),
        .SUM_BITS  (SUM1_BITS),
        .OUT_BITS  (OUT_BITS),
        .OUT_CH    (C1_OUT_CH),
        .SHIFT_R   (5),
        .RELU_EN   (1)
    ) u_conv1 (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (in_valid),
        .pix_in    (in_pix_adj),
        .pix_ready (c1_ready),
        .w_flat    (c1_w_flat),
        .b_flat    (c1_b_flat),
        .valid_out (c1_valid),
        .ch_idx    (c1_ch),
        .pix_out1  (c1_pix1),
        .pix_out2  (c1_pix2),
        .pix_out3  (c1_pix3),
        .pix_out4  (c1_pix4),
        .pix_out5  (c1_pix5),
        .pix_out6  (c1_pix6)
    );

    // =========================================================================
    // 2) sub2
    // =========================================================================
    wire                         s2_valid;
    wire signed [OUT_BITS-1:0] c3_pix1,c3_pix2,c3_pix3,c3_pix4,c3_pix5,c3_pix6;

    sub2_bank #(
        .FM_W     (IMG_W-4),
        .OUT_BITS (OUT_BITS),
        .IN_CH    (C3_IN_CH)
    ) u_sub2 (
        .clk        (clk),
        .rst_n      (rst_n),
        .c1_valid   (c1_valid),
        .c1_ch      (c1_ch),
        .c1_pix1    (c1_pix1),
        .c1_pix2    (c1_pix2),
        .c1_pix3    (c1_pix3),
        .c1_pix4    (c1_pix4),
        .c1_pix5    (c1_pix5),
        .c1_pix6    (c1_pix6),
        .valid_out  (s2_valid),
        .pix_in1    (c3_pix1),
        .pix_in2    (c3_pix2),
        .pix_in3    (c3_pix3),
        .pix_in4    (c3_pix4),
        .pix_in5    (c3_pix5),
        .pix_in6    (c3_pix6)
    );

    // =========================================================================
    // 3) conv3
    // =========================================================================
    wire                         c3_valid;
    wire [15:0]                  c3_ch;
    wire signed [OUT_BITS-1:0]   c3_pix;

    conv3 #(
        .IMG_WIDTH ( (IMG_W-4)/2 ),
        .IN_CH     (C3_IN_CH),
        .OUT_CH    (C3_OUT_CH),
        .PIX_BITS  (OUT_BITS),
        .WW_BITS   (WW_BITS),
        .PROD_BITS (PROD3_BITS),
        .SUM_BITS  (SUM3_BITS),
        .OUT_BITS  (OUT_BITS),
        .SHIFT_R   (5)
    ) u_conv3 (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (s2_valid),
        .pix_in1   (c3_pix1),
        .pix_in2   (c3_pix2),
        .pix_in3   (c3_pix3),
        .pix_in4   (c3_pix4),
        .pix_in5   (c3_pix5),
        .pix_in6   (c3_pix6),
        .w_flat    (c3_w_flat),
        .b_flat    (c3_b_flat),
        .valid_out (c3_valid),
        .ch_idx    (c3_ch),
        .pix_out   (c3_pix)
    );

    // =========================================================================
    // 4) sub4
    // =========================================================================
    wire                         s4_valid;
    wire [C5_IN_CH*OUT_BITS-1:0] s4_pix16_flat;

    sub4_bank #(
        .FM_W     ( ((IMG_W-4)/2) - 4 ),
        .OUT_BITS (OUT_BITS)
    ) u_sub4 (
        .clk        (clk),
        .rst_n      (rst_n),
        .c3_valid   (c3_valid),
        .c3_ch      (c3_ch),
        .c3_pix     (c3_pix),
        .valid_out  (s4_valid),
        .pix16_flat (s4_pix16_flat)
    );

    // =========================================================================
    // 5) conv5
    // =========================================================================
    wire                         c5_valid;
    wire [15:0]                  c5_ch;
    wire signed [OUT_BITS-1:0]   c5_pix;
    wire                         c5_vec_valid;

    conv5 #(
        .IN_CH     (C5_IN_CH),
        .OUT_CH    (C5_OUT_CH),
        .PIX_BITS  (OUT_BITS),
        .WW_BITS   (WW_BITS),
        .PROD_BITS (PROD5_BITS),
        .SUM_BITS  (SUM5_BITS),
        .OUT_BITS  (OUT_BITS),
        .SHIFT_R   (8),
        .RELU_EN   (1),
        .OC_PAR    (8)
    ) u_conv5 (
        .clk         (clk),
        .rst_n       (rst_n),
        .valid_in    (s4_valid),
        .pix_in_flat (s4_pix16_flat),
        .w_flat      (c5_w_flat),
        .b_flat      (c5_b_flat),
        .valid_out   (c5_valid),
        .ch_idx      (c5_ch),
        .pix_out     (c5_pix),
        .vec_valid   (c5_vec_valid)
    );

    // =========================================================================
    // 6) FC1 (120 -> 84) x84
    // =========================================================================
    wire [FC120_OUT-1:0]                 fc1_valids;
    wire signed [FC120_OUT*OUT_BITS-1:0] fc1_vec_flat;

    genvar fn;
    generate
      for (fn=0; fn<FC120_OUT; fn=fn+1) begin : G_FC1
        wire signed [WW_BITS*C5_OUT_CH-1:0]  w_slice =
            fc120_w_flat[(fn*C5_OUT_CH*WW_BITS) +: (C5_OUT_CH*WW_BITS)];
        wire signed [OUT_BITS-1:0]           b_slice =
            fc120_b_flat[(fn*OUT_BITS) +: OUT_BITS];
        wire v1;
        wire signed [OUT_BITS-1:0] y1;

        fc_120 #(
          .CH_NUM    (C5_OUT_CH),
          .IN_BITS   (OUT_BITS),
          .W_BITS    (WW_BITS),
          .BIAS_BITS (OUT_BITS),
          .OUT_WIDTH (OUT_BITS)
        ) U_FC1 (
          .clk        (clk),
          .rst_n      (rst_n),
          .s_valid    (c5_valid),
          .s_ch_idx   (c5_ch),
          .s_pix      (c5_pix),
          .s_vec_valid(c5_vec_valid),
          .in_weights (w_slice),
          .bias       (b_slice),
          .valid_out  (v1),
          .out        (y1)
        );

        assign fc1_valids[fn] = v1;
        assign fc1_vec_flat[fn*OUT_BITS +: OUT_BITS] = y1;
      end
    endgenerate

    // FC1 -> FC2 shift (optional)
    wire signed [FC120_OUT*OUT_BITS-1:0] fc1_shr_flat;
    genvar si;
    generate
      for (si=0; si<FC120_OUT; si=si+1) begin : G_FC1_TO_FC2_SHR
        wire signed [OUT_BITS-1:0] d = fc1_vec_flat[si*OUT_BITS +: OUT_BITS];
        assign fc1_shr_flat[si*OUT_BITS +: OUT_BITS] =
          (FC1_TO_FC2_SHIFT==0) ? d : ($signed(d) >>> FC1_TO_FC2_SHIFT);
      end
    endgenerate

    // =========================================================================
    // 7) FC2 (84 -> 10) x10 (8b weights sign-extended to 16b locally)
    // =========================================================================
    wire [FC84_OUT-1:0]                 fc2_valids;
    wire signed [FC84_OUT*OUT_BITS-1:0] fc2_logits_flat;

    genvar cls, wi;
    generate
      for (cls=0; cls<FC84_OUT; cls=cls+1) begin : G_FC2
        // w: 8 -> 16 sign-extend
        wire signed [WW_BITS*FC120_OUT-1:0]  w2_slice_8 =
            fc84_w_flat[(cls*FC120_OUT*WW_BITS) +: (FC120_OUT*WW_BITS)];
        wire signed [OUT_BITS*FC120_OUT-1:0] w2_slice_16;
        for (wi=0; wi<FC120_OUT; wi=wi+1) begin : G_WEXT
          wire signed [WW_BITS-1:0] w8 = w2_slice_8[wi*WW_BITS +: WW_BITS];
          assign w2_slice_16[wi*OUT_BITS +: OUT_BITS] =
              {{(OUT_BITS-WW_BITS){w8[WW_BITS-1]}}, w8};
        end

        wire signed [OUT_BITS-1:0] b2_slice =
            fc84_b_flat[(cls*OUT_BITS) +: OUT_BITS];

        wire v2; wire signed [OUT_BITS-1:0] y2;

        fc_84 #(
          .N         (84),
          .IN_WIDTH  (OUT_BITS),
          .W_WIDTH   (OUT_BITS),
          .BIAS_WIDTH(OUT_BITS),
          .OUT_WIDTH (OUT_BITS),
          .SHIFT_R   (10),
          .SAT_EN    (1),
          .RELU_EN   (0),
          .ACC_WIDTH (OUT_BITS + OUT_BITS + 8)
        ) U_FC2 (
          .clk        (clk),
          .rst_n      (rst_n),
          .valid_in   (fc84_vec_valid),
          .in         (fc1_shr_flat),   // 84*16
          .in_weights (w2_slice_16),    // 84*16 (sign-extended)
          .bias       (b2_slice),       // 16
          .valid_out  (v2),
          .out        (y2)
        );

        assign fc2_valids[cls] = v2;
        assign fc2_logits_flat[cls*OUT_BITS +: OUT_BITS] = y2;
      end
    endgenerate

    // gather FC1 valids to one vector-valid
    reg [FC120_OUT-1:0] fc1_seen_mask;
    reg                 fc84_vec_valid;
    wire all_neurons_valid = &(fc1_seen_mask | fc1_valids);

    always @(posedge clk) begin
        if (!rst_n) begin
            fc1_seen_mask  <= {FC120_OUT{1'b0}};
            fc84_vec_valid <= 1'b0;
        end else begin
            fc84_vec_valid <= 1'b0;
            if (c5_vec_valid) begin
                fc1_seen_mask <= {FC120_OUT{1'b0}};
            end else if (all_neurons_valid) begin
                fc84_vec_valid <= 1'b1;
                fc1_seen_mask  <= {FC120_OUT{1'b0}};
            end else if (|fc1_valids) begin
                fc1_seen_mask <= fc1_seen_mask | fc1_valids;
            end
        end
    end

    // =========================================================================
    // 8) logits out + argmax
    // =========================================================================
    reg                                 prob_valid_r;
    reg  signed [FC84_OUT*OUT_BITS-1:0] prob10_flat_r;
    integer t;
    always @(posedge clk) begin
        if (!rst_n) begin
            prob_valid_r  <= 1'b0;
            prob10_flat_r <= {FC84_OUT*OUT_BITS{1'b0}};
        end else begin
            prob_valid_r <= 1'b0;
            if (&fc2_valids) begin
                for (t=0; t<FC84_OUT; t=t+1)
                    prob10_flat_r[t*OUT_BITS +: OUT_BITS] <=
                        fc2_logits_flat[t*OUT_BITS +: OUT_BITS];
                prob_valid_r <= 1'b1;
            end
        end
    end
    assign prob10_flat = prob10_flat_r;
    assign prob_valid  = prob_valid_r;

    // argmax (>= ties go to higher index)
    reg  [3:0]  argmax_idx_c;
    reg  signed [OUT_BITS-1:0] argmax_val_c;
    integer a;
    always @* begin
        argmax_idx_c = 4'd0;
        argmax_val_c = prob10_flat_r[0*OUT_BITS +: OUT_BITS];
        for (a=1; a<FC84_OUT; a=a+1) begin
            if ($signed(prob10_flat_r[a*OUT_BITS +: OUT_BITS]) >=
                $signed(argmax_val_c)) begin
                argmax_val_c = prob10_flat_r[a*OUT_BITS +: OUT_BITS];
                argmax_idx_c = a[3:0];
            end
        end
    end

    reg  [3:0] argmax_idx_r;
    reg        pred_valid_q;
    always @(posedge clk) begin
        if (!rst_n) begin
            argmax_idx_r <= 4'd0;
            pred_valid_q <= 1'b0;
        end else begin
            pred_valid_q <= prob_valid_r;
            if (prob_valid_r) begin
                argmax_idx_r <= argmax_idx_c;
            end
        end
    end

    assign pred_digit = argmax_idx_r;
    assign pred_valid = pred_valid_q;

endmodule
