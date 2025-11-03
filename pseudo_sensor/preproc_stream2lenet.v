// 전처리 → LeNet 어댑터
// q_* 스트림에서 프레임당 1클럭 start 펄스와(옵션) 스트림 valid/pixel을 제공
module preproc_stream2lenet #(
  parameter integer PIX_BITS = 8     // LeNet 입력 비트수
)(
  input  wire                    clk,
  input  wire                    srst,          // active-HIGH

  // from quantize_s8
  input  wire                    q_valid,
  input  wire                    q_line_last,
  input  wire                    q_frame_last,
  input  wire signed [7:0]       q_pixel,       // quantize 출력이 8비트 signed

  // to LeNet (둘 다 내보냄: 시스템에서 선택해 연결)
  output wire                    lenet_start,   // 프레임당 1클럭 start 펄스
  output wire                    lenet_v,       // per-pixel valid (q_valid 그대로)
  output wire signed [PIX_BITS-1:0] lenet_pix   // 픽셀 데이터
);

  // q_valid 라이징 검출 + 프레임당 1회만 허용
  reg qv_d, armed;
  always @(posedge clk) begin
    if (srst) begin
      qv_d  <= 1'b0;
      armed <= 1'b1;
    end else begin
      qv_d <= q_valid;

      // 프레임 끝에서 다음 프레임을 위해 무장
      if (q_valid && q_frame_last)
        armed <= 1'b1;
      // 프레임의 첫 라이징에서 1회 쏘고 해제
      else if (q_valid && ~qv_d && armed)
        armed <= 1'b0;
    end
  end

  assign lenet_start = (q_valid & ~qv_d) & armed;

  // 스트림 경로는 그대로 전달
  assign lenet_v = q_valid;

  // 비트폭 캐스팅 (PIX_BITS != 8 지원)
  generate
    if (PIX_BITS == 8) begin : g_pix8
      assign lenet_pix = q_pixel;
    end else if (PIX_BITS > 8) begin : g_ext
      assign lenet_pix = {{(PIX_BITS-8){q_pixel[7]}}, q_pixel}; // sign-extend
    end else begin : g_trunc
      // 상위비트 유지, 하위 PIX_BITS만 전달 (부호 유지)
      assign lenet_pix = q_pixel[7 -: PIX_BITS];
    end
  endgenerate

endmodule
