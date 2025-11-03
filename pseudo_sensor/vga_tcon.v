`timescale 1ns/1ps
// ============================================================================
// VGA Timing Controller
// - px[9:0], py[8:0] : Active 영역에서의 유효 좌표(0..W-1 / 0..H-1)
// - de               : Active video 구간
// - hsync, vsync     : 폴라리티 선택 가능(기본 negative)
// - sof              : 프레임 시작 1클럭 펄스 (h_cnt==0 && v_cnt==0)
// - eof              : 프레임 끝  1클럭 펄스 (h_cnt==H_TOTAL-1 && v_cnt==V_TOTAL-1)
// ============================================================================
module vga_tcon #(
  // Active 해상도
  parameter integer H_ACTIVE   = 640,
  parameter integer V_ACTIVE   = 480,
  // Front porch / Sync / Back porch
  parameter integer H_FP       = 16,
  parameter integer H_SYNC     = 96,
  parameter integer H_BP       = 48,
  parameter integer V_FP       = 10,
  parameter integer V_SYNC     = 2,
  parameter integer V_BP       = 33,
  // Sync polarity (1=negative, 0=positive)
  parameter HSYNC_NEG          = 1,
  parameter VSYNC_NEG          = 1
)(
  input  wire        p_clk,
  input  wire        arst_p_n,   // active-LOW async reset

  output reg  [9:0]  px,         // 0..H_ACTIVE-1
  output reg  [8:0]  py,         // 0..V_ACTIVE-1
  output wire        de,
  output wire        hsync,
  output wire        vsync,
  output wire        sof,        // 1clk @ frame start
  output wire        eof         // 1clk @ frame end
);

  // --------------------------------------------------------------------------
  // Counters
  // --------------------------------------------------------------------------
  localparam integer H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
  localparam integer V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;

  // 폭은 여유 있게 지정 (640x480 기준 h: 0..799, v: 0..524)
  reg [10:0] h_cnt;
  reg [9:0]  v_cnt;

  wire h_line_last  = (h_cnt == H_TOTAL-1);
  wire v_frame_last = (v_cnt == V_TOTAL-1);

  always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
      h_cnt <= 11'd0;
    end else begin
      if (h_line_last) h_cnt <= 11'd0;
      else             h_cnt <= h_cnt + 11'd1;
    end
  end

  always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
      v_cnt <= 10'd0;
    end else if (h_line_last) begin
      if (v_frame_last) v_cnt <= 10'd0;
      else              v_cnt <= v_cnt + 10'd1;
    end
  end

  // --------------------------------------------------------------------------
  // DE / Active coordinates
  // --------------------------------------------------------------------------
  wire h_active = (h_cnt < H_ACTIVE);
  wire v_active = (v_cnt < V_ACTIVE);
  assign de = h_active & v_active;

  always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
      px <= 10'd0;
      py <= 9'd0;
    end else begin
      if (de) begin
        px <= h_cnt[9:0];
        py <= v_cnt[8:0];
      end else begin
        px <= 10'd0;
        py <= 9'd0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // HSYNC / VSYNC (raw → polarity 적용)
  // --------------------------------------------------------------------------
  wire hsync_raw = (h_cnt >= (H_ACTIVE + H_FP)) &&
                   (h_cnt <  (H_ACTIVE + H_FP + H_SYNC));
  wire vsync_raw = (v_cnt >= (V_ACTIVE + V_FP)) &&
                   (v_cnt <  (V_ACTIVE + V_FP + V_SYNC));

  assign hsync = HSYNC_NEG ? ~hsync_raw : hsync_raw;
  assign vsync = VSYNC_NEG ? ~vsync_raw : vsync_raw;

  // --------------------------------------------------------------------------
  // SOF / EOF (1clk pulse)
  // --------------------------------------------------------------------------
  assign sof = (h_cnt == 0) && (v_cnt == 0);
  assign eof = h_line_last && v_frame_last;

endmodule
