// Reusable core wrapper for the bounded unified scalar 60x bus profile.
module ppc_core_bus60x #(
  parameter int DISPATCH_WIDTH = 1,
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
  parameter int DIV_LATENCY = 20,
  // Includes the existing serialized ISYNC/SYNC/EIEIO profile.
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,

  output logic                    retire_valid_o,
  input  logic                    retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output logic                    halted_o,
  output logic                    ifetch_error_o,
  output logic                    bus_protocol_error_o,
  output logic                    bus_busy_o,

  input  logic                     redirect_valid_i,
  input  logic                     redirect_all_i,
  input  logic                     redirect_keep_pivot_i,
  input  ppc_pkg::completion_tag_t redirect_pivot_i,
  input  logic [31:0]              redirect_target_i,
  output logic                     redirect_accepted_o,

  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        abb_n_i,
  output logic        abb_n_o,
  output logic        abb_oe_o,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  output logic [31:0] a_o,
  output logic [4:0]  tt_o,
  output logic        tbst_n_o,
  output logic [2:0]  tsiz_o,
  output logic [1:0]  tc_o,
  output logic        ci_n_o,
  output logic        wt_n_o,
  output logic        gbl_n_o,
  output logic [1:0]  cse_o,
  output logic        addr_oe_o,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  input  logic        dbg_n_i,
  input  logic        dbb_n_i,
  output logic        dbb_n_o,
  output logic        dbb_oe_o,
  input  logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i
);
  logic core_halted;
  logic imem_req_valid, imem_req_ready;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [31:0] dmem_rsp_rdata;

  logic bus_req_valid, bus_req_ready, bus_req_instruction, bus_req_write;
  logic [31:0] bus_req_addr, bus_req_wdata;
  logic [3:0] bus_req_wstrb;
  logic bus_rsp_valid, bus_rsp_ready, bus_rsp_error;
  logic [31:0] bus_rsp_rdata;
  logic router_busy, adapter_busy;

  // Keep this instance name stable for integration benches and debug paths.
  logic [3:0] unused_context;
  logic [32:0] unused_interrupt;
  logic [32:0] unused_decrementer;
  logic [47:0] unused_bat_csr;
  logic [36:0] unused_tlb_inv;
  logic [89:0] unused_tlb_fill;
  logic [41:0] unused_segment_csr;
  ppc_core #(
    .DISPATCH_WIDTH(DISPATCH_WIDTH),
    .RESET_PC(RESET_PC),
    .DIV_LATENCY(DIV_LATENCY),
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS)
  ) core (
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
    .clk_i, .rst_ni,
    .imem_req_valid_o(imem_req_valid),
    .imem_req_ready_i(imem_req_ready),
    .imem_req_addr_o(imem_req_addr),
    .imem_rsp_valid_i(imem_rsp_valid),
    .imem_rsp_ready_o(imem_rsp_ready),
    .imem_rsp_insn_i(imem_rsp_insn),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .dmem_req_valid_o(dmem_req_valid),
    .dmem_req_ready_i(dmem_req_ready),
    .dmem_req_write_o(dmem_req_write),
    .dmem_req_addr_o(dmem_req_addr),
    .dmem_req_wdata_o(dmem_req_wdata),
    .dmem_req_wstrb_o(dmem_req_wstrb),
    .dmem_rsp_valid_i(dmem_rsp_valid),
    .dmem_rsp_ready_o(dmem_rsp_ready),
    .dmem_rsp_rdata_i(dmem_rsp_rdata),
    .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), .dmem_rsp_error_i(dmem_rsp_error),
    .retire_valid_o, .retire_ready_i, .retire_o,
    .halted_o(core_halted),
    .redirect_valid_i, .redirect_all_i, .redirect_keep_pivot_i,
    .redirect_pivot_i, .redirect_target_i, .redirect_accepted_o
  );

  ppc_bus60x_arbiter router (
    .clk_i, .rst_ni,
    .imem_req_valid_i(imem_req_valid),
    .imem_req_ready_o(imem_req_ready),
    .imem_req_addr_i(imem_req_addr),
    .imem_rsp_valid_o(imem_rsp_valid),
    .imem_rsp_ready_i(imem_rsp_ready),
    .imem_rsp_insn_o(imem_rsp_insn),
    .dmem_req_valid_i(dmem_req_valid),
    .dmem_req_ready_o(dmem_req_ready),
    .dmem_req_write_i(dmem_req_write),
    .dmem_req_addr_i(dmem_req_addr),
    .dmem_req_wdata_i(dmem_req_wdata),
    .dmem_req_wstrb_i(dmem_req_wstrb),
    .dmem_rsp_valid_o(dmem_rsp_valid),
    .dmem_rsp_ready_i(dmem_rsp_ready),
    .dmem_rsp_rdata_o(dmem_rsp_rdata),
    .dmem_rsp_error_o(dmem_rsp_error),
    .bus_req_valid_o(bus_req_valid),
    .bus_req_ready_i(bus_req_ready),
    .bus_req_instruction_o(bus_req_instruction),
    .bus_req_write_o(bus_req_write),
    .bus_req_addr_o(bus_req_addr),
    .bus_req_wdata_o(bus_req_wdata),
    .bus_req_wstrb_o(bus_req_wstrb),
    .bus_rsp_valid_i(bus_rsp_valid),
    .bus_rsp_ready_o(bus_rsp_ready),
    .bus_rsp_rdata_i(bus_rsp_rdata),
    .bus_rsp_error_i(bus_rsp_error),
    .ifetch_error_o, .busy_o(router_busy)
  );

  ppc_bus60x bus (
    .clk_i, .rst_ni,
    .req_valid_i(bus_req_valid), .req_ready_o(bus_req_ready),
    .req_instruction_i(bus_req_instruction),
    .req_write_i(bus_req_write), .req_addr_i(bus_req_addr),
    .req_wdata_i(bus_req_wdata), .req_wstrb_i(bus_req_wstrb),
    .rsp_valid_o(bus_rsp_valid), .rsp_ready_i(bus_rsp_ready),
    .rsp_rdata_o(bus_rsp_rdata), .rsp_error_o(bus_rsp_error),
    .busy_o(adapter_busy), .protocol_error_o(bus_protocol_error_o),
    .br_n_o, .bg_n_i, .abb_n_i, .abb_n_o, .abb_oe_o,
    .ts_n_o, .ts_oe_o, .a_o, .tt_o, .tbst_n_o, .tsiz_o,
    .tc_o, .ci_n_o, .wt_n_o, .gbl_n_o, .cse_o, .addr_oe_o,
    .aack_n_i, .artry_n_i, .dbg_n_i, .dbb_n_i,
    .dbb_n_o, .dbb_oe_o, .d_i, .d_o, .d_oe_o,
    .ta_n_i, .drtry_n_i, .tea_n_i
  );

  // Transport-fatal instruction errors are externally visible as a stopped
  // wrapper.  Already resident core work may drain; no failed fetch response
  // is ever presented as an instruction.
  assign halted_o = core_halted || ifetch_error_o;
  assign bus_busy_o = router_busy || adapter_busy;
endmodule
