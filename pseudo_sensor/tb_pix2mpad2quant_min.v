`timescale 1ns/1ps

module tb_pix2mpad2quant_min;

  // ----------------------------
  // 기본 파라미터 (프로젝트 값과 일치)
  // ----------------------------
  localparam integer H_ACTIVE   = 640;
  localparam integer V_ACTIVE   = 480;
  localparam integer F_SIZE     = H_ACTIVE*V_ACTIVE; // 307200
  localparam integer ADDR_FRAME = 19;                // 0..(F_SIZE-1) 19bit
  localparam integer DATA_WIDTH = 8;

  // MaxPool/Pad 파라미터
  localparam integer BLK      = 20;                  // 20x20 pooling
  localparam integer OUT_W    = H_ACTIVE/BLK;        // 32
  localparam integer OUT_H    = V_ACTIVE/BLK;        // 24
  localparam integer PAD      = 4;                   // zeropad 위/아래 4줄
  localparam integer OUT_W_PAD= OUT_W;               // 32
  localparam integer OUT_H_PAD= OUT_H + 2*PAD;       // 32

  // ----------------------------
  // 클록/리셋
  // ----------------------------
  reg  clk_in_100 = 1'b0;
  always #5 clk_in_100 = ~clk_in_100;  // 100 MHz

  reg  arst_n;
  initial begin
    arst_n = 1'b0;               // active-LOW
    repeat (20) @(posedge clk_in_100);
    arst_n = 1'b1;
  end

  wire srst = ~arst_n;           // pad/quantize는 active-HIGH

  // ----------------------------
  // vga_pixel_top (ROM→dual BRAM 포함)
  // ----------------------------
  wire        vga_hs, vga_vs, vga_de;
  wire [7:0]  vga_pixel;

  reg  [ADDR_FRAME-1:0] addr_c_drv = {ADDR_FRAME{1'b0}};
  wire [ADDR_FRAME-1:0] addr_c_i    = addr_c_drv;
  wire [DATA_WIDTH-1:0] dout_c_o;

  wire [3:0] image_num_c_o;
  wire       swap_c_o;

  vga_pixel_top #(
    .H_ACTIVE   (H_ACTIVE),
    .V_ACTIVE   (V_ACTIVE),
    .F_SIZE     (F_SIZE),
    .ADDR_FRAME (ADDR_FRAME),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_pix (
    .clk_in_100 (clk_in_100),
    .arst_n     (arst_n),

    .hsync      (vga_hs),
    .vsync      (vga_vs),
    .de_out     (vga_de),
    .vga_pixel  (vga_pixel),

    .addr_c_i   (addr_c_i),
    .dout_c_o   (dout_c_o),
    .image_num_c_o (image_num_c_o),
    .swap_c_o   (swap_c_o)
  );

  // ----------------------------
  // CORE 측 BRAM 읽기 → MaxPool 입력 스트림 생성
  // (READ_LAT = 1 가정. SystemVerilog 금지)
  // ----------------------------
  reg         reading;
  reg [31:0]  iaddr;
  reg         have_data;
  reg         in_valid;
  reg  [7:0]  in_pixel;

  // Vivado Verilog에서는 (iaddr+1)[…] 금지 → 임시 변수로 계산
  wire [31:0] nxt_addr = iaddr + 32'd1;

  // frame 시작을 swap_c_o로 삼음
  reg  swap_q;
  wire swap_rise = (swap_c_o & ~swap_q);
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) swap_q <= 1'b0;
    else         swap_q <= swap_c_o;
  end

  // enable
  reg en = 1'b1;
  reg en_mp = 1'b1;

  // READ_LAT=1 타이밍에 맞춰 addr→1clk 뒤 data 사용
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      reading    <= 1'b0;
      iaddr      <= 32'd0;
      addr_c_drv <= {ADDR_FRAME{1'b0}};
      have_data  <= 1'b0;
      in_valid   <= 1'b0;
      in_pixel   <= 8'd0;
    end else begin
      // 기본값
      in_valid  <= 1'b0;
      have_data <= 1'b0;

      // 프레임 전환 직후에 읽기 시작 (약간 여유 1~2clk 둬도 OK)
      if (!reading && swap_rise) begin
        reading    <= 1'b1;
        iaddr      <= 32'd0;
        addr_c_drv <= {ADDR_FRAME{1'b0}}; // 첫 주소
        have_data  <= 1'b0;               // 첫 data는 다음 사이클부터
      end
      else if (reading) begin
        // 이전 사이클 addr에 대한 data가 지금 들어옴
        if (have_data) begin
          in_valid <= 1'b1;
          in_pixel <= dout_c_o;   // 정렬: addr→1clk data
        end

        // 다음 주소 드라이브
        if (iaddr < F_SIZE-1) begin
          iaddr      <= nxt_addr;
          addr_c_drv <= nxt_addr[ADDR_FRAME-1:0];
          have_data  <= 1'b1;
        end else begin
          // 마지막 샘플 처리 후 종료
          reading   <= 1'b0;
          have_data <= 1'b0;
        end
      end
    end
  end

  // ----------------------------
  // Maxpool 20x20
  // ----------------------------
  wire        mp_valid;
  wire [7:0]  mp_pixel;
  wire        mp_line_last;
  wire        mp_frame_last;

  maxpool20x20 #(
    .IN_W (H_ACTIVE),
    .IN_H (V_ACTIVE),
    .BLK  (BLK)
  ) u_mp (
    .clk         (clk_in_100),
    .srst        (srst),
    .en          (en),
    .en_mp       (en_mp),
    .in_valid    (in_valid),
    .in_pixel    (in_pixel),
    .out_valid   (mp_valid),
    .out_pixel   (mp_pixel),
    .line_last   (mp_line_last),
    .frame_last  (mp_frame_last)
  );
  
    // === MP→ZP 정렬 래퍼 (1clk) ===
  reg        mp_valid_d, mp_line_last_d, mp_frame_last_d;
  reg [7:0]  mp_pixel_d;

  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      mp_valid_d      <= 1'b0;
      mp_line_last_d  <= 1'b0;
      mp_frame_last_d <= 1'b0;
      mp_pixel_d      <= 8'd0;
    end else begin
      // mp_valid 펄스와 mp_pixel/line_last/frame_last를 같은 싸이클로 정렬
      mp_valid_d      <= mp_valid;
      mp_line_last_d  <= mp_line_last;
      mp_frame_last_d <= mp_frame_last;
      mp_pixel_d      <= mp_pixel;
    end
  end

  // ----------------------------
  // Zeropad (32x24 → 32x32)
  // ----------------------------
  wire        zp_valid;
  wire [7:0]  zp_pixel;
  wire        zp_line_last;
  wire        zp_frame_last;
  wire        zp_is_pad;

  zeropad_rows #(
    .W   (OUT_W),
    .HIN (OUT_H),
    .PAD (PAD)
  ) u_zp (
    .clk           (clk_in_100),
    .srst          (srst),
    .in_valid      (mp_valid_d),       // ★ 정렬된 신호 사용
    .in_pixel      (mp_pixel_d),       // ★
    .in_line_last  (mp_line_last_d),   // ★
    .out_valid     (zp_valid),
    .out_pixel     (zp_pixel),
    .out_line_last (zp_line_last),
    .out_frame_last(zp_frame_last),
    .out_is_pad    (zp_is_pad)
  );

  // ----------------------------
  // Quantize (ZERO_POINT=128)
  // ----------------------------
  wire              q_valid;
  wire signed [7:0] q_pixel;
  wire              q_line_last;
  wire              q_frame_last;

  quantize_s8 #(
    .ZERO_POINT (8'd128)
  ) u_q (
    .clk           (clk_in_100),
    .srst          (srst),
    .in_valid      (zp_valid),
    .in_pixel      (zp_pixel),
    .in_line_last  (zp_line_last),
    .in_frame_last (zp_frame_last),
    .in_is_pad     (zp_is_pad),
    .out_valid     (q_valid),
    .out_pixel     (q_pixel),
    .out_line_last (q_line_last),
    .out_frame_last(q_frame_last)
  );

  // ----------------------------
  // 카운터 & 간단 체크 (필수 신호만)
  // ----------------------------
  integer mp_cnt,  mp_lines,  mp_frames;
  integer zp_cnt,  zp_lines,  zp_frames;
  integer q_cnt,   q_lines,   q_frames;

  // MaxPool 카운팅
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      mp_cnt<=0; mp_lines<=0; mp_frames<=0;
    end else begin
      if (mp_valid)      mp_cnt   <= mp_cnt + 1;
      if (mp_line_last)  mp_lines <= mp_lines + 1;
      if (mp_frame_last) mp_frames<= mp_frames + 1;
    end
  end

  // Zeropad 카운팅
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      zp_cnt<=0; zp_lines<=0; zp_frames<=0;
    end else begin
      if (zp_valid)      zp_cnt   <= zp_cnt + 1;
      if (zp_line_last)  zp_lines <= zp_lines + 1;
      if (zp_frame_last) zp_frames<= zp_frames + 1;
    end
  end

  // Quantize 카운팅 + 간단 데이터 체크(패딩이면 0이어야 함)
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      q_cnt<=0; q_lines<=0; q_frames<=0;
    end else begin
      if (q_valid) begin
        q_cnt <= q_cnt + 1;
        // pad 영역이면 양자화 결과는 반드시 0
        if (zp_is_pad && (q_pixel !== 8'sd0))
          $display("[%0t] **ERROR** pad pixel not zero! q=%0d", $time, q_pixel);
      end
      if (q_line_last)  q_lines  <= q_lines + 1;
      if (q_frame_last) q_frames <= q_frames + 1;
    end
  end

  // ----------------------------
  // 프레임별 요약: swap_rise 이후 일정 시간 관찰
  // ----------------------------
  task print_frame_summary(input integer idx);
    begin
      $display("FRAME#%0d MP : out=%0d (exp %0d)  lines=%0d (exp 24)",
               idx, mp_cnt, OUT_W*OUT_H, mp_lines);
      $display("FRAME#%0d ZP : out=%0d (exp %0d)  lines=%0d (exp 32)",
               idx, zp_cnt, OUT_W_PAD*OUT_H_PAD, zp_lines);
      $display("FRAME#%0d  Q : out=%0d (exp %0d)  lines=%0d (exp 32)",
               idx, q_cnt,  OUT_W_PAD*OUT_H_PAD, q_lines);
    end
  endtask

  integer seen;
  initial begin
    seen = 0;
    // reset release 대기
    wait (arst_n==1'b1);
    // 두 프레임만 확인
    repeat (2) begin
      // 프레임 전환 대기
      @(posedge clk_in_100);
      wait (swap_rise==1'b1);

      // 카운터 리셋
      mp_cnt=0; mp_lines=0; mp_frames=0;
      zp_cnt=0; zp_lines=0; zp_frames=0;
      q_cnt =0; q_lines =0; q_frames=0;

      // 프레임 충분히 관찰 (대략 6ms면 넉넉)
      repeat (600000) @(posedge clk_in_100);

      print_frame_summary(seen);
      seen = seen + 1;
    end

    $display("SUMMARY: checked %0d frames. Done.", seen);
    $finish;
  end

endmodule


