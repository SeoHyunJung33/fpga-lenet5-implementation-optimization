`timescale 1ns/1ps
// FULL PATH TB (ROM?Üídual BRAM?ÜíMaxPool 20x20?ÜíZeroPad rows(¬±4)?ÜíQuantize s8)
// - ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ: vga_pixel_top.swap_c_o ?ÉÅ?äπ?ó£Ïß?
// - Ï£? Í≤?Ï¶?: pad ?ñâ/?éò?ù¥Î°úÎìú ?ñâ Íµ¨Î∂Ñ, ?ùº?ù∏/?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ, Ï¥? ?îΩ???àò Ïπ¥Ïö¥?ä∏
module tb_pix2mpad2quant_min4;

  // -----------------------------
  // Project params (VGA 640x480)
  // -----------------------------
  localparam integer H_ACTIVE    = 640;
  localparam integer V_ACTIVE    = 480;
  localparam integer F_SIZE      = H_ACTIVE * V_ACTIVE; // 307200
  localparam integer ADDR_FRAME  = 19;
  localparam integer DATA_WIDTH  = 8;

  // MaxPool/ZeroPad params
  localparam integer BLK         = 20;                  // 20x20
  localparam integer OUT_W       = H_ACTIVE/BLK;        // 32
  localparam integer OUT_H       = V_ACTIVE/BLK;        // 24
  localparam integer PAD         = 4;                   // top/bottom rows
  localparam integer OUT_W_PAD   = OUT_W;               // 32
  localparam integer OUT_H_PAD   = OUT_H + 2*PAD;       // 32

  // ?ãúÎÆ? ???ûÑ?ïÑ?õÉ(?îÑ?†à?ûÑ Í∏∞Îã§Î¶?): VGA 33ms/frame ?Üí ?ó¨?ú† 60ms
  localparam integer WAIT_SWAP_TIMEOUT_NS = 60_000_000;

  // -----------------------------
  // Clocks & reset
  // -----------------------------
  reg clk_in_100 = 1'b0;
  always #5 clk_in_100 = ~clk_in_100; // 100 MHz

  reg arst_n;
  initial begin
    arst_n = 1'b0;                 // active-LOW reset
    repeat (20) @(posedge clk_in_100);
    arst_n = 1'b1;
  end
  wire srst = ~arst_n;             // ?ùºÎ∂? Î™®Îìà active-HIGH

  // -----------------------------
  // DUT: vga_pixel_top (ROM?Üídual BRAM)
  // -----------------------------
  wire        vga_hs, vga_vs, vga_de;
  wire [7:0]  vga_pixel;

  reg  [ADDR_FRAME-1:0] addr_c_drv = {ADDR_FRAME{1'b0}};
  wire [ADDR_FRAME-1:0] addr_c_i   = addr_c_drv;
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
    .clk_in_100    (clk_in_100),
    .arst_n        (arst_n),
    .hsync         (vga_hs),
    .vsync         (vga_vs),
    .de_out        (vga_de),
    .vga_pixel     (vga_pixel),
    .addr_c_i      (addr_c_i),
    .dout_c_o      (dout_c_o),
    .image_num_c_o (image_num_c_o),
    .swap_c_o      (swap_c_o)
  );

  // -----------------------------
  // CORE-side BRAM Port-C reader
  //   - 1clk sync read ?Üí have_dataÎ°? Î≥¥Ï†ï
  //   - ?îÑ?†à?ûÑ ?ïà?†ï ?úÑ?ï¥ swap_rise ?õÑ ?ùΩÍ∏? ?ãú?ûë
  // -----------------------------
  reg         reading;
  reg [31:0]  iaddr;
  reg         have_data;
  reg         in_valid;
  reg  [7:0]  in_pixel;
  wire [31:0] nxt_addr = iaddr + 32'd1;

  reg  swap_q;
  always @(posedge clk_in_100 or negedge arst_n)
    if (!arst_n) swap_q <= 1'b0;
    else         swap_q <= swap_c_o;
  wire swap_rise = (swap_c_o & ~swap_q);

  // enable
  reg en    = 1'b1;
  reg en_mp = 1'b1;

  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      reading    <= 1'b0;
      iaddr      <= 32'd0;
      addr_c_drv <= {ADDR_FRAME{1'b0}};
      have_data  <= 1'b0;
      in_valid   <= 1'b0;
      in_pixel   <= 8'd0;
    end else begin
      in_valid  <= 1'b0;
      have_data <= 1'b0;

      if (!reading && swap_rise) begin
        reading    <= 1'b1;
        iaddr      <= 32'd0;
        addr_c_drv <= {ADDR_FRAME{1'b0}};
      end
      else if (reading) begin
        if (have_data) begin
          in_valid <= 1'b1;
          in_pixel <= dout_c_o;
        end
        if (iaddr < F_SIZE-1) begin
          iaddr      <= nxt_addr;
          addr_c_drv <= nxt_addr[ADDR_FRAME-1:0];
          have_data  <= 1'b1;
        end else begin
          reading   <= 1'b0;  // last sample handled
          have_data <= 1'b0;
        end
      end
    end
  end

  // -----------------------------
  // MaxPool 20x20
  // -----------------------------
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

  // -----------------------------
  // ZeroPad rows (top/bottom 4)
  // -----------------------------
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
    .clk            (clk_in_100),
    .srst           (srst),
    .in_valid       (mp_valid),
    .in_pixel       (mp_pixel),
    .in_line_last   (mp_line_last),

    .out_valid      (zp_valid),
    .out_pixel      (zp_pixel),
    .out_line_last  (zp_line_last),
    .out_frame_last (zp_frame_last),
    .out_is_pad     (zp_is_pad)
  );

  // -----------------------------
  // Quantize s8 (ZERO_POINT=128)
  // -----------------------------
  wire              q_valid;
  wire signed [7:0] q_pixel;
  wire              q_line_last;
  wire              q_frame_last;
  wire              q_is_pad;

  quantize_s8 #(
    .ZERO_POINT (8'd128)
  ) u_q (
    .clk            (clk_in_100),
    .srst           (srst),
    .in_valid       (zp_valid),
    .in_pixel       (zp_pixel),
    .in_line_last   (zp_line_last),
    .in_frame_last  (zp_frame_last),
    .in_is_pad      (zp_is_pad),
    .out_valid      (q_valid),
    .out_pixel      (q_pixel),
    .out_line_last  (q_line_last),
    .out_frame_last (q_frame_last),
    .out_is_pad     (q_is_pad)
  );

  // =========================================================
  //                    SELF-CHECKERS
  // =========================================================
  // Ïπ¥Ïö¥?Ñ∞
  integer mp_cnt, mp_lines;
  integer zp_cnt, zp_lines;
  integer q_cnt,  q_lines;
  integer pad_errs;

  // ?ùº?ù∏ ?Ç¥ ?Éò?îå Ïπ¥Ïö¥?Ñ∞ (q Í≤ΩÎ°ú Í∏∞Ï?)
  integer q_line_pix;
  // ?îÑ?†à?ûÑ ?Ç¥ ?ùº?ù∏ ?ù∏?ç±?ä§ (0..31)
  integer q_line_idx;

  // 1) Ïπ¥Ïö¥?Ñ∞/?ùº?ù∏ ?ù∏?ç±?ä§/?å®?î© Í∑úÏπô Ï≤¥ÌÅ¨
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      mp_cnt <= 0; mp_lines <= 0;
      zp_cnt <= 0; zp_lines <= 0;
      q_cnt  <= 0; q_lines  <= 0; pad_errs <= 0;
      q_line_pix <= 0; q_line_idx <= 0;
    end else begin
      // MP
      if (mp_valid) begin
        mp_cnt <= mp_cnt + 1;
        if (mp_line_last) mp_lines <= mp_lines + 1;
      end
      // ZP
      if (zp_valid) begin
        zp_cnt <= zp_cnt + 1;
        if (zp_line_last) zp_lines <= zp_lines + 1;
      end

      // Q (?ïµ?ã¨ Í≤??Ç¨)
      if (q_valid) begin
        q_cnt      <= q_cnt + 1;
        q_line_pix <= q_line_pix + 1;

        // (A) ?ùº?ù∏Î≥? ?Éò?îå?àò Í∞ïÏ†ú: Í∞? ?ùº?ù∏?? ?†ï?ôï?ûà OUT_W_PADÍ∞?
        if (q_line_pix > OUT_W_PAD) begin
          $fatal(1, "[Q-LINE] too many samples in a line (>%0d) at line=%0d", OUT_W_PAD, q_line_idx);
        end

        // (B) ?å®?î© ?ñâ ?åêÎ≥?: top PADÏ§? & bottom PADÏ§ÑÏ? Î∞òÎìú?ãú pad=1, ?îΩ??=0
        if (q_line_idx < PAD || q_line_idx >= (PAD + OUT_H)) begin
          if (!q_is_pad) begin
            $fatal(1, "[PAD] expected pad row but q_is_pad=0 at line=%0d col=%0d", q_line_idx, q_line_pix-1);
          end
          if (q_pixel !== 8'sd0) begin
            $fatal(1, "[PAD] pad pixel must be 0 at line=%0d col=%0d, q=%0d(0x%0h)", q_line_idx, q_line_pix-1, $signed(q_pixel), q_pixel);
          end
        end else begin
          // (C) ?éò?ù¥Î°úÎìú ?ñâ: pad=0 ?ù¥?ñ¥?ïº ?ï®
          if (q_is_pad) begin
            $fatal(1, "[PAYLOAD] unexpected pad=1 inside payload rows at line=%0d col=%0d", q_line_idx, q_line_pix-1);
          end
        end

        // ?ùº?ù∏ ?Åù Ï≤òÎ¶¨
        if (q_line_last) begin
          // °⁄ ∫Ò¬˜¥‹ ¡ı∞° ≈∏¿Ãπ÷ ∫∏¡§: "¿Ãπ¯ ªÁ¿Ã≈¨ «»ºø"¿ª ∆˜«‘«ÿ ∫Ò±≥
          if ((q_line_pix + 1) != OUT_W_PAD) begin
            $fatal(1, "[Q-LINE] pixel count mismatch at line=%0d : got %0d, exp %0d",
                   q_line_idx, (q_line_pix + 1), OUT_W_PAD);
          end
          q_lines    <= q_lines + 1;
          q_line_pix <= 0;
          q_line_idx <= q_line_idx + 1;
        end

        // ?îÑ?†à?ûÑ ?Åù Ï≤òÎ¶¨
        if (q_frame_last) begin
          if (q_lines + 1 != OUT_H_PAD) begin
            $fatal(1, "[Q-FRAME] line count mismatch: got %0d, exp %0d", q_lines+1, OUT_H_PAD);
          end
          if (q_cnt + 1 != OUT_W_PAD*OUT_H_PAD) begin
            $fatal(1, "[Q-FRAME] pixel count mismatch: got %0d, exp %0d", q_cnt+1, OUT_W_PAD*OUT_H_PAD);
          end
          // ?îÑ?†à?ûÑ ?öî?ïΩ Ï∂úÎ†•
          $display("Q-FRAME OK: pixels=%0d, lines=%0d (exp %0d x %0d)", q_cnt+1, q_lines+1, OUT_W_PAD, OUT_H_PAD);
          // ?ã§?ùå ?îÑ?†à?ûÑ ??Îπ? Ï¥àÍ∏∞?ôî
          q_cnt<=0; q_lines<=0; q_line_pix<=0; q_line_idx<=0;
        end
      end
    end
  end

  // =========================================================
  //          Frame observer with TIMEOUT protection
  // =========================================================
  task wait_one_frame(input integer idx);
    integer t0;
    begin
      // swap_rise ??Í∏? (TIMEOUT ?è¨?ï®)
      t0 = $time;
      fork
        begin : W_SWAP
          wait (swap_rise);
          disable TOUT_SWAP;
        end
        begin : TOUT_SWAP
          #(WAIT_SWAP_TIMEOUT_NS);
          $fatal(1, "[TIMEOUT] swap_c_o did not rise within %0d ns (frame %0d)", WAIT_SWAP_TIMEOUT_NS, idx);
        end
      join

      // Ï≤? q_valid ??Í∏? (?åå?ù¥?îÑ Ïß??ó∞ Î≥¥Ï†ï)
      fork
        begin : W_QV
          wait (q_valid);
          disable TOUT_QV;
        end
        begin : TOUT_QV
          #(WAIT_SWAP_TIMEOUT_NS);
          $fatal(1, "[TIMEOUT] q_valid did not assert after swap for frame %0d", idx);
        end
      join

      // q_frame_lastÍπåÏ? ??Í∏?
      fork
        begin : W_QFL
          wait (q_frame_last);
          disable TOUT_QFL;
        end
        begin : TOUT_QFL
          #(WAIT_SWAP_TIMEOUT_NS);
          $fatal(1, "[TIMEOUT] q_frame_last did not assert for frame %0d", idx);
        end
      join
      repeat (3) @(posedge clk_in_100);
      $display("FRAME #%0d DONE.", idx);
    end
  endtask

  integer seen;
  initial begin
    seen = 0;
    wait (arst_n==1'b1);
    // ?îÑ?†à?ûÑ 2Í∞? Í≤?Ï¶?
    wait_one_frame(seen); seen = seen + 1;
    wait_one_frame(seen); seen = seen + 1;
    $display("SUMMARY: checked %0d frames. Done.", seen);
    $finish;
  end

endmodule
