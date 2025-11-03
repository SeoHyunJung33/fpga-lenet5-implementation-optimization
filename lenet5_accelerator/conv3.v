`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// conv3 (IN_CH=6 ����, level-valid �Է��� �����ϰ� �����ϴ� ���� ������)
//  - �Է�: 6ä�� 5x5 ������ ��Ʈ��(valid)
//  - ����: ������ A/B 2���� ���� + OUT_CH ��ŭ ä�� �߻�
//  - oc �±׸� fire_sum�� ����ȭ�� ������ �� ch_idx �������̿� ����
//  - adder_tree_pipe ����(5) + ��� ���� 3�� + acc 1�� �� �±� ������ 9��
//  - ��� �������� ���� 0 �ʱ�ȭ(X ����)
// -----------------------------------------------------------------------------
module conv3 #(
    parameter IMG_WIDTH  = 14,
    parameter IN_CH      = 6,    // ���� 6
    parameter OUT_CH     = 16,
    parameter PIX_BITS   = 16,
    parameter WW_BITS    = 8,
    parameter PROD_BITS  = PIX_BITS + WW_BITS,
    parameter SUM_BITS   = PROD_BITS + 5, // 25tap
    parameter OUT_BITS   = 16,
    parameter SHIFT_R    = 0
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         valid_in,
    input  wire [PIX_BITS-1:0]   pix_in1,
    input  wire [PIX_BITS-1:0]   pix_in2,
    input  wire [PIX_BITS-1:0]   pix_in3,
    input  wire [PIX_BITS-1:0]   pix_in4,
    input  wire [PIX_BITS-1:0]   pix_in5,
    input  wire [PIX_BITS-1:0]   pix_in6,

    input  wire signed [OUT_CH*IN_CH*25*WW_BITS-1:0] w_flat,
    input  wire signed [OUT_CH*SUM_BITS-1:0]         b_flat,

    output reg                          valid_out,
    output reg        [15:0]            ch_idx,
    output reg  signed [OUT_BITS-1:0]   pix_out
);
    localparam integer P_W      = PIX_BITS + 1; 
    // ---------------- util: CLOG2 ----------------
    function integer CLOG2; input integer v; integer t; begin
        t=v-1; CLOG2=0; while(t>0) begin t=t>>1; CLOG2=CLOG2+1; end
    end endfunction
    localparam integer OC_W = (OUT_CH<=1)?1:CLOG2(OUT_CH);
    
    wire signed [P_W-1:0] pix_in_se1 = {1'b0, pix_in1};
    wire signed [P_W-1:0] pix_in_se2 = {1'b0, pix_in2};
    wire signed [P_W-1:0] pix_in_se3 = {1'b0, pix_in3};
    wire signed [P_W-1:0] pix_in_se4 = {1'b0, pix_in4};
    wire signed [P_W-1:0] pix_in_se5 = {1'b0, pix_in5};
    wire signed [P_W-1:0] pix_in_se6 = {1'b0, pix_in6};
    
    // ===== 6x 5x5 window generators =====
    wire v0,v1,v2,v3,v4,v5;
    // ch0
    wire signed [P_W-1:0]
      w00_0,w01_0,w02_0,w03_0,w04_0,  w10_0,w11_0,w12_0,w13_0,w14_0,
      w20_0,w21_0,w22_0,w23_0,w24_0,  w30_0,w31_0,w32_0,w33_0,w34_0,
      w40_0,w41_0,w42_0,w43_0,w44_0;
    // ch1
    wire signed [P_W-1:0]
      w00_1,w01_1,w02_1,w03_1,w04_1,  w10_1,w11_1,w12_1,w13_1,w14_1,
      w20_1,w21_1,w22_1,w23_1,w24_1,  w30_1,w31_1,w32_1,w33_1,w34_1,
      w40_1,w41_1,w42_1,w43_1,w44_1;
    // ch2
    wire signed [P_W-1:0]
      w00_2,w01_2,w02_2,w03_2,w04_2,  w10_2,w11_2,w12_2,w13_2,w14_2,
      w20_2,w21_2,w22_2,w23_2,w24_2,  w30_2,w31_2,w32_2,w33_2,w34_2,
      w40_2,w41_2,w42_2,w43_2,w44_2;
    // ch3
    wire signed [P_W-1:0]
      w00_3,w01_3,w02_3,w03_3,w04_3,  w10_3,w11_3,w12_3,w13_3,w14_3,
      w20_3,w21_3,w22_3,w23_3,w24_3,  w30_3,w31_3,w32_3,w33_3,w34_3,
      w40_3,w41_3,w42_3,w43_3,w44_3;
    // ch4
    wire signed [P_W-1:0]
      w00_4,w01_4,w02_4,w03_4,w04_4,  w10_4,w11_4,w12_4,w13_4,w14_4,
      w20_4,w21_4,w22_4,w23_4,w24_4,  w30_4,w31_4,w32_4,w33_4,w34_4,
      w40_4,w41_4,w42_4,w43_4,w44_4;
    // ch5
    wire signed [P_W-1:0]
      w00_5,w01_5,w02_5,w03_5,w04_5,  w10_5,w11_5,w12_5,w13_5,w14_5,
      w20_5,w21_5,w22_5,w23_5,w24_5,  w30_5,w31_5,w32_5,w33_5,w34_5,
      w40_5,w41_5,w42_5,w43_5,w44_5;

    win5x5_stream #(.IMG_WIDTH(IMG_WIDTH), .PIX_BITS(P_W)) U0(
      .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .pix_in(pix_in_se1), .valid_out(v0),
      .w00(w00_0),.w01(w01_0),.w02(w02_0),.w03(w03_0),.w04(w04_0),
      .w10(w10_0),.w11(w11_0),.w12(w12_0),.w13(w13_0),.w14(w14_0),
      .w20(w20_0),.w21(w21_0),.w22(w22_0),.w23(w23_0),.w24(w24_0),
      .w30(w30_0),.w31(w31_0),.w32(w32_0),.w33(w33_0),.w34(w34_0),
      .w40(w40_0),.w41(w41_0),.w42(w42_0),.w43(w43_0),.w44(w44_0)
    );
    win5x5_stream #(.IMG_WIDTH(IMG_WIDTH), .PIX_BITS(P_W)) U1(
      .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .pix_in(pix_in_se2), .valid_out(v1),
      .w00(w00_1),.w01(w01_1),.w02(w02_1),.w03(w03_1),.w04(w04_1),
      .w10(w10_1),.w11(w11_1),.w12(w12_1),.w13(w13_1),.w14(w14_1),
      .w20(w20_1),.w21(w21_1),.w22(w22_1),.w23(w23_1),.w24(w24_1),
      .w30(w30_1),.w31(w31_1),.w32(w32_1),.w33(w33_1),.w34(w34_1),
      .w40(w40_1),.w41(w41_1),.w42(w42_1),.w43(w43_1),.w44(w44_1)
    );
    win5x5_stream #(.IMG_WIDTH(IMG_WIDTH), .PIX_BITS(P_W)) U2(
      .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .pix_in(pix_in_se3), .valid_out(v2),
      .w00(w00_2),.w01(w01_2),.w02(w02_2),.w03(w03_2),.w04(w04_2),
      .w10(w10_2),.w11(w11_2),.w12(w12_2),.w13(w13_2),.w14(w14_2),
      .w20(w20_2),.w21(w21_2),.w22(w22_2),.w23(w23_2),.w24(w24_2),
      .w30(w30_2),.w31(w31_2),.w32(w32_2),.w33(w33_2),.w34(w34_2),
      .w40(w40_2),.w41(w41_2),.w42(w42_2),.w43(w43_2),.w44(w44_2)
    );
    win5x5_stream #(.IMG_WIDTH(IMG_WIDTH), .PIX_BITS(P_W)) U3(
      .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .pix_in(pix_in_se4), .valid_out(v3),
      .w00(w00_3),.w01(w01_3),.w02(w02_3),.w03(w03_3),.w04(w04_3),
      .w10(w10_3),.w11(w11_3),.w12(w12_3),.w13(w13_3),.w14(w14_3),
      .w20(w20_3),.w21(w21_3),.w22(w22_3),.w23(w23_3),.w24(w24_3),
      .w30(w30_3),.w31(w31_3),.w32(w32_3),.w33(w33_3),.w34(w34_3),
      .w40(w40_3),.w41(w41_3),.w42(w42_3),.w43(w43_3),.w44(w44_3)
    );
    win5x5_stream #(.IMG_WIDTH(IMG_WIDTH), .PIX_BITS(P_W)) U4(
      .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .pix_in(pix_in_se5), .valid_out(v4),
      .w00(w00_4),.w01(w01_4),.w02(w02_4),.w03(w03_4),.w04(w04_4),
      .w10(w10_4),.w11(w11_4),.w12(w12_4),.w13(w13_4),.w14(w14_4),
      .w20(w20_4),.w21(w21_4),.w22(w22_4),.w23(w23_4),.w24(w24_4),
      .w30(w30_4),.w31(w31_4),.w32(w32_4),.w33(w33_4),.w34(w34_4),
      .w40(w40_4),.w41(w41_4),.w42(w42_4),.w43(w43_4),.w44(w44_4)
    );
    win5x5_stream #(.IMG_WIDTH(IMG_WIDTH), .PIX_BITS(P_W)) U5(
      .clk(clk), .rst_n(rst_n), .valid_in(valid_in), .pix_in(pix_in_se6), .valid_out(v5),
      .w00(w00_5),.w01(w01_5),.w02(w02_5),.w03(w03_5),.w04(w04_5),
      .w10(w10_5),.w11(w11_5),.w12(w12_5),.w13(w13_5),.w14(w14_5),
      .w20(w20_5),.w21(w21_5),.w22(w22_5),.w23(w23_5),.w24(w24_5),
      .w30(w30_5),.w31(w31_5),.w32(w32_5),.w33(w33_5),.w34(w34_5),
      .w40(w40_5),.w41(w41_5),.w42(w42_5),.w43(w43_5),.w44(w44_5)
    );

    // -------------------------------------------------------------------------
    // v_all �޽�(6ä���� ���� ��ġ �����츦 ���ÿ� ���� �� 1)
    // -------------------------------------------------------------------------
    wire v_all = v0 & v1 & v2 & v3 & v4 & v5;
    reg  v_all_d;
    wire v_all_p = v_all & ~v_all_d; // ��¿��� �޽�
    always @(posedge clk) begin
      if (!rst_n) v_all_d <= 1'b0;
      else        v_all_d <= v_all;
    end

    // -------------------------------------------------------------------------
    // ���� ����(A/B): ������ 6ch��25tap ����
    //  - A/B ���� full �÷���, ���� �Һ� ���� useA
    // -------------------------------------------------------------------------
    reg winA_full, winB_full, useA;

    // ---- A bank regs
    reg signed [P_W-1:0]
      r00_0_A,r01_0_A,r02_0_A,r03_0_A,r04_0_A,  r10_0_A,r11_0_A,r12_0_A,r13_0_A,r14_0_A,
      r20_0_A,r21_0_A,r22_0_A,r23_0_A,r24_0_A,  r30_0_A,r31_0_A,r32_0_A,r33_0_A,r34_0_A,
      r40_0_A,r41_0_A,r42_0_A,r43_0_A,r44_0_A;
    reg signed [P_W-1:0]
      r00_1_A,r01_1_A,r02_1_A,r03_1_A,r04_1_A,  r10_1_A,r11_1_A,r12_1_A,r13_1_A,r14_1_A,
      r20_1_A,r21_1_A,r22_1_A,r23_1_A,r24_1_A,  r30_1_A,r31_1_A,r32_1_A,r33_1_A,r34_1_A,
      r40_1_A,r41_1_A,r42_1_A,r43_1_A,r44_1_A;
    reg signed [P_W-1:0]
      r00_2_A,r01_2_A,r02_2_A,r03_2_A,r04_2_A,  r10_2_A,r11_2_A,r12_2_A,r13_2_A,r14_2_A,
      r20_2_A,r21_2_A,r22_2_A,r23_2_A,r24_2_A,  r30_2_A,r31_2_A,r32_2_A,r33_2_A,r34_2_A,
      r40_2_A,r41_2_A,r42_2_A,r43_2_A,r44_2_A;
    reg signed [P_W-1:0]
      r00_3_A,r01_3_A,r02_3_A,r03_3_A,r04_3_A,  r10_3_A,r11_3_A,r12_3_A,r13_3_A,r14_3_A,
      r20_3_A,r21_3_A,r22_3_A,r23_3_A,r24_3_A,  r30_3_A,r31_3_A,r32_3_A,r33_3_A,r34_3_A,
      r40_3_A,r41_3_A,r42_3_A,r43_3_A,r44_3_A;
    reg signed [P_W-1:0]
      r00_4_A,r01_4_A,r02_4_A,r03_4_A,r04_4_A,  r10_4_A,r11_4_A,r12_4_A,r13_4_A,r14_4_A,
      r20_4_A,r21_4_A,r22_4_A,r23_4_A,r24_4_A,  r30_4_A,r31_4_A,r32_4_A,r33_4_A,r34_4_A,
      r40_4_A,r41_4_A,r42_4_A,r43_4_A,r44_4_A;
    reg signed [P_W-1:0]
      r00_5_A,r01_5_A,r02_5_A,r03_5_A,r04_5_A,  r10_5_A,r11_5_A,r12_5_A,r13_5_A,r14_5_A,
      r20_5_A,r21_5_A,r22_5_A,r23_5_A,r24_5_A,  r30_5_A,r31_5_A,r32_5_A,r33_5_A,r34_5_A,
      r40_5_A,r41_5_A,r42_5_A,r43_5_A,r44_5_A;

    // ---- B bank regs
    reg signed [P_W-1:0]
      r00_0_B,r01_0_B,r02_0_B,r03_0_B,r04_0_B,  r10_0_B,r11_0_B,r12_0_B,r13_0_B,r14_0_B,
      r20_0_B,r21_0_B,r22_0_B,r23_0_B,r24_0_B,  r30_0_B,r31_0_B,r32_0_B,r33_0_B,r34_0_B,
      r40_0_B,r41_0_B,r42_0_B,r43_0_B,r44_0_B;
    reg signed [P_W-1:0]
      r00_1_B,r01_1_B,r02_1_B,r03_1_B,r04_1_B,  r10_1_B,r11_1_B,r12_1_B,r13_1_B,r14_1_B,
      r20_1_B,r21_1_B,r22_1_B,r23_1_B,r24_1_B,  r30_1_B,r31_1_B,r32_1_B,r33_1_B,r34_1_B,
      r40_1_B,r41_1_B,r42_1_B,r43_1_B,r44_1_B;
    reg signed [P_W-1:0]
      r00_2_B,r01_2_B,r02_2_B,r03_2_B,r04_2_B,  r10_2_B,r11_2_B,r12_2_B,r13_2_B,r14_2_B,
      r20_2_B,r21_2_B,r22_2_B,r23_2_B,r24_2_B,  r30_2_B,r31_2_B,r32_2_B,r33_2_B,r34_2_B,
      r40_2_B,r41_2_B,r42_2_B,r43_2_B,r44_2_B;
    reg signed [P_W-1:0]
      r00_3_B,r01_3_B,r02_3_B,r03_3_B,r04_3_B,  r10_3_B,r11_3_B,r12_3_B,r13_3_B,r14_3_B,
      r20_3_B,r21_3_B,r22_3_B,r23_3_B,r24_3_B,  r30_3_B,r31_3_B,r32_3_B,r33_3_B,r34_3_B,
      r40_3_B,r41_3_B,r42_3_B,r43_3_B,r44_3_B;
    reg signed [P_W-1:0]
      r00_4_B,r01_4_B,r02_4_B,r03_4_B,r04_4_B,  r10_4_B,r11_4_B,r12_4_B,r13_4_B,r14_4_B,
      r20_4_B,r21_4_B,r22_4_B,r23_4_B,r24_4_B,  r30_4_B,r31_4_B,r32_4_B,r33_4_B,r34_4_B,
      r40_4_B,r41_4_B,r42_4_B,r43_4_B,r44_4_B;
    reg signed [P_W-1:0]
      r00_5_B,r01_5_B,r02_5_B,r03_5_B,r04_5_B,  r10_5_B,r11_5_B,r12_5_B,r13_5_B,r14_5_B,
      r20_5_B,r21_5_B,r22_5_B,r23_5_B,r24_5_B,  r30_5_B,r31_5_B,r32_5_B,r33_5_B,r34_5_B,
      r40_5_B,r41_5_B,r42_5_B,r43_5_B,r44_5_B;

    // ��ġ ����(task ���� ���� �Ҵ�)
    // A/B�� �� ���Կ� ����
    always @(posedge clk) begin
      if (!rst_n) begin
        winA_full <= 1'b0; winB_full <= 1'b0;
        // ��� ��ġ �������� 0 �ʱ�ȭ (A/B, 6ch��25)
        { r00_0_A,r01_0_A,r02_0_A,r03_0_A,r04_0_A,  r10_0_A,r11_0_A,r12_0_A,r13_0_A,r14_0_A,
          r20_0_A,r21_0_A,r22_0_A,r23_0_A,r24_0_A,  r30_0_A,r31_0_A,r32_0_A,r33_0_A,r34_0_A,
          r40_0_A,r41_0_A,r42_0_A,r43_0_A,r44_0_A } <= {25*P_W{1'b0}};
        { r00_1_A,r01_1_A,r02_1_A,r03_1_A,r04_1_A,  r10_1_A,r11_1_A,r12_1_A,r13_1_A,r14_1_A,
          r20_1_A,r21_1_A,r22_1_A,r23_1_A,r24_1_A,  r30_1_A,r31_1_A,r32_1_A,r33_1_A,r34_1_A,
          r40_1_A,r41_1_A,r42_1_A,r43_1_A,r44_1_A } <= {25*P_W{1'b0}};
        { r00_2_A,r01_2_A,r02_2_A,r03_2_A,r04_2_A,  r10_2_A,r11_2_A,r12_2_A,r13_2_A,r14_2_A,
          r20_2_A,r21_2_A,r22_2_A,r23_2_A,r24_2_A,  r30_2_A,r31_2_A,r32_2_A,r33_2_A,r34_2_A,
          r40_2_A,r41_2_A,r42_2_A,r43_2_A,r44_2_A } <= {25*P_W{1'b0}};
        { r00_3_A,r01_3_A,r02_3_A,r03_3_A,r04_3_A,  r10_3_A,r11_3_A,r12_3_A,r13_3_A,r14_3_A,
          r20_3_A,r21_3_A,r22_3_A,r23_3_A,r24_3_A,  r30_3_A,r31_3_A,r32_3_A,r33_3_A,r34_3_A,
          r40_3_A,r41_3_A,r42_3_A,r43_3_A,r44_3_A } <= {25*P_W{1'b0}};
        { r00_4_A,r01_4_A,r02_4_A,r03_4_A,r04_4_A,  r10_4_A,r11_4_A,r12_4_A,r13_4_A,r14_4_A,
          r20_4_A,r21_4_A,r22_4_A,r23_4_A,r24_4_A,  r30_4_A,r31_4_A,r32_4_A,r33_4_A,r34_4_A,
          r40_4_A,r41_4_A,r42_4_A,r43_4_A,r44_4_A } <= {25*P_W{1'b0}};
        { r00_5_A,r01_5_A,r02_5_A,r03_5_A,r04_5_A,  r10_5_A,r11_5_A,r12_5_A,r13_5_A,r14_5_A,
          r20_5_A,r21_5_A,r22_5_A,r23_5_A,r24_5_A,  r30_5_A,r31_5_A,r32_5_A,r33_5_A,r34_5_A,
          r40_5_A,r41_5_A,r42_5_A,r43_5_A,r44_5_A } <= {25*P_W{1'b0}};
        { r00_0_B,r01_0_B,r02_0_B,r03_0_B,r04_0_B,  r10_0_B,r11_0_B,r12_0_B,r13_0_B,r14_0_B,
          r20_0_B,r21_0_B,r22_0_B,r23_0_B,r24_0_B,  r30_0_B,r31_0_B,r32_0_B,r33_0_B,r34_0_B,
          r40_0_B,r41_0_B,r42_0_B,r43_0_B,r44_0_B } <= {25*P_W{1'b0}};
        { r00_1_B,r01_1_B,r02_1_B,r03_1_B,r04_1_B,  r10_1_B,r11_1_B,r12_1_B,r13_1_B,r14_1_B,
          r20_1_B,r21_1_B,r22_1_B,r23_1_B,r24_1_B,  r30_1_B,r31_1_B,r32_1_B,r33_1_B,r34_1_B,
          r40_1_B,r41_1_B,r42_1_B,r43_1_B,r44_1_B } <= {25*P_W{1'b0}};
        { r00_2_B,r01_2_B,r02_2_B,r03_2_B,r04_2_B,  r10_2_B,r11_2_B,r12_2_B,r13_2_B,r14_2_B,
          r20_2_B,r21_2_B,r22_2_B,r23_2_B,r24_2_B,  r30_2_B,r31_2_B,r32_2_B,r33_2_B,r34_2_B,
          r40_2_B,r41_2_B,r42_2_B,r43_2_B,r44_2_B } <= {25*P_W{1'b0}};
        { r00_3_B,r01_3_B,r02_3_B,r03_3_B,r04_3_B,  r10_3_B,r11_3_B,r12_3_B,r13_3_B,r14_3_B,
          r20_3_B,r21_3_B,r22_3_B,r23_3_B,r24_3_B,  r30_3_B,r31_3_B,r32_3_B,r33_3_B,r34_3_B,
          r40_3_B,r41_3_B,r42_3_B,r43_3_B,r44_3_B } <= {25*P_W{1'b0}};
        { r00_4_B,r01_4_B,r02_4_B,r03_4_B,r04_4_B,  r10_4_B,r11_4_B,r12_4_B,r13_4_B,r14_4_B,
          r20_4_B,r21_4_B,r22_4_B,r23_4_B,r24_4_B,  r30_4_B,r31_4_B,r32_4_B,r33_4_B,r34_4_B,
          r40_4_B,r41_4_B,r42_4_B,r43_4_B,r44_4_B } <= {25*P_W{1'b0}};
        { r00_5_B,r01_5_B,r02_5_B,r03_5_B,r04_5_B,  r10_5_B,r11_5_B,r12_5_B,r13_5_B,r14_5_B,
          r20_5_B,r21_5_B,r22_5_B,r23_5_B,r24_5_B,  r30_5_B,r31_5_B,r32_5_B,r33_5_B,r34_5_B,
          r40_5_B,r41_5_B,r42_5_B,r43_5_B,r44_5_B } <= {25*P_W{1'b0}};
      end else if (v_all_p) begin
        // �� ���Կ� ����
        if (!winA_full) begin
          // ch0..5, 25tap ��� A�� ��ġ
          { r00_0_A,r01_0_A,r02_0_A,r03_0_A,r04_0_A,  r10_0_A,r11_0_A,r12_0_A,r13_0_A,r14_0_A,
            r20_0_A,r21_0_A,r22_0_A,r23_0_A,r24_0_A,  r30_0_A,r31_0_A,r32_0_A,r33_0_A,r34_0_A,
            r40_0_A,r41_0_A,r42_0_A,r43_0_A,r44_0_A } <=
          { w44_0,w43_0,w42_0,w41_0,w40_0,w34_0,w33_0,w32_0,w31_0,w30_0,
            w24_0,w23_0,w22_0,w21_0,w20_0,w14_0,w13_0,w12_0,w11_0,w10_0,
            w04_0,w03_0,w02_0,w01_0,w00_0 };
          { r00_1_A,r01_1_A,r02_1_A,r03_1_A,r04_1_A,  r10_1_A,r11_1_A,r12_1_A,r13_1_A,r14_1_A,
            r20_1_A,r21_1_A,r22_1_A,r23_1_A,r24_1_A,  r30_1_A,r31_1_A,r32_1_A,r33_1_A,r34_1_A,
            r40_1_A,r41_1_A,r42_1_A,r43_1_A,r44_1_A } <=
          { w44_1,w43_1,w42_1,w41_1,w40_1,w34_1,w33_1,w32_1,w31_1,w30_1,
            w24_1,w23_1,w22_1,w21_1,w20_1,w14_1,w13_1,w12_1,w11_1,w10_1,
            w04_1,w03_1,w02_1,w01_1,w00_1 };
          { r00_2_A,r01_2_A,r02_2_A,r03_2_A,r04_2_A,  r10_2_A,r11_2_A,r12_2_A,r13_2_A,r14_2_A,
            r20_2_A,r21_2_A,r22_2_A,r23_2_A,r24_2_A,  r30_2_A,r31_2_A,r32_2_A,r33_2_A,r34_2_A,
            r40_2_A,r41_2_A,r42_2_A,r43_2_A,r44_2_A } <=
          { w44_2,w43_2,w42_2,w41_2,w40_2,w34_2,w33_2,w32_2,w31_2,w30_2,
            w24_2,w23_2,w22_2,w21_2,w20_2,w14_2,w13_2,w12_2,w11_2,w10_2,
            w04_2,w03_2,w02_2,w01_2,w00_2 };
          { r00_3_A,r01_3_A,r02_3_A,r03_3_A,r04_3_A,  r10_3_A,r11_3_A,r12_3_A,r13_3_A,r14_3_A,
            r20_3_A,r21_3_A,r22_3_A,r23_3_A,r24_3_A,  r30_3_A,r31_3_A,r32_3_A,r33_3_A,r34_3_A,
            r40_3_A,r41_3_A,r42_3_A,r43_3_A,r44_3_A } <=
          { w44_3,w43_3,w42_3,w41_3,w40_3,w34_3,w33_3,w32_3,w31_3,w30_3,
            w24_3,w23_3,w22_3,w21_3,w20_3,w14_3,w13_3,w12_3,w11_3,w10_3,
            w04_3,w03_3,w02_3,w01_3,w00_3 };
          { r00_4_A,r01_4_A,r02_4_A,r03_4_A,r04_4_A,  r10_4_A,r11_4_A,r12_4_A,r13_4_A,r14_4_A,
            r20_4_A,r21_4_A,r22_4_A,r23_4_A,r24_4_A,  r30_4_A,r31_4_A,r32_4_A,r33_4_A,r34_4_A,
            r40_4_A,r41_4_A,r42_4_A,r43_4_A,r44_4_A } <=
          { w44_4,w43_4,w42_4,w41_4,w40_4,w34_4,w33_4,w32_4,w31_4,w30_4,
            w24_4,w23_4,w22_4,w21_4,w20_4,w14_4,w13_4,w12_4,w11_4,w10_4,
            w04_4,w03_4,w02_4,w01_4,w00_4 };
          { r00_5_A,r01_5_A,r02_5_A,r03_5_A,r04_5_A,  r10_5_A,r11_5_A,r12_5_A,r13_5_A,r14_5_A,
            r20_5_A,r21_5_A,r22_5_A,r23_5_A,r24_5_A,  r30_5_A,r31_5_A,r32_5_A,r33_5_A,r34_5_A,
            r40_5_A,r41_5_A,r42_5_A,r43_5_A,r44_5_A } <=
          { w44_5,w43_5,w42_5,w41_5,w40_5,w34_5,w33_5,w32_5,w31_5,w30_5,
            w24_5,w23_5,w22_5,w21_5,w20_5,w14_5,w13_5,w12_5,w11_5,w10_5,
            w04_5,w03_5,w02_5,w01_5,w00_5 };
          winA_full <= 1'b1;
        end else if (!winB_full) begin
          { r00_0_B,r01_0_B,r02_0_B,r03_0_B,r04_0_B,  r10_0_B,r11_0_B,r12_0_B,r13_0_B,r14_0_B,
            r20_0_B,r21_0_B,r22_0_B,r23_0_B,r24_0_B,  r30_0_B,r31_0_B,r32_0_B,r33_0_B,r34_0_B,
            r40_0_B,r41_0_B,r42_0_B,r43_0_B,r44_0_B } <=
          { w44_0,w43_0,w42_0,w41_0,w40_0,w34_0,w33_0,w32_0,w31_0,w30_0,
            w24_0,w23_0,w22_0,w21_0,w20_0,w14_0,w13_0,w12_0,w11_0,w10_0,
            w04_0,w03_0,w02_0,w01_0,w00_0 };
          { r00_1_B,r01_1_B,r02_1_B,r03_1_B,r04_1_B,  r10_1_B,r11_1_B,r12_1_B,r13_1_B,r14_1_B,
            r20_1_B,r21_1_B,r22_1_B,r23_1_B,r24_1_B,  r30_1_B,r31_1_B,r32_1_B,r33_1_B,r34_1_B,
            r40_1_B,r41_1_B,r42_1_B,r43_1_B,r44_1_B } <=
          { w44_1,w43_1,w42_1,w41_1,w40_1,w34_1,w33_1,w32_1,w31_1,w30_1,
            w24_1,w23_1,w22_1,w21_1,w20_1,w14_1,w13_1,w12_1,w11_1,w10_1,
            w04_1,w03_1,w02_1,w01_1,w00_1 };
          { r00_2_B,r01_2_B,r02_2_B,r03_2_B,r04_2_B,  r10_2_B,r11_2_B,r12_2_B,r13_2_B,r14_2_B,
            r20_2_B,r21_2_B,r22_2_B,r23_2_B,r24_2_B,  r30_2_B,r31_2_B,r32_2_B,r33_2_B,r34_2_B,
            r40_2_B,r41_2_B,r42_2_B,r43_2_B,r44_2_B } <=
          { w44_2,w43_2,w42_2,w41_2,w40_2,w34_2,w33_2,w32_2,w31_2,w30_2,
            w24_2,w23_2,w22_2,w21_2,w20_2,w14_2,w13_2,w12_2,w11_2,w10_2,
            w04_2,w03_2,w02_2,w01_2,w00_2 };
          { r00_3_B,r01_3_B,r02_3_B,r03_3_B,r04_3_B,  r10_3_B,r11_3_B,r12_3_B,r13_3_B,r14_3_B,
            r20_3_B,r21_3_B,r22_3_B,r23_3_B,r24_3_B,  r30_3_B,r31_3_B,r32_3_B,r33_3_B,r34_3_B,
            r40_3_B,r41_3_B,r42_3_B,r43_3_B,r44_3_B } <=
          { w44_3,w43_3,w42_3,w41_3,w40_3,w34_3,w33_3,w32_3,w31_3,w30_3,
            w24_3,w23_3,w22_3,w21_3,w20_3,w14_3,w13_3,w12_3,w11_3,w10_3,
            w04_3,w03_3,w02_3,w01_3,w00_3 };
          { r00_4_B,r01_4_B,r02_4_B,r03_4_B,r04_4_B,  r10_4_B,r11_4_B,r12_4_B,r13_4_B,r14_4_B,
            r20_4_B,r21_4_B,r22_4_B,r23_4_B,r24_4_B,  r30_4_B,r31_4_B,r32_4_B,r33_4_B,r34_4_B,
            r40_4_B,r41_4_B,r42_4_B,r43_4_B,r44_4_B } <=
          { w44_4,w43_4,w42_4,w41_4,w40_4,w34_4,w33_4,w32_4,w31_4,w30_4,
            w24_4,w23_4,w22_4,w21_4,w20_4,w14_4,w13_4,w12_4,w11_4,w10_4,
            w04_4,w03_4,w02_4,w01_4,w00_4 };
          { r00_5_B,r01_5_B,r02_5_B,r03_5_B,r04_5_B,  r10_5_B,r11_5_B,r12_5_B,r13_5_B,r14_5_B,
            r20_5_B,r21_5_B,r22_5_B,r23_5_B,r24_5_B,  r30_5_B,r31_5_B,r32_5_B,r33_5_B,r34_5_B,
            r40_5_B,r41_5_B,r42_5_B,r43_5_B,r44_5_B } <=
          { w44_5,w43_5,w42_5,w41_5,w40_5,w34_5,w33_5,w32_5,w31_5,w30_5,
            w24_5,w23_5,w22_5,w21_5,w20_5,w14_5,w13_5,w12_5,w11_5,w10_5,
            w04_5,w03_5,w02_5,w01_5,w00_5 };
          winB_full <= 1'b1;
        end
        // �� �� full�̸� ������: ���⼭�� ���(����) - �ʿ� �� �÷��� �߰�
      end
    end

    // -------------------------------------------------------------------------
    // �߻� ������: ���� �Һ�
    // -------------------------------------------------------------------------
    reg latched;
    reg [OC_W-1:0] oc;
    reg [OC_W:0]   rem;
    reg            fire_sum;

    always @(posedge clk) begin
      if (!rst_n) begin
        latched  <= 1'b0;
        useA     <= 1'b1;
        oc       <= {OC_W{1'b0}};
        rem      <= {(OC_W+1){1'b0}};
        fire_sum <= 1'b0;
      end else begin
        fire_sum <= 1'b0;

        if (!latched) begin
          if (winA_full || winB_full) begin
            useA     <= winA_full ? 1'b1 : 1'b0;
            latched  <= 1'b1;
            oc       <= {OC_W{1'b0}};
            rem      <= OUT_CH-1;   // ù �߻�� ����
            fire_sum <= 1'b1;
          end
        end else begin
          if (rem != 0) begin
            oc       <= oc + {{(OC_W-1){1'b0}},1'b1};
            rem      <= rem - {{OC_W{1'b0}},1'b1};
            fire_sum <= 1'b1;
          end else begin
            // �� ��ġ ��: �Һ� �Ϸ�
            latched <= 1'b0;
            if (useA) winA_full <= 1'b0;
            else      winB_full <= 1'b0;
          end
        end
      end
    end

    // ===== pick helpers (>> ����) =====
    function signed [WW_BITS-1:0] pick_w;
      input [OUT_CH*IN_CH*25*WW_BITS-1:0] bus; input integer base;
      begin pick_w = bus[base +: WW_BITS]; end
    endfunction
    function signed [SUM_BITS-1:0] pick_b;
      input [OUT_CH*SUM_BITS-1:0] bus; input integer base;
      begin pick_b = bus[base +: SUM_BITS]; end
    endfunction

    // weight base (oc ����)
    integer base_ic0, base_ic1, base_ic2, base_ic3, base_ic4, base_ic5;
    always @(*) begin
      base_ic0 = (oc*IN_CH*25 + 0*25) * WW_BITS;
      base_ic1 = (oc*IN_CH*25 + 1*25) * WW_BITS;
      base_ic2 = (oc*IN_CH*25 + 2*25) * WW_BITS;
      base_ic3 = (oc*IN_CH*25 + 3*25) * WW_BITS;
      base_ic4 = (oc*IN_CH*25 + 4*25) * WW_BITS;
      base_ic5 = (oc*IN_CH*25 + 5*25) * WW_BITS;
    end

    // ===== 6���� adder_tree (A/B ���� + Ŭ�� ����Ʈ) =====
    // ���� ��� ������ �ȼ� ������
    `define SEL(A,B) (useA ? (A) : (B))

    wire v_psum0,v_psum1,v_psum2,v_psum3,v_psum4,v_psum5;
    wire signed [SUM_BITS-1:0] s0,s1,s2,s3,s4,s5;

    adder_tree_pipe #(.IN_W(PROD_BITS), .SUM_W(SUM_BITS)) U_AT0 (
      .clk(clk), .rst_n(rst_n), .valid_in(fire_sum),
      .in0 ( fire_sum ? (`SEL(r00_0_A,r00_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 0)) : {PROD_BITS{1'b0}} ),
      .in1 ( fire_sum ? (`SEL(r01_0_A,r01_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 1)) : {PROD_BITS{1'b0}} ),
      .in2 ( fire_sum ? (`SEL(r02_0_A,r02_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 2)) : {PROD_BITS{1'b0}} ),
      .in3 ( fire_sum ? (`SEL(r03_0_A,r03_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 3)) : {PROD_BITS{1'b0}} ),
      .in4 ( fire_sum ? (`SEL(r04_0_A,r04_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 4)) : {PROD_BITS{1'b0}} ),
      .in5 ( fire_sum ? (`SEL(r10_0_A,r10_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 5)) : {PROD_BITS{1'b0}} ),
      .in6 ( fire_sum ? (`SEL(r11_0_A,r11_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 6)) : {PROD_BITS{1'b0}} ),
      .in7 ( fire_sum ? (`SEL(r12_0_A,r12_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 7)) : {PROD_BITS{1'b0}} ),
      .in8 ( fire_sum ? (`SEL(r13_0_A,r13_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 8)) : {PROD_BITS{1'b0}} ),
      .in9 ( fire_sum ? (`SEL(r14_0_A,r14_0_B)*pick_w(w_flat, base_ic0 + WW_BITS* 9)) : {PROD_BITS{1'b0}} ),
      .in10( fire_sum ? (`SEL(r20_0_A,r20_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*10)) : {PROD_BITS{1'b0}} ),
      .in11( fire_sum ? (`SEL(r21_0_A,r21_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*11)) : {PROD_BITS{1'b0}} ),
      .in12( fire_sum ? (`SEL(r22_0_A,r22_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*12)) : {PROD_BITS{1'b0}} ),
      .in13( fire_sum ? (`SEL(r23_0_A,r23_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*13)) : {PROD_BITS{1'b0}} ),
      .in14( fire_sum ? (`SEL(r24_0_A,r24_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*14)) : {PROD_BITS{1'b0}} ),
      .in15( fire_sum ? (`SEL(r30_0_A,r30_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*15)) : {PROD_BITS{1'b0}} ),
      .in16( fire_sum ? (`SEL(r31_0_A,r31_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*16)) : {PROD_BITS{1'b0}} ),
      .in17( fire_sum ? (`SEL(r32_0_A,r32_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*17)) : {PROD_BITS{1'b0}} ),
      .in18( fire_sum ? (`SEL(r33_0_A,r33_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*18)) : {PROD_BITS{1'b0}} ),
      .in19( fire_sum ? (`SEL(r34_0_A,r34_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*19)) : {PROD_BITS{1'b0}} ),
      .in20( fire_sum ? (`SEL(r40_0_A,r40_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*20)) : {PROD_BITS{1'b0}} ),
      .in21( fire_sum ? (`SEL(r41_0_A,r41_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*21)) : {PROD_BITS{1'b0}} ),
      .in22( fire_sum ? (`SEL(r42_0_A,r42_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*22)) : {PROD_BITS{1'b0}} ),
      .in23( fire_sum ? (`SEL(r43_0_A,r43_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*23)) : {PROD_BITS{1'b0}} ),
      .in24( fire_sum ? (`SEL(r44_0_A,r44_0_B)*pick_w(w_flat, base_ic0 + WW_BITS*24)) : {PROD_BITS{1'b0}} ),
      .valid_out(v_psum0), .sum(s0) );

    adder_tree_pipe #(.IN_W(PROD_BITS), .SUM_W(SUM_BITS)) U_AT1 (
      .clk(clk), .rst_n(rst_n), .valid_in(fire_sum),
      .in0 ( fire_sum ? (`SEL(r00_1_A,r00_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 0)) : {PROD_BITS{1'b0}} ),
      .in1 ( fire_sum ? (`SEL(r01_1_A,r01_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 1)) : {PROD_BITS{1'b0}} ),
      .in2 ( fire_sum ? (`SEL(r02_1_A,r02_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 2)) : {PROD_BITS{1'b0}} ),
      .in3 ( fire_sum ? (`SEL(r03_1_A,r03_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 3)) : {PROD_BITS{1'b0}} ),
      .in4 ( fire_sum ? (`SEL(r04_1_A,r04_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 4)) : {PROD_BITS{1'b0}} ),
      .in5 ( fire_sum ? (`SEL(r10_1_A,r10_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 5)) : {PROD_BITS{1'b0}} ),
      .in6 ( fire_sum ? (`SEL(r11_1_A,r11_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 6)) : {PROD_BITS{1'b0}} ),
      .in7 ( fire_sum ? (`SEL(r12_1_A,r12_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 7)) : {PROD_BITS{1'b0}} ),
      .in8 ( fire_sum ? (`SEL(r13_1_A,r13_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 8)) : {PROD_BITS{1'b0}} ),
      .in9 ( fire_sum ? (`SEL(r14_1_A,r14_1_B)*pick_w(w_flat, base_ic1 + WW_BITS* 9)) : {PROD_BITS{1'b0}} ),
      .in10( fire_sum ? (`SEL(r20_1_A,r20_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*10)) : {PROD_BITS{1'b0}} ),
      .in11( fire_sum ? (`SEL(r21_1_A,r21_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*11)) : {PROD_BITS{1'b0}} ),
      .in12( fire_sum ? (`SEL(r22_1_A,r22_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*12)) : {PROD_BITS{1'b0}} ),
      .in13( fire_sum ? (`SEL(r23_1_A,r23_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*13)) : {PROD_BITS{1'b0}} ),
      .in14( fire_sum ? (`SEL(r24_1_A,r24_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*14)) : {PROD_BITS{1'b0}} ),
      .in15( fire_sum ? (`SEL(r30_1_A,r30_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*15)) : {PROD_BITS{1'b0}} ),
      .in16( fire_sum ? (`SEL(r31_1_A,r31_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*16)) : {PROD_BITS{1'b0}} ),
      .in17( fire_sum ? (`SEL(r32_1_A,r32_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*17)) : {PROD_BITS{1'b0}} ),
      .in18( fire_sum ? (`SEL(r33_1_A,r33_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*18)) : {PROD_BITS{1'b0}} ),
      .in19( fire_sum ? (`SEL(r34_1_A,r34_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*19)) : {PROD_BITS{1'b0}} ),
      .in20( fire_sum ? (`SEL(r40_1_A,r40_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*20)) : {PROD_BITS{1'b0}} ),
      .in21( fire_sum ? (`SEL(r41_1_A,r41_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*21)) : {PROD_BITS{1'b0}} ),
      .in22( fire_sum ? (`SEL(r42_1_A,r42_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*22)) : {PROD_BITS{1'b0}} ),
      .in23( fire_sum ? (`SEL(r43_1_A,r43_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*23)) : {PROD_BITS{1'b0}} ),
      .in24( fire_sum ? (`SEL(r44_1_A,r44_1_B)*pick_w(w_flat, base_ic1 + WW_BITS*24)) : {PROD_BITS{1'b0}} ),
      .valid_out(v_psum1), .sum(s1) );

    adder_tree_pipe #(.IN_W(PROD_BITS), .SUM_W(SUM_BITS)) U_AT2 (
      .clk(clk), .rst_n(rst_n), .valid_in(fire_sum),
      .in0 ( fire_sum ? (`SEL(r00_2_A,r00_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 0)) : {PROD_BITS{1'b0}} ),
      .in1 ( fire_sum ? (`SEL(r01_2_A,r01_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 1)) : {PROD_BITS{1'b0}} ),
      .in2 ( fire_sum ? (`SEL(r02_2_A,r02_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 2)) : {PROD_BITS{1'b0}} ),
      .in3 ( fire_sum ? (`SEL(r03_2_A,r03_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 3)) : {PROD_BITS{1'b0}} ),
      .in4 ( fire_sum ? (`SEL(r04_2_A,r04_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 4)) : {PROD_BITS{1'b0}} ),
      .in5 ( fire_sum ? (`SEL(r10_2_A,r10_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 5)) : {PROD_BITS{1'b0}} ),
      .in6 ( fire_sum ? (`SEL(r11_2_A,r11_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 6)) : {PROD_BITS{1'b0}} ),
      .in7 ( fire_sum ? (`SEL(r12_2_A,r12_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 7)) : {PROD_BITS{1'b0}} ),
      .in8 ( fire_sum ? (`SEL(r13_2_A,r13_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 8)) : {PROD_BITS{1'b0}} ),
      .in9 ( fire_sum ? (`SEL(r14_2_A,r14_2_B)*pick_w(w_flat, base_ic2 + WW_BITS* 9)) : {PROD_BITS{1'b0}} ),
      .in10( fire_sum ? (`SEL(r20_2_A,r20_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*10)) : {PROD_BITS{1'b0}} ),
      .in11( fire_sum ? (`SEL(r21_2_A,r21_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*11)) : {PROD_BITS{1'b0}} ),
      .in12( fire_sum ? (`SEL(r22_2_A,r22_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*12)) : {PROD_BITS{1'b0}} ),
      .in13( fire_sum ? (`SEL(r23_2_A,r23_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*13)) : {PROD_BITS{1'b0}} ),
      .in14( fire_sum ? (`SEL(r24_2_A,r24_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*14)) : {PROD_BITS{1'b0}} ),
      .in15( fire_sum ? (`SEL(r30_2_A,r30_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*15)) : {PROD_BITS{1'b0}} ),
      .in16( fire_sum ? (`SEL(r31_2_A,r31_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*16)) : {PROD_BITS{1'b0}} ),
      .in17( fire_sum ? (`SEL(r32_2_A,r32_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*17)) : {PROD_BITS{1'b0}} ),
      .in18( fire_sum ? (`SEL(r33_2_A,r33_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*18)) : {PROD_BITS{1'b0}} ),
      .in19( fire_sum ? (`SEL(r34_2_A,r34_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*19)) : {PROD_BITS{1'b0}} ),
      .in20( fire_sum ? (`SEL(r40_2_A,r40_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*20)) : {PROD_BITS{1'b0}} ),
      .in21( fire_sum ? (`SEL(r41_2_A,r41_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*21)) : {PROD_BITS{1'b0}} ),
      .in22( fire_sum ? (`SEL(r42_2_A,r42_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*22)) : {PROD_BITS{1'b0}} ),
      .in23( fire_sum ? (`SEL(r43_2_A,r43_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*23)) : {PROD_BITS{1'b0}} ),
      .in24( fire_sum ? (`SEL(r44_2_A,r44_2_B)*pick_w(w_flat, base_ic2 + WW_BITS*24)) : {PROD_BITS{1'b0}} ),
      .valid_out(v_psum2), .sum(s2) );

    adder_tree_pipe #(.IN_W(PROD_BITS), .SUM_W(SUM_BITS)) U_AT3 (
      .clk(clk), .rst_n(rst_n), .valid_in(fire_sum),
      .in0 ( fire_sum ? (`SEL(r00_3_A,r00_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 0)) : {PROD_BITS{1'b0}} ),
      .in1 ( fire_sum ? (`SEL(r01_3_A,r01_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 1)) : {PROD_BITS{1'b0}} ),
      .in2 ( fire_sum ? (`SEL(r02_3_A,r02_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 2)) : {PROD_BITS{1'b0}} ),
      .in3 ( fire_sum ? (`SEL(r03_3_A,r03_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 3)) : {PROD_BITS{1'b0}} ),
      .in4 ( fire_sum ? (`SEL(r04_3_A,r04_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 4)) : {PROD_BITS{1'b0}} ),
      .in5 ( fire_sum ? (`SEL(r10_3_A,r10_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 5)) : {PROD_BITS{1'b0}} ),
      .in6 ( fire_sum ? (`SEL(r11_3_A,r11_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 6)) : {PROD_BITS{1'b0}} ),
      .in7 ( fire_sum ? (`SEL(r12_3_A,r12_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 7)) : {PROD_BITS{1'b0}} ),
      .in8 ( fire_sum ? (`SEL(r13_3_A,r13_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 8)) : {PROD_BITS{1'b0}} ),
      .in9 ( fire_sum ? (`SEL(r14_3_A,r14_3_B)*pick_w(w_flat, base_ic3 + WW_BITS* 9)) : {PROD_BITS{1'b0}} ),
      .in10( fire_sum ? (`SEL(r20_3_A,r20_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*10)) : {PROD_BITS{1'b0}} ),
      .in11( fire_sum ? (`SEL(r21_3_A,r21_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*11)) : {PROD_BITS{1'b0}} ),
      .in12( fire_sum ? (`SEL(r22_3_A,r22_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*12)) : {PROD_BITS{1'b0}} ),
      .in13( fire_sum ? (`SEL(r23_3_A,r23_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*13)) : {PROD_BITS{1'b0}} ),
      .in14( fire_sum ? (`SEL(r24_3_A,r24_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*14)) : {PROD_BITS{1'b0}} ),
      .in15( fire_sum ? (`SEL(r30_3_A,r30_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*15)) : {PROD_BITS{1'b0}} ),
      .in16( fire_sum ? (`SEL(r31_3_A,r31_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*16)) : {PROD_BITS{1'b0}} ),
      .in17( fire_sum ? (`SEL(r32_3_A,r32_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*17)) : {PROD_BITS{1'b0}} ),
      .in18( fire_sum ? (`SEL(r33_3_A,r33_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*18)) : {PROD_BITS{1'b0}} ),
      .in19( fire_sum ? (`SEL(r34_3_A,r34_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*19)) : {PROD_BITS{1'b0}} ),
      .in20( fire_sum ? (`SEL(r40_3_A,r40_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*20)) : {PROD_BITS{1'b0}} ),
      .in21( fire_sum ? (`SEL(r41_3_A,r41_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*21)) : {PROD_BITS{1'b0}} ),
      .in22( fire_sum ? (`SEL(r42_3_A,r42_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*22)) : {PROD_BITS{1'b0}} ),
      .in23( fire_sum ? (`SEL(r43_3_A,r43_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*23)) : {PROD_BITS{1'b0}} ),
      .in24( fire_sum ? (`SEL(r44_3_A,r44_3_B)*pick_w(w_flat, base_ic3 + WW_BITS*24)) : {PROD_BITS{1'b0}} ),
      .valid_out(v_psum3), .sum(s3) );

    adder_tree_pipe #(.IN_W(PROD_BITS), .SUM_W(SUM_BITS)) U_AT4 (
      .clk(clk), .rst_n(rst_n), .valid_in(fire_sum),
      .in0 ( fire_sum ? (`SEL(r00_4_A,r00_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 0)) : {PROD_BITS{1'b0}} ),
      .in1 ( fire_sum ? (`SEL(r01_4_A,r01_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 1)) : {PROD_BITS{1'b0}} ),
      .in2 ( fire_sum ? (`SEL(r02_4_A,r02_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 2)) : {PROD_BITS{1'b0}} ),
      .in3 ( fire_sum ? (`SEL(r03_4_A,r03_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 3)) : {PROD_BITS{1'b0}} ),
      .in4 ( fire_sum ? (`SEL(r04_4_A,r04_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 4)) : {PROD_BITS{1'b0}} ),
      .in5 ( fire_sum ? (`SEL(r10_4_A,r10_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 5)) : {PROD_BITS{1'b0}} ),
      .in6 ( fire_sum ? (`SEL(r11_4_A,r11_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 6)) : {PROD_BITS{1'b0}} ),
      .in7 ( fire_sum ? (`SEL(r12_4_A,r12_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 7)) : {PROD_BITS{1'b0}} ),
      .in8 ( fire_sum ? (`SEL(r13_4_A,r13_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 8)) : {PROD_BITS{1'b0}} ),
      .in9 ( fire_sum ? (`SEL(r14_4_A,r14_4_B)*pick_w(w_flat, base_ic4 + WW_BITS* 9)) : {PROD_BITS{1'b0}} ),
      .in10( fire_sum ? (`SEL(r20_4_A,r20_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*10)) : {PROD_BITS{1'b0}} ),
      .in11( fire_sum ? (`SEL(r21_4_A,r21_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*11)) : {PROD_BITS{1'b0}} ),
      .in12( fire_sum ? (`SEL(r22_4_A,r22_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*12)) : {PROD_BITS{1'b0}} ),
      .in13( fire_sum ? (`SEL(r23_4_A,r23_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*13)) : {PROD_BITS{1'b0}} ),
      .in14( fire_sum ? (`SEL(r24_4_A,r24_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*14)) : {PROD_BITS{1'b0}} ),
      .in15( fire_sum ? (`SEL(r30_4_A,r30_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*15)) : {PROD_BITS{1'b0}} ),
      .in16( fire_sum ? (`SEL(r31_4_A,r31_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*16)) : {PROD_BITS{1'b0}} ),
      .in17( fire_sum ? (`SEL(r32_4_A,r32_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*17)) : {PROD_BITS{1'b0}} ),
      .in18( fire_sum ? (`SEL(r33_4_A,r33_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*18)) : {PROD_BITS{1'b0}} ),
      .in19( fire_sum ? (`SEL(r34_4_A,r34_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*19)) : {PROD_BITS{1'b0}} ),
      .in20( fire_sum ? (`SEL(r40_4_A,r40_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*20)) : {PROD_BITS{1'b0}} ),
      .in21( fire_sum ? (`SEL(r41_4_A,r41_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*21)) : {PROD_BITS{1'b0}} ),
      .in22( fire_sum ? (`SEL(r42_4_A,r42_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*22)) : {PROD_BITS{1'b0}} ),
      .in23( fire_sum ? (`SEL(r43_4_A,r43_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*23)) : {PROD_BITS{1'b0}} ),
      .in24( fire_sum ? (`SEL(r44_4_A,r44_4_B)*pick_w(w_flat, base_ic4 + WW_BITS*24)) : {PROD_BITS{1'b0}} ),
      .valid_out(v_psum4), .sum(s4) );

    adder_tree_pipe #(.IN_W(PROD_BITS), .SUM_W(SUM_BITS)) U_AT5 (
      .clk(clk), .rst_n(rst_n), .valid_in(fire_sum),
      .in0 ( fire_sum ? (`SEL(r00_5_A,r00_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 0)) : {PROD_BITS{1'b0}} ),
      .in1 ( fire_sum ? (`SEL(r01_5_A,r01_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 1)) : {PROD_BITS{1'b0}} ),
      .in2 ( fire_sum ? (`SEL(r02_5_A,r02_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 2)) : {PROD_BITS{1'b0}} ),
      .in3 ( fire_sum ? (`SEL(r03_5_A,r03_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 3)) : {PROD_BITS{1'b0}} ),
      .in4 ( fire_sum ? (`SEL(r04_5_A,r04_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 4)) : {PROD_BITS{1'b0}} ),
      .in5 ( fire_sum ? (`SEL(r10_5_A,r10_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 5)) : {PROD_BITS{1'b0}} ),
      .in6 ( fire_sum ? (`SEL(r11_5_A,r11_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 6)) : {PROD_BITS{1'b0}} ),
      .in7 ( fire_sum ? (`SEL(r12_5_A,r12_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 7)) : {PROD_BITS{1'b0}} ),
      .in8 ( fire_sum ? (`SEL(r13_5_A,r13_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 8)) : {PROD_BITS{1'b0}} ),
      .in9 ( fire_sum ? (`SEL(r14_5_A,r14_5_B)*pick_w(w_flat, base_ic5 + WW_BITS* 9)) : {PROD_BITS{1'b0}} ),
      .in10( fire_sum ? (`SEL(r20_5_A,r20_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*10)) : {PROD_BITS{1'b0}} ),
      .in11( fire_sum ? (`SEL(r21_5_A,r21_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*11)) : {PROD_BITS{1'b0}} ),
      .in12( fire_sum ? (`SEL(r22_5_A,r22_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*12)) : {PROD_BITS{1'b0}} ),
      .in13( fire_sum ? (`SEL(r23_5_A,r23_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*13)) : {PROD_BITS{1'b0}} ),
      .in14( fire_sum ? (`SEL(r24_5_A,r24_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*14)) : {PROD_BITS{1'b0}} ),
      .in15( fire_sum ? (`SEL(r30_5_A,r30_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*15)) : {PROD_BITS{1'b0}} ),
      .in16( fire_sum ? (`SEL(r31_5_A,r31_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*16)) : {PROD_BITS{1'b0}} ),
      .in17( fire_sum ? (`SEL(r32_5_A,r32_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*17)) : {PROD_BITS{1'b0}} ),
      .in18( fire_sum ? (`SEL(r33_5_A,r33_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*18)) : {PROD_BITS{1'b0}} ),
      .in19( fire_sum ? (`SEL(r34_5_A,r34_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*19)) : {PROD_BITS{1'b0}} ),
      .in20( fire_sum ? (`SEL(r40_5_A,r40_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*20)) : {PROD_BITS{1'b0}} ),
      .in21( fire_sum ? (`SEL(r41_5_A,r41_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*21)) : {PROD_BITS{1'b0}} ),
      .in22( fire_sum ? (`SEL(r42_5_A,r42_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*22)) : {PROD_BITS{1'b0}} ),
      .in23( fire_sum ? (`SEL(r43_5_A,r43_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*23)) : {PROD_BITS{1'b0}} ),
      .in24( fire_sum ? (`SEL(r44_5_A,r44_5_B)*pick_w(w_flat, base_ic5 + WW_BITS*24)) : {PROD_BITS{1'b0}} ),
      .valid_out(v_psum5), .sum(s5) );

    // ===== adder_tree ��� ��ġ(�۸�ġ/X ����) =====
    reg signed [SUM_BITS-1:0] s0_q, s1_q, s2_q, s3_q, s4_q, s5_q;
    reg v_all_q;
    always @(posedge clk) begin
      if (!rst_n) begin
        s0_q<=0; s1_q<=0; s2_q<=0; s3_q<=0; s4_q<=0; s5_q<=0;
        v_all_q <= 1'b0;
      end else begin
        if (v_psum0) s0_q <= s0;
        if (v_psum1) s1_q <= s1;
        if (v_psum2) s2_q <= s2;
        if (v_psum3) s3_q <= s3;
        if (v_psum4) s4_q <= s4;
        if (v_psum5) s5_q <= s5;
        v_all_q <= (v_psum0 & v_psum1 & v_psum2 & v_psum3 & v_psum4 & v_psum5);
      end
    end

    // ===== 3�� ���� =====
    reg signed [SUM_BITS-1:0] a0,a1,a2; reg va;
    always @(posedge clk) begin
      if (!rst_n) begin a0<=0;a1<=0;a2<=0;va<=1'b0; end
      else begin va<=v_all_q; if (v_all_q) begin a0<=s0_q+s1_q; a1<=s2_q+s3_q; a2<=s4_q+s5_q; end end
    end
    reg signed [SUM_BITS-1:0] b0; reg vb;
    always @(posedge clk) begin
      if (!rst_n) begin b0<=0; vb<=1'b0; end
      else begin vb<=va; if (va) b0<=a0+a1; end end

    reg signed [SUM_BITS-1:0] s_comb; reg vs;
    always @(posedge clk) begin
      if (!rst_n) begin s_comb<=0; vs<=1'b0; end
      else begin vs<=vb; if (vb) s_comb<=b0+a2; end end

    // -------------------------------------------------------------------------
    // oc �±� ������ (fire_sum ������ ����)
    // adder_tree(5) + comb(3) + acc(1) = �� 9��
    // -------------------------------------------------------------------------
    localparam integer LAT_AT   = 6;
    localparam integer LAT_COMB = 3;
    localparam integer LAT_VS   = LAT_AT + LAT_COMB; // 8
    localparam integer LAT_ACC  = LAT_VS + 1;        // 9

    reg                 tag_v   [0:LAT_ACC];
    reg [OC_W-1:0]      oc_tag  [0:LAT_ACC];
    integer tk;
    always @(posedge clk) begin
      if (!rst_n) begin
        for (tk=0; tk<=LAT_ACC; tk=tk+1) begin
          tag_v[tk]  <= 1'b0;
          oc_tag[tk] <= {OC_W{1'b0}};
        end
      end else begin
        tag_v[0]  <= fire_sum;
        if (fire_sum) oc_tag[0] <= oc;
        for (tk=1; tk<=LAT_ACC; tk=tk+1) begin
          tag_v[tk]  <= tag_v[tk-1];
          oc_tag[tk] <= oc_tag[tk-1];
        end
      end
    end

    wire [OC_W-1:0] oc_vs  = oc_tag[LAT_VS];
    wire [OC_W-1:0] oc_acc = oc_tag[LAT_ACC];

    // ���̾: vs �� 1Ŭ�� �ռ��� �غ��ؼ� acc���� ���(�Ʒ� acc���� +)
    wire signed [SUM_BITS-1:0] bias_next = pick_b(b_flat, oc_vs*SUM_BITS);
    reg  signed [OUT_BITS-1:0] bias_cur;
    always @(posedge clk) begin
      if (!rst_n) bias_cur <= {SUM_BITS{1'b0}};
      else        bias_cur <= bias_next;
    end

    // ===== finalize (acc/bias/shift/ReLU) =====
    reg                        v_acc;
    reg signed [OUT_BITS-1:0]  acc;
    
    always @(posedge clk) begin
      if (!rst_n) begin
        v_acc     <= 1'b0;
        acc       <= {OUT_BITS{1'b0}};
        valid_out <= 1'b0;
        pix_out   <= {OUT_BITS{1'b0}};
        ch_idx    <= 16'd0;
      end else begin
        // sum+bias �Ϸ�(valid�� vs) �� �� Ŭ�� �� acc ��ġ
        v_acc <= vs;
        if (vs) acc <= s_comb[28:13] + bias_cur;

        // ���
        valid_out <= v_acc;
        ch_idx    <= {{(16-OC_W){1'b0}}, oc_acc};

        if (v_acc) begin
            pix_out <= acc[OUT_BITS-1:0];
        end
      end
    end

    `undef SEL

endmodule
