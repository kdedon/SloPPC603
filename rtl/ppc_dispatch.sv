`default_nettype none
// One-entry IU reservation station; pending operands retain producer identity.
module ppc_dispatch (
  input logic clk_i, rst_ni,
  input logic cancel_i,
  input logic dispatch_valid_i,
  output logic dispatch_ready_o,
  input ppc_pkg::rs_entry_t entry_i,
  input logic wake_valid_i,
  input ppc_pkg::wake_packet_t wake_i,
  output logic issue_valid_o,
  input logic issue_ready_i,
  output ppc_pkg::issue_packet_t issue_o
);
  import ppc_pkg::*;
  logic occupied;
  rs_entry_t entry;
  operand_t resolved_a, resolved_b;
  function automatic operand_t resolve(input operand_t pending);
    operand_t operand;
    operand = pending;
    if (!pending.ready && wake_valid_i && pending.tag == wake_i.tag &&
        pending.producer == wake_i.producer) begin
      operand.ready = 1'b1;
      operand.value = wake_i.value;
    end
    return operand;
  endfunction
  assign resolved_a = resolve(entry.a);
  assign resolved_b = resolve(entry.b);
  assign issue_valid_o = !cancel_i && occupied && resolved_a.ready && resolved_b.ready;
  assign issue_o.ctrl = entry.ctrl;
  assign issue_o.a = resolved_a.value;
  assign issue_o.b = resolved_b.value;
  assign dispatch_ready_o = !cancel_i && (!occupied || (issue_valid_o && issue_ready_i));
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      occupied <= 1'b0;
      entry <= '0;
    end else begin
      entry.a <= resolved_a;
      entry.b <= resolved_b;
      if (cancel_i || (issue_valid_o && issue_ready_i)) occupied <= 1'b0;
      if (dispatch_valid_i && dispatch_ready_o) begin
        occupied <= 1'b1;
        entry.ctrl <= entry_i.ctrl;
        // Also accept a wake coincident with capture of a pending source.
        entry.a <= resolve(entry_i.a);
        entry.b <= resolve(entry_i.b);
      end
    end
  end
endmodule
`default_nettype wire
