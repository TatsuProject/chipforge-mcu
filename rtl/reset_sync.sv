module reset_sync (
  input  wire clk,
  input  wire rst_n_async,  // external pushbutton or async reset, active low
  output reg  rst_n_sync    // synchronized reset, active low
);

  reg sync_ff;

  // Async assert (on rst_n_async=0), sync release (on posedge clk)
  always @(posedge clk or negedge rst_n_async) begin
    if (!rst_n_async) begin
      sync_ff   <= 1'b0;
      rst_n_sync<= 1'b0;
    end else begin
      sync_ff   <= 1'b1;
      rst_n_sync<= sync_ff;
    end
  end

endmodule
