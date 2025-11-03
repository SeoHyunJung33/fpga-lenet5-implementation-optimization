module frame_swap_gen_eof (
  input  wire p_clk,
  input  wire arst_p_n,  // active-low
  input  wire eof,
  output reg  swap_p
);
  reg eof_d;

  always @(posedge p_clk or negedge arst_p_n) begin
    if (!arst_p_n) begin
      eof_d  <= 1'b0;
      swap_p <= 1'b0;
    end else begin
      eof_d  <= eof;
      swap_p <= eof & ~eof_d;  // rising-edge one-shot (registered)
    end
  end
endmodule
