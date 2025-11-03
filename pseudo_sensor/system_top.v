module system_top (
  input  wire         clk_in_100,   // 100MHz
  input  wire         arst_n,       // Global async reset, active-LOW

  // ---- Meta ----
  output wire [3:0]   image_num,
  
  output wire         lenet_start,          // 프레임 시작 1clk 펄스
  output wire         lenet_v,              // per-pixel valid (= q_valid)
  output wire signed [7:0] lenet_pix,
        
  output wire [7:0]   vga_pixel
);

  wire srst_n_core;
  rst_sync u_rst_core (
    .clk    (clk_in_100),
    .arst_n (arst_n),
    .srst_n (srst_n_core)
  );
  wire srst_core = ~srst_n_core;  // active-HIGH


  wire [18:0] addr_c;   // 640*480=307200 
  wire [7:0]  dout_c;
  wire [3:0]  image_num_c;
  wire        swap_c;


  vga_pixel_top #(
    .H_ACTIVE   (640),
    .V_ACTIVE   (480),
    .ADDR_FRAME (19),
    .DATA_WIDTH (8)
  ) u_pix (
    .clk_in_100    (clk_in_100),
    .arst_n        (arst_n),
    .vga_pixel     (vga_pixel),
    .addr_c_i      (addr_c),
    .dout_c_o      (dout_c),
    .image_num_c_o (image_num_c),
    .swap_c_o      (swap_c)
  );

  // ---- core (maxpool → zeropad → quantize) ----
  // 내부 q_* 신호를 preproc로 넘길 것이므로 wire 선언
  wire        q_valid;
  wire        q_line_last;
  wire        q_frame_last;
  wire signed [7:0] q_pixel;

  vga_core_top #(
    .IN_W (640), .IN_H (480), .AB(19), .BLK(20), .PAD(4)
  ) u_core (
    .clk          (clk_in_100),
    .srst         (srst_core),      // active-HIGH
    .start        (swap_c),
    .addr_c       (addr_c),
    .dout_c       (dout_c),
    .image_num_in (image_num_c),
    .image_num_core (image_num),
    .q_valid_o      (q_valid),
    .q_line_last_o  (q_line_last),
    .q_frame_last_o (q_frame_last),
    .q_pixel_o      (q_pixel)
  );
  
  
    // quantize_s8 인스턴스 바로 아래
  preproc_stream2lenet #(
    .PIX_BITS(8)                 // LeNet 입력 비트수에 맞게
  ) u_stream2lenet (
    .clk          (clk_in_100),
    .srst         (srst_core),
  
    .q_valid      (q_valid),
    .q_line_last  (q_line_last),
    .q_frame_last (q_frame_last),
    .q_pixel      (q_pixel),
  
    .lenet_start  (lenet_start),   // 프레임 시작 1클럭
    .lenet_v      (lenet_v),       // per-pixel valid (=q_valid)
    .lenet_pix    (lenet_pix)      // 픽셀 데이터
  );

endmodule
