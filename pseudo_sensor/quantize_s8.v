// quantize_s8.v  (ZERO_POINT 기준 양자화, PAD=0 강제)
module quantize_s8 #(
  parameter signed [7:0] ZERO_POINT = 8'sd128
)(
  input  wire             clk,
  input  wire             srst,            // active-HIGH
  // in (valid-gated stream)
  input  wire             in_valid,
  input  wire      [7:0]  in_pixel,        // u8
  input  wire             in_line_last,
  input  wire             in_frame_last,
  input  wire             in_is_pad,       // 1 = pad 픽셀

  // out
  output reg              out_valid,
  output reg signed [7:0] out_pixel,       // s8
  output reg              out_line_last,
  output reg              out_frame_last,
  output reg              out_is_pad
);

  // 파이프 1단 (valid과 함께 정렬)
  reg             vld_ff;
  reg      [7:0]  pix_ff;
  reg             ll_ff, fl_ff;
  reg             pad_ff;

  always @(posedge clk) begin
    if (srst) begin
      vld_ff <= 1'b0;
      pix_ff <= 8'd0;
      ll_ff  <= 1'b0;
      fl_ff  <= 1'b0;
      pad_ff <= 1'b0;
    end else begin
      vld_ff <= in_valid;
      if (in_valid) begin
        pix_ff <= in_pixel;
        ll_ff  <= in_line_last;
        fl_ff  <= in_frame_last;
        pad_ff <= in_is_pad;          // ★ PAD 플래그를 valid와 함께 샘플링
      end else begin
        // valid가 0일 땐 '이전 값 유지'(버블 채우기)
        ll_ff  <= 1'b0;
        fl_ff  <= 1'b0;
        pad_ff <= 1'b0;
      end
    end
  end

  // 파이프 2단: 실제 양자화 + PAD=0 강제
  always @(posedge clk) begin
    if (srst) begin
      out_valid      <= 1'b0;
      out_pixel      <= 8'sd0;
      out_line_last  <= 1'b0;
      out_frame_last <= 1'b0;
      out_is_pad     <= 1'b0;
    end else begin
      out_valid      <= vld_ff;
      out_line_last  <= vld_ff ? ll_ff  : 1'b0;  // ★ valid로 게이트
      out_frame_last <= vld_ff ? fl_ff  : 1'b0;  // ★ valid로 게이트
      out_is_pad     <= vld_ff ? pad_ff : 1'b0;  // ★ PAD 플래그 유지

      if (vld_ff) begin
        // ★ PAD면 무조건 0. 그렇지 않으면 (u8 - ZERO_POINT)
        if (pad_ff) begin
          out_pixel <= 8'sd0;
        end else begin
          // u8 -> s9로 확장 후 ZERO_POINT 빼기 (wrap 방지용)
          out_pixel <= $signed({1'b0, pix_ff}) - $signed(ZERO_POINT);
        end
      end
    end
  end
endmodule
