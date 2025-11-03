`timescale 1ns/1ps
// ============================================================================
// lenet5_accel_wrap
//  - Bridges preprocess pixel stream to lenet5_core
//  - Instantiates weights_loader_flat (ROM IPs -> flat buses)
//  - Packages scores into 128b AXI-Stream (2 beats: meta, scores[0..7])
//  - Aligns image_num by 2 frames (preprocess(1) + pipeline(1))
// ============================================================================
module lenet5_accel_wrap #(
  parameter integer PIX_BITS   = 8,
  parameter integer WW_BITS    = 8,
  parameter integer OUT_BITS   = 16,
  parameter integer IMG_W      = 32,
  parameter integer FC84_OUT   = 10,
  // core geometry
  parameter integer C1_OUT_CH  = 6,
  parameter integer C3_IN_CH   = 6,
  parameter integer C3_OUT_CH  = 16,
  parameter integer C5_IN_CH   = 16,
  parameter integer C5_OUT_CH  = 120,
  parameter integer FC120_OUT  = 84
)(
  input  wire                    clk,
  input  wire                    arst_n,

  // From preprocess/sensor
  input  wire                    lenet_start,   // 1clk pulse @ frame start (after preprocess)
  input  wire                    lenet_v,       // per-line valid (active video)
  input  wire  signed [7:0]      lenet_pix,     // signed pixels for core
  input  wire  [3:0]             image_num,     // frame id from upstream

  // AXI4-Stream Master (to SDE C2H s_axis 128b)
  output reg  [127:0]            m_axis_tdata,
  output reg                     m_axis_tvalid,
  output reg                     m_axis_tlast,
  input  wire                    m_axis_tready,
  output reg                     m_axis_tuser    // beat tag (0:meta, 1:scores)
);

  // ===========================================================================
  // Reset
  // ===========================================================================
  wire rst_n = arst_n;

  // ===========================================================================
  // Weights/Bias loader (assumes ROM IP 1-cycle latency; loader compensates)
  // ===========================================================================
  wire [WW_BITS*(C1_OUT_CH*25)-1:0]            c1_w_flat;
  wire [16*C1_OUT_CH-1:0]                      c1_b_flat;

  wire [WW_BITS*(C3_OUT_CH*C3_IN_CH*25)-1:0]   c3_w_flat;
  wire [(OUT_BITS+WW_BITS+5)*C3_OUT_CH-1:0]    c3_b_flat;

  wire [WW_BITS*(C5_OUT_CH*C5_IN_CH*25)-1:0]   c5_w_flat;
  wire [(OUT_BITS+WW_BITS+9)*C5_OUT_CH-1:0]    c5_b_flat;

  wire [WW_BITS*(FC120_OUT*C5_OUT_CH)-1:0]     fc120_w_flat;
  wire [OUT_BITS*FC120_OUT-1:0]                fc120_b_flat;

  wire [WW_BITS*(FC84_OUT*FC120_OUT)-1:0]      fc84_w_flat;
  wire [OUT_BITS*FC84_OUT-1:0]                 fc84_b_flat;

  wire loaded;

  weights_loader_flat #(
    .WW_BITS(WW_BITS), .OUT_BITS(OUT_BITS),
    .C1_OUT_CH(C1_OUT_CH), .C3_IN_CH(C3_IN_CH), .C3_OUT_CH(C3_OUT_CH),
    .C5_IN_CH(C5_IN_CH), .C5_OUT_CH(C5_OUT_CH),
    .FC120_OUT(FC120_OUT), .FC84_OUT(FC84_OUT)
  ) U_WLOAD (
    .clk(clk), .rst_n(rst_n),
    .c1_w_flat(c1_w_flat), .c1_b_flat(c1_b_flat),
    .c3_w_flat(c3_w_flat), .c3_b_flat(c3_b_flat),
    .c5_w_flat(c5_w_flat), .c5_b_flat(c5_b_flat),
    .fc120_w_flat(fc120_w_flat), .fc120_b_flat(fc120_b_flat),
    .fc84_w_flat(fc84_w_flat), .fc84_b_flat(fc84_b_flat),
    .loaded(loaded)
  );

  // ===========================================================================
  // Core
  // ===========================================================================
  wire                              core_prob_valid;
  wire signed [FC84_OUT*OUT_BITS-1:0] core_prob_flat;
  wire [3:0]                        core_pred_digit;
  wire                              core_pred_valid;
  wire                              s_ready;

  lenet5_core #(
    .PIX_BITS(PIX_BITS), .WW_BITS(WW_BITS), .OUT_BITS(OUT_BITS),
    .IMG_W(IMG_W),
    .C1_OUT_CH(C1_OUT_CH),
    .C3_IN_CH(C3_IN_CH), .C3_OUT_CH(C3_OUT_CH),
    .C5_IN_CH(C5_IN_CH), .C5_OUT_CH(C5_OUT_CH),
    .FC120_OUT(FC120_OUT), .FC84_OUT(FC84_OUT)
  ) U_CORE (
    .clk(clk), .rst_n(rst_n),
    .in_valid(lenet_v & loaded),
    .in_pix  (lenet_pix),
    .in_ready(s_ready),

    .c1_w_flat(c1_w_flat), .c1_b_flat(c1_b_flat),
    .c3_w_flat(c3_w_flat), .c3_b_flat(c3_b_flat),
    .c5_w_flat(c5_w_flat), .c5_b_flat(c5_b_flat),
    .fc120_w_flat(fc120_w_flat), .fc120_b_flat(fc120_b_flat),
    .fc84_w_flat(fc84_w_flat), .fc84_b_flat(fc84_b_flat),

    .prob_valid (core_prob_valid),
    .prob10_flat(core_prob_flat),
    .pred_digit (core_pred_digit),
    .pred_valid (core_pred_valid)
  );

  // ===========================================================================
  // Cycle counter & T0/T1 (speed markers)
  //  - T0: first lenet_v of the frame
  //  - T1: when pred_valid fires (end of inference)
  // ===========================================================================
  reg [63:0] cyc;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cyc <= 64'd0;
    else        cyc <= cyc + 64'd1;
  end

  reg [63:0] T0, T1;
  reg        started;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      started <= 1'b0;
      T0      <= 64'd0;
      T1      <= 64'd0;
    end else begin
      if (!started && lenet_v) begin
        started <= 1'b1;
        T0      <= cyc;
      end
      if (core_pred_valid) begin
        T1      <= cyc;
        started <= 1'b0;
      end
    end
  end

  // ===========================================================================
  // image_num +2 frames (ROM load align(1) + preprocess frame latency(1))
  // ===========================================================================
  reg [3:0] imgnum_q0, imgnum_q1, imgnum_q2;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      imgnum_q0 <= 4'd0;
      imgnum_q1 <= 4'd0;
      imgnum_q2 <= 4'd0;
    end else if (lenet_start) begin
      imgnum_q0 <= image_num;
      imgnum_q1 <= imgnum_q0;
      imgnum_q2 <= imgnum_q1;
    end
  end

  // ===========================================================================
  // AXI4-Stream (128b) 2-beat: beat0(meta), beat1(scores[0..7])
  // Moore FSM for clean handshakes
  // ===========================================================================
  localparam AXI_IDLE = 2'd0;
  localparam AXI_B0   = 2'd1;
  localparam AXI_B1   = 2'd2;

  reg [1:0] st, st_n;

  always @* begin
    st_n = st;
    case (st)
      AXI_IDLE: if (core_prob_valid)            st_n = AXI_B0;
      AXI_B0  : if (m_axis_tvalid && m_axis_tready) st_n = AXI_B1;
      AXI_B1  : if (m_axis_tvalid && m_axis_tready) st_n = AXI_IDLE;
      default : st_n = AXI_IDLE;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) st <= AXI_IDLE;
    else        st <= st_n;
  end

  // unpack 16b scores from core_prob_flat
  wire signed [15:0] sc [0:FC84_OUT-1];
  genvar gi;
  generate
    for (gi = 0; gi < FC84_OUT; gi = gi + 1) begin : GSC
      assign sc[gi] = core_prob_flat[gi*OUT_BITS +: OUT_BITS];
    end
  endgenerate

  // AXIS outputs
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      m_axis_tuser  <= 1'b0;
      m_axis_tdata  <= 128'd0;
    end else begin
      case (st)
        AXI_IDLE: begin
          // prepare next beat0 when entering AXI_B0
          m_axis_tvalid <= 1'b0;
          m_axis_tlast  <= 1'b0;
          m_axis_tuser  <= 1'b0;
          m_axis_tdata  <= 128'd0;
          if (core_prob_valid) begin
            // drive valid in next state
            // (state reg updates next cycle; here just keep defaults)
          end
        end

        AXI_B0: begin
          m_axis_tvalid <= 1'b1;
          m_axis_tlast  <= 1'b0;
          m_axis_tuser  <= 1'b0; // meta
          // {T1_hi, T0_hi, reserved24, imgnum(4), pred(4), T1_lo}
          m_axis_tdata  <= { T1[63:32], T0[63:32], 24'd0, imgnum_q2, core_pred_digit, T1[31:0] };
        end

        AXI_B1: begin
          m_axis_tvalid <= 1'b1;
          m_axis_tlast  <= 1'b1;
          m_axis_tuser  <= 1'b1; // scores
          // 8 scores (little-endian 16b lanes)
          m_axis_tdata <= {
  core_prob_flat[7*OUT_BITS +: OUT_BITS],
  core_prob_flat[6*OUT_BITS +: OUT_BITS],
  core_prob_flat[5*OUT_BITS +: OUT_BITS],
  core_prob_flat[4*OUT_BITS +: OUT_BITS],
  core_prob_flat[3*OUT_BITS +: OUT_BITS],
  core_prob_flat[2*OUT_BITS +: OUT_BITS],
  core_prob_flat[1*OUT_BITS +: OUT_BITS],
  core_prob_flat[0*OUT_BITS +: OUT_BITS]
};
        end

        default: begin
          m_axis_tvalid <= 1'b0;
          m_axis_tlast  <= 1'b0;
          m_axis_tuser  <= 1'b0;
          m_axis_tdata  <= 128'd0;
        end
      endcase
    end
  end

endmodule

