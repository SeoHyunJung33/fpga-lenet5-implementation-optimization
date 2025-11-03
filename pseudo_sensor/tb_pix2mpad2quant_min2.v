`timescale 1ns/1ps

// ------------------------------------------------------------
//  TB: ROM(vga_pixel_top) -> dual BRAM -> MaxPool(20x20)
//      -> ZeroPad(?úÑ/?ïÑ?ûò 4Ï§?) -> Quantize(s8)
//  ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ?äî swap_c_o(=bank swap) ?ÉÅ?äπ?ó£Ïß? Í∏∞Ï?.
//  Í¥?Ï∞∞Ï? q_frame_lastÎ°? ?†ï?ôï?ûà ?Åä?ñ¥ Ïπ¥Ïö¥?ä∏ mismatch Î∞©Ï?.
// ------------------------------------------------------------
module tb_pix2mpad2quant_min2;

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

  wire srst = ~arst_n;             // pad/quantize?äî active-HIGH

  // =========================
  // vga_pixel_top (ROM?Üídual BRAM)
  // =========================
  wire        vga_hs, vga_vs, vga_de;
  wire [7:0]  vga_pixel;

  reg  [ADDR_FRAME-1:0] addr_c_drv = {ADDR_FRAME{1'b0}};
  wire [ADDR_FRAME-1:0] addr_c_i   = addr_c_drv;
  wire [DATA_WIDTH-1:0] dout_c_o;

  wire [3:0] image_num_c_o;
  wire       swap_c_o;

  // DUT: ?îΩ?? ?Éù?Ñ±(+dual BRAM)
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

  // =========================
  // CORE Î¶¨Îçî (READ_LAT=1 Í∞??†ï)
  // =========================
  reg         reading;
  reg [31:0]  iaddr;
  reg         have_data;
  reg         in_valid;
  reg  [7:0]  in_pixel;

  // Vivado Verilog: (iaddr+1)[..] Í∏àÏ? ?Üí ?ûÑ?ãú Î≥??àòÎ°? Í≥ÑÏÇ∞
  wire [31:0] nxt_addr = iaddr + 32'd1;

  // ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ: swap ?ÉÅ?äπ?ó£Ïß?
  reg  swap_q;
  always @(posedge clk_in_100 or negedge arst_n)
    if (!arst_n) swap_q <= 1'b0;
    else         swap_q <= swap_c_o;

  wire swap_rise = (swap_c_o & ~swap_q);

  // enable
  reg en    = 1'b1;
  reg en_mp = 1'b1;

  // Ï£ºÏÜåÍµ¨Îèô?Üí1clk?í§ ?ç∞?ù¥?Ñ∞ ?Ç¨?ö©
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
        // ?ù¥?†Ñ Ï£ºÏÜå?ùò ?ç∞?ù¥?Ñ∞ ?Ç¨?ö©
        if (have_data) begin
          in_valid <= 1'b1;
          in_pixel <= dout_c_o;
        end
        // ?ã§?ùå Ï£ºÏÜå
        if (iaddr < F_SIZE-1) begin
          iaddr      <= nxt_addr;
          addr_c_drv <= nxt_addr[ADDR_FRAME-1:0];
          have_data  <= 1'b1;
        end else begin
          reading   <= 1'b0;  // ÎßàÏ?Îß? ?Éò?îå Ï≤òÎ¶¨ ?õÑ Ï¢ÖÎ£å
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

  // =========================
  // ZeroPad (?úÑ/?ïÑ?ûò 4Ï§? ?Üí 32x32)
  // =========================
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
    .in_frame_last  (mp_frame_last), 
    .out_valid      (zp_valid),
    .out_pixel      (zp_pixel),
    .out_line_last  (zp_line_last),
    .out_frame_last (zp_frame_last),
    .out_is_pad     (zp_is_pad)
  );

  // =========================
  // Quantize (s8, ZERO_POINT=128)
  // =========================
  wire              q_valid;
  wire signed [7:0] q_pixel;
  wire              q_line_last;
  wire              q_frame_last;
  wire              q_is_pad; // zeropad_rows?óê?Ñú ?†Ñ?ã¨

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

  // =========================
  // Ïπ¥Ïö¥?Ñ∞ & Í≤?Ï¶? (q ?èÑÎ©îÏù∏ Í∏∞Ï?)
  // =========================
  integer mp_cnt,  mp_lines;
  integer zp_cnt,  zp_lines;
  integer q_cnt,   q_lines;
  integer pad_errs;
  

  // MaxPool Ïπ¥Ïö¥?ä∏ (Ï∞∏Í≥†?ö©)
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      mp_cnt  <= 0;
      mp_lines<= 0;
    end else begin
      if (mp_valid)     mp_cnt   <= mp_cnt + 1;
      if (mp_line_last) mp_lines <= mp_lines + 1;
    end
  end

  // ZeroPad Ïπ¥Ïö¥?ä∏ (Ï∞∏Í≥†?ö©)
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      zp_cnt  <= 0;
      zp_lines<= 0;
    end else begin
      if (zp_valid)     zp_cnt   <= zp_cnt + 1;
      if (zp_line_last) zp_lines <= zp_lines + 1;
    end
  end

  // Quantize Ïπ¥Ïö¥?ä∏ + ?å®?î© 0 Ï≤¥ÌÅ¨ (Í≤?Ï¶? Í∏∞Ï?)
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      q_cnt   <= 0;
      q_lines <= 0;
      pad_errs<= 0;
    end else begin
      if (q_valid) begin
        q_cnt <= q_cnt + 1;

        // ?å®?î© ?úÑÏπòÎäî Î∞òÎìú?ãú 0?ù¥?ñ¥?ïº ?ï®
        if (q_is_pad && (q_pixel !== 8'sd0)) begin
          $display("[%0t] **ERROR** pad pixel not zero! q=%0d (0x%0h)",
                   $time, $signed(q_pixel), q_pixel);
          pad_errs <= pad_errs + 1;
        end

        if (q_line_last) q_lines <= q_lines + 1;
      end
    end
  end

  // =========================
  // ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ ?ãúÍ∞ÅÌôî?ö©: ?å®?î© ?ãú?ûë/Ï¢ÖÎ£å ÎßàÏª§(?åå?òï Í¥?Ï∞? ?é∏?ùò)
  // =========================
  // q ?èÑÎ©îÏù∏?óê?Ñú ?ÉÅ?ã® ?å®?î© Íµ¨Í∞Ñ ?îå?ûòÍ∑?(top_pad_phase),
  // ?éò?ù¥Î°úÎìúÍ∞? ?ïúÎ≤àÏù¥?ùº?èÑ ?Çò?ò§Î©? payload_seen=1,
  // Í∑? ?ù¥?õÑ?ùò pad?äî ?ïò?ã® ?å®?î©(bottom_pad_phase)Î°? Ï∑®Í∏â.
  reg top_pad_phase, bottom_pad_phase, payload_seen;
  always @(posedge clk_in_100 or negedge arst_n) begin
    if (!arst_n) begin
      top_pad_phase    <= 1'b0;
      bottom_pad_phase <= 1'b0;
      payload_seen     <= 1'b0;
    end else begin
      // ?îÑ?†à?ûÑ ?ãú?ûë ?èôÍ∏∞Ìôî: q_validÍ∞? Ï≤òÏùå ?ú∞ ?ïå top_pad_phase ?ãú?ûë
      if (swap_rise) begin
        top_pad_phase    <= 1'b0;
        bottom_pad_phase <= 1'b0;
        payload_seen     <= 1'b0;
      end
      if (q_valid && !payload_seen) begin
        // q_validÍ∞? Ï≤òÏùå 1?ù¥ ?êò?äî ?Ç¨?ù¥?Å¥?ùÑ top ?å®?î© ?ãú?ûë?úºÎ°? ?ëú?ãú
        if (!top_pad_phase) top_pad_phase <= 1'b1;
        if (!q_is_pad) begin
          payload_seen  <= 1'b1;   // ?éò?ù¥Î°úÎìúÍ∞? ?Çò?ò§Î©? top ?å®?î© ?Åù
          top_pad_phase <= 1'b0;
        end
      end else if (q_valid && payload_seen) begin
        // ?éò?ù¥Î°úÎìú ?ù¥?õÑ?óê ?ã§?ãú padÍ∞? ?Çò?ò§Î©? bottom ?å®?î©
        if (q_is_pad) bottom_pad_phase <= 1'b1;
      end
      // ?îÑ?†à?ûÑ Ï¢ÖÎ£å ?ãú Î™®Îëê ?Å¥Î¶¨Ïñ¥(Î≥¥Í∏∞ Ï¢ãÍ≤å)
      if (q_frame_last) begin
        top_pad_phase    <= 1'b0;
        bottom_pad_phase <= 1'b0;
      end
    end
  end

  // =========================
  // Ï∂úÎ†• ?öî?ïΩ + ?îÑ?†à?ûÑ Í¥?Ï∞? Î£®Ìã¥
  // =========================
  task print_frame_summary(input integer idx);
    begin
      $display("FRAME#%0d MP : out=%0d (exp %0d)  lines=%0d (exp 24)",
               idx, mp_cnt, OUT_W*OUT_H, mp_lines);
      $display("FRAME#%0d ZP : out=%0d (exp %0d)  lines=%0d (exp 32)",
               idx, zp_cnt, OUT_W_PAD*OUT_H_PAD, zp_lines);
      $display("FRAME#%0d  Q : out=%0d (exp %0d)  lines=%0d (exp 32)  pad_errs=%0d",
               idx, q_cnt,  OUT_W_PAD*OUT_H_PAD, q_lines, pad_errs);
    end
  endtask

  task observe_one_frame(input integer idx);
    begin
      // ?îÑ?†à?ûÑ Í≤ΩÍ≥Ñ ??Í∏?
      wait (swap_rise);

      // Ïπ¥Ïö¥?Ñ∞ ?Å¥Î¶¨Ïñ¥
      mp_cnt=0; mp_lines=0;
      zp_cnt=0; zp_lines=0;
      q_cnt =0; q_lines =0;
      pad_errs=0;

      // ?åå?ù¥?îÑ?ùº?ù∏ Ï±ÑÏ? Î≥¥Ï†ï: q_valid?ùò Ï≤? 1 ??Í∏?
      wait (q_valid == 1'b1);

      // ?ù¥ ?îÑ?†à?ûÑ?ùò q_frame_lastÍπåÏ? Í¥?Ï∞?
      wait (q_frame_last == 1'b1);
      repeat (3) @(posedge clk_in_100); // Íº¨Î¶¨ ?ó¨?ú†

      print_frame_summary(idx);
    end
  endtask

  integer seen;
  initial begin
    seen = 0;
    wait (arst_n==1'b1);

    // ?îÑ?†à?ûÑ 2Í∞úÎßå Ï≤¥ÌÅ¨(?ïÑ?öî?ãú ?äòÎ¶¨Í∏∞)
    observe_one_frame(seen); seen = seen + 1;
    observe_one_frame(seen); seen = seen + 1;

    $display("SUMMARY: checked %0d frames. Done.", seen);
    $finish;
  end

endmodule
