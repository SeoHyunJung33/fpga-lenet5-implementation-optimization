`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// conv1.v  (Pure Verilog-2001, streaming 5x5 conv, 1 in-channel -> OUT_CH)
//  - win5x5_stream ������ ����
//  - �����츦 ��ġ(hold=1)�� �� OUT_CH�� ä���� "����"�� ���(�� ä��/clk)
//  - adder_tree25_pipe(valid_out) = 5Ŭ�� ���� �� bias/ch�� 5Ŭ�� ����
//  - pix_ready ���: hold=1 ���� 0. ������ �����ϸ� pix_ready=1�� ���� valid_in=1�� ���� ����.
// -----------------------------------------------------------------------------
module conv1 #(
    parameter IMG_WIDTH  = 32,
    parameter PIX_BITS   = 8,                 // signed pixel
    parameter WW_BITS    = 8,                 // signed weight
    parameter PROD_BITS  = PIX_BITS + WW_BITS,
    parameter SUM_BITS   = PROD_BITS + 5,     // 25-term sum headroom
    parameter OUT_BITS   = 16,
    parameter OUT_CH     = 6,                 // LeNet-5 conv1 default
    parameter SHIFT_R    = 0                 // optional right shift
)(
    input  wire                         clk,
    input  wire                         rst_n,        // synchronous, active-low

    // input pixel stream
    input  wire                         valid_in,     // <-- TB�� ��ġ
    input  wire [PIX_BITS-1:0]   pix_in,       // <-- TB�� ��ġ
    output wire                         pix_ready,    // optional back-pressure

    // w_flat = {ch0_w00..w24, ch1_w00..w24, ...} (MSB..LSB)
    input  wire signed [OUT_CH*25*WW_BITS-1:0] w_flat,
    // b_flat = {ch0_b, ch1_b, ...}
    input  wire signed [OUT_CH*16-1:0]   b_flat,

    output reg                          valid_out,
    output reg        [15:0]            ch_idx,
    output reg  signed [OUT_BITS-1:0]   pix_out1, pix_out2, pix_out3, pix_out4, pix_out5, pix_out6
);
    localparam integer P_W      = PIX_BITS + 1;        // 내부 픽셀 폭 (signed)
    localparam integer PROD_INT = P_W + WW_BITS;       // 내부 곱셈 폭
    localparam integer SUM_INT  = PROD_INT + 5;        // 내부 합 폭(25tap headroom)
    
      // 입력 zero-extend → signed P_W
    wire signed [P_W-1:0] pix_in_se = {1'b0, pix_in};

    // ---------------- 5x5 window generator ----------------
    wire win_v;
    wire signed [P_W-1:0] w00,w01,w02,w03,w04,
                               w10,w11,w12,w13,w14,
                               w20,w21,w22,w23,w24,
                               w30,w31,w32,w33,w34,
                               w40,w41,w42,w43,w44;

    win5x5_stream #(
        .IMG_WIDTH(IMG_WIDTH),
        .PIX_BITS (P_W)
    ) U_WIN (
        .clk(clk), .rst_n(rst_n),
        .valid_in(valid_in), .pix_in(pix_in_se),
        .valid_out(win_v),
        .w00(w00), .w01(w01), .w02(w02), .w03(w03), .w04(w04),
        .w10(w10), .w11(w11), .w12(w12), .w13(w13), .w14(w14),
        .w20(w20), .w21(w21), .w22(w22), .w23(w23), .w24(w24),
        .w30(w30), .w31(w31), .w32(w32), .w33(w33), .w34(w34),
        .w40(w40), .w41(w41), .w42(w42), .w43(w43), .w44(w44)
    );

    // ---------------- LATCH 5x5 window while serializing channels ----------
    reg        hold;          // 1: ���� ��ġ�� �����츦 ä�� ����ȭ ��� ��
    reg [15:0] ch;            // ���� ��� ���� ä��(0..OUT_CH-1)

    // ������ back-pressure: hold=1�̸� �� �̻� �ȼ� ���� �Ұ�
    assign pix_ready = ~hold;

    reg signed [P_W-1:0]
        r00,r01,r02,r03,r04,  r10,r11,r12,r13,r14,
        r20,r21,r22,r23,r24,  r30,r31,r32,r33,r34,
        r40,r41,r42,r43,r44;

    always @(posedge clk) begin
        if (!rst_n) begin
            hold <= 1'b0;
            ch   <= 16'd0;
            r00<=0;r01<=0;r02<=0;r03<=0;r04<=0;  r10<=0;r11<=0;r12<=0;r13<=0;r14<=0;
            r20<=0;r21<=0;r22<=0;r23<=0;r24<=0;  r30<=0;r31<=0;r32<=0;r33<=0;r34<=0;
            r40<=0;r41<=0;r42<=0;r43<=0;r44<=0;
        end else begin
            if (win_v && !hold) begin
                // �� 5x5 ������ ��ġ, ä�� ����ȭ ����
                hold <= 1'b1;
                ch   <= 16'd0;

                r00<=w00; r01<=w01; r02<=w02; r03<=w03; r04<=w04;
                r10<=w10; r11<=w11; r12<=w12; r13<=w13; r14<=w14;
                r20<=w20; r21<=w21; r22<=w22; r23<=w23; r24<=w24;
                r30<=w30; r31<=w31; r32<=w32; r33<=w33; r34<=w34;
                r40<=w40; r41<=w41; r42<=w42; r43<=w43; r44<=w44;
            end else if (hold) begin
                // ä�� ����ȭ ����
                if (ch == OUT_CH-1) begin
                    hold <= 1'b0;              // ������ ä�α��� �������� hold ����
                    ch   <= 16'd0;
                end else begin
                    ch   <= ch + 16'd1;
                end
            end
        end
    end

    // ---------------- helpers: slice from flat buses ----------------
    function signed [WW_BITS-1:0] pick_w;
        input      [OUT_CH*25*WW_BITS-1:0] bus;
        input integer base;
        reg        [OUT_CH*25*WW_BITS-1:0] tmp;
        begin
            tmp    = bus >> base;
            pick_w = tmp[WW_BITS-1:0];
        end
    endfunction
    function signed [SUM_BITS-1:0] pick_b;
        input      [OUT_CH*SUM_BITS-1:0] bus;
        input integer base;
        reg        [OUT_CH*SUM_BITS-1:0] tmp;
        begin
            tmp    = bus >> base;
            pick_b = tmp[SUM_BITS-1:0];
        end
    endfunction

    integer base_w_00, base_b;
    always @(*) begin
        base_w_00 = (ch*25)*WW_BITS;
        base_b    = ch*SUM_BITS;
    end
    
    localparam FILTER_SIZE = 5;
    
    reg signed [WW_BITS - 1:0] weight_1 [0:FILTER_SIZE * FILTER_SIZE - 1];
    reg signed [WW_BITS - 1:0] weight_2 [0:FILTER_SIZE * FILTER_SIZE - 1];
    reg signed [WW_BITS - 1:0] weight_3 [0:FILTER_SIZE * FILTER_SIZE - 1];
    reg signed [WW_BITS - 1:0] weight_4 [0:FILTER_SIZE * FILTER_SIZE - 1];
    reg signed [WW_BITS - 1:0] weight_5 [0:FILTER_SIZE * FILTER_SIZE - 1];
    reg signed [WW_BITS - 1:0] weight_6 [0:FILTER_SIZE * FILTER_SIZE - 1];
    
    reg signed [16-1:0]bias[0:5] ;
    
    integer i;
    always @(*) begin
        for(i=0;i<=24;i=i+1)begin
            weight_1[i]=w_flat[(8*i)+:8];
            weight_2[i]=w_flat[(8*24+8*i)+:8];
            weight_3[i]=w_flat[(8*24*2+8*i)+:8];
            weight_4[i]=w_flat[(8*24*3+8*i)+:8];
            weight_5[i]=w_flat[(8*24*4+8*i)+:8];
            weight_6[i]=w_flat[(8*24*5+8*i)+:8];
        end
        for(i=0;i<=5;i=i+1) begin
           bias[i]=b_flat[(16*i)+:16];
        end
    end
    
    
    // ======================================================================
    // PROD_1
    // ======================================================================
    wire signed [PROD_INT-1:0] p00_1 = r00*weight_1[ 0], p01_1 = r01*weight_1[ 1], p02_1 = r02*weight_1[ 2], p03_1 = r03*weight_1[ 3], p04_1 = r04*weight_1[ 4];
    wire signed [PROD_INT-1:0] p10_1 = r10*weight_1[ 5], p11_1 = r11*weight_1[ 6], p12_1 = r12*weight_1[ 7], p13_1 = r13*weight_1[ 8], p14_1 = r14*weight_1[ 9];
    wire signed [PROD_INT-1:0] p20_1 = r20*weight_1[10], p21_1 = r21*weight_1[11], p22_1 = r22*weight_1[12], p23_1 = r23*weight_1[13], p24_1 = r24*weight_1[14];
    wire signed [PROD_INT-1:0] p30_1 = r30*weight_1[15], p31_1 = r31*weight_1[16], p32_1 = r32*weight_1[17], p33_1 = r33*weight_1[18], p34_1 = r34*weight_1[19];
    wire signed [PROD_INT-1:0] p40_1 = r40*weight_1[20], p41_1 = r41*weight_1[21], p42_1 = r42*weight_1[22], p43_1 = r43*weight_1[23], p44_1 = r44*weight_1[24];

    // ======================================================================
    // PROD_2
    // ======================================================================
    wire signed [PROD_INT-1:0] p00_2 = r00*weight_2[ 0], p01_2 = r01*weight_2[ 1], p02_2 = r02*weight_2[ 2], p03_2 = r03*weight_2[ 3], p04_2 = r04*weight_2[ 4];
    wire signed [PROD_INT-1:0] p10_2 = r10*weight_2[ 5], p11_2 = r11*weight_2[ 6], p12_2 = r12*weight_2[ 7], p13_2 = r13*weight_2[ 8], p14_2 = r14*weight_2[ 9];
    wire signed [PROD_INT-1:0] p20_2 = r20*weight_2[10], p21_2 = r21*weight_2[11], p22_2 = r22*weight_2[12], p23_2 = r23*weight_2[13], p24_2 = r24*weight_2[14];
    wire signed [PROD_INT-1:0] p30_2 = r30*weight_2[15], p31_2 = r31*weight_2[16], p32_2 = r32*weight_2[17], p33_2 = r33*weight_2[18], p34_2 = r34*weight_2[19];
    wire signed [PROD_INT-1:0] p40_2 = r40*weight_2[20], p41_2 = r41*weight_2[21], p42_2 = r42*weight_2[22], p43_2 = r43*weight_2[23], p44_2 = r44*weight_2[24];

    // ======================================================================
    // PROD_3
    // ======================================================================
    wire signed [PROD_INT-1:0] p00_3 = r00*weight_3[ 0], p01_3 = r01*weight_3[ 1], p02_3 = r02*weight_3[ 2], p03_3 = r03*weight_3[ 3], p04_3 = r04*weight_3[ 4];
    wire signed [PROD_INT-1:0] p10_3 = r10*weight_3[ 5], p11_3 = r11*weight_3[ 6], p12_3 = r12*weight_3[ 7], p13_3 = r13*weight_3[ 8], p14_3 = r14*weight_3[ 9];
    wire signed [PROD_INT-1:0] p20_3 = r20*weight_3[10], p21_3 = r21*weight_3[11], p22_3 = r22*weight_3[12], p23_3 = r23*weight_3[13], p24_3 = r24*weight_3[14];
    wire signed [PROD_INT-1:0] p30_3 = r30*weight_3[15], p31_3 = r31*weight_3[16], p32_3 = r32*weight_3[17], p33_3 = r33*weight_3[18], p34_3 = r34*weight_3[19];
    wire signed [PROD_INT-1:0] p40_3 = r40*weight_3[20], p41_3 = r41*weight_3[21], p42_3 = r42*weight_3[22], p43_3 = r43*weight_3[23], p44_3 = r44*weight_3[24];

    // ======================================================================
    // PROD_4
    // ======================================================================
    wire signed [PROD_INT-1:0] p00_4 = r00*weight_4[ 0], p01_4 = r01*weight_4[ 1], p02_4 = r02*weight_4[ 2], p03_4 = r03*weight_4[ 3], p04_4 = r04*weight_4[ 4];
    wire signed [PROD_INT-1:0] p10_4 = r10*weight_4[ 5], p11_4 = r11*weight_4[ 6], p12_4 = r12*weight_4[ 7], p13_4 = r13*weight_4[ 8], p14_4 = r14*weight_4[ 9];
    wire signed [PROD_INT-1:0] p20_4 = r20*weight_4[10], p21_4 = r21*weight_4[11], p22_4 = r22*weight_4[12], p23_4 = r23*weight_4[13], p24_4 = r24*weight_4[14];
    wire signed [PROD_INT-1:0] p30_4 = r30*weight_4[15], p31_4 = r31*weight_4[16], p32_4 = r32*weight_4[17], p33_4 = r33*weight_4[18], p34_4 = r34*weight_4[19];
    wire signed [PROD_INT-1:0] p40_4 = r40*weight_4[20], p41_4 = r41*weight_4[21], p42_4 = r42*weight_4[22], p43_4 = r43*weight_4[23], p44_4 = r44*weight_4[24];

    // ======================================================================
    // PROD_5
    // ======================================================================
    wire signed [PROD_INT-1:0] p00_5 = r00*weight_5[ 0], p01_5 = r01*weight_5[ 1], p02_5 = r02*weight_5[ 2], p03_5 = r03*weight_5[ 3], p04_5 = r04*weight_5[ 4];
    wire signed [PROD_INT-1:0] p10_5 = r10*weight_5[ 5], p11_5 = r11*weight_5[ 6], p12_5 = r12*weight_5[ 7], p13_5 = r13*weight_5[ 8], p14_5 = r14*weight_5[ 9];
    wire signed [PROD_INT-1:0] p20_5 = r20*weight_5[10], p21_5 = r21*weight_5[11], p22_5 = r22*weight_5[12], p23_5 = r23*weight_5[13], p24_5 = r24*weight_5[14];
    wire signed [PROD_INT-1:0] p30_5 = r30*weight_5[15], p31_5 = r31*weight_5[16], p32_5 = r32*weight_5[17], p33_5 = r33*weight_5[18], p34_5 = r34*weight_5[19];
    wire signed [PROD_INT-1:0] p40_5 = r40*weight_5[20], p41_5 = r41*weight_5[21], p42_5 = r42*weight_5[22], p43_5 = r43*weight_5[23], p44_5 = r44*weight_5[24];

    // ======================================================================
    // PROD_6
    // ======================================================================
    wire signed [PROD_INT-1:0] p00_6 = r00*weight_6[ 0], p01_6 = r01*weight_6[ 1], p02_6 = r02*weight_6[ 2], p03_6 = r03*weight_6[ 3], p04_6 = r04*weight_6[ 4];
    wire signed [PROD_INT-1:0] p10_6 = r10*weight_6[ 5], p11_6 = r11*weight_6[ 6], p12_6 = r12*weight_6[ 7], p13_6 = r13*weight_6[ 8], p14_6 = r14*weight_6[ 9];
    wire signed [PROD_INT-1:0] p20_6 = r20*weight_6[10], p21_6 = r21*weight_6[11], p22_6 = r22*weight_6[12], p23_6 = r23*weight_6[13], p24_6 = r24*weight_6[14];
    wire signed [PROD_INT-1:0] p30_6 = r30*weight_6[15], p31_6 = r31*weight_6[16], p32_6 = r32*weight_6[17], p33_6 = r33*weight_6[18], p34_6 = r34*weight_6[19];
    wire signed [PROD_INT-1:0] p40_6 = r40*weight_6[20], p41_6 = r41*weight_6[21], p42_6 = r42*weight_6[22], p43_6 = r43*weight_6[23], p44_6 = r44*weight_6[24];

    //bias
    
    // adder tree (latency=5)
    wire               sum_v;
    wire signed [15:0] sum_1;
    wire signed [15:0] sum_2;
    wire signed [15:0] sum_3;
    wire signed [15:0] sum_4;
    wire signed [15:0] sum_5;
    wire signed [15:0] sum_6;
    
    adder_tree_pipe #(.IN_W(PROD_INT), .SUM_W(SUM_INT)) SUM_1 (
        .clk(clk), .rst_n(rst_n), .valid_in(hold),
        .in0 (p00_1), .in1 (p01_1), .in2 (p02_1), .in3 (p03_1), .in4 (p04_1),
        .in5 (p10_1), .in6 (p11_1), .in7 (p12_1), .in8 (p13_1), .in9 (p14_1),
        .in10(p20_1), .in11(p21_1), .in12(p22_1), .in13(p23_1), .in14(p24_1),
        .in15(p30_1), .in16(p31_1), .in17(p32_1), .in18(p33_1), .in19(p34_1),
        .in20(p40_1), .in21(p41_1), .in22(p42_1), .in23(p43_1), .in24(p44_1),
        .valid_out(sum_v), .sum(sum_1)
    );
    adder_tree_pipe #(.IN_W(PROD_INT), .SUM_W(SUM_INT)) SUM_2 (
        .clk(clk), .rst_n(rst_n), .valid_in(hold),
        .in0 (p00_2), .in1 (p01_2), .in2 (p02_1), .in3 (p03_2), .in4 (p04_2),
        .in5 (p10_2), .in6 (p11_2), .in7 (p12_2), .in8 (p13_2), .in9 (p14_2),
        .in10(p20_2), .in11(p21_2), .in12(p22_2), .in13(p23_2), .in14(p24_2),
        .in15(p30_2), .in16(p31_2), .in17(p32_2), .in18(p33_2), .in19(p34_2),
        .in20(p40_2), .in21(p41_2), .in22(p42_2), .in23(p43_2), .in24(p44_2),
        .valid_out(sum_v), .sum(sum_2)
    );
    adder_tree_pipe #(.IN_W(PROD_INT), .SUM_W(SUM_INT)) SUM_3 (
        .clk(clk), .rst_n(rst_n), .valid_in(hold),
        .in0 (p00_3), .in1 (p01_3), .in2 (p02_3), .in3 (p03_3), .in4 (p04_3),
        .in5 (p10_3), .in6 (p11_3), .in7 (p12_3), .in8 (p13_3), .in9 (p14_3),
        .in10(p20_3), .in11(p21_3), .in12(p22_3), .in13(p23_3), .in14(p24_3),
        .in15(p30_3), .in16(p31_3), .in17(p32_3), .in18(p33_3), .in19(p34_3),
        .in20(p40_3), .in21(p41_3), .in22(p42_3), .in23(p43_3), .in24(p44_3),
        .valid_out(sum_v), .sum(sum_3)
    );
    adder_tree_pipe #(.IN_W(PROD_INT), .SUM_W(SUM_INT)) SUM_4 (
        .clk(clk), .rst_n(rst_n), .valid_in(hold),
        .in0 (p00_4), .in1 (p01_4), .in2 (p02_4), .in3 (p03_4), .in4 (p04_4),
        .in5 (p10_4), .in6 (p11_4), .in7 (p12_4), .in8 (p13_4), .in9 (p14_4),
        .in10(p20_4), .in11(p21_4), .in12(p22_4), .in13(p23_4), .in14(p24_4),
        .in15(p30_4), .in16(p31_4), .in17(p32_4), .in18(p33_4), .in19(p34_4),
        .in20(p40_4), .in21(p41_4), .in22(p42_4), .in23(p43_4), .in24(p44_4),
        .valid_out(sum_v), .sum(sum_4)
    );
    adder_tree_pipe #(.IN_W(PROD_INT), .SUM_W(SUM_INT)) SUM_5 (
        .clk(clk), .rst_n(rst_n), .valid_in(hold),
        .in0 (p00_5), .in1 (p01_5), .in2 (p02_5), .in3 (p03_5), .in4 (p04_5),
        .in5 (p10_5), .in6 (p11_5), .in7 (p12_5), .in8 (p13_5), .in9 (p14_5),
        .in10(p20_5), .in11(p21_5), .in12(p22_5), .in13(p23_5), .in14(p24_5),
        .in15(p30_5), .in16(p31_5), .in17(p32_5), .in18(p33_5), .in19(p34_5),
        .in20(p40_5), .in21(p41_5), .in22(p42_5), .in23(p43_5), .in24(p44_5),
        .valid_out(sum_v), .sum(sum_5)
    );
    adder_tree_pipe #(.IN_W(PROD_INT), .SUM_W(SUM_INT)) SUM_6 (
        .clk(clk), .rst_n(rst_n), .valid_in(hold),
        .in0 (p00_6), .in1 (p01_6), .in2 (p02_6), .in3 (p03_6), .in4 (p04_6),
        .in5 (p10_6), .in6 (p11_6), .in7 (p12_6), .in8 (p13_6), .in9 (p14_6),
        .in10(p20_6), .in11(p21_6), .in12(p22_6), .in13(p23_6), .in14(p24_6),
        .in15(p30_6), .in16(p31_6), .in17(p32_6), .in18(p33_6), .in19(p34_6),
        .in20(p40_6), .in21(p41_6), .in22(p42_6), .in23(p43_6), .in24(p44_6),
        .valid_out(sum_v), .sum(sum_6)
    );


    // output (same cycle as sum_v) 
    wire signed [OUT_BITS-1:0] acc_pre1 = sum_1[15:0] + bias[0];
    wire signed [OUT_BITS-1:0] acc_pre2 = sum_2[15:0] + bias[1];
    wire signed [OUT_BITS-1:0] acc_pre3 = sum_3[15:0] + bias[2];
    wire signed [OUT_BITS-1:0] acc_pre4 = sum_4[15:0] + bias[3];
    wire signed [OUT_BITS-1:0] acc_pre5 = sum_5[15:0] + bias[4];
    wire signed [OUT_BITS-1:0] acc_pre6 = sum_6[15:0] + bias[5];
    
    
    
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            pix_out1 <=0; pix_out2<=0; pix_out3<=0; pix_out4<=0; pix_out5<=0; pix_out6   <= 0;
            ch_idx    <= 0;
        end else begin
            valid_out <= sum_v;
            if (sum_v) begin   
                pix_out1 <= acc_pre1;
                pix_out2 <= acc_pre2;
                pix_out3 <= acc_pre3;
                pix_out4 <= acc_pre4;
                pix_out5 <= acc_pre5;
                pix_out6 <= acc_pre6;
            end
        end
    end

endmodule
