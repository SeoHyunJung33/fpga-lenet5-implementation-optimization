// -----------------------------------------------------------------------------
// zeropad_rows.v
//  - 입력(mp) 한 프레임( W x HIN )을 먼저 캡처하면서 mp_valid 펄스 간격을 계측
//  - 그 템포(slot_period)로 TOP 4줄 → 캡처본 재생 24줄 → BOT 4줄을
//    "mp_valid처럼 1clk 펄스"로 내보냄 (라인 템포 완전 일치)
//  - 출력 라인/프레임 경계도 slot_period 기반으로 정확히 1clk 펄스
//  - 다음 프레임은 다시 CAP → TOP → PAY → BOT 순환 (1-프레임 레이턴시)
// -----------------------------------------------------------------------------
`timescale 1ns/1ps
module zeropad_rows #(
  parameter integer W   = 32,
  parameter integer HIN = 24,
  parameter integer PAD = 4
)(
  input  wire       clk,
  input  wire       srst,            // active-HIGH

  // 입력: mp 스테이지 출력 (1픽셀/펄스)
  input  wire       in_valid,        // mp_valid
  input  wire [7:0] in_pixel,        // mp_pixel
  input  wire       in_line_last,    // mp_line_last (한 줄 마지막 픽셀에서 1clk)

  // 출력: 패딩 포함 (W x (HIN+2*PAD))
  output reg        out_valid,
  output reg [7:0]  out_pixel,
  output reg        out_line_last,   // 한 줄 마지막 픽셀에서 1clk
  output reg        out_frame_last,  // 프레임 마지막 픽셀에서 1clk
  output reg        out_is_pad       // 패딩 구간(Top/Bot)에서 1
);

  // --------------------------
  // 유틸: 정수 clog2 (Verilog-2001)
  // --------------------------
  function integer CLOG2;
    input integer x;
    integer i;
    begin
      i = 0;
      while ((1<<i) < x) i = i + 1;
      CLOG2 = i;
    end
  endfunction

  // --------------------------
  // 프레임 버퍼 (W*HIN 바이트)
  // --------------------------
  localparam integer DEPTH = W*HIN;
  localparam integer A_W   = CLOG2(DEPTH);

  reg [7:0] fb [0:DEPTH-1];

  reg [A_W-1:0] wr_addr;      // CAP에서 사용
  reg [A_W-1:0] rd_addr;      // PAY에서 사용

  // --------------------------
  // 템포 계측 (mp_valid 펄스 간격)
  // --------------------------
  reg        iv_d;
  wire       iv_rise = in_valid & ~iv_d;

  reg        ill_d;
  wire       ill_rise = in_line_last & ~ill_d;

  reg [15:0] slot_cnt;
  reg [15:0] slot_period;     // 동일 라인 내 mp_valid 간격(클럭수)

  // --------------------------
  // 상태/카운터
  // --------------------------
  localparam [2:0] S_CAP = 3'd0,  // 입력 프레임 캡처 + 템포 계측
                   S_TOP = 3'd1,  // TOP PAD  (PAD lines)
                   S_PAY = 3'd2,  // PAYLOAD  (HIN lines)
                   S_BOT = 3'd3;  // BOTTOM PAD (PAD lines)

  reg [2:0] st;

  // PAD/재생 공통 진행(슬롯 단위)
  reg [9:0] px_in_line;       // 0..W-1 (슬롯 단위 증가)
  reg [6:0] lines_done;       // 진행한 라인 수 (Top/PAY/Bot 각각에서 사용)

  // PAD/재생용 슬롯 틱 (mp_valid 템포와 동일한 간격의 1clk 펄스)
  reg  [15:0] gen_cnt;
  wire        have_tempo = (slot_period != 16'd0);
  wire        slot_tick  = have_tempo && (gen_cnt == slot_period - 1);

  // --------------------------
  // 순서 로직
  // --------------------------
  integer i;
  always @(posedge clk) begin
    if (srst) begin
      // 입력측 edge 검출기
      iv_d        <= 1'b0;
      ill_d       <= 1'b0;

      // 템포 계측
      slot_cnt    <= 16'd0;
      slot_period <= 16'd0;

      // 프레임 버퍼 주소
      wr_addr     <= {A_W{1'b0}};
      rd_addr     <= {A_W{1'b0}};

      // 출력/상태 초기화
      out_valid      <= 1'b0;
      out_pixel      <= 8'd0;
      out_line_last  <= 1'b0;
      out_frame_last <= 1'b0;
      out_is_pad     <= 1'b0;

      st          <= S_CAP;
      px_in_line  <= 10'd0;
      lines_done  <= 7'd0;
      gen_cnt     <= 16'd0;

    end else begin
      // edge 검출기 갱신
      iv_d  <= in_valid;
      ill_d <= in_line_last;

      // 기본 출력 디폴트
      out_valid      <= 1'b0;
      out_line_last  <= 1'b0;
      out_frame_last <= 1'b0;
      out_is_pad     <= 1'b0;

      //------------------------------------------------------
      // 템포(슬롯 간격) 계측: 같은 라인 내에서 in_valid 상승 간격을 계측
      //------------------------------------------------------
      slot_cnt <= slot_cnt + 16'd1;
      if (iv_rise) begin
        // 첫 펄스 후부터 간격 측정
        if (slot_period == 16'd0)
          slot_period <= slot_cnt;     // 초기값
        else
          slot_period <= slot_cnt;     // 필요시 이동평균 등으로 안정화 가능
        slot_cnt <= 16'd1;             // 현재 펄스부터 다시 계측 시작
      end
      if (ill_rise) begin
        slot_cnt <= 16'd0;             // 라인 넘길 때 카운터 재시작
      end

      //------------------------------------------------------
      // PAD/재생용 슬롯 틱 발생기
      //------------------------------------------------------
      if (st==S_TOP || st==S_PAY || st==S_BOT) begin
        if (have_tempo) begin
          gen_cnt <= slot_tick ? 16'd0 : (gen_cnt + 16'd1);
        end else begin
          gen_cnt <= 16'd0; // 템포 미확정이면 대기
        end
      end else begin
        gen_cnt <= 16'd0;   // CAP에서는 틱 카운터 정지
      end

      //------------------------------------------------------
      // 상태기계
      //------------------------------------------------------
      case (st)
        // ====================================================
        // 1) CAPTURE (입력 프레임 전체 저장 + 템포 계측)
        // ====================================================
        S_CAP: begin
          // 입력 픽셀은 in_valid 펄스 때만 1개씩 들어온다.
          if (in_valid) begin
            fb[wr_addr] <= in_pixel;
            wr_addr     <= wr_addr + {{(A_W-1){1'b0}},1'b1};
          end

          // 프레임 끝 판단: 마지막 줄의 마지막 픽셀에서 in_line_last가 1clk
          // (TB/상위에서 mp_frame_last가 있다면 그것을 활용해도 됨)
          if (ill_rise && (wr_addr == DEPTH-1)) begin
            // 캡처 완료 → TOP PAD로 전이 (템포가 계측되어 있어야 함)
            st         <= S_TOP;
            rd_addr    <= {A_W{1'b0}};
            px_in_line <= 10'd0;
            lines_done <= 7'd0;
          end
        end

        // ====================================================
        // 2) TOP PADDING (PAD lines)
        // ====================================================
        S_TOP: begin
          if (slot_tick) begin
            out_valid  <= 1'b1;
            out_is_pad <= 1'b1;
            out_pixel  <= 8'd0;

            if (px_in_line == W-1) begin
              out_line_last <= 1'b1;
              px_in_line    <= 10'd0;
              if (lines_done == PAD-1) begin
                st         <= S_PAY;
                lines_done <= 7'd0;
              end else begin
                lines_done <= lines_done + 7'd1;
              end
            end else begin
              px_in_line <= px_in_line + 10'd1;
            end
          end
        end

        // ====================================================
        // 3) PAYLOAD REPLAY (HIN lines)
        // ====================================================
        S_PAY: begin
          if (slot_tick) begin
            out_valid  <= 1'b1;
            out_is_pad <= 1'b0;
            out_pixel  <= fb[rd_addr];
            rd_addr    <= rd_addr + {{(A_W-1){1'b0}},1'b1};

            if (px_in_line == W-1) begin
              out_line_last <= 1'b1;
              px_in_line    <= 10'd0;
              if (lines_done == HIN-1) begin
                st         <= S_BOT;
                lines_done <= 7'd0;
              end else begin
                lines_done <= lines_done + 7'd1;
              end
            end else begin
              px_in_line <= px_in_line + 10'd1;
            end
          end
        end

        // ====================================================
        // 4) BOTTOM PADDING (PAD lines)
        // ====================================================
        S_BOT: begin
          if (slot_tick) begin
            out_valid  <= 1'b1;
            out_is_pad <= 1'b1;
            out_pixel  <= 8'd0;

            if (px_in_line == W-1) begin
              out_line_last <= 1'b1;
              px_in_line    <= 10'd0;
              if (lines_done == PAD-1) begin
                out_frame_last <= 1'b1;   // 프레임의 마지막 픽셀
                // 다음 프레임 준비 (다시 CAP으로)
                st         <= S_CAP;
                wr_addr    <= {A_W{1'b0}};
                rd_addr    <= {A_W{1'b0}};
                lines_done <= 7'd0;
              end else begin
                lines_done <= lines_done + 7'd1;
              end
            end else begin
              px_in_line <= px_in_line + 10'd1;
            end
          end
        end

        default: st <= S_CAP;
      endcase
    end
  end

endmodule


