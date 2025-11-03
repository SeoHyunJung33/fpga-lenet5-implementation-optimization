`timescale 1ns/1ps //
module dual_bram_pp_with_meta #(
  parameter integer ADDR_WIDTH = 19,
  parameter integer DATA_WIDTH = 8,
  parameter integer DEPTH      = 307200  // 640*480


)(
  // Pixel domain - Write & VGA Read
  input  wire                   p_clk,
  input  wire                   arst_p_n,           // active-LOW
  input  wire                   we_p,               // write enable (active when writing bank)
  input  wire [ADDR_WIDTH-1:0]  addr_p,             // write address
  input  wire [DATA_WIDTH-1:0]  din_p,              // write data
  input  wire                   swap_p,             // 1clk pulse @ frame end
  input  wire [3:0]             image_num_in_p,     // meta write (banked)

  // VGA read (Display)
  input  wire [ADDR_WIDTH-1:0]  addr_pix,           // read address (VGA)
  output reg  [DATA_WIDTH-1:0]  dout_pix,           // read data (VGA)
  output wire [3:0]             image_num_pix,      // meta for VGA bank

  // Core domain - Read
  input  wire                   c_clk,
  input  wire                   arst_c_n,           // active-LOW
  input  wire [ADDR_WIDTH-1:0]  addr_c,             // core read address
  output reg  [DATA_WIDTH-1:0]  dout_c,             // core read data
  input  wire                   swap_c,             // 1clk @ c_clk (CDC'ed swap_p)
  output wire [3:0]             image_num_c         // meta in core domain
);

  // XPM 요구: 파워-오브-투 크기
  localparam integer DEPTH_P2  = (1 << ADDR_WIDTH);
  localparam integer MEM_BITS  = DATA_WIDTH * DEPTH_P2;
// ----------------------------
  // Bank toggle (pixel domain) - swap_p를 1클럭 지연 후 토글
  // ----------------------------
  reg bank_p;        // 0: writing A / reading B, 1: writing B / reading A
  reg swap_p_q;      // 1clk delayed swap_p (토글 트리거 용도)
  
  always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
      bank_p   <= 1'b0;
      swap_p_q <= 1'b0;
    end else begin
      swap_p_q <= swap_p;          // EOF 직후 1클럭 지연
      if (swap_p_q) bank_p <= ~bank_p;
    end
  end
  
  wire wr_sel_A   = (bank_p == 1'b0);
  wire rd_sel_A_p = ~wr_sel_A; // VGA는 write의 반대 뱅크를 읽음

  // ----------------------------
  // Meta (image number), pixel domain per-bank
  // ----------------------------
  reg [3:0] meta_a_p, meta_b_p;
  always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
      meta_a_p <= 4'd0; meta_b_p <= 4'd0;
    end else if (swap_p) begin
      if (wr_sel_A) meta_a_p <= image_num_in_p;
      else          meta_b_p <= image_num_in_p;
    end
  end

  // VGA 측 메타: 현재 읽는 뱅크
  assign image_num_pix = rd_sel_A_p ? meta_a_p : meta_b_p;

  // ----------------------------
  // Core-side: read-bank toggle by swap_c
  // ----------------------------
  // rd_sel_A_c = 1 → Core가 Bank-A 읽음, 0 → Core가 Bank-B 읽음
  reg rd_sel_A_c;
  always @(posedge c_clk or negedge arst_c_n) begin
    if (!arst_c_n)       rd_sel_A_c <= 1'b0;   // 초기: Bank-B 읽기 (pixel 초기 A write 가정)
    else if (swap_c)     rd_sel_A_c <= ~rd_sel_A_c;
  end

  // ----------------------------
  // XPM TDPRAM per bank (A/B)
  // Port map policy:
  //  - Port A @ p_clk : write OR VGA read (p_clk)  → MUX
  //  - Port B @ c_clk : core read only
  // ----------------------------
  // Bank A
  wire [DATA_WIDTH-1:0] a_doutA_p;  // Port A dout (p_clk)
  wire [DATA_WIDTH-1:0] a_doutB_c;  // Port B dout (c_clk)

  reg        a_weA;
  reg [ADDR_WIDTH-1:0] a_addrA;
  reg [DATA_WIDTH-1:0] a_dinA;
  always @* begin
    if (wr_sel_A) begin
      a_weA   = we_p;
      a_addrA = addr_p;
      a_dinA  = din_p;
    end else begin
      a_weA   = 1'b0;
      a_addrA = addr_pix;
      a_dinA  = {DATA_WIDTH{1'b0}};
    end
  end

  xpm_memory_tdpram #(
    .MEMORY_SIZE         (MEM_BITS),
    .MEMORY_PRIMITIVE    ("block"),
    .CLOCKING_MODE       ("independent_clock"),
    .READ_LATENCY_A      (2),
    .READ_LATENCY_B      (2),
    .WRITE_MODE_A        ("read_first"),
    .WRITE_MODE_B        ("read_first"),
    .READ_DATA_WIDTH_A   (DATA_WIDTH),
    .WRITE_DATA_WIDTH_A  (DATA_WIDTH),
    .ADDR_WIDTH_A        (ADDR_WIDTH), //19
    .READ_DATA_WIDTH_B   (DATA_WIDTH),
    .WRITE_DATA_WIDTH_B  (DATA_WIDTH),
    .ADDR_WIDTH_B        (ADDR_WIDTH) //19
  ) u_bram_A (
    .clka    (p_clk),
    .rsta    (!arst_p_n),
    .ena     (1'b1),
    .regcea  (1'b1),
    .wea     (a_weA),
    .addra   (a_addrA),
    .dina    (a_dinA),
    .douta   (a_doutA_p),

    .clkb    (c_clk),
    .rstb    (!arst_c_n),
    .enb     (1'b1),
    .regceb  (1'b1),
    .web     (1'b0),
    .addrb   (addr_c),
    .dinb    ({DATA_WIDTH{1'b0}}),
    .doutb   (a_doutB_c),

    .sleep           (1'b0),
    .injectsbiterra (1'b0),   
    .injectdbiterra (1'b0),   
    .injectsbiterrb (1'b0),   
    .injectdbiterrb (1'b0),   
    .sbiterra       (),      
    .dbiterra       (),     
    .sbiterrb       (),      
    .dbiterrb       ()
  );

  // Bank B
  wire [DATA_WIDTH-1:0] b_doutA_p;
  wire [DATA_WIDTH-1:0] b_doutB_c;

  reg        b_weA;
  reg [ADDR_WIDTH-1:0] b_addrA;
  reg [DATA_WIDTH-1:0] b_dinA;
  always @* begin
    if (!wr_sel_A) begin
      b_weA   = we_p;
      b_addrA = addr_p;
      b_dinA  = din_p;
    end else begin
      b_weA   = 1'b0;
      b_addrA = addr_pix;
      b_dinA  = {DATA_WIDTH{1'b0}};
    end
  end

  xpm_memory_tdpram #(
    .MEMORY_SIZE         (MEM_BITS),
    .MEMORY_PRIMITIVE    ("block"),
    .CLOCKING_MODE       ("independent_clock"),
    .READ_LATENCY_A      (2),
    .READ_LATENCY_B      (2),
    .WRITE_MODE_A        ("read_first"),
    .WRITE_MODE_B        ("read_first"),
    .READ_DATA_WIDTH_A   (DATA_WIDTH),
    .WRITE_DATA_WIDTH_A  (DATA_WIDTH),
    .ADDR_WIDTH_A        (ADDR_WIDTH),
    .READ_DATA_WIDTH_B   (DATA_WIDTH),
    .WRITE_DATA_WIDTH_B  (DATA_WIDTH),
    .ADDR_WIDTH_B        (ADDR_WIDTH)
  ) u_bram_B (
    .clka    (p_clk),
    .rsta    (!arst_p_n),
    .ena     (1'b1),
    .regcea  (1'b1),
    .wea     (b_weA),
    .addra   (b_addrA),
    .dina    (b_dinA),
    .douta   (b_doutA_p),

    .clkb    (c_clk),
    .rstb    (!arst_c_n),
    .enb     (1'b1),
    .regceb  (1'b1),
    .web     (1'b0),
    .addrb   (addr_c),
    .dinb    ({DATA_WIDTH{1'b0}}),
    .doutb   (b_doutB_c),

    .sleep           (1'b0),
    .injectsbiterra (1'b0),   // A 주입
    .injectdbiterra (1'b0),   // A 주입
    .injectsbiterrb (1'b0),   // ★ 추가: B 주입
    .injectdbiterrb (1'b0),   // ★ 추가: B 주입
    .sbiterra       (),       // ★ 추가: A 에러 출력
    .dbiterra       (),       // ★ 추가: A 에러 출력
    .sbiterrb       (),       // B 에러 출력
    .dbiterrb       ()
  );

  // ----------------------------
  // VGA data mux (pixel domain)
  // ----------------------------
  always @(*) begin
    if (rd_sel_A_p) dout_pix = a_doutA_p;
    else            dout_pix = b_doutA_p;
  end

  // ----------------------------
  // Core data mux (core domain)
  // ----------------------------
  always @(*) begin
    if (rd_sel_A_c) dout_c = a_doutB_c;
    else            dout_c = b_doutB_c;
  end

  // ----------------------------
  // Meta → Core domain (2FF sync)
  // ----------------------------
  wire [3:0] meta_rd_p = rd_sel_A_c ? meta_a_p : meta_b_p;
  reg  [3:0] meta_sync1, meta_sync2;
  always @(posedge c_clk or negedge arst_c_n) begin
    if (!arst_c_n) begin
      meta_sync1 <= 4'd0; meta_sync2 <= 4'd0;
    end else begin
      meta_sync1 <= meta_rd_p;
      meta_sync2 <= meta_sync1;
    end
  end
  assign image_num_c = meta_sync2;

endmodule

