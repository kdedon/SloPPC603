// Registered storage; no combinational bypass. Full queues reclaim next cycle.
module ppc_fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 6
) (
  input logic clk_i, rst_ni,
  input logic clear_i,
  input logic push_valid_i,
  output logic push_ready_o,
  input logic [WIDTH-1:0] push_data_i,
  output logic pop_valid_o,
  input logic pop_ready_i,
  output logic [WIDTH-1:0] pop_data_o
);
  localparam int PTR_WIDTH = $clog2(DEPTH);
  localparam int COUNT_WIDTH = $clog2(DEPTH + 1);
  logic [WIDTH-1:0] entries [DEPTH];
  logic [PTR_WIDTH-1:0] rd_ptr, wr_ptr;
  logic [COUNT_WIDTH-1:0] count;
  logic push, pop;
  assign push_ready_o = rst_ni && !clear_i && (count < COUNT_WIDTH'(DEPTH));
  assign pop_valid_o = rst_ni && !clear_i && (count != 0);
  // Data is meaningful only with pop_valid_o. Invalidation withdraws valid
  // immediately without placing the clear/recovery path on the data mux.
  // Keep reset and empty output behavior; a clear edge discards the old head.
  assign pop_data_o = (rst_ni && count != 0) ? entries[rd_ptr] : '0;
  assign push = push_valid_i && push_ready_o;
  assign pop = pop_valid_o && pop_ready_i;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear_i) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
      count <= '0;
    end else begin
      if (push) begin
        entries[wr_ptr] <= push_data_i;
        wr_ptr <= (wr_ptr == PTR_WIDTH'(DEPTH-1)) ? '0 : wr_ptr + 1'b1;
      end
      if (pop)
        rd_ptr <= (rd_ptr == PTR_WIDTH'(DEPTH-1)) ? '0 : rd_ptr + 1'b1;
      case ({push, pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: ;
      endcase
    end
  end
endmodule
