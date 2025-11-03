`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// fc_84 (Verilog-2001)
// - 84�� �Է� ���Ϳ� 84�� ����ġ�� dot + bias
// - 9-stage ���������� (�Է� ��ġ �� �� �� 42 �� 21 �� 11 �� 6 �� 3 �� 2 �� 1)
// - �Ķ����: ��(�Է�/����ġ/���̾/���), ����Ʈ, ��ȭ ���, ReLU ���
// - ���� �����̽��� LSB-first (+:) �� Top ��ŷ�� ���� ����
// - �����: +define+FC2_DEBUG �� ���� �ܰ� �� �α�
// -----------------------------------------------------------------------------
module fc_84 #(
    parameter integer N           = 84,
    parameter integer IN_WIDTH    = 16,                 // �Է� ���� ��� ��
    parameter integer W_WIDTH     = 16,                 // ����ġ ��� ��
    parameter integer BIAS_WIDTH  = 16,                 // ���̾ ��
    parameter integer OUT_WIDTH   = 16,                 // ��� ��
    parameter integer SHIFT_R     = 0,                  // ���� �� �����Ʈ (arithmetic)
    parameter integer SAT_EN      = 1,                  // ��ȭ ���(1) / �̻��(0)
    parameter integer ACC_WIDTH   = IN_WIDTH + W_WIDTH + 8 // ���� ����(�ʿ�� ����)
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           valid_in,

    input  wire signed [N*IN_WIDTH-1:0]   in,
    input  wire signed [N*W_WIDTH-1:0]    in_weights,
    input  wire signed [BIAS_WIDTH-1:0]   bias,

    output wire                           valid_out,
    output wire signed [OUT_WIDTH-1:0]    out
);

    // ------------------ Stage 1 : �Է� ��ġ ------------------
    reg  signed [N*IN_WIDTH-1:0]  in_s1;
    reg  signed [N*W_WIDTH-1:0]   w_s1;
    reg  signed [BIAS_WIDTH-1:0]  b_s1;
    reg                           v_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_s1 <= {N*IN_WIDTH{1'b0}};
            w_s1  <= {N*W_WIDTH{1'b0}};
            b_s1  <= {BIAS_WIDTH{1'b0}};
            v_s1  <= 1'b0;
        end else begin
            v_s1 <= valid_in;
            if (valid_in) begin
                in_s1 <= in;
                w_s1  <= in_weights;
                b_s1  <= bias;
            end
        end
    end

    // ���� (LSB-first ����)
    wire signed [IN_WIDTH-1:0] in_a [0:N-1];
    wire signed [W_WIDTH-1:0]  w_a  [0:N-1];
    genvar gi;
    generate
        for (gi=0; gi<N; gi=gi+1) begin : G_UNPK
            assign in_a[gi] = in_s1[gi*IN_WIDTH +: IN_WIDTH];
            assign w_a [gi] = w_s1 [gi*W_WIDTH  +: W_WIDTH ];
        end
    endgenerate

    // ------------------ Stage 2 : �� ------------------
    localparam integer PROD_W = IN_WIDTH + W_WIDTH;

    reg  signed [PROD_W-1:0]  prod_s2 [0:N-1];
    reg  signed [ACC_WIDTH-1:0] b_s2;
    reg                        v_s2;

    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j=0; j<N; j=j+1) prod_s2[j] <= {PROD_W{1'b0}};
            b_s2 <= {ACC_WIDTH{1'b0}};
            v_s2 <= 1'b0;
        end else begin
            v_s2 <= v_s1;
            // sign-extend bias to ACC_WIDTH
            b_s2 <= {{(ACC_WIDTH-BIAS_WIDTH){b_s1[BIAS_WIDTH-1]}}, b_s1};
            if (v_s1) begin
                for (j=0; j<N; j=j+1)
                    prod_s2[j] <= in_a[j] * w_a[j];
            end
        end
    end

    // helper: product Ȯ��
    function [ACC_WIDTH-1:0] ext_prod;
        input signed [PROD_W-1:0] p;
        begin
            ext_prod = {{(ACC_WIDTH-PROD_W){p[PROD_W-1]}}, p};
        end
    endfunction

    // ------------------ Stage 3..9 : �ջ� Ʈ�� ------------------
    // s3: 42, s4: 21, s5: 11(10+1), s6: 6(5+1), s7: 3, s8: 2(1+1), s9: 1
    integer x;

    reg  signed [ACC_WIDTH-1:0] s3 [0:41];
    reg  signed [ACC_WIDTH-1:0] s4 [0:20];
    reg  signed [ACC_WIDTH-1:0] s5 [0:10];
    reg  signed [ACC_WIDTH-1:0] s6 [0:5];
    reg  signed [ACC_WIDTH-1:0] s7 [0:2];
    reg  signed [ACC_WIDTH-1:0] s8 [0:1];
    reg  signed [ACC_WIDTH-1:0] s9;

    reg  signed [OUT_WIDTH-1:0] b_s3, b_s4, b_s5, b_s6, b_s7, b_s8, b_s9;
    reg                         v_s3, v_s4, v_s5, v_s6, v_s7, v_s8, v_s9;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (x=0;x<42;x=x+1) s3[x] <= {ACC_WIDTH{1'b0}};
            for (x=0;x<21;x=x+1) s4[x] <= {ACC_WIDTH{1'b0}};
            for (x=0;x<11;x=x+1) s5[x] <= {ACC_WIDTH{1'b0}};
            for (x=0;x<6; x=x+1) s6[x] <= {ACC_WIDTH{1'b0}};
            for (x=0;x<3; x=x+1) s7[x] <= {ACC_WIDTH{1'b0}};
            s8[0] <= {ACC_WIDTH{1'b0}};
            s8[1] <= {ACC_WIDTH{1'b0}};
            s9    <= {ACC_WIDTH{1'b0}};

            {b_s3,b_s4,b_s5,b_s6,b_s7,b_s8,b_s9} <= {7*OUT_WIDTH{1'b0}};
            {v_s3,v_s4,v_s5,v_s6,v_s7,v_s8,v_s9} <= 7'b0;
        end else begin
            // ��ȿ/���̾ ������ �̵�
            v_s3 <= v_s2; v_s4 <= v_s3; v_s5 <= v_s4; v_s6 <= v_s5; v_s7 <= v_s6; v_s8 <= v_s7; v_s9 <= v_s8;
            b_s3 <= b_s2; b_s4 <= b_s3; b_s5 <= b_s4; b_s6 <= b_s5; b_s7 <= b_s6; b_s8 <= b_s7; b_s9 <= b_s8;

            // s3: 84 -> 42
            if (v_s2) begin
                for (x=0; x<42; x=x+1)
                    s3[x] <= $signed(ext_prod(prod_s2[2*x])) + $signed(ext_prod(prod_s2[2*x+1]));
            end

            // s4: 42 -> 21
            if (v_s3) begin
                for (x=0; x<21; x=x+1)
                    s4[x] <= s3[2*x] + s3[2*x+1];
            end

            // s5: 21 -> 10 + carry(1) = 11
            if (v_s4) begin
                for (x=0; x<10; x=x+1)
                    s5[x] <= s4[2*x] + s4[2*x+1];
                s5[10] <= s4[20];
            end

            // s6: 11 -> 5 + carry(1) = 6
            if (v_s5) begin
                for (x=0; x<5; x=x+1)
                    s6[x] <= s5[2*x] + s5[2*x+1];
                s6[5] <= s5[10];
            end

            // s7: 6 -> 3
            if (v_s6) begin
                for (x=0; x<3; x=x+1)
                    s7[x] <= s6[2*x] + s6[2*x+1];
            end

            // s8: 3 -> 2 (1 + carry 1)
            if (v_s7) begin
                s8[0] <= s7[0] + s7[1];
                s8[1] <= s7[2];
            end

            // s9: 2 -> 1
            if (v_s8) begin
                s9 <= s8[0] + s8[1];
            end
        end
    end

    // ------------------ ���� ���� (bias + shift + sat) ------------------
    wire signed [OUT_WIDTH-1:0] sum_bias  = s9[23:8] + b_s9;

    // ���� �������� & valid
    reg  signed [OUT_WIDTH-1:0] out_r;
    reg                         v_out_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_r   <= {OUT_WIDTH{1'b0}};
            v_out_r <= 1'b0;
        end else begin
            v_out_r <= v_s9;
            if (v_s9) out_r <= sum_bias;
        end
    end

    assign out       = out_r;
    assign valid_out = v_out_r;

`ifdef FC2_DEBUG
    // v_s9 ����Ŭ�� ���� �� �α�
    always @(posedge clk) if (rst_n && v_s9) begin
        $display("[FC2][DBG] sum_raw=%0d  bias=%0d  sum_bias=%0d  sum_shift=%0d  out=%0d",
                 s9, b_s9, sum_bias, sum_shift);
    end
`endif

endmodule
