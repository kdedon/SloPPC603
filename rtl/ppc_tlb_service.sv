// Software-loaded 4-KiB page TLB boundary; see TLB_SERVICE.md.
// Local reset invalidates entries; real 603e reset does NOT clear TLB valids.
module ppc_tlb_service #(
  parameter bit ENABLE_RUNTIME_INVALIDATE = 1'b0,
  parameter bit ENABLE_RUNTIME_REFILL = 1'b0
) (
  input logic clk_i, rst_ni,
  input logic prepare_commit_i, prepare_abort_i,
  output logic commit_ack_valid_o,
  input logic commit_ack_ready_i,
  output logic transaction_idle_o,
  input logic req_valid_i,
  output logic req_ready_o,
  input logic [2:0] req_kind_i,
  input logic req_bank_i,
  input logic [31:0] req_ea_i,
  input logic [23:0] req_vsid_i,
  input logic req_pr_i, req_ks_i, req_kp_i, req_n_i, req_t_i, req_write_i,
  input logic req_way_i,
  input logic [19:0] req_rpn_i,
  input logic req_c_i,
  input logic [3:0] req_wimg_i,
  input logic [1:0] req_pp_i,
  output logic rsp_valid_o,
  input logic rsp_ready_i,
  output logic [2:0] rsp_kind_o,
  output logic rsp_bank_o,
  output logic [31:0] rsp_ea_o,
  output logic rsp_allow_o, rsp_hit_o, rsp_miss_o,
  output logic rsp_protection_fault_o, rsp_guarded_fault_o, rsp_no_execute_o,
  output logic rsp_direct_store_unsupported_o, rsp_needs_changed_o,
  output logic rsp_privileged_o, rsp_refill_rejected_o,
  output logic rsp_unsupported_o, rsp_invalid_input_o,
  output logic [1:0] rsp_match_o,
  output logic rsp_way_o,
  output logic [31:0] rsp_pa_o,
  output logic [3:0] rsp_wimg_o,
  output logic [1:0] rsp_pp_o,
  output logic rsp_c_o, rsp_r_o
);
  localparam logic [2:0] LOOKUP = 3'd0, REFILL = 3'd1,
    INVALIDATE_SET = 3'd2, PREPARE_INVALIDATE = 3'd4,
    PREPARE_REFILL = 3'd5;
  typedef struct packed {
    logic [23:0] vsid;
    logic [10:0] page_tag;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
  } entry_t;
  typedef struct packed {
    logic [2:0] kind;
    logic bank;
    logic [31:0] ea;
    logic allow_access, hit, miss, protection_fault, guarded_fault, no_execute;
    logic direct_store, needs_changed, privileged, refill_rejected;
    logic unsupported, invalid_input;
    logic [1:0] matched;
    logic way;
    logic [31:0] pa;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic c, r;
  } response_t;

  // Bank 0 = ITLB, bank 1 = DTLB. UM 5.4.3.1/Figure 5-7.
  logic [1:0][1:0][31:0] valid_q;
  entry_t entries_q [2][2][32];
  typedef struct packed {
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
  } page_t;
  page_t selected_entry;
  entry_t refill_entry;
  response_t response_q, response_d;
  logic response_valid_q, request_fire, fill_commit, invalidate_commit;
  logic prepared_q, prepared_is_refill_q, commit_ack_q;
  logic prepared_bank_q, prepared_way_q;
  logic [4:0] prepared_set_q;
  entry_t prepared_entry_q;
  logic [4:0] set_index;
  logic [1:0] matched;
  logic selected_way, selected_key, protection_denied;

  assign req_ready_o = rst_ni && !prepared_q && !commit_ack_q &&
                       (!response_valid_q || rsp_ready_i);
  assign commit_ack_valid_o = rst_ni &&
    (ENABLE_RUNTIME_INVALIDATE || ENABLE_RUNTIME_REFILL) && commit_ack_q;
  assign transaction_idle_o = rst_ni && !response_valid_q &&
                              !prepared_q && !commit_ack_q;
  assign rsp_valid_o = rst_ni && response_valid_q;
  assign request_fire = req_valid_i && req_ready_o;
  assign {rsp_kind_o, rsp_bank_o, rsp_ea_o, rsp_allow_o, rsp_hit_o,
    rsp_miss_o, rsp_protection_fault_o, rsp_guarded_fault_o, rsp_no_execute_o,
    rsp_direct_store_unsupported_o, rsp_needs_changed_o, rsp_privileged_o,
    rsp_refill_rejected_o, rsp_unsupported_o, rsp_invalid_input_o,
    rsp_match_o, rsp_way_o, rsp_pa_o, rsp_wimg_o, rsp_pp_o, rsp_c_o, rsp_r_o} = response_q;

  always_comb begin
    // Manual EA15..19 -> HDL [16:12]; EA4..14 -> HDL [27:17].
    // EA0..3 selects the caller's segment register and is deliberately not tagged.
    set_index = req_ea_i[16:12];
    matched = '0;
    for (int way = 0; way < 2; way++) begin
      matched[way] = valid_q[req_bank_i][way][set_index] &&
        entries_q[req_bank_i][way][set_index].vsid == req_vsid_i &&
        entries_q[req_bank_i][way][set_index].page_tag == req_ea_i[27:17];
    end
    selected_way = matched[1];
    selected_entry.rpn = entries_q[req_bank_i][selected_way][set_index].rpn;
    selected_entry.c = entries_q[req_bank_i][selected_way][set_index].c;
    selected_entry.wimg = entries_q[req_bank_i][selected_way][set_index].wimg;
    selected_entry.pp = entries_q[req_bank_i][selected_way][set_index].pp;
    selected_key = req_pr_i ? req_kp_i : req_ks_i;
    // PEM Table 7-21: page PP differs from BAT PP.
    protection_denied = (selected_key && selected_entry.pp == 2'b00) ||
      (req_write_i && (selected_entry.pp == 2'b11 ||
                      (selected_key && selected_entry.pp == 2'b01)));
    refill_entry.vsid = req_vsid_i;
    refill_entry.page_tag = req_ea_i[27:17];
    refill_entry.rpn = req_rpn_i;
    refill_entry.c = req_c_i;
    refill_entry.wimg = req_wimg_i;
    refill_entry.pp = req_pp_i;
    fill_commit = 1'b0;
    invalidate_commit = 1'b0;
    response_d = '0;
    response_d.kind = req_kind_i;
    response_d.bank = req_bank_i;
    response_d.ea = req_ea_i;
    case (req_kind_i)
      LOOKUP: begin
        if (!req_bank_i && req_write_i) response_d.invalid_input = 1'b1;
        else if (req_t_i) response_d.direct_store = 1'b1;
        else if (!req_bank_i && req_n_i) response_d.no_execute = 1'b1;
        else if (matched == 2'b00) response_d.miss = 1'b1;
        else if (matched == 2'b11) response_d.invalid_input = 1'b1;
        else begin
          response_d.hit = 1'b1;
          response_d.matched = matched;
          response_d.way = selected_way;
          response_d.wimg = selected_entry.wimg;
          response_d.pp = selected_entry.pp;
          response_d.c = selected_entry.c;
          // UM 5.4.1.1: every valid 603e TLB entry is effectively referenced.
          response_d.r = 1'b1;
          if (protection_denied) response_d.protection_fault = 1'b1;
          else if (!req_bank_i && selected_entry.wimg[0]) response_d.guarded_fault = 1'b1;
          else if (req_write_i && !selected_entry.c) response_d.needs_changed = 1'b1;
          else begin
            response_d.allow_access = 1'b1;
            response_d.pa = {selected_entry.rpn, req_ea_i[11:0]};
          end
        end
      end
      REFILL: begin
        if (req_pr_i) response_d.privileged = 1'b1;
        // Local unambiguous-bank policy; source does not define a duplicate winner.
        else if (matched[!req_way_i]) response_d.refill_rejected = 1'b1;
        else fill_commit = 1'b1;
      end
      INVALIDATE_SET: begin
        if (req_pr_i) response_d.privileged = 1'b1;
        else invalidate_commit = 1'b1;
      end
      PREPARE_INVALIDATE: begin
        if (!ENABLE_RUNTIME_INVALIDATE) response_d.unsupported = 1'b1;
        else if (req_pr_i) response_d.privileged = 1'b1;
      end
      PREPARE_REFILL: begin
        if (!ENABLE_RUNTIME_REFILL) response_d.unsupported = 1'b1;
        else if (req_pr_i) response_d.privileged = 1'b1;
        // Match the immediate-refill duplicate policy at preparation.
        else if (matched[!req_way_i]) response_d.refill_rejected = 1'b1;
      end
      default: response_d.unsupported = 1'b1;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      valid_q <= '0;
      response_valid_q <= 1'b0;
      response_q <= '0;
      prepared_q <= 1'b0;
      prepared_is_refill_q <= 1'b0;
      prepared_bank_q <= 1'b0;
      prepared_way_q <= 1'b0;
      prepared_set_q <= '0;
      prepared_entry_q <= '0;
      commit_ack_q <= 1'b0;
      // Entry data/tag storage is intentionally not reset; valids own visibility.
    end else begin
      if (response_valid_q && rsp_ready_i) response_valid_q <= 1'b0;
      if (ENABLE_RUNTIME_INVALIDATE || ENABLE_RUNTIME_REFILL) begin
        if (commit_ack_q && commit_ack_ready_i) commit_ack_q <= 1'b0;
        if (prepare_abort_i) prepared_q <= 1'b0;
        else if (prepare_commit_i && prepared_q &&
                 (!response_valid_q || rsp_ready_i)) begin
          if (prepared_is_refill_q) begin
            entries_q[prepared_bank_q][prepared_way_q][prepared_set_q] <=
              prepared_entry_q;
            valid_q[prepared_bank_q][prepared_way_q][prepared_set_q] <= 1'b1;
          end else begin
            for (int bank = 0; bank < 2; bank++) begin
              for (int way = 0; way < 2; way++)
                valid_q[bank][way][prepared_set_q] <= 1'b0;
            end
          end
          prepared_q <= 1'b0;
          commit_ack_q <= 1'b1;
        end
      end
      if (request_fire) begin
        response_valid_q <= 1'b1;
        response_q <= response_d;
        if (ENABLE_RUNTIME_INVALIDATE && req_kind_i == PREPARE_INVALIDATE &&
            !req_pr_i && !prepare_abort_i) begin
          prepared_q <= 1'b1;
          prepared_is_refill_q <= 1'b0;
          prepared_set_q <= set_index;
        end
        if (ENABLE_RUNTIME_REFILL && req_kind_i == PREPARE_REFILL &&
            !req_pr_i && !matched[!req_way_i] && !prepare_abort_i) begin
          prepared_q <= 1'b1;
          prepared_is_refill_q <= 1'b1;
          prepared_bank_q <= req_bank_i;
          prepared_way_q <= req_way_i;
          prepared_set_q <= set_index;
          prepared_entry_q <= refill_entry;
        end
        if (fill_commit) begin
          entries_q[req_bank_i][req_way_i][set_index] <= refill_entry;
          valid_q[req_bank_i][req_way_i][set_index] <= 1'b1;
        end
        if (invalidate_commit) begin
          // 603e tlbie invalidates FOUR entries, with no tag/VSID comparison.
          for (int bank = 0; bank < 2; bank++) begin
            for (int way = 0; way < 2; way++) valid_q[bank][way][set_index] <= 1'b0;
          end
        end
      end
    end
  end

  // synthesis translate_off
  always @(posedge clk_i) if (rst_ni &&
    (ENABLE_RUNTIME_INVALIDATE || ENABLE_RUNTIME_REFILL)) begin
    if (prepare_commit_i) assert (prepared_q && !commit_ack_q &&
      (!response_valid_q || rsp_ready_i) && !prepare_abort_i)
      else $error("TLB prepared commit lacks consumed reservation");
    if (commit_ack_q) assert (!prepared_q)
      else $error("TLB prepared reservation and ack overlap");
    if (prepared_q || commit_ack_q) assert (!req_ready_o)
      else $error("TLB prepared reservation lost exclusive slot");
  end
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    rsp_valid_o && !rsp_ready_i |=>
      rsp_valid_o && $stable({rsp_kind_o, rsp_bank_o, rsp_ea_o,
        rsp_allow_o, rsp_hit_o, rsp_miss_o, rsp_protection_fault_o,
        rsp_guarded_fault_o, rsp_no_execute_o,
        rsp_direct_store_unsupported_o, rsp_needs_changed_o,
        rsp_privileged_o, rsp_refill_rejected_o, rsp_unsupported_o,
        rsp_invalid_input_o, rsp_match_o, rsp_way_o, rsp_pa_o,
        rsp_wimg_o, rsp_pp_o, rsp_c_o, rsp_r_o}))
    else $error("held TLB response changed");
  // synthesis translate_on
endmodule
