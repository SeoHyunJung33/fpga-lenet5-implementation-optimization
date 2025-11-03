`timescale 1ns/1ps
// ------------------------------------------------------------
// FULL PATH TB (uses IPs):
// ROM(vga_pixel_top: rom_img_0..9, clk_wiz_0) ?Üí dual BRAM ?Üí MaxPool(20x20)
//   ?Üí ZeroPad(top/bottom 4 rows) ?Üí Quantize(s8)
// ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ: swap_c_o ?ÉÅ?äπ?ó£Ïß? (= bank swap)
// Ï∂úÎ†• Í¥?Ï∞?: q_frame_lastÎ°? ?îÑ?†à?ûÑ ?ã®?úÑ ?†ï?ôï?ûà ?Åä?ñ¥?Ñú Ïπ¥Ïö¥?ä∏
// ------------------------------------------------------------
module tb_pix2mpad2quant_min3;

  // =========================
  // ?îÑÎ°úÏ†ù?ä∏ ?åå?ùºÎØ∏ÌÑ∞
  // =========================
  localparam integer H_ACTIVE    = 640;
  localparam integer V_ACTIVE    = 480;
  localparam integer F_SIZE      = H_ACTIVE * V_ACTIVE; // 307200
  localparam integer ADDR_FRAME  = 19;                  // 0..F_SIZE-1
  localparam integer DATA_WIDTH  = 8;

  // MaxPool/ZeroPad ?åå?ùºÎØ∏ÌÑ∞
  localparam integer BLK         = 20;                  // 20x20
  localparam integer OUT_W       = H_ACTIVE/BLK;        // 32
  localparam integer OUT_H       = V_ACTIVE/BLK;        // 24
  localparam integer PAD         = 4;                   // ?ÉÅ/?ïò 4Ï§?
  localparam integer OUT_W_PAD   = OUT_W;               // 32
  localparam integer OUT_H_PAD   = OUT_H + 2*PAD;       // 32

  // =========================
  // ?Å¥Î°? / Î¶¨ÏÖã
  // =========================
  reg clk_in_100 = 1'b0;
  always #5 clk_in_100 = ~clk_in_100; // 100 MHz

  reg arst_n;
  initial begin
    arst_n = 1'b0;                 // active-LOW reset
    repeat (20) @(posedge clk_in_100);
    arst_n = 1'b1;
  end

  // =========================
  // vga_pixel_top (ROM?Üídual BRAM)
  // =========================
  wire        hsync, vsync, de_out;
  wire [7:0]  vga_pixel;
  wire [18:0] addr_c_o;
  wire [7:0]  dout_c_o;
  wire [3:0]  image_num_c_o;
  wire        swap_c_o;

  vga_pixel_top #(
    .H_ACTIVE   (H_ACTIVE),
    .V_ACTIVE   (V_ACTIVE),
    .F_SIZE     (F_SIZE),
    .ADDR_FRAME (ADDR_FRAME),
    .DATA_WIDTH (DATA_WIDTH)
  ) u_pix (
    .clk_in_100     (clk_in_100),
    .arst_n         (arst_n),
    .hsync          (hsync),
    .vsync          (vsync),
    .de_out         (de_out),
    .vga_pixel      (vga_pixel),
    .addr_c_i       (addr_c_o),
    .dout_c_o       (dout_c_o),
    .image_num_c_o  (image_num_c_o),
    .swap_c_o       (swap_c_o)
  );

  // =========================
  // COREÏ∏?: BRAM Port-C ?ùΩÍ∏? Íµ¨Îèô
  // =========================
  reg                  reading=1'b0, have_data=1'b0;
  reg  [31:0]          iaddr;
  wire [31:0]          nxt_addr = iaddr + 32'd1;
  reg  [ADDR_FRAME-1:0] addr_c_drv;
  assign addr_c_o = addr_c_drv;

  // swap ?ÉÅ?äπ?ó£Ïß? Í≤?Ï∂? (?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ)
  reg swap_d;
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) swap_d <= 1'b0;
    else         swap_d <= swap_c_o;
  end
  wire swap_rise = (swap_c_o & ~swap_d);

  // ?ä§?ä∏Î¶ºÌôî: dout_c_o ?Üí maxpool ?ûÖ?†•
  reg        in_valid;
  reg [7:0]  in_pixel;
  reg        in_line_last, in_frame_last; // pad/quant Í≤ΩÎ°ú?óê?Ñú?äî ?Ç¨?ö©X (zeropadÍ∞? ?Éù?Ñ±)
  initial begin
    in_valid=0; in_pixel=0; in_line_last=0; in_frame_last=0;
    addr_c_drv = {ADDR_FRAME{1'b0}};
  end

  // ?ïú ?îÑ?†à?ûÑ(=F_SIZEÍ∞?) ?è¨?ä∏-C Ï£ºÏÜå 0..F_SIZE-1 ?àúÏ∞? ?ùΩÍ∏?
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      reading     <= 1'b0;
      have_data   <= 1'b0;
      iaddr       <= 32'd0;
      addr_c_drv  <= {ADDR_FRAME{1'b0}};
      in_valid    <= 1'b0;
      in_pixel    <= 8'd0;
    end else begin
      in_valid <= 1'b0;
      have_data<= 1'b0;

      if (!reading && swap_rise) begin
        reading    <= 1'b1;
        iaddr      <= 32'd0;
        addr_c_drv <= {ADDR_FRAME{1'b0}};
      end else if (reading) begin
        // BRAM 1clk read latency Î≥¥Ï†ï: ?ù¥?†Ñ Ï£ºÏÜå?ùò ?ç∞?ù¥?Ñ∞ ?Ç¨?ö©
        if (have_data) begin
          in_valid <= 1'b1;
          in_pixel <= dout_c_o;
        end
        // ?ã§?ùå Ï£ºÏÜå ÏßÑÌñâ
        if (iaddr < F_SIZE-1) begin
          iaddr      <= nxt_addr;
          addr_c_drv <= nxt_addr[ADDR_FRAME-1:0];
          have_data  <= 1'b1;
        end else begin
          reading   <= 1'b0;   // ÎßàÏ?Îß? ?Éò?îå Ï≤òÎ¶¨ ?õÑ Ï¢ÖÎ£å
          have_data <= 1'b0;
        end
      end
    end
  end

  // =========================
  // MaxPool 20x20
  // =========================
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
    .srst        (~arst_n),
    .en          (1'b1),
    .en_mp       (1'b1),
    .in_valid    (in_valid),
    .in_pixel    (in_pixel),
    .out_valid   (mp_valid),
    .out_pixel   (mp_pixel),
    .line_last   (mp_line_last),
    .frame_last  (mp_frame_last)
  );

  // =========================
  // ZeroPad(?úÑ/?ïÑ?ûò 4Ï§?)
  // =========================
  wire        zp_valid;
  wire [7:0]  zp_pixel;
  wire        zp_line_last;
  wire        zp_frame_last;
  wire        zp_is_pad;

  zeropad_rows #(.W(OUT_W), .HIN(OUT_H), .PAD(PAD)) u_zp (
    .clk          (clk_in_100),
    .srst         (~arst_n),
    .in_valid     (mp_valid),
    .in_pixel     (mp_pixel),
    .in_line_last (mp_line_last),
    .in_frame_last(mp_frame_last),
    .out_valid    (zp_valid),
    .out_pixel    (zp_pixel),
    .out_line_last(zp_line_last),
    .out_frame_last(zp_frame_last),
    .out_is_pad   (zp_is_pad)
  );

  // =========================
  // Quantize(s8)
  // =========================
  wire              q_valid;
  wire signed [7:0] q_pixel;
  wire              q_line_last;
  wire              q_frame_last;
  wire              q_is_pad;

  quantize_s8 u_q (
    .clk           (clk_in_100),
    .srst          (~arst_n),
    .in_valid      (zp_valid),
    .in_pixel      (zp_pixel),
    .in_line_last  (zp_line_last),
    .in_frame_last (zp_frame_last),
    .in_is_pad     (zp_is_pad),
    .out_valid     (q_valid),
    .out_pixel     (q_pixel),
    .out_line_last (q_line_last),
    .out_frame_last(q_frame_last),
    .out_is_pad    (q_is_pad)
  );

  // =========================
  // Ïπ¥Ïö¥?Ñ∞/Ï≤¥ÌÅ¨
  // =========================
  integer mp_cnt, mp_lines;
  integer zp_cnt, zp_lines;
  integer q_cnt,  q_lines;
  integer pad_errs;

  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      mp_cnt<=0; mp_lines<=0; zp_cnt<=0; zp_lines<=0; q_cnt<=0; q_lines<=0; pad_errs<=0;
    end else begin
      if (mp_valid) begin
        mp_cnt <= mp_cnt + 1;
        if (mp_line_last) mp_lines <= mp_lines + 1;
      end
      if (zp_valid) begin
        zp_cnt <= zp_cnt + 1;
        if (zp_line_last) zp_lines <= zp_lines + 1;
      end
      if (q_valid) begin
        q_cnt <= q_cnt + 1;
        if (q_line_last) q_lines <= q_lines + 1;
        // ?å®?î©?? Î∞òÎìú?ãú 0
        if (q_is_pad && (q_pixel !== 8'sd0)) begin
          $display("[%0t] **ERROR** pad pixel not zero! q=%0d (0x%0h)", $time, $signed(q_pixel), q_pixel);
          pad_errs <= pad_errs + 1;
        end
      end
    end
  end

  // ?öî?ïΩ Ï∂úÎ†•
  task print_frame_summary(input integer idx);
    begin
      $display("FRAME#%0d MP : out=%0d (exp %0d)  lines=%0d (exp 24)",
               idx, mp_cnt, OUT_W*OUT_H, mp_lines);
      $display("FRAME#%0d ZP : out=%0d (exp %0d)  lines=%0d (exp 32)",
               idx, zp_cnt, OUT_W_PAD*OUT_H_PAD, zp_lines);
      $display("FRAME#%0d Q  : out=%0d (exp %0d)  lines=%0d (exp 32), pad_errs=%0d",
               idx, q_cnt,  OUT_W_PAD*OUT_H_PAD, q_lines, pad_errs);
    end
  endtask

  // ?îÑ?†à?ûÑÎ≥? Í¥?Ï∞? Î£®Ìã¥
  task observe_one_frame(input integer idx);
    begin
      // ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ ??Í∏?
      wait (swap_rise);

      // ?åå?ù¥?îÑ Ï±ÑÏ? ?†Ñ?ôò: Ï≤? q_valid ?ú∞ ?ïåÍπåÏ? ??Í∏?
      wait (q_valid == 1'b1);

      // ?ù¥ ?îÑ?†à?ûÑ?ùò q_frame_lastÍπåÏ? Í¥?Ï∞?
      wait (q_frame_last == 1'b1);

      // ?öî?ïΩ Ï∂úÎ†•
      print_frame_summary(idx);

      // Í∞ÑÎã® ?ï©Í≤? Í∏∞Ï?
      if (mp_cnt  !== OUT_W*OUT_H)       $display("**WARN** MP count mismatch.");
      if (zp_cnt  !== OUT_W_PAD*OUT_H_PAD) $display("**WARN** ZP count mismatch.");
      if (q_cnt   !== OUT_W_PAD*OUT_H_PAD) $display("**WARN** Q  count mismatch.");
      if (pad_errs !== 0)                $display("**WARN** pad zero check failed: %0d", pad_errs);

      // ?ã§?ùå ?îÑ?†à?ûÑ ??Îπ? Ïπ¥Ïö¥?Ñ∞ Î¶¨ÏÖã
      mp_cnt=0; mp_lines=0; zp_cnt=0; zp_lines=0; q_cnt=0; q_lines=0; pad_errs=0;
    end
  endtask

  integer seen;
  initial begin
    seen = 0;
    // (?Ñ†?Éù) VCD
    // $dumpfile("tb_pix2mpad2quant_min2.vcd");
    // $dumpvars(0, tb_pix2mpad2quant_min2);

    wait (arst_n==1'b1);

    // ?îÑ?†à?ûÑ 2Í∞úÎßå Ï≤¥ÌÅ¨(?ïÑ?öî?ãú ?äòÎ¶¨Í∏∞)
    observe_one_frame(seen); seen = seen + 1;
    observe_one_frame(seen); seen = seen + 1;

    $display("SUMMARY: checked %0d frames. Done.", seen);
    $finish;
  end

endmodule
