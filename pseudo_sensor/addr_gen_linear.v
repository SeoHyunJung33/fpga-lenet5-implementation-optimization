module addr_gen_linear #(
    parameter integer ADDR_WIDTH = 19
)(
    input wire p_clk,
    input wire arst_p_n,
    input wire de,
    input wire sof,
    output reg [ADDR_WIDTH-1:0] addr
);

always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
        addr<={ADDR_WIDTH{1'b0}};
    end else if (sof) begin
        addr<={ADDR_WIDTH{1'b0}};
    end else if (de) begin
        addr<=addr+1'b1;
    end
end

endmodule