module pulse_sync #(
  parameter integer SYNC_STAGES = 2  // >=2
)(
  input  wire p_clk,
  input  wire srst_p_n,   // active-low sync reset
  input  wire pulse_p,    // source pulse (1clk)
  input  wire c_clk,
  input  wire srst_c_n,   // active-low sync reset
  output wire pulse_c     // target-domain pulse (1clk)
);
  // toggle flops in source domain
  reg tgl_p;
  always @(posedge p_clk) begin
    if (!srst_p_n)
      tgl_p <= 1'b0;
    else if (pulse_p)
      tgl_p <= ~tgl_p;
  end

  // synchronize toggle into c_clk domain
  (* ASYNC_REG = "TRUE" *) reg [SYNC_STAGES-1:0] sync_c;
  integer i;
  always @(posedge c_clk) begin
    if (!srst_c_n)
      sync_c <= {SYNC_STAGES{1'b0}};
    else begin
      sync_c[0] <= tgl_p;
      for (i=1;i<SYNC_STAGES;i=i+1)
        sync_c[i] <= sync_c[i-1];
    end
  end

  assign pulse_c = sync_c[SYNC_STAGES-1] ^ sync_c[SYNC_STAGES-2];
endmodule
