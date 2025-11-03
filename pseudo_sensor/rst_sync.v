module rst_sync #(
    parameter integer STAGES = 3
)(
    input  wire clk,
    input  wire arst_n,      // async active-low
    output wire srst_n       // sync  active-low
);
    (* ASYNC_REG = "TRUE" *) reg [STAGES-1:0] shreg;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            shreg <= {STAGES{1'b0}};
        else
            shreg <= {shreg[STAGES-2:0], 1'b1};
    end

    assign srst_n = shreg[STAGES-1];
endmodule