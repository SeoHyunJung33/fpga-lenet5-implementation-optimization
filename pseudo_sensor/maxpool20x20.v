module maxpool20x20 #(
  parameter IN_W=640, IN_H=480, BLK=20
)(
  input  wire       clk,
  input  wire       srst,
  input  wire       en,
  input  wire       en_mp,
  input  wire       in_valid,
  input  wire [7:0] in_pixel,
  output reg        out_valid,      // 1clk per block
  output reg [7:0]  out_pixel,
  output reg        line_last,      // last of 32 columns
  output reg        frame_last      // last output of frame
);
  localparam OUT_W = IN_W/BLK; // 32
  localparam OUT_H = IN_H/BLK; // 24

  reg [8:0]  cnt;       // 0..399
  wire       cnt_zero = (cnt==9'd0);
  wire       cnt_last = (cnt==(BLK*BLK-1));

  reg [7:0]  max_ff;
  wire       do_acc = in_valid & en & en_mp;
  wire [7:0] next_max = (in_pixel > max_ff)? in_pixel : max_ff;

  // 출력 좌표 카운터로 경계 생성 (mod 없이)
  reg [5:0] out_x;               // 0..OUT_W-1
  reg [5:0] out_y;               // 0..OUT_H-1
 always @(posedge clk) begin
     if (srst) begin
       cnt<=0; max_ff<=0; out_valid<=0; out_pixel<=0;
       out_x<=0; out_y<=0; line_last<=0; frame_last<=0;
     end else begin
       out_valid<=0; line_last<=0; frame_last<=0;
 
       if (in_valid & en) begin
         if (cnt_zero) max_ff <= in_pixel;
         else if (do_acc) max_ff <= next_max;
 
         cnt <= cnt_last ? 9'd0 : (cnt + 1'b1);
 
         if (cnt_last) begin
           out_valid <= 1'b1;
           out_pixel <= max_ff;
 
           // 경계: mod 없이 카운터 비교
           if (out_x == OUT_W-1) begin
             line_last <= 1'b1;
             out_x <= 0;
             if (out_y == OUT_H-1) begin
               frame_last <= 1'b1;
               out_y <= 0;
             end else begin
               out_y <= out_y + 1'b1;
             end
           end else begin
             out_x <= out_x + 1'b1;
           end
         end
       end
     end
   end
 endmodule

