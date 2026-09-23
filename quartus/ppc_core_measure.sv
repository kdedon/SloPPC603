module ppc_core_measure (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic [31:0] stimulus_i,
  output logic activity_o
);
  import ppc_pkg::*;

  logic req_valid;
  logic [31:0] req_addr;
  logic rsp_valid;
  logic rsp_ready;
  logic [31:0] rsp_insn;
  logic retire_valid;
  retire_packet_t retire;
  logic halted;

  (* preserve *) logic [31:0] retire_digest;

  logic unused_redirect_accepted;
  logic [3:0] unused_context;
  logic [32:0] unused_interrupt;
  logic [70:0] unused_dmem;
  logic [32:0] unused_decrementer;
  logic [47:0] unused_bat_csr;
  logic [36:0] unused_tlb_inv;
  logic [89:0] unused_tlb_fill;
  logic [41:0] unused_segment_csr;
  ppc_core dut (
    .clk_i,
    .rst_ni,
    .tlb_fill_req_valid_o(unused_tlb_fill[89]),
    .tlb_fill_req_bank_o(unused_tlb_fill[88]),
    .tlb_fill_req_ea_o(unused_tlb_fill[87:56]),
    .tlb_fill_req_vsid_o(unused_tlb_fill[55:32]),
    .tlb_fill_req_way_o(unused_tlb_fill[31]),
    .tlb_fill_req_rpn_o(unused_tlb_fill[30:11]),
    .tlb_fill_req_c_o(unused_tlb_fill[10]),
    .tlb_fill_req_wimg_o(unused_tlb_fill[9:6]),
    .tlb_fill_req_pp_o(unused_tlb_fill[5:4]),
    .tlb_fill_rsp_ready_o(unused_tlb_fill[3]),
    .tlb_fill_commit_o(unused_tlb_fill[2]),
    .tlb_fill_abort_o(unused_tlb_fill[1]),
    .tlb_fill_ack_ready_o(unused_tlb_fill[0]),
    .tlb_fill_req_ready_i(1'b0),
    .tlb_fill_rsp_valid_i(1'b0),
    .tlb_fill_rsp_error_i(1'b0),
    .tlb_fill_ack_valid_i(1'b0),
    .tlb_fill_idle_i(1'b1),
    .tlb_inv_req_valid_o(unused_tlb_inv[0]),
    .tlb_inv_req_ready_i(1'b0),
    .tlb_inv_req_ea_o(unused_tlb_inv[32:1]),
    .tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(unused_tlb_inv[33]),
    .tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(unused_tlb_inv[34]),
    .tlb_inv_abort_o(unused_tlb_inv[35]),
    .tlb_inv_ack_valid_i(1'b0),
    .tlb_inv_ack_ready_o(unused_tlb_inv[36]),
    .tlb_inv_idle_i(1'b1),
    .segment_csr_req_valid_o(unused_segment_csr[41]), .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[40]), .segment_csr_req_index_o(unused_segment_csr[39:36]),
    .segment_csr_req_data_o(unused_segment_csr[35:4]), .segment_csr_rsp_valid_i(1'b0),
    .segment_csr_rsp_ready_o(unused_segment_csr[3]), .segment_csr_rsp_data_i(32'b0),
    .segment_csr_rsp_error_i(1'b0), .segment_csr_commit_o(unused_segment_csr[2]),
    .segment_csr_abort_o(unused_segment_csr[1]), .segment_csr_ack_valid_i(1'b0),
    .segment_csr_ack_ready_o(unused_segment_csr[0]), .segment_csr_idle_i(1'b1),
    .bat_csr_req_valid_o(unused_bat_csr[47]), .bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]), .bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_csr[35:4]), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0), .bat_csr_commit_o(unused_bat_csr[2]),
    .bat_csr_abort_o(unused_bat_csr[1]), .bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b0),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    
    .dmem_req_valid_o(unused_dmem[0]), .dmem_req_ready_i(1'b0),
    .dmem_req_write_o(unused_dmem[1]), .dmem_req_addr_o(unused_dmem[33:2]),
    .dmem_req_wdata_o(unused_dmem[65:34]), .dmem_req_wstrb_o(unused_dmem[69:66]),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(unused_dmem[70]),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), .dmem_rsp_error_i(1'b0),
    .imem_req_valid_o(req_valid),
    .imem_req_ready_i(!rsp_valid),
    .imem_req_addr_o(req_addr),
    .imem_rsp_valid_i(rsp_valid),
    .imem_rsp_ready_o(rsp_ready),
    .imem_rsp_insn_i(rsp_insn),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .retire_valid_o(retire_valid),
    .retire_ready_i(1'b1),
    .retire_o(retire),
    .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(unused_redirect_accepted)
  );

  // One-cycle registered responder. addi r3,r3,1 is legal in the scaffold.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rsp_valid <= 1'b0;
      rsp_insn <= 32'h3863_0001;
    end else begin
      if (rsp_valid && rsp_ready)
        rsp_valid <= 1'b0;
      if (req_valid && !rsp_valid) begin
        rsp_valid <= 1'b1;
        rsp_insn <= stimulus_i;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni)
      retire_digest <= 32'h603e_0000;
    else if (retire_valid)
      retire_digest <= {retire_digest[30:0], retire_digest[31]} ^
                       retire.pc ^ retire.insn ^ retire.value ^ req_addr ^
                       {31'b0, retire.alignment_exception} ^
                       {29'b0, retire.fetch_fault} ^
                       {29'b0, retire.data_fault} ^
                       retire.page_miss.ea ^ retire.page_miss.sr ^
                       {27'b0, retire.page_miss.pr, retire.page_miss.ir,
                        retire.page_miss.dr, retire.page_miss.write, retire.page_miss.way} ^
                       {31'b0, retire.rename_owned} ^
                       retire.update_value ^
                       retire.cr_delta ^ retire.xer_delta ^ {29'b0, retire.cr_field} ^
                       {23'b0, retire.cr_mask, retire.write_cr_fields} ^
                       {26'b0, retire.cr_bit, retire.write_cr_bit} ^
                       {27'b0, retire.needs_flags, retire.write_xer, retire.write_ca, retire.write_ov_so, retire.write_cr0} ^
                       {15'b0, retire.illegal, retire.gpr_write,
                        retire.update_write, retire.update_gpr,
                        retire.gpr, retire.tag, halted};
  end

  assign activity_o = ^retire_digest;
endmodule
