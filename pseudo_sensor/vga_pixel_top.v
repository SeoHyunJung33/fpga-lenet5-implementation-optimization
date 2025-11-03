`timescale 1ns/1ps
module vga_pixel_top #(
  parameter integer H_ACTIVE    = 640,
  parameter integer V_ACTIVE    = 480,
  parameter integer F_SIZE      = 640*480,
  parameter integer ADDR_FRAME  = 19,
  parameter integer DATA_WIDTH  = 8
)(
  input  wire               clk_in_100,   // core clock 100MHz
  input  wire               arst_n,       // active-LOW global reset

  // Display out (system_top에 노출)
  output wire               hsync,
  output wire               vsync,
  output wire               de_out,
  output wire [7:0]         vga_pixel,

  // ---- Core read 인터페이스 (bram_to_axis_reader 등과 바로 연결용) ----
  input  wire [ADDR_FRAME-1:0] addr_c_i,
  output wire [DATA_WIDTH-1:0] dout_c_o,
  output wire [3:0]            image_num_c_o,
  output wire swap_c_o
  
  `ifdef SIM_CHECK
    output wire                dbg_p_clk,
    output wire                dbg_de,
    output wire [ADDR_FRAME-1:0] dbg_addr_frame,
    output wire [DATA_WIDTH-1:0] dbg_rom_pixel,
  `endif
);

  // --------------------------------------------------------------------------
  // Clocks & Reset
  // --------------------------------------------------------------------------
  wire c_clk = clk_in_100;

  // ---- CLOCK BLOCK ----
  wire p_clk;
  wire mmcm_locked;

  localparam USE_IP_CLK = 1;
  generate
    if (USE_IP_CLK) begin : G_USE_MMCM
      // 너의 IP는 reset(Active High)
      clk_wiz_0 u_mmcm (
        .clk_in1 (clk_in_100),
        .reset   (~arst_n),
        .clk_out1(p_clk),
        .locked  (mmcm_locked)
      );
    end else begin : G_USE_DIV
      reg [2:0] div;
      always @(posedge clk_in_100 or negedge arst_n) begin
        if (!arst_n) div <= 3'd0;
        else         div <= div + 3'd1;
      end
      assign p_clk       = div[2];
      assign mmcm_locked = 1'b1;
    end
  endgenerate
  // ----------------------

  wire srst_p_n;
  wire srst_c_n;
  wire pix_arst_n = arst_n & mmcm_locked;

  rst_sync u_rst_pix  (.clk(p_clk), .arst_n(pix_arst_n), .srst_n(srst_p_n));
  rst_sync u_rst_core (.clk(c_clk), .arst_n(arst_n),     .srst_n(srst_c_n));

  // --------------------------------------------------------------------------
  // VGA timing / Address
  // --------------------------------------------------------------------------
  wire [9:0] px;
  wire [8:0] py;
  wire de, sof, eof;

  vga_tcon #(
    .H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE),
    .H_FP(16), .H_SYNC(96), .H_BP(48),
    .V_FP(10), .V_SYNC(2),  .V_BP(33),
    .HSYNC_NEG(1), .VSYNC_NEG(1)
  ) u_tcon (
    .p_clk   (p_clk),
    .arst_p_n(srst_p_n),
    .px      (px),
    .py      (py),
    .de      (de),
    .hsync   (hsync),
    .vsync   (vsync),
    .sof     (sof),
    .eof     (eof)
  );

  assign de_out = de;

  wire [ADDR_FRAME-1:0] addr_frame;
  addr_gen_linear #(.ADDR_WIDTH(ADDR_FRAME)) u_addr (
    .p_clk   (p_clk),
    .arst_p_n(srst_p_n),
    .de      (de),
    .sof     (sof),
    .addr    (addr_frame)
  );

  // --------------------------------------------------------------------------
  // 이미지 선택: 0→9 순환 (프레임 끝마다)
  // --------------------------------------------------------------------------
  reg [3:0] image_num;
  always @(posedge p_clk or negedge srst_p_n) begin
    if (!srst_p_n)                           image_num <= 4'd0;
    else if (eof)                            image_num <= (image_num==4'd9) ? 4'd0 : (image_num + 4'd1);
  end

  // --------------------------------------------------------------------------
  // ROM 10장 + MUX → rom_pixel
  // --------------------------------------------------------------------------
  wire [DATA_WIDTH-1:0] rom_pixel;
  rom10_mux #(.ADDR_FRAME(ADDR_FRAME), .DATA_WIDTH(DATA_WIDTH)) u_rom_mux (
    .p_clk     (p_clk),
    .addr_frame(addr_frame),
    .sel       (image_num),
    .dout      (rom_pixel)
  );

  // --------------------------------------------------------------------------
  // EOF → swap_p (은행 토글용)
  // --------------------------------------------------------------------------
  wire swap_p;
  frame_swap_gen_eof u_swap (
    .p_clk   (p_clk),
    .arst_p_n(srst_p_n),
    .eof     (eof),
    .swap_p  (swap_p)
  );

  // --------------------------------------------------------------------------
  // 픽셀→코어 펄스 동기화: swap_p → swap_c
  // --------------------------------------------------------------------------
wire swap_c;
  pulse_sync u_pulse_swap (
    p_clk,      // src_clk
    srst_p_n,   // src_rst_n  (모듈이 active-H reset이면 ~srst_p_n 으로 바꾸세요)
    swap_p,     // src_pulse
    c_clk,      // dst_clk
    srst_c_n,   // dst_rst_n  (active-H면 ~srst_c_n)
    swap_c      // dst_pulse
  );

  // --------------------------------------------------------------------------
  // Ping-Pong BRAM with Meta
  // --------------------------------------------------------------------------
  wire [DATA_WIDTH-1:0] disp_pixel;
  wire [3:0]            image_num_pix;

  wire [DATA_WIDTH-1:0] dout_c_w;
  wire [3:0]            image_num_c_w;

  dual_bram_pp_with_meta #(
    .ADDR_WIDTH (ADDR_FRAME),
    .DATA_WIDTH (DATA_WIDTH),
    .DEPTH      (F_SIZE)
  ) u_mem (
    // pixel write + VGA read
    .p_clk          (p_clk),
    .arst_p_n       (srst_p_n),
    .we_p           (de),               // de 동안 write
    .addr_p         (addr_frame),
    .din_p          (rom_pixel),
    .swap_p         (swap_p),
    .image_num_in_p (image_num),

    .addr_pix       (addr_frame),       // 현재 읽는 뱅크에서 동일 주소 읽기
    .dout_pix       (disp_pixel),
    .image_num_pix  (image_num_pix),

    // core read
    .c_clk          (c_clk),
    .arst_c_n       (srst_c_n),
    .addr_c         (addr_c_i),
    .dout_c         (dout_c_w),
    .swap_c         (swap_c),
    .image_num_c    (image_num_c_w)
  );
  
  `ifdef SIM_CHECK
    assign dbg_p_clk       = p_clk;        // 픽셀클럭
    assign dbg_de          = de;           // 디스플레이 유효
    assign dbg_addr_frame  = addr_frame;   // 선형 주소(0..F_SIZE-1)
    assign dbg_rom_pixel   = rom_pixel;    // ROM 출력(원본 픽셀)
  `endif

  // Display out
  assign vga_pixel     = disp_pixel;

  // Core interface to downstream modules
  assign dout_c_o      = dout_c_w;
  assign image_num_c_o = image_num_c_w;
  
  assign swap_c_o = swap_c;

endmodule

