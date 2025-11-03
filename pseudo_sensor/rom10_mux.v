module rom10_mux #(
  parameter integer ADDR_FRAME = 19,
  parameter integer DATA_WIDTH = 8
)(
  input  wire                    p_clk,
  input  wire [ADDR_FRAME-1:0]   addr_frame,
  input  wire [3:0]              sel,
  output reg  [DATA_WIDTH-1:0]   dout
);
  wire [DATA_WIDTH-1:0] d0,d1,d2,d3,d4,d5,d6,d7,d8,d9;

  // Block Memory Generator (Single Port ROM, Use ENA pin) 
  rom_img_0 u_rom0 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d0));
  rom_img_1 u_rom1 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d1));
  rom_img_2 u_rom2 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d2));
  rom_img_3 u_rom3 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d3));
  rom_img_4 u_rom4 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d4));
  rom_img_5 u_rom5 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d5));
  rom_img_6 u_rom6 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d6));
  rom_img_7 u_rom7 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d7));
  rom_img_8 u_rom8 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d8));
  rom_img_9 u_rom9 (.clka(p_clk), .ena(1'b1), .addra(addr_frame), .douta(d9));

  always @* begin
    dout = {DATA_WIDTH{1'b0}};  // 안전 기본값
    case (sel)
      4'd0: dout = d0;
      4'd1: dout = d1;
      4'd2: dout = d2;
      4'd3: dout = d3;
      4'd4: dout = d4;
      4'd5: dout = d5;
      4'd6: dout = d6;
      4'd7: dout = d7;
      4'd8: dout = d8;
      4'd9: dout = d9;
      default: /* keep 0 */;
    endcase
  end
endmodule
