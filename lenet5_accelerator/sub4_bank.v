// -----------------------------------------------------------------------------
// sub4_bank (ss-major �Է�, Pure Verilog-2001)
// - �Է� ����: ss=0��1��2��3, �� ss���� ch=0..15 ������ 2x2 maxpool
// - ss==3 && ch==15 ���� {ch15..ch0} ��ŷ + valid_out=1
// - c3_valid ���� ���� ���� ���� ����(������) �� X ���� ����
// -----------------------------------------------------------------------------
module sub4_bank #(
    parameter integer FM_W     = 10,   // ȣȯ��(�̻��)
    parameter integer OUT_BITS = 16,
    parameter integer RELU_EN  = 1
)(
    input  wire                       clk,
    input  wire                       rst_n,     // sync, active-low
    input  wire                       c3_valid,
    input  wire [15:0]                c3_ch,     // 0..15
    input  wire signed [OUT_BITS-1:0] c3_pix,

    output reg                        valid_out,
    output reg  [16*OUT_BITS-1:0]     pix16_flat
);

    localparam integer OUT_CH  = 16;
    localparam integer CH_LAST = OUT_CH-1;

    // two's complement �ּҰ�
    localparam signed [OUT_BITS-1:0] SIGNED_MIN = {1'b1, {(OUT_BITS-1){1'b0}}};

    // ---------- ReLU ----------
    function signed [OUT_BITS-1:0] relu;
        input signed [OUT_BITS-1:0] x;
        begin
          if (RELU_EN==1)
            relu= x[OUT_BITS-1] ? {OUT_BITS{1'b0}} : x;
          else
            relu = x;
        end
    endfunction
    
    // -------------------------------------------------------------------------
    // ä�� one-hot (c3_valid�� ������)
    // -------------------------------------------------------------------------
    wire [OUT_CH-1:0] en_ch;
    genvar gi;
    generate
        for (gi=0; gi<OUT_CH; gi=gi+1) begin : G_ENCH
            assign en_ch[gi] = c3_valid & (c3_ch == gi[15:0]);
        end
    endgenerate

    // -------------------------------------------------------------------------
    // ss(0..3): ������ ä�ο����� ���� (��ȿ �Է��� ��)
    // -------------------------------------------------------------------------
    reg [1:0] ss;
    always @(posedge clk) begin
        if (!rst_n) begin
            ss <= 2'd0;
        end else if (c3_valid && (c3_ch==CH_LAST[15:0])) begin
            ss <= (ss==2'd3) ? 2'd0 : (ss + 2'd1);
        end
    end

    // -------------------------------------------------------------------------
    // per-channel ����: row0(ss=0/1), row1(ss=2/3)�� 2-�� max
    // -------------------------------------------------------------------------
    reg signed [OUT_BITS-1:0] row0_acc [0:OUT_CH-1];
    reg signed [OUT_BITS-1:0] row1_acc [0:OUT_CH-1];
    reg signed [OUT_BITS-1:0] pooled   [0:OUT_CH-1];

    integer ch;
    // ��Ŭ�� ��ð��� ���� ����(���ŷ) - ������ �������� Ÿ��������
    // �������Ͱ� �ƴ϶� �� ����� �ӽ� �����θ� ����.
    reg signed [OUT_BITS-1:0] new_row1;
    reg signed [OUT_BITS-1:0] final_now;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (ch=0; ch<OUT_CH; ch=ch+1) begin
                row0_acc[ch] <= SIGNED_MIN;
                row1_acc[ch] <= SIGNED_MIN;
                pooled  [ch] <= SIGNED_MIN;
            end
        end else if (c3_valid) begin
            for (ch=0; ch<OUT_CH; ch=ch+1) if (en_ch[ch]) begin
                case (ss)
                  2'd0: begin
                      row0_acc[ch] <= c3_pix;
                  end
                  2'd1: begin
                      row0_acc[ch] <= (c3_pix > row0_acc[ch]) ? c3_pix : row0_acc[ch];
                  end
                  2'd2: begin
                      row1_acc[ch] <= c3_pix;
                  end
                  2'd3: begin
                      new_row1   = (c3_pix > row1_acc[ch]) ? c3_pix : row1_acc[ch];
                      final_now  = (row0_acc[ch] > new_row1) ? row0_acc[ch] : new_row1;

                      row1_acc[ch] <= new_row1;   // ��1 ���� �ֽ�ȭ
                      pooled  [ch] <= final_now;  // �� ��ġ�� ���� max Ȯ��
                  end
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // ����: ss==3 && ch==15 �� {ch15..ch0} ��ŷ + valid_out=1
    //  - ch15�� ���� ����Ŭ�� ���ŵǴ� ���� ��� �ݿ��ؾ� �ϹǷ� final_now ���
    //    (pooled[15]�� <= �����̹Ƿ� ���� ����Ŭ ������ ������)
    // -------------------------------------------------------------------------
    wire fire = c3_valid & (c3_ch==CH_LAST[15:0]) & (ss==2'd3);

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_out  <= 1'b0;
            pix16_flat <= {16*OUT_BITS{1'b0}};
        end else begin
            valid_out <= 1'b0;
            if (fire) begin
                // ch15�� ��� ������(final_now): �� always ����� ���� ���� ����
                new_row1  = (relu(c3_pix) > row1_acc[CH_LAST]) ? relu(c3_pix) : row1_acc[CH_LAST];
                final_now = (row0_acc[CH_LAST] > new_row1) ? row0_acc[CH_LAST] : new_row1;

                pix16_flat <= {
                    final_now,                  // ch15 (��Ŭ�� ��ð�)
                    pooled[14], pooled[13], pooled[12],
                    pooled[11], pooled[10], pooled[ 9], pooled[ 8],
                    pooled[ 7], pooled[ 6], pooled[ 5], pooled[ 4],
                    pooled[ 3], pooled[ 2], pooled[ 1], pooled[ 0]
                };
                valid_out <= 1'b1;
            end
        end
    end

endmodule
