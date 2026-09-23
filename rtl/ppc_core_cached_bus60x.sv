// Core wrapper with a bounded instruction cache, burst refill master, and
// serialized fair sharing with the existing scalar data-bus master.
module ppc_core_cached_bus60x #(
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
  output logic                    icache_hit_o,
  output logic                    icache_miss_o,
  output logic                    icache_busy_o,

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
  logic imem_req_valid, imem_req_ready, cache_fetch_ready;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [31:0] dmem_rsp_rdata;

  logic cache_fetch_rsp_valid, cache_fetch_rsp_ready, cache_fetch_rsp_error;
  logic [31:0] cache_fetch_rsp_insn;
  logic cache_line_req_valid, cache_line_req_ready, cache_line_instruction;
  logic [31:0] cache_line_addr;
  logic [1:0] cache_line_critical;
  logic cache_line_rsp_valid, cache_line_rsp_ready, cache_line_rsp_error;
  logic [255:0] cache_line_rsp_data;
  logic cache_protocol_error;
  logic unused_icache_invalidate_done;

  logic scalar_req_ready, scalar_rsp_valid, scalar_rsp_error, scalar_busy;
  logic [31:0] scalar_rsp_rdata;
  logic scalar_protocol_error;
  logic scalar_br_n, scalar_bg_n, scalar_abb_in_n;
  logic scalar_abb_n, scalar_abb_oe, scalar_ts_n, scalar_ts_oe;
  logic [31:0] scalar_a;
  logic [4:0] scalar_tt;
  logic scalar_tbst_n;
  logic [2:0] scalar_tsiz;
  logic [1:0] scalar_tc, scalar_cse;
  logic scalar_ci_n, scalar_wt_n, scalar_gbl_n, scalar_addr_oe;
  logic scalar_aack_n, scalar_artry_n, scalar_dbg_n, scalar_dbb_in_n;
  logic scalar_dbb_n, scalar_dbb_oe;
  logic [63:0] scalar_d_o;
  logic scalar_d_oe, scalar_ta_n, scalar_drtry_n, scalar_tea_n;

  logic line_busy, line_protocol_error;
  logic line_br_n, line_bg_n, line_abb_in_n;
  logic line_abb_n, line_abb_oe, line_ts_n, line_ts_oe;
  logic [31:0] line_a;
  logic [4:0] line_tt;
  logic line_tbst_n;
  logic [2:0] line_tsiz;
  logic [1:0] line_tc, line_cse;
  logic line_ci_n, line_wt_n, line_gbl_n, line_addr_oe;
  logic line_aack_n, line_artry_n, line_dbg_n, line_dbb_in_n;
  logic line_dbb_n, line_dbb_oe;
  logic [63:0] line_d_o;
  logic line_d_oe, line_ta_n, line_drtry_n, line_tea_n;

  logic scalar_selected, line_selected, selector_busy;
  logic selector_protocol_error;
  logic scalar_pins_released, line_pins_released;
  logic ifetch_error_q;

  // Keep the core instance name stable for independent integration benches.
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

  ppc_icache icache (
    .clk_i, .rst_ni,
    .fetch_valid_i(imem_req_valid && !ifetch_error_q),
    .fetch_ready_o(cache_fetch_ready), .fetch_addr_i(imem_req_addr),
    .fetch_rsp_valid_o(cache_fetch_rsp_valid),
    .fetch_rsp_ready_i(cache_fetch_rsp_ready),
    .fetch_rsp_insn_o(cache_fetch_rsp_insn),
    .fetch_rsp_error_o(cache_fetch_rsp_error),
    .kill_i(1'b0), .invalidate_i(1'b0),
    .invalidate_done_o(unused_icache_invalidate_done),
    .line_req_valid_o(cache_line_req_valid),
    .line_req_ready_i(cache_line_req_ready),
    .line_req_line_addr_o(cache_line_addr),
    .line_req_critical_dw_o(cache_line_critical),
    .line_req_instruction_o(cache_line_instruction),
    .line_rsp_valid_i(cache_line_rsp_valid),
    .line_rsp_ready_o(cache_line_rsp_ready),
    .line_rsp_line_i(cache_line_rsp_data),
    .line_rsp_error_i(cache_line_rsp_error),
    .busy_o(icache_busy_o), .hit_o(icache_hit_o),
    .miss_o(icache_miss_o), .protocol_error_o(cache_protocol_error)
  );

  assign imem_req_ready = cache_fetch_ready && !ifetch_error_q;
  assign imem_rsp_valid = cache_fetch_rsp_valid &&
                          !cache_fetch_rsp_error && !ifetch_error_q;
  assign imem_rsp_insn = cache_fetch_rsp_insn;
  assign cache_fetch_rsp_ready = cache_fetch_rsp_error ?
                                  1'b1 : imem_rsp_ready;

  ppc_bus60x scalar_bus (
    .clk_i, .rst_ni,
    .req_valid_i(dmem_req_valid && !ifetch_error_q),
    .req_ready_o(scalar_req_ready), .req_instruction_i(1'b0),
    .req_write_i(dmem_req_write), .req_addr_i(dmem_req_addr),
    .req_wdata_i(dmem_req_wdata), .req_wstrb_i(dmem_req_wstrb),
    .rsp_valid_o(scalar_rsp_valid), .rsp_ready_i(dmem_rsp_ready),
    .rsp_rdata_o(scalar_rsp_rdata), .rsp_error_o(scalar_rsp_error),
    .busy_o(scalar_busy), .protocol_error_o(scalar_protocol_error),
    .br_n_o(scalar_br_n), .bg_n_i(scalar_bg_n),
    .abb_n_i(scalar_abb_in_n), .abb_n_o(scalar_abb_n),
    .abb_oe_o(scalar_abb_oe), .ts_n_o(scalar_ts_n),
    .ts_oe_o(scalar_ts_oe), .a_o(scalar_a), .tt_o(scalar_tt),
    .tbst_n_o(scalar_tbst_n), .tsiz_o(scalar_tsiz),
    .tc_o(scalar_tc), .ci_n_o(scalar_ci_n), .wt_n_o(scalar_wt_n),
    .gbl_n_o(scalar_gbl_n), .cse_o(scalar_cse),
    .addr_oe_o(scalar_addr_oe), .aack_n_i(scalar_aack_n),
    .artry_n_i(scalar_artry_n), .dbg_n_i(scalar_dbg_n),
    .dbb_n_i(scalar_dbb_in_n), .dbb_n_o(scalar_dbb_n),
    .dbb_oe_o(scalar_dbb_oe), .d_i(d_i), .d_o(scalar_d_o),
    .d_oe_o(scalar_d_oe), .ta_n_i(scalar_ta_n),
    .drtry_n_i(scalar_drtry_n), .tea_n_i(scalar_tea_n)
  );

  assign dmem_req_ready = scalar_req_ready && !ifetch_error_q;
  assign dmem_rsp_valid = scalar_rsp_valid;
  assign dmem_rsp_rdata = scalar_rsp_rdata;
  assign dmem_rsp_error = scalar_rsp_error;

  ppc_bus60x_line_read line_bus (
    .clk_i, .rst_ni,
    .req_valid_i(cache_line_req_valid),
    .req_ready_o(cache_line_req_ready),
    .req_line_addr_i(cache_line_addr),
    .req_critical_dw_i(cache_line_critical),
    .req_instruction_i(cache_line_instruction),
    .rsp_valid_o(cache_line_rsp_valid),
    .rsp_ready_i(cache_line_rsp_ready),
    .rsp_line_o(cache_line_rsp_data),
    .rsp_error_o(cache_line_rsp_error),
    .busy_o(line_busy), .protocol_error_o(line_protocol_error),
    .br_n_o(line_br_n), .bg_n_i(line_bg_n),
    .abb_n_i(line_abb_in_n), .abb_n_o(line_abb_n),
    .abb_oe_o(line_abb_oe), .ts_n_o(line_ts_n),
    .ts_oe_o(line_ts_oe), .a_o(line_a), .tt_o(line_tt),
    .tbst_n_o(line_tbst_n), .tsiz_o(line_tsiz),
    .tc_o(line_tc), .ci_n_o(line_ci_n), .wt_n_o(line_wt_n),
    .gbl_n_o(line_gbl_n), .cse_o(line_cse),
    .addr_oe_o(line_addr_oe), .aack_n_i(line_aack_n),
    .artry_n_i(line_artry_n), .dbg_n_i(line_dbg_n),
    .dbb_n_i(line_dbb_in_n), .dbb_n_o(line_dbb_n),
    .dbb_oe_o(line_dbb_oe), .d_i(d_i), .d_o(line_d_o),
    .d_oe_o(line_d_oe), .ta_n_i(line_ta_n),
    .drtry_n_i(line_drtry_n), .tea_n_i(line_tea_n)
  );

  assign scalar_pins_released = !scalar_abb_oe && !scalar_ts_oe &&
                                !scalar_addr_oe && !scalar_dbb_oe &&
                                !scalar_d_oe;
  assign line_pins_released = !line_abb_oe && !line_ts_oe &&
                              !line_addr_oe && !line_dbb_oe && !line_d_oe;

  ppc_bus60x_master_select selector (
    .clk_i, .rst_ni,
    .scalar_br_n_i(scalar_br_n), .scalar_busy_i(scalar_busy),
    .scalar_pins_released_i(scalar_pins_released),
    .scalar_bg_n_o(scalar_bg_n), .line_br_n_i(line_br_n),
    .line_busy_i(line_busy), .line_pins_released_i(line_pins_released),
    .line_bg_n_o(line_bg_n), .bg_n_i,
    .scalar_selected_o(scalar_selected), .line_selected_o(line_selected),
    .busy_o(selector_busy), .protocol_error_o(selector_protocol_error)
  );

  // Only the captured physical owner observes termination inputs.
  assign scalar_abb_in_n = scalar_selected ? abb_n_i : 1'b1;
  assign scalar_aack_n = scalar_selected ? aack_n_i : 1'b1;
  assign scalar_artry_n = scalar_selected ? artry_n_i : 1'b1;
  assign scalar_dbg_n = scalar_selected ? dbg_n_i : 1'b1;
  assign scalar_dbb_in_n = scalar_selected ? dbb_n_i : 1'b1;
  assign scalar_ta_n = scalar_selected ? ta_n_i : 1'b1;
  assign scalar_drtry_n = scalar_selected ? drtry_n_i : 1'b1;
  assign scalar_tea_n = scalar_selected ? tea_n_i : 1'b1;
  assign line_abb_in_n = line_selected ? abb_n_i : 1'b1;
  assign line_aack_n = line_selected ? aack_n_i : 1'b1;
  assign line_artry_n = line_selected ? artry_n_i : 1'b1;
  assign line_dbg_n = line_selected ? dbg_n_i : 1'b1;
  assign line_dbb_in_n = line_selected ? dbb_n_i : 1'b1;
  assign line_ta_n = line_selected ? ta_n_i : 1'b1;
  assign line_drtry_n = line_selected ? drtry_n_i : 1'b1;
  assign line_tea_n = line_selected ? tea_n_i : 1'b1;

  always_comb begin
    br_n_o = 1'b1;
    abb_n_o = 1'b1;
    abb_oe_o = 1'b0;
    ts_n_o = 1'b1;
    ts_oe_o = 1'b0;
    a_o = 32'b0;
    tt_o = 5'b0;
    tbst_n_o = 1'b1;
    tsiz_o = 3'b0;
    tc_o = 2'b0;
    ci_n_o = 1'b1;
    wt_n_o = 1'b1;
    gbl_n_o = 1'b1;
    cse_o = 2'b0;
    addr_oe_o = 1'b0;
    dbb_n_o = 1'b1;
    dbb_oe_o = 1'b0;
    d_o = 64'b0;
    d_oe_o = 1'b0;
    if (scalar_selected) begin
      br_n_o = scalar_br_n;
      abb_n_o = scalar_abb_n;
      abb_oe_o = scalar_abb_oe;
      ts_n_o = scalar_ts_n;
      ts_oe_o = scalar_ts_oe;
      a_o = scalar_a;
      tt_o = scalar_tt;
      tbst_n_o = scalar_tbst_n;
      tsiz_o = scalar_tsiz;
      tc_o = scalar_tc;
      ci_n_o = scalar_ci_n;
      wt_n_o = scalar_wt_n;
      gbl_n_o = scalar_gbl_n;
      cse_o = scalar_cse;
      addr_oe_o = scalar_addr_oe;
      dbb_n_o = scalar_dbb_n;
      dbb_oe_o = scalar_dbb_oe;
      d_o = scalar_d_o;
      d_oe_o = scalar_d_oe;
    end else if (line_selected) begin
      br_n_o = line_br_n;
      abb_n_o = line_abb_n;
      abb_oe_o = line_abb_oe;
      ts_n_o = line_ts_n;
      ts_oe_o = line_ts_oe;
      a_o = line_a;
      tt_o = line_tt;
      tbst_n_o = line_tbst_n;
      tsiz_o = line_tsiz;
      tc_o = line_tc;
      ci_n_o = line_ci_n;
      wt_n_o = line_wt_n;
      gbl_n_o = line_gbl_n;
      cse_o = line_cse;
      addr_oe_o = line_addr_oe;
      dbb_n_o = line_dbb_n;
      dbb_oe_o = line_dbb_oe;
      d_o = line_d_o;
      d_oe_o = line_d_oe;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni)
      ifetch_error_q <= 1'b0;
    else if (cache_fetch_rsp_valid && cache_fetch_rsp_ready &&
             cache_fetch_rsp_error)
      ifetch_error_q <= 1'b1;
  end

  assign ifetch_error_o = rst_ni && ifetch_error_q;
  assign halted_o = core_halted || ifetch_error_o;
  assign bus_protocol_error_o = cache_protocol_error ||
    scalar_protocol_error || line_protocol_error || selector_protocol_error;
  assign bus_busy_o = selector_busy || scalar_busy || line_busy ||
                      icache_busy_o || ifetch_error_o;
endmodule
