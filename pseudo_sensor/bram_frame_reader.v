module bram_frame_reader #(
  parameter integer IN_W   = 640,
  parameter integer IN_H   = 480,
  parameter integer AB     = 19            
)(
  input  wire              clk,
  input  wire              srst,           

  input  wire              start,          
  output reg  [AB-1:0]     bram_addr,      
  input  wire       [7:0]  bram_dout,      

  output reg               valid,
  output reg               sof,           
  output reg               eol,            
  output reg        [7:0]  data
);
  localparam integer NPIX = IN_W*IN_H;

  reg        run;          
  reg        rd_pending;  
  reg [AB:0] idx_addr;     
  reg [AB:0] idx_out;      
   reg [15:0] x_cnt;

  always @(posedge clk) begin
    if (srst) begin
      run<=1'b0; rd_pending<=1'b0; idx_addr<=0; idx_out<=0; x_cnt<=0;
      bram_addr<=0; valid<=1'b0; sof<=1'b0; eol<=1'b0; data<=8'd0;
    end else begin
      valid<=1'b0; sof<=1'b0; eol<=1'b0;
if (start && !run) begin
              run<=1; idx_addr<=0; idx_out<=0; x_cnt<=0;
              bram_addr<=0; rd_pending<=1;      // 1clk prime
            end else if (run) begin
              // 도착 데이터 출력
              if (rd_pending) begin
                rd_pending<=0;
                data  <= bram_dout;
                valid <= 1'b1;
                sof   <= (idx_out==0);
                eol   <= (x_cnt == IN_W-1);     // ★ mod 대신 비교
                // 다음 x_cnt 준비 (출력 발생 시점에 동작)
                if (x_cnt == IN_W-1) x_cnt <= 0;
                else                 x_cnt <= x_cnt + 1'b1;
              end
      
              // 다음 주소 발행
              if (!rd_pending && (idx_addr < NPIX)) begin
                bram_addr  <= idx_addr[AB-1:0];
                idx_addr   <= idx_addr + 1'b1;
                rd_pending <= 1'b1;
              end
      
              // 출력 카운트
              if (valid) begin
                if (idx_out == NPIX-1) run <= 1'b0;
                else                   idx_out <= idx_out + 1'b1;
              end
            end
          end
        end
      endmodule
