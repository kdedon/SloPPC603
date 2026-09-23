// One-entry IU reservation station; pending operands retain producer identity.
module ppc_dispatch (
  input logic clk_i, rst_ni,
  input logic cancel_i,
  input logic dispatch_valid_i,
  output logic dispatch_ready_o,
  input ppc_pkg::alu_op_t op_i,
  input ppc_pkg::completion_tag_t producer_i,
  input ppc_pkg::operand_t a_i, b_i,
  input logic [31:0] mask_i,
  input logic [4:0] shift_i,
  input logic ca_i,
  input logic so_i,
  input logic write_ca_i,
  input logic write_ov_so_i,
  input logic write_cr0_i,
  input logic wake_valid_i,
  input ppc_pkg::wake_packet_t wake_i,
  output logic issue_valid_o,
  input logic issue_ready_i,
  output ppc_pkg::issue_packet_t issue_o
);
  import ppc_pkg::*;
  logic occupied;
  alu_op_t op;
  completion_tag_t producer;
  operand_t a, b, resolved_a, resolved_b;
  logic [31:0] mask;
  logic [4:0] shift;
  logic ca_in, so_in, write_ca, write_ov_so, write_cr0;
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
  assign resolved_a = resolve(a);
  assign resolved_b = resolve(b);
  assign issue_valid_o = rst_ni && !cancel_i && occupied && resolved_a.ready && resolved_b.ready;
  assign issue_o.op = op;
  assign issue_o.producer = producer;
  assign issue_o.a = resolved_a.value;
  assign issue_o.b = resolved_b.value;
  assign issue_o.mask = mask;
  assign issue_o.shift = shift;
  assign issue_o.ca_in = ca_in;
  assign issue_o.so_in = so_in;
  assign issue_o.write_ca = write_ca;
  assign issue_o.write_ov_so = write_ov_so;
  assign issue_o.write_cr0 = write_cr0;
  assign dispatch_ready_o = rst_ni && !cancel_i && (!occupied || (issue_valid_o && issue_ready_i));
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      occupied <= 1'b0;
      op <= ALU_ADD;
      producer <= '0;
      a <= '0;
      b <= '0;
      mask <= '0;
      shift <= '0;
      ca_in <= 1'b0;
      so_in <= 1'b0;
      write_ca <= 1'b0;
      write_ov_so <= 1'b0;
      write_cr0 <= 1'b0;
    end else begin
      a <= resolved_a;
      b <= resolved_b;
      if (cancel_i || (issue_valid_o && issue_ready_i)) occupied <= 1'b0;
      if (dispatch_valid_i && dispatch_ready_o) begin
        occupied <= 1'b1;
        op <= op_i;
        producer <= producer_i;
        mask <= mask_i;
        shift <= shift_i;
        ca_in <= ca_i;
        so_in <= so_i;
        write_ca <= write_ca_i;
        write_ov_so <= write_ov_so_i;
        write_cr0 <= write_cr0_i;
        // Also accept a wake coincident with capture of a pending source.
        a <= resolve(a_i);
        b <= resolve(b_i);
      end
    end
  end
endmodule
