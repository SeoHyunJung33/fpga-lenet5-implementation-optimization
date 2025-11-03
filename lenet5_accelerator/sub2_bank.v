`timescale 1ns/1ps

module sub2_bank #(
  parameter FM_W     = 28,  // 입력 feature map 너비/높이 (정사각형 가정)
  parameter OUT_BITS = 16,
  parameter IN_CH    = 6,   // 이 모듈은 6채널 병렬 입출력을 가정
  parameter RELU_EN  = 1
)(
  input  wire                        clk,
  input  wire                        rst_n,
  input  wire                        c1_valid,          // 좌표당 6채널 유효 신호
  input  wire [15:0]                 c1_ch,             // (병렬 입력에서는 미사용, 인터페이스 호환용)
  input  wire signed [OUT_BITS-1:0]  c1_pix1,
  input  wire signed [OUT_BITS-1:0]  c1_pix2,
  input  wire signed [OUT_BITS-1:0]  c1_pix3,
  input  wire signed [OUT_BITS-1:0]  c1_pix4,
  input  wire signed [OUT_BITS-1:0]  c1_pix5,
  input  wire signed [OUT_BITS-1:0]  c1_pix6,

  output reg                         valid_out,         // 풀링 결과 유효(odd col & odd row에서 1)
  output reg        [OUT_BITS-1:0]   pix_in1,           // 채널1 풀링 결과
  output reg        [OUT_BITS-1:0]   pix_in2,
  output reg        [OUT_BITS-1:0]   pix_in3,
  output reg        [OUT_BITS-1:0]   pix_in4,
  output reg        [OUT_BITS-1:0]   pix_in5,
  output reg        [OUT_BITS-1:0]   pix_in6
);

  // ---------- clog2 ----------
  function integer clog2;
    input integer value; integer i;
    begin
      clog2 = 0; for (i=value-1; i>0; i=i>>1) clog2 = clog2 + 1;
    end
  endfunction

  localparam COL_BITS   = (FM_W <= 2) ? 1 : clog2(FM_W);
  localparam HALF_W     = (FM_W/2);
  localparam PREV_DEPTH = IN_CH * HALF_W;

  // ---------- 좌표 카운터 ----------
  reg [COL_BITS-1:0] col, row;
  wire end_col  = (col == FM_W-1);
  wire end_row  = (row == FM_W-1);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      col <= {COL_BITS{1'b0}};
      row <= {COL_BITS{1'b0}};
    end else if (c1_valid) begin
      if (end_col) begin
        col <= {COL_BITS{1'b0}};
        row <= end_row ? {COL_BITS{1'b0}} : (row + {{(COL_BITS-1){1'b0}},1'b1});
      end else begin
        col <= col + {{(COL_BITS-1){1'b0}},1'b1};
      end
    end
  end

  // ---------- 짝/홀 ----------
  wire col_even = ~col[0];
  wire row_even = ~row[0];

  // 2x2 블록의 가로 pair index (0..HALF_W-1)
  wire [COL_BITS-2:0] pair_idx = col[COL_BITS-1:1]; // == col >> 1

  // ---------- ReLU ----------
  function signed [OUT_BITS-1:0] relu;
    input signed [OUT_BITS-1:0] x;
    begin
      if (RELU_EN)
        relu = x[OUT_BITS-1] ? {OUT_BITS{1'b0}} : x;
      else
        relu = x;
    end
  endfunction

  // ---------- max ----------
  function signed [OUT_BITS-1:0] smax2;
    input signed [OUT_BITS-1:0] a,b;
    begin smax2 = (a >= b) ? a : b; end
  endfunction

  // ---------- 채널별 파이프(수평/수직 최대 비교용) ----------
  // even_hold[ch]    : 수평짝의 첫 픽셀(짝수 col) ReLU 저장
  // hmax_cur[ch]     : 수평 2개 중 최대값 (짝수/홀수 col 묶음)
  // prev_row_hmax    : 바로 위 행(짝수 row)의 수평최대들을 보관 (채널×HALF_W 개)
  // pmax_buf[ch]     : 최종 2x2 블록 최대 (짝수/홀수 row 묶음까지 완료)
  reg signed [OUT_BITS-1:0] even_hold    [0:IN_CH-1];
  reg signed [OUT_BITS-1:0] hmax_cur     [0:IN_CH-1];
  reg signed [OUT_BITS-1:0] prev_row_hmax[0:PREV_DEPTH-1];
  reg signed [OUT_BITS-1:0] pmax_buf     [0:IN_CH-1];

  // 입력을 배열로 다루기
  wire signed [OUT_BITS-1:0] in_ch [0:IN_CH-1];
  assign in_ch[0] = c1_pix1;
  assign in_ch[1] = c1_pix2;
  assign in_ch[2] = c1_pix3;
  assign in_ch[3] = c1_pix4;
  assign in_ch[4] = c1_pix5;
  assign in_ch[5] = c1_pix6;

  integer i;
  integer idx;  // prev_row_hmax 인덱스

  // ---------- 본 연산 ----------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i=0; i<IN_CH; i=i+1) begin
        even_hold[i] <= {OUT_BITS{1'b0}};
        hmax_cur[i]  <= {OUT_BITS{1'b0}};
        pmax_buf[i]  <= {OUT_BITS{1'b0}};
      end
      for (i=0; i<PREV_DEPTH; i=i+1) prev_row_hmax[i] <= {OUT_BITS{1'b0}};
      valid_out <= 1'b0;
      {pix_in1,pix_in2,pix_in3,pix_in4,pix_in5,pix_in6} <= {6*OUT_BITS{1'b0}};
    end else begin
      valid_out <= 1'b0;

      if (c1_valid) begin
        // 채널별로 동시 처리
        for (i=0; i<IN_CH; i=i+1) begin
          if (col_even) begin
            // 가로 짝의 첫 픽셀: ReLU 저장
            even_hold[i] <= relu(in_ch[i]);
          end else begin
            // 가로 짝의 둘째 픽셀: 수평 최대
            hmax_cur[i]  <= smax2(even_hold[i], relu(in_ch[i]));

            // 세로 처리
            idx = i*HALF_W + pair_idx; // 채널 i의 pair index
            if (row_even) begin
              // 짝수 행: 수평최대를 보관
              prev_row_hmax[idx] <= smax2(even_hold[i], relu(in_ch[i]));
            end else begin
              // 홀수 행: 위 행의 수평최대와 현재 수평최대의 최대 → 2x2 max
              pmax_buf[i] <= smax2(prev_row_hmax[idx], smax2(even_hold[i], relu(in_ch[i])));
            end
          end
        end

        // 2x2 블록이 완성되는 지점에서 결과 배출 (col, row 모두 홀수일 때)
        if (!col_even && !row_even) begin
          valid_out <= 1'b1;
          // 채널 순서대로 출력 고정
          pix_in1 <= pmax_buf[0];
          pix_in2 <= pmax_buf[1];
          pix_in3 <= pmax_buf[2];
          pix_in4 <= pmax_buf[3];
          pix_in5 <= pmax_buf[4];
          pix_in6 <= pmax_buf[5];
        end
      end
    end
  end

endmodule