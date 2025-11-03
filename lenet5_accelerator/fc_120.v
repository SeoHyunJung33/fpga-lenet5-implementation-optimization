`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// fc_120  (streaming input from conv5 + internal 120ch buffer)
// - s_valid/s_ch_idx/s_pix �� ä�κ� ����, s_vec_valid���� 120-vector ��ġ
// - 9-stage Ʈ�� �� (�� ����: ���Ǻ� Ȯ��/����)
// - Verilog-2001
// -----------------------------------------------------------------------------
module fc_120 #(
    parameter integer CH_NUM    = 120,   // �Է� ä�� ��
    parameter integer IN_BITS   = 16,    // conv5.pix_out ��Ʈ��
    parameter integer W_BITS    = 8,     // ����ġ ��Ʈ��  (����: 8)
    parameter integer BIAS_BITS = 16,    // ���̾ ��Ʈ��(����: 16)
    parameter integer OUT_WIDTH = 16     // ���/���� ��   (����: 16)
)(
    input                           clk,
    input                           rst_n,

    // conv5 �� fc_120 ��Ʈ��
    input                           s_valid,     // conv5.valid_out
    input       [6:0]              s_ch_idx,    // conv5.ch_idx (0..CH_NUM-1)
    input       [IN_BITS-1:0]     s_pix,       // conv5.pix_out
    input                           s_vec_valid, // conv5.vec_valid (���� ���� ���� ��ȣ)

    // ����ġ/���̾ (�ش� ���� ���� �����̽�)
    input  signed [W_BITS*CH_NUM-1:0]   in_weights,  // [0..CH_NUM-1]
    input  signed [BIAS_BITS-1:0]       bias,

    // ���
    output                          valid_out,   // 9-stage �� valid
    output signed [OUT_WIDTH-1:0]   out          // ���� ��� + bias
);
 // ���� = log2(120) ? 7bit, ���� 2bit ��
localparam integer PROD_W = IN_BITS + W_BITS;                  // 24
localparam integer ACC_W  = (PROD_W + $clog2(CH_NUM) + 2);     // 24+7+2 = 33

    integer i, k, x;

    // =========================================================================
    // 1) �Է� ��Ʈ�� ���� (ä�� �ּ� ��� ����)
    // =========================================================================
    localparam integer P_W = IN_BITS + 1;
    reg signed [P_W-1:0] ibuf [0:CH_NUM-1];
    wire                      ch_in_range = (s_ch_idx < CH_NUM-1);

    always @(posedge clk) begin
        if (!rst_n) begin
            for (i=0; i<CH_NUM; i=i+1) ibuf[i] <= {IN_BITS{1'b0}};
        end 
        else if (s_valid && ch_in_range) begin
            ibuf[s_ch_idx] <= {1'b0, s_pix};
        end 
        else
        ibuf[s_ch_idx] <= {1'b0, s_pix};   
    end

    // =========================================================================
    // 2) Stage1: vec_valid���� ����/����ġ/���̾ ��ġ
    // =========================================================================
    reg signed [P_W*CH_NUM-1:0] in_s1;
    reg signed [W_BITS*CH_NUM-1:0]  w_s1;
    reg signed [BIAS_BITS-1:0]      b_s1;
    reg                             v_s1;

    always @(posedge clk) begin
        if (!rst_n) begin
            in_s1 <= {P_W*CH_NUM{1'b0}};
            w_s1  <= {W_BITS*CH_NUM{1'b0}};
            b_s1  <= {BIAS_BITS{1'b0}};
            v_s1  <= 1'b0;
        end else begin
            v_s1 <= s_vec_valid;  // �� ���� �Ϸ� ����
            if (s_vec_valid) begin
                for (i=0; i<CH_NUM; i=i+1)
                    in_s1[P_W*i +: P_W] <= ibuf[i];
                w_s1 <= in_weights;
                b_s1 <= bias;
            end
        end
    end

    // =========================================================================
    // 3) Stage2: �� (IN_BITS �� W_BITS �� PROD_W)
    // =========================================================================
    reg  signed [PROD_W-1:0] prod_s2 [0:CH_NUM-1];
    reg  signed [ACC_W-1:0]  b_s2;
    reg                      v_s2;

    // �� ���� ��ȣȮ��/����
    function signed [ACC_W-1:0] se_bias_to_acc;
        input signed [BIAS_BITS-1:0] b;
        begin
            if (ACC_W > BIAS_BITS)    se_bias_to_acc = {{(ACC_W-BIAS_BITS){b[BIAS_BITS-1]}}, b};
            else                      se_bias_to_acc = b[ACC_W-1:0]; // ����
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            for (k=0; k<CH_NUM; k=k+1) prod_s2[k] <= {PROD_W{1'b0}};
            b_s2 <= {ACC_W{1'b0}};
            v_s2 <= 1'b0;
        end else begin
            v_s2 <= v_s1;
            b_s2 <= se_bias_to_acc(b_s1);
            if (v_s1) begin
                for (k=0; k<CH_NUM; k=k+1) begin
                    prod_s2[k] <= in_s1[P_W*k +: P_W] * w_s1 [W_BITS*k +: W_BITS];
                end
            end
        end
    end

    // =========================================================================
    // 4) Stage3..9: ���������� �� (�� ����: ���Ǻ� Ȯ��/����)
    // =========================================================================
    reg signed [ACC_W-1:0] s3[0:59], s4[0:29], s5[0:14], s6[0:7], s7[0:3], s8[0:1], s9;
    reg signed [ACC_W-1:0] b_s3, b_s4, b_s5, b_s6, b_s7, b_s8, b_s9;
    reg                    v_s3, v_s4, v_s5, v_s6, v_s7, v_s8, v_s9;

    function signed [ACC_W-1:0] se_prod_to_acc;
        input signed [PROD_W-1:0] p;
        begin
            if (ACC_W > PROD_W)  se_prod_to_acc = {{(ACC_W-PROD_W){p[PROD_W-1]}}, p};
            else                 se_prod_to_acc = p[ACC_W-1:0]; // ����
        end
    endfunction
     integer n;
    always @(posedge clk) begin
        if (!rst_n) begin            
            for (n=0;n<60;n=n+1) s3[n] <= {ACC_W{1'b0}};
            for (n=0;n<30;n=n+1) s4[n] <= {ACC_W{1'b0}};
            for (n=0;n<15;n=n+1) s5[n] <= {ACC_W{1'b0}};
            for (n=0;n<8; n=n+1) s6[n] <= {ACC_W{1'b0}};
            for (n=0;n<4; n=n+1) s7[n] <= {ACC_W{1'b0}};
            for (n=0;n<2; n=n+1) s8[n] <= {ACC_W{1'b0}};
            s9  <= {ACC_W{1'b0}};
            {b_s3,b_s4,b_s5,b_s6,b_s7,b_s8,b_s9} <= {7{ {ACC_W{1'b0}} }};
            {v_s3,v_s4,v_s5,v_s6,v_s7,v_s8,v_s9} <= 7'b0;
        end else begin
            // valid / bias ����������
            v_s3<=v_s2; v_s4<=v_s3; v_s5<=v_s4; v_s6<=v_s5; v_s7<=v_s6; v_s8<=v_s7; v_s9<=v_s8;
            b_s3<=b_s2; b_s4<=b_s3; b_s5<=b_s4; b_s6<=b_s5; b_s7<=b_s6; b_s8<=b_s7; b_s9<=b_s8;

            if (v_s2) begin
                for (x=0;x<60;x=x+1)
                    s3[x] <= $signed(se_prod_to_acc(prod_s2[x*2])) + $signed(se_prod_to_acc(prod_s2[x*2+1]));
            end
            if (v_s3) begin
                for (x=0;x<30;x=x+1) s4[x] <= s3[x*2] + s3[x*2+1];
            end
            if (v_s4) begin
                for (x=0;x<15;x=x+1) s5[x] <= s4[x*2] + s4[x*2+1];
            end
            if (v_s5) begin
                for (x=0;x<7;x=x+1) s6[x] <= s5[x*2] + s5[x*2+1];
                s6[7] <= s5[14]; // carry
            end
            if (v_s6) begin
                for (x=0;x<4;x=x+1) s7[x] <= s6[x*2] + s6[x*2+1];
            end
            if (v_s7) begin
                s8[0] <= s7[0] + s7[1];
                s8[1] <= s7[2] + s7[3];
            end
            if (v_s8) begin
                s9 <= s8[0] + s8[1];
            end
        end
    end

    // =========================================================================
    // 5) ��� ��������
    // =========================================================================
    reg signed [ACC_W-1:0] out_reg;
    always @(posedge clk) begin
        if (!rst_n) out_reg <= {ACC_W{1'b0}};
        else if (v_s9) out_reg <= s9[27:12] + b_s9[15:0];
    end

    assign out       = out_reg;
    assign valid_out = v_s9;
endmodule
