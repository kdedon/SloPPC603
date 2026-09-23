// Fair serialized selector for the scalar and line-read 60x masters.
// Physical ownership is retained through response consumption and pin release.
module ppc_bus60x_master_select (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic scalar_br_n_i,
  input  logic scalar_busy_i,
  input  logic scalar_pins_released_i,
  output logic scalar_bg_n_o,
  input  logic line_br_n_i,
  input  logic line_busy_i,
  input  logic line_pins_released_i,
  output logic line_bg_n_o,
  input  logic bg_n_i,
  output logic scalar_selected_o,
  output logic line_selected_o,
  output logic busy_o,
  output logic protocol_error_o
);
  typedef enum logic [1:0] {
    OWNER_NONE,
    OWNER_SCALAR,
    OWNER_LINE,
    OWNER_INVALID
  } owner_t;

  owner_t owner_q;
  logic last_completed_line_q;
  logic choose_scalar, choose_line;
  logic protocol_error_q;

  always_comb begin
    choose_scalar = 1'b0;
    choose_line = 1'b0;
    if (rst_ni && owner_q == OWNER_NONE) begin
      if (!scalar_br_n_i && !line_br_n_i) begin
        // Select the side opposite the most recently completed owner.
        choose_scalar = last_completed_line_q;
        choose_line = !last_completed_line_q;
      end else begin
        choose_scalar = !scalar_br_n_i;
        choose_line = !line_br_n_i;
      end
    end

    scalar_selected_o = rst_ni &&
      (owner_q == OWNER_SCALAR || choose_scalar);
    line_selected_o = rst_ni &&
      (owner_q == OWNER_LINE || choose_line);
    busy_o = rst_ni && owner_q != OWNER_NONE;
    protocol_error_o = rst_ni && protocol_error_q;
  end

  // Keep external BG outside the request-selection cone.  Selection depends
  // only on held BR/history, avoiding a false combinational BG/BR loop in a
  // responder that derives its grant from the aggregate physical request.
  assign scalar_bg_n_o = scalar_selected_o ? bg_n_i : 1'b1;
  assign line_bg_n_o = line_selected_o ? bg_n_i : 1'b1;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      owner_q <= OWNER_NONE;
      // Seed scalar as the previous owner so a first tie selects line refill.
      last_completed_line_q <= 1'b0;
      protocol_error_q <= 1'b0;
    end else begin
      unique case (owner_q)
        OWNER_NONE: begin
          if (choose_scalar)
            owner_q <= OWNER_SCALAR;
          else if (choose_line)
            owner_q <= OWNER_LINE;
        end
        OWNER_SCALAR: begin
          if (!scalar_busy_i && scalar_pins_released_i) begin
            last_completed_line_q <= 1'b0;
            owner_q <= OWNER_NONE;
          end
        end
        OWNER_LINE: begin
          if (!line_busy_i && line_pins_released_i) begin
            last_completed_line_q <= 1'b1;
            owner_q <= OWNER_NONE;
          end
        end
        default: begin
          owner_q <= OWNER_NONE;
          protocol_error_q <= 1'b1;
        end
      endcase
      if (scalar_selected_o && line_selected_o)
        protocol_error_q <= 1'b1;
    end
  end
endmodule
