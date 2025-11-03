`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// conv5 (Verilog-2001, clean)
// - IN_CH:16, OUT_CH:120 (parameterizable)
// - 25-tap �� IN_CH accumulation, OC_PAR lanes in parallel
// - Safe lane mask, variable part-select for weights/bias (Verilog-2001 +:)
// - FSM: COLLECT -> ACC -> FINALIZE(1clk buffer) -> EMIT
// - v_tree_all = &((~lane_mask_vec) | v_tree_lane) : ignore inactive lanes
// - FIX: IC ����(tree_ce�� ����Ʈ) �� ù ���� ���� ����
// -----------------------------------------------------------------------------
module conv5 #(
  parameter integer IN_CH     = 16,
  parameter integer OUT_CH    = 120,
  parameter integer PIX_BITS  = 16,
  parameter integer WW_BITS   = 8,
  parameter integer PROD_BITS = PIX_BITS + WW_BITS,
  parameter integer SUM_BITS  = PROD_BITS + 9,
  parameter integer OUT_BITS  = 16,
  parameter integer SHIFT_R   = 0,
  parameter integer RELU_EN   = 1,
  parameter integer OC_PAR    = 8
)(
  input  wire                             clk,
  input  wire                             rst_n,
  input  wire                             valid_in,
  input  wire [IN_CH*PIX_BITS-1:0] pix_in_flat,
  input  wire signed [OUT_CH*IN_CH*25*WW_BITS-1:0] w_flat,
  input  wire signed [OUT_CH*SUM_BITS-1:0]         b_flat,
  output reg                              valid_out,
  output reg        [6:0]                ch_idx,
  output reg        [OUT_BITS-1:0]       pix_out,
  output reg                              vec_valid
);
  localparam integer P_W      = PIX_BITS + 1; 
  
  function signed [WW_BITS-1:0] pick_w;
    input      [OUT_CH*IN_CH*25*WW_BITS-1:0] bus;
    input integer base; begin pick_w = bus[base +: WW_BITS]; end
  endfunction
  function signed [SUM_BITS-1:0] pick_b;
    input      [OUT_CH*SUM_BITS-1:0] bus;
    input integer base; begin pick_b = bus[base +: SUM_BITS]; end
  endfunction
  function signed [SUM_BITS-1:0] ext_sum;
    input signed [PROD_BITS-1:0] x;
    begin ext_sum = {{(SUM_BITS-PROD_BITS){x[PROD_BITS-1]}}, x}; end
  endfunction

  reg signed [IN_CH*PIX_BITS-1:0] fbuf [0:24];
  reg  [5:0] s_cnt;   // 0..24
  reg  [4:0] ic;      // 0..IN_CH-1

  wire signed [P_W-1:0] tap0  = {1'b0, fbuf[ 0][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap1  = {1'b0, fbuf[ 1][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap2  = {1'b0, fbuf[ 2][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap3  = {1'b0, fbuf[ 3][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap4  = {1'b0, fbuf[ 4][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap5  = {1'b0, fbuf[ 5][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap6  = {1'b0, fbuf[ 6][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap7  = {1'b0, fbuf[ 7][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap8  = {1'b0, fbuf[ 8][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap9  = {1'b0, fbuf[ 9][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap10 = {1'b0, fbuf[10][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap11 = {1'b0, fbuf[11][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap12 = {1'b0, fbuf[12][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap13 = {1'b0, fbuf[13][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap14 = {1'b0, fbuf[14][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap15 = {1'b0, fbuf[15][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap16 = {1'b0, fbuf[16][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap17 = {1'b0, fbuf[17][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap18 = {1'b0, fbuf[18][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap19 = {1'b0, fbuf[19][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap20 = {1'b0, fbuf[20][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap21 = {1'b0, fbuf[21][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap22 = {1'b0, fbuf[22][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap23 = {1'b0, fbuf[23][ic*PIX_BITS +: PIX_BITS]};
  wire signed [P_W-1:0] tap24 = {1'b0, fbuf[24][ic*PIX_BITS +: PIX_BITS]};

  localparam [1:0] S_COLLECT=2'd0, S_ACC=2'd1, S_FINALIZE=2'd2, S_EMIT=2'd3;
  reg [1:0] state, next_state;

  reg  [15:0] oc_base, oc_base_start;
  reg  [4:0]  acc_cnt;
  reg         acc_clear, is_injecting;
  reg  [7:0]  emit_idx;

  reg  signed [SUM_BITS-1:0] acc       [0:OC_PAR-1];
  reg  [OUT_BITS-1:0] final_pix [0:OC_PAR-1];
  reg         [15:0]         final_ch  [0:OC_PAR-1];
  reg         [OC_PAR-1:0]   out_mask;

  wire [OC_PAR-1:0] lane_mask_vec, v_tree_lane;
  wire signed [OC_PAR*SUM_BITS-1:0] lane_sum_flat;

  localparam integer TREE_LAT = 5;

  wire v_tree_all = &((~lane_mask_vec) | v_tree_lane);
  wire v_tree_all_w = v_tree_all;
  wire acc_done = (state==S_ACC) && v_tree_all_w && (acc_cnt == IN_CH-1);
  wire tree_ce  = (state==S_ACC) & ~acc_clear & is_injecting;

  always @(posedge clk) begin
    if (!rst_n) state <= S_COLLECT;
    else        state <= next_state;
  end

  always @* begin
    next_state = state;
    case (state)
      S_COLLECT:  if (valid_in && (s_cnt==6'd24)) next_state = S_ACC;
      S_ACC:      if (acc_done)                   next_state = S_FINALIZE;
      S_FINALIZE:                                 next_state = S_EMIT;
      S_EMIT: begin
        if (emit_idx == OC_PAR)
          next_state = (oc_base + OC_PAR < OUT_CH) ? S_ACC : S_COLLECT;
        else
          next_state = S_EMIT;
      end
    endcase
  end

  genvar gi;
  generate
    for (gi=0; gi<OC_PAR; gi=gi+1) begin : G_TREES
      wire [15:0] oc_lane   = oc_base + gi[15:0];
      wire        lane_mask = (oc_lane < OUT_CH);
      assign lane_mask_vec[gi] = lane_mask;

      wire [31:0] base_w_idx_raw  = (((oc_lane*IN_CH) + ic) * 25) * WW_BITS;
      wire [31:0] base_w_idx_safe = lane_mask ? base_w_idx_raw : 32'd0;

      wire tree_ce_lane = tree_ce & lane_mask;

      wire signed [P_W-1:0] t0  = tree_ce_lane ? tap0  : {P_W{1'b0}};
      wire signed [P_W-1:0] t1  = tree_ce_lane ? tap1  : {P_W{1'b0}};
      wire signed [P_W-1:0] t2  = tree_ce_lane ? tap2  : {P_W{1'b0}};
      wire signed [P_W-1:0] t3  = tree_ce_lane ? tap3  : {P_W{1'b0}};
      wire signed [P_W-1:0] t4  = tree_ce_lane ? tap4  : {P_W{1'b0}};
      wire signed [P_W-1:0] t5  = tree_ce_lane ? tap5  : {P_W{1'b0}};
      wire signed [P_W-1:0] t6  = tree_ce_lane ? tap6  : {P_W{1'b0}};
      wire signed [P_W-1:0] t7  = tree_ce_lane ? tap7  : {P_W{1'b0}};
      wire signed [P_W-1:0] t8  = tree_ce_lane ? tap8  : {P_W{1'b0}};
      wire signed [P_W-1:0] t9  = tree_ce_lane ? tap9  : {P_W{1'b0}};
      wire signed [P_W-1:0] t10 = tree_ce_lane ? tap10 : {P_W{1'b0}};
      wire signed [P_W-1:0] t11 = tree_ce_lane ? tap11 : {P_W{1'b0}};
      wire signed [P_W-1:0] t12 = tree_ce_lane ? tap12 : {P_W{1'b0}};
      wire signed [P_W-1:0] t13 = tree_ce_lane ? tap13 : {P_W{1'b0}};
      wire signed [P_W-1:0] t14 = tree_ce_lane ? tap14 : {P_W{1'b0}};
      wire signed [P_W-1:0] t15 = tree_ce_lane ? tap15 : {P_W{1'b0}};
      wire signed [P_W-1:0] t16 = tree_ce_lane ? tap16 : {P_W{1'b0}};
      wire signed [P_W-1:0] t17 = tree_ce_lane ? tap17 : {P_W{1'b0}};
      wire signed [P_W-1:0] t18 = tree_ce_lane ? tap18 : {P_W{1'b0}};
      wire signed [P_W-1:0] t19 = tree_ce_lane ? tap19 : {P_W{1'b0}};
      wire signed [P_W-1:0] t20 = tree_ce_lane ? tap20 : {P_W{1'b0}};
      wire signed [P_W-1:0] t21 = tree_ce_lane ? tap21 : {P_W{1'b0}};
      wire signed [P_W-1:0] t22 = tree_ce_lane ? tap22 : {P_W{1'b0}};
      wire signed [P_W-1:0] t23 = tree_ce_lane ? tap23 : {P_W{1'b0}};
      wire signed [P_W-1:0] t24 = tree_ce_lane ? tap24 : {P_W{1'b0}};

      wire signed [WW_BITS-1:0]  w0  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 0) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w1  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 1) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w2  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 2) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w3  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 3) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w4  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 4) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w5  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 5) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w6  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 6) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w7  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 7) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w8  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 8) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w9  = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS* 9) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w10 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*10) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w11 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*11) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w12 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*12) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w13 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*13) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w14 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*14) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w15 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*15) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w16 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*16) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w17 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*17) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w18 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*18) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w19 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*19) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w20 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*20) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w21 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*21) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w22 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*22) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w23 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*23) : {WW_BITS{1'b0}};
      wire signed [WW_BITS-1:0]  w24 = tree_ce_lane ? pick_w(w_flat, base_w_idx_safe + WW_BITS*24) : {WW_BITS{1'b0}};

      wire signed [PROD_BITS-1:0] m0  = t0  * w0;
      wire signed [PROD_BITS-1:0] m1  = t1  * w1;
      wire signed [PROD_BITS-1:0] m2  = t2  * w2;
      wire signed [PROD_BITS-1:0] m3  = t3  * w3;
      wire signed [PROD_BITS-1:0] m4  = t4  * w4;
      wire signed [PROD_BITS-1:0] m5  = t5  * w5;
      wire signed [PROD_BITS-1:0] m6  = t6  * w6;
      wire signed [PROD_BITS-1:0] m7  = t7  * w7;
      wire signed [PROD_BITS-1:0] m8  = t8  * w8;
      wire signed [PROD_BITS-1:0] m9  = t9  * w9;
      wire signed [PROD_BITS-1:0] m10 = t10 * w10;
      wire signed [PROD_BITS-1:0] m11 = t11 * w11;
      wire signed [PROD_BITS-1:0] m12 = t12 * w12;
      wire signed [PROD_BITS-1:0] m13 = t13 * w13;
      wire signed [PROD_BITS-1:0] m14 = t14 * w14;
      wire signed [PROD_BITS-1:0] m15 = t15 * w15;
      wire signed [PROD_BITS-1:0] m16 = t16 * w16;
      wire signed [PROD_BITS-1:0] m17 = t17 * w17;
      wire signed [PROD_BITS-1:0] m18 = t18 * w18;
      wire signed [PROD_BITS-1:0] m19 = t19 * w19;
      wire signed [PROD_BITS-1:0] m20 = t20 * w20;
      wire signed [PROD_BITS-1:0] m21 = t21 * w21;
      wire signed [PROD_BITS-1:0] m22 = t22 * w22;
      wire signed [PROD_BITS-1:0] m23 = t23 * w23;
      wire signed [PROD_BITS-1:0] m24 = t24 * w24;

      reg signed [SUM_BITS-1:0] s1 [0:12];
      reg signed [SUM_BITS-1:0] s2 [0:6];
      reg signed [SUM_BITS-1:0] s3 [0:3];
      reg signed [SUM_BITS-1:0] s4 [0:1];
      reg signed [SUM_BITS-1:0] s5;
      reg [TREE_LAT-1:0] vpipe;
      integer si;

      always @(posedge clk) begin
        if (!rst_n) begin
          for (si=0; si<=12; si=si+1) s1[si] <= {SUM_BITS{1'b0}};
          for (si=0; si<=6;  si=si+1) s2[si] <= {SUM_BITS{1'b0}};
          for (si=0; si<=3;  si=si+1) s3[si] <= {SUM_BITS{1'b0}};
          s4[0] <= {SUM_BITS{1'b0}};
          s4[1] <= {SUM_BITS{1'b0}};
          s5    <= {SUM_BITS{1'b0}};
          vpipe <= {TREE_LAT{1'b0}};
        end else begin
          vpipe <= {vpipe[TREE_LAT-2:0], tree_ce_lane};
          s1[ 0] <= ext_sum(m0 ) + ext_sum(m1 );
          s1[ 1] <= ext_sum(m2 ) + ext_sum(m3 );
          s1[ 2] <= ext_sum(m4 ) + ext_sum(m5 );
          s1[ 3] <= ext_sum(m6 ) + ext_sum(m7 );
          s1[ 4] <= ext_sum(m8 ) + ext_sum(m9 );
          s1[ 5] <= ext_sum(m10) + ext_sum(m11);
          s1[ 6] <= ext_sum(m12) + ext_sum(m13);
          s1[ 7] <= ext_sum(m14) + ext_sum(m15);
          s1[ 8] <= ext_sum(m16) + ext_sum(m17);
          s1[ 9] <= ext_sum(m18) + ext_sum(m19);
          s1[10] <= ext_sum(m20) + ext_sum(m21);
          s1[11] <= ext_sum(m22) + ext_sum(m23);
          s1[12] <= ext_sum(m24);
          s2[0] <= s1[0] + s1[1];
          s2[1] <= s1[2] + s1[3];
          s2[2] <= s1[4] + s1[5];
          s2[3] <= s1[6] + s1[7];
          s2[4] <= s1[8] + s1[9];
          s2[5] <= s1[10] + s1[11];
          s2[6] <= s1[12];
          s3[0] <= s2[0] + s2[1];
          s3[1] <= s2[2] + s2[3];
          s3[2] <= s2[4] + s2[5];
          s3[3] <= s2[6];
          s4[0] <= s3[0] + s3[1];
          s4[1] <= s3[2] + s3[3];
          s5    <= s4[0] + s4[1];
        end
      end

      assign v_tree_lane[gi] = vpipe[TREE_LAT-1];
      assign lane_sum_flat[gi*SUM_BITS +: SUM_BITS] = s5;
    end
  endgenerate

  wire signed [OC_PAR*SUM_BITS-1:0] t_relu_flat;
  genvar fk;
  generate
    for (fk=0; fk<OC_PAR; fk=fk+1) begin : G_FINAL
      wire [15:0] oc_b   = oc_base_start + fk[15:0];
      wire        mask_b = (oc_b < OUT_CH);
      wire [31:0] base_b = mask_b ? (oc_b*SUM_BITS) : 32'd0;

      wire signed [OUT_BITS-1:0] b_cur   = mask_b ? pick_b(b_flat, base_b) : {OUT_BITS{1'b0}};
      wire signed [OUT_BITS-1:0] add_cur = acc[fk][26:11] + b_cur;
      wire signed [OUT_BITS-1:0] relu_cur  = (RELU_EN==1) ? (add_cur[OUT_BITS-1] ? {OUT_BITS{1'b0}} : add_cur)
                                                          : add_cur;
      assign t_relu_flat[fk*OUT_BITS +: OUT_BITS] = relu_cur;
    end
  endgenerate
 integer kk2; 
  integer i,k;
  always @(posedge clk) begin
    if (!rst_n) begin
      state<=S_COLLECT; s_cnt<=0; ic<=0; oc_base<=0; oc_base_start<=0;
      acc_cnt<=0; acc_clear<=1'b0; is_injecting<=1'b0; emit_idx<=0;
      valid_out<=1'b0; pix_out<={OUT_BITS{1'b0}}; vec_valid<=1'b0;
      for (i=0; i<25; i=i+1) fbuf[i] <= {IN_CH*PIX_BITS{1'b0}};
      for (k=0; k<OC_PAR; k=k+1) begin
        acc[k] <= {SUM_BITS{1'b0}}; final_pix[k]<={OUT_BITS{1'b0}}; final_ch[k]<=16'd0;
      end
      out_mask <= {OC_PAR{1'b0}};
    end else begin
      valid_out<=1'b0; vec_valid<=1'b0;

      case (state)
        S_COLLECT: begin
          if (valid_in) begin
            fbuf[s_cnt] <= pix_in_flat;
            if (s_cnt==6'd24) begin
              s_cnt<=0; ic<=0; oc_base<=0; acc_cnt<=0; acc_clear<=1'b1; is_injecting<=1'b1;
            end else begin
              s_cnt <= s_cnt + 6'd1;
            end
          end
        end

        S_ACC: begin
          if (acc_clear) begin
           for (kk2=0; kk2<OC_PAR; kk2=kk2+1) acc[kk2] <= {SUM_BITS{1'b0}};
            acc_cnt<=0; acc_clear<=1'b0;
          end
          if (v_tree_all_w) begin
            for (k=0; k<OC_PAR; k=k+1)
              acc[k] <= acc[k] + lane_sum_flat[k*SUM_BITS +: SUM_BITS];
            if (acc_cnt == IN_CH-1) begin
              oc_base_start <= oc_base;
              for (k=0; k<OC_PAR; k=k+1) begin
                final_ch[k] <= oc_base + k[15:0];
                out_mask[k] <= (oc_base + k < OUT_CH);
              end
            end
            acc_cnt <= acc_cnt + 5'd1;
          end
          // �� FIX: ����(tree_ce) ����Ŭ������ ic ����
          if (is_injecting && tree_ce) begin
            if (ic == IN_CH-1) begin
              ic <= 0; is_injecting <= 1'b0;
            end else begin
              ic <= ic + 5'd1;
            end
          end
        end

        S_FINALIZE: begin
          for (k=0; k<OC_PAR; k=k+1)
            final_pix[k] <= t_relu_flat[k*OUT_BITS +: OUT_BITS];
          emit_idx <= 0;
        end

        S_EMIT: begin
          if (emit_idx < OC_PAR) begin
            if (out_mask[emit_idx]) begin
              valid_out <= 1'b1;
              pix_out   <= final_pix[emit_idx];
              ch_idx    <= final_ch [emit_idx];
            end
            emit_idx <= emit_idx + 8'd1;
          end else begin
            emit_idx <= 0;
            if (oc_base + OC_PAR < OUT_CH) begin
              oc_base <= oc_base + OC_PAR[15:0];
              ic<=0; acc_cnt<=0; acc_clear<=1'b1; is_injecting<=1'b1;
            end else begin
              vec_valid <= 1'b1;
            end
          end
        end
      endcase
    end
  end

endmodule
