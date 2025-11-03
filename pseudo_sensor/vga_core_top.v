// core_nonaxi_top.v
// BRAM ?넂 (?썝蹂? ?뒪?듃由?) + (MaxPool?넂Pad?넂Quantize) ?쟾泥섎━ ?뒪?듃由?
module vga_core_top #(
  parameter integer IN_W   = 640,
  parameter integer IN_H   = 480,
  parameter integer AB     = 19,
  parameter integer BLK    = 20,   // MaxPool stride
  parameter integer PAD    = 4     // Pad rows
)(
  input  wire              clk,
  input  wire              srst,          // active-HIGH

  input  wire              start,         // 1clk @ frame start (swap_c)
  output wire [AB-1:0]     addr_c,        // BRAM Port-C addr
  input  wire       [7:0]  dout_c,        // BRAM Port-C data

  input  wire       [3:0]  image_num_in,
  output reg        [3:0]  image_num_core,

  // ORIGINAL stream (u8)
  output wire              orig_valid,
  output wire              orig_sof,
  output wire              orig_eol,
  output wire      [7:0]   orig_data,

  // PROCESSED stream (s8)
  output wire              proc_valid,
  output wire              proc_sof,
  output wire              proc_eol,
  output wire signed [7:0] proc_data,
  
  output wire              q_valid_o,
  output wire              q_line_last_o,
  output wire              q_frame_last_o,
  output wire signed [7:0] q_pixel_o
);

  wire rd_v, rd_sof, rd_eol;
  wire [7:0] rd_d;

  bram_frame_reader #(
    .IN_W(IN_W), .IN_H(IN_H), .AB(AB)
  ) u_rdr (
    .clk(clk), .srst(srst),
    .start(start),
    .bram_addr(addr_c),
    .bram_dout(dout_c),
    .valid(rd_v), .sof(rd_sof), .eol(rd_eol), .data(rd_d)
  );

  assign orig_valid = rd_v;
  assign orig_sof   = rd_sof;
  assign orig_eol   = rd_eol;
  assign orig_data  = rd_d;

  always @(posedge clk) begin
    if (srst) image_num_core <= 4'd0;
    else if (orig_sof) image_num_core <= image_num_in;
  end

  wire        mp_v, mp_ll, mp_fl;
  wire [7:0]  mp_pix;

  maxpool20x20 #(
    .IN_W(IN_W), .IN_H(IN_H), .BLK(BLK)
  ) u_mp (
    .clk       (clk),
    .srst      (srst),
    .en        (1'b1),
    .en_mp     (1'b1),
    .in_valid  (rd_v),
    .in_pixel  (rd_d),
    .out_valid (mp_v),
    .out_pixel (mp_pix),
    .line_last (mp_ll),
    .frame_last(mp_fl)
  );
  
    // === MP → ZP 정렬 래퍼 (1clk) ===
  reg        mp_v_d, mp_ll_d, mp_fl_d;
  reg [7:0]  mp_pix_d;

  always @(posedge clk) begin
    if (srst) begin
      mp_v_d   <= 1'b0;
      mp_ll_d  <= 1'b0;
      mp_fl_d  <= 1'b0;
      mp_pix_d <= 8'd0;
    end else begin
      // valid / pixel / last 신호를 같은 싸이클로 정렬
      mp_v_d   <= mp_v;
      mp_ll_d  <= mp_ll;
      mp_fl_d  <= mp_fl;
      mp_pix_d <= mp_pix;
    end
  end

  // --- 3) ZeroPad rows : 32x24 ?넂 32x32 (+ pad flag) ---
  localparam integer OUT_W = IN_W/BLK;   // 32
  localparam integer OUT_H = IN_H/BLK;   // 24

  wire        zp_v, zp_ll, zp_fl, zp_is_pad;
  wire [7:0]  zp_pix;

  zeropad_rows #(
    .W(OUT_W), .HIN(OUT_H), .PAD(PAD)
  ) u_zp (
    .clk(clk), .srst(srst),
    .in_valid       (mp_v_d),     // ← 정렬된 신호 사용
    .in_pixel       (mp_pix_d),   // ← 정렬된 신호 사용
    .in_line_last   (mp_ll_d),    // ← 정렬된 신호 사용
    .out_valid    (zp_v),
    .out_pixel    (zp_pix),
    .out_line_last(zp_ll),
    .out_frame_last(zp_fl),
    .out_is_pad   (zp_is_pad)    
  );

  wire        q_v, q_ll, q_fl;
  wire signed [7:0] q_pix;

  quantize_s8 #(.ZERO_POINT(8'd128)) u_q (
    .clk(clk), .srst(srst),
    .in_valid     (zp_v),
    .in_pixel     (zp_pix),
    .in_line_last (zp_ll),
    .in_frame_last(zp_fl),
    .in_is_pad    (zp_is_pad),   
    .out_valid    (q_v),
    .out_pixel    (q_pix),
    .out_line_last(q_ll),
    .out_frame_last(q_fl)
  );
 


  reg seen_first;
  always @(posedge clk) begin
    if (srst) seen_first <= 1'b0;
    else if (q_v && q_fl) seen_first <= 1'b0; 
    else if (q_v && !seen_first) seen_first <= 1'b1;
  end

  assign proc_valid = q_v;
  assign proc_sof   = (q_v && !seen_first);
  assign proc_eol   = q_ll;
  assign proc_data  = q_pix;
  
  // 내부에서 할당
  assign q_valid_o      = q_v;
  assign q_line_last_o  = q_ll;
  assign q_frame_last_o = q_fl;
  assign q_pixel_o      = q_pix;
endmodule

