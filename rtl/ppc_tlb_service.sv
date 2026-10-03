// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Software-loaded 4-KiB page instruction and data TLBs.
// Local reset clears valids; 603e hardware reset leaves them unchanged.
// HAS_602 adds the 602 entry bits (602UM Figure 5-17): ITLB NE and SE, and
// protection-only entries (req_po_i) holding 32 per-page NE or WE bits for
// a 128-KiB region, indexed by EA11-14 and tagged by EA0-10 and SR0's VSID
// (602UM 5.6.1, Figure 5-22).
module ppc_tlb_service #(
  parameter bit ENABLE_RUNTIME_INVALIDATE = 1'b0,
  parameter bit ENABLE_RUNTIME_REFILL = 1'b0,
  // Sets per TLB (two ways each): 32 on the 603e and 603, 16 on the 602.
  parameter int TLB_SETS = 32,
  parameter bit HAS_602 = 1'b0
) (
  input logic clk_i, rst_ni,
  input logic prepare_commit_i, prepare_abort_i,
  output logic commit_ack_valid_o,
  input logic commit_ack_ready_i,
  output logic transaction_idle_o,
  input logic req_valid_i,
  output logic req_ready_o,
  input ppc_pkg::tlb_req_kind_t req_kind_i,
  input logic req_bank_i,
  input logic [31:0] req_ea_i,
  input logic [23:0] req_vsid_i,
  input logic req_pr_i, req_ks_i, req_kp_i, req_n_i, req_t_i, req_write_i,
  input logic req_way_i,
  input logic [19:0] req_rpn_i,
  input logic req_c_i,
  input logic [3:0] req_wimg_i,
  input logic [1:0] req_pp_i,
  // 602: protection-only request, and RPA bits 20-24 less C ({20, NE, SE,
  // R, 29}) for a load.
  input logic req_po_i,
  input logic [4:0] req_ext_i,
  output logic rsp_valid_o,
  input logic rsp_ready_i,
  output ppc_pkg::tlb_req_kind_t rsp_kind_o,
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
  output logic rsp_c_o, rsp_r_o,
  output ppc_pkg::esa_enable_t rsp_esa_o
);
  import ppc_pkg::*;
  // The set index is the low EA page bits (UM EA15..19, 602UM EA16..19);
  // the remaining EA4 page bits form the tag.
  localparam int SET_W = $clog2(TLB_SETS);
  localparam int TAG_W = 16 - SET_W;
  // 602 entries add {po, RPA 20, NE, SE, R, RPA 29}.
  localparam int EXT_W = HAS_602 ? 6 : 1;
  // synthesis translate_off
  if (TLB_SETS != 32 && TLB_SETS != 16) begin : g_reject_sets
    $fatal(1, "TLB_SETS %0d is not a 603e (32) or 602 (16) geometry", TLB_SETS);
  end
  if (HAS_602 && TLB_SETS != 16) begin : g_reject_602_sets
    $fatal(1, "602 protection-only indexing needs the 16-set TLB");
  end
  // synthesis translate_on
  // Protection-only sets use EA11-14 (HDL [20:17]) and tag EA0-10 ([31:21]).
  // Each helper reads one slice of its EA argument.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [SET_W-1:0] set_of(logic [31:0] ea, logic po);
    return (HAS_602 && po) ? ea[17 +: SET_W] : ea[12 +: SET_W];
  endfunction
  function automatic logic [TAG_W-1:0] tag_of(logic [31:0] ea, logic po);
    logic [15:0] po_tag;
    po_tag = {5'b0, ea[31:21]};
    return (HAS_602 && po) ? po_tag[TAG_W-1:0] : ea[27 -: TAG_W];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  typedef struct packed {
    logic [23:0] vsid;
    logic [TAG_W-1:0] page_tag;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic [EXT_W-1:0] ext;
  } entry_t;
  typedef struct packed {
    tlb_req_kind_t kind;
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
    esa_enable_t esa;
  } response_t;
  typedef struct packed {
    tlb_req_kind_t kind;
    logic bank;
    logic [31:0] ea;
    logic [23:0] vsid;
    logic pr, ks, kp, n, t, write, way;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic po;
    logic [4:0] ext;
    logic abort;
  } request_t;

  // Bank 0 = ITLB, bank 1 = DTLB. UM 5.4.3.1/Figure 5-7.
  // Entries live in one RAM per way addressed by {bank, set}; valids stay in
  // flops so reset and tlbie clear them at once. A request reads both ways on
  // its accepting edge; the next edge classifies it from the registered read
  // and registers the response.
  logic [1:0][1:0][TLB_SETS-1:0] valid_q;
  // One LRU bit per set and bank names the way to replace next (UM Table
  // 5-10, SRR1[WAY]). A hit or refill of one way points it at the other.
  logic [1:0][TLB_SETS-1:0] lru_q;
  entry_t [1:0] entry_rd;
  logic ram_write;
  logic [1:0] ram_write_way;
  logic [SET_W:0] ram_write_addr;
  entry_t ram_write_data;
  request_t request_q;
  logic lookup_q;
  typedef struct packed {
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic [EXT_W-1:0] ext;
  } page_t;
  page_t selected_entry;
  entry_t refill_entry;
  response_t response_q, response_d;
  logic response_valid_q, request_fire, fill_commit, invalidate_commit;
  logic prepare_invalidate, prepare_refill;
  logic prepared_q, prepared_is_refill_q, commit_ack_q;
  logic prepared_bank_q, prepared_way_q, prepared_duplicate_q;
  logic [SET_W-1:0] prepared_set_q;
  entry_t prepared_entry_q;
  logic [SET_W-1:0] set_index;
  logic [1:0] matched;
  logic selected_way, selected_key, protection_denied, prepared_write;
  logic [31:0] selected_word;
  logic selected_ne, selected_se, po_bit;
  // Six-bit views of the variant-width entry extension; the po flag of the
  // selected view and the loaded fields of a 603e refill go unread.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [5:0] selected_ext, refill_ext;
  /* verilator lint_on UNUSEDSIGNAL */

  assign req_ready_o = rst_ni && !prepared_q && !commit_ack_q && !lookup_q &&
                       (!response_valid_q || rsp_ready_i);
  assign commit_ack_valid_o = rst_ni &&
    (ENABLE_RUNTIME_INVALIDATE || ENABLE_RUNTIME_REFILL) && commit_ack_q;
  assign transaction_idle_o = rst_ni && !response_valid_q && !lookup_q &&
                              !prepared_q && !commit_ack_q;
  assign rsp_valid_o = rst_ni && response_valid_q;
  assign request_fire = req_valid_i && req_ready_o;
  assign {rsp_kind_o, rsp_bank_o, rsp_ea_o, rsp_allow_o, rsp_hit_o,
    rsp_miss_o, rsp_protection_fault_o, rsp_guarded_fault_o, rsp_no_execute_o,
    rsp_direct_store_unsupported_o, rsp_needs_changed_o, rsp_privileged_o,
    rsp_refill_rejected_o, rsp_unsupported_o, rsp_invalid_input_o,
    rsp_match_o, rsp_way_o, rsp_pa_o, rsp_wimg_o, rsp_pp_o, rsp_c_o, rsp_r_o,
    rsp_esa_o} = response_q;

  // Prepared refill commit and immediate refill never share an edge: a
  // reservation blocks acceptance, and the refill decision needs the read.
  assign prepared_write = (ENABLE_RUNTIME_INVALIDATE || ENABLE_RUNTIME_REFILL) &&
    !prepare_abort_i && prepare_commit_i && prepared_q &&
    (!response_valid_q || rsp_ready_i) && prepared_is_refill_q;
  always_comb begin
    ram_write = prepared_write || fill_commit;
    ram_write_way = '0;
    if (prepared_write) begin
      ram_write_way[prepared_way_q] = 1'b1;
      ram_write_addr = {prepared_bank_q, prepared_set_q};
      ram_write_data = prepared_entry_q;
    end else begin
      ram_write_way[request_q.way] = 1'b1;
      ram_write_addr = {request_q.bank, set_index};
      ram_write_data = refill_entry;
    end
  end

  genvar ram_way;
  generate for (ram_way = 0; ram_way < 2; ram_way = ram_way + 1) begin : g_way
    ppc_tlb_ram #(.WIDTH($bits(entry_t)), .DEPTH(2 * TLB_SETS)) entries (
      .clk_i,
      .write_i(ram_write && ram_write_way[ram_way]),
      .write_addr_i(ram_write_addr), .write_data_i(ram_write_data),
      .read_addr_i({req_bank_i, set_of(req_ea_i, req_po_i)}),
      .read_data_o(entry_rd[ram_way])
    );
  end endgenerate

  always_comb begin
    // 32 sets: EA15..19 -> HDL [16:12], tag EA4..14 -> [27:17].
    // 16 sets: EA16..19 -> HDL [15:12], tag EA4..15 -> [27:16].
    // EA0..3 selects the caller's segment register and is deliberately not tagged.
    set_index = set_of(request_q.ea, request_q.po);
    matched = '0;
    for (int way = 0; way < 2; way++) begin
      matched[way] = valid_q[request_q.bank][way][set_index] &&
        entry_rd[way].vsid == request_q.vsid &&
        entry_rd[way].page_tag == tag_of(request_q.ea, request_q.po) &&
        (!HAS_602 || entry_rd[way].ext[EXT_W-1] == request_q.po);
    end
    selected_way = matched[1];
    selected_entry.rpn = entry_rd[selected_way].rpn;
    selected_entry.c = entry_rd[selected_way].c;
    selected_entry.wimg = entry_rd[selected_way].wimg;
    selected_entry.pp = entry_rd[selected_way].pp;
    selected_entry.ext = entry_rd[selected_way].ext;
    // The loaded RPA word; a protection-only entry's bit n guards page n
    // of its region, selected by EA15-19 (602UM Figures 5-22 to 5-24).
    selected_word = '0;
    selected_ne = 1'b0;
    selected_se = 1'b0;
    po_bit = 1'b0;
    selected_ext = '0;
    selected_ext[EXT_W-1:0] = selected_entry.ext;
    if (HAS_602) begin
      selected_word = {selected_entry.rpn, selected_ext[4:1],
        selected_entry.c, selected_entry.wimg, selected_ext[0],
        selected_entry.pp};
      selected_ne = selected_word[10];
      selected_se = selected_word[9];
      po_bit = selected_word[5'd31 - request_q.ea[16:12]];
    end
    selected_key = request_q.pr ? request_q.kp : request_q.ks;
    // PEM Table 7-21: page PP differs from BAT PP.
    protection_denied = (selected_key && selected_entry.pp == 2'b00) ||
      (request_q.write && (selected_entry.pp == 2'b11 ||
                      (selected_key && selected_entry.pp == 2'b01)));
    refill_entry.vsid = request_q.vsid;
    refill_entry.page_tag = tag_of(request_q.ea, request_q.po);
    refill_entry.rpn = request_q.rpn;
    refill_entry.c = request_q.c;
    refill_entry.wimg = request_q.wimg;
    refill_entry.pp = request_q.pp;
    refill_ext = HAS_602 ? {request_q.po, request_q.ext} : 6'b0;
    refill_entry.ext = refill_ext[EXT_W-1:0];
    fill_commit = 1'b0;
    invalidate_commit = 1'b0;
    prepare_invalidate = 1'b0;
    prepare_refill = 1'b0;
    response_d = '0;
    response_d.kind = request_q.kind;
    response_d.bank = request_q.bank;
    response_d.ea = request_q.ea;
    case (request_q.kind)
      TLB_LOOKUP: begin
        if (!request_q.bank && request_q.write) response_d.invalid_input = 1'b1;
        else if (HAS_602 && request_q.po) begin
          // 602UM Figures 5-27 and 5-28: SR0 T and N are ignored; key 0
          // allows every access, key 1 reads the entry's NE or WE bit.
          // PA = EA; R and C are not kept. The caller supplies HID0[WIMG].
          if (!selected_key) begin
            response_d.hit = 1'b1;
            response_d.allow_access = 1'b1;
            response_d.pa = request_q.ea;
            response_d.r = 1'b1;
            response_d.c = 1'b1;
            if (!request_q.bank) response_d.esa = ESA_PO_BASE;
          end else if (matched == 2'b00) begin
            response_d.miss = 1'b1;
            response_d.way = lru_q[request_q.bank][set_index];
          end else if (matched == 2'b11) response_d.invalid_input = 1'b1;
          else begin
            response_d.hit = 1'b1;
            response_d.matched = matched;
            response_d.way = selected_way;
            response_d.r = 1'b1;
            response_d.c = 1'b1;
            if (!request_q.bank && po_bit) response_d.no_execute = 1'b1;
            else if (request_q.bank && request_q.write && !po_bit)
              response_d.protection_fault = 1'b1;
            else begin
              response_d.allow_access = 1'b1;
              response_d.pa = request_q.ea;
              if (!request_q.bank) response_d.esa = ESA_PO_SER;
            end
          end
        end
        else if (request_q.t) response_d.direct_store = 1'b1;
        else if (!request_q.bank && request_q.n) response_d.no_execute = 1'b1;
        else if (matched == 2'b00) begin
          response_d.miss = 1'b1;
          response_d.way = lru_q[request_q.bank][set_index];
        end else if (matched == 2'b11) response_d.invalid_input = 1'b1;
        else begin
          response_d.hit = 1'b1;
          response_d.matched = matched;
          response_d.way = selected_way;
          response_d.wimg = selected_entry.wimg;
          response_d.pp = selected_entry.pp;
          response_d.c = selected_entry.c;
          // UM 5.4.1.1: every valid 603e TLB entry is effectively referenced.
          response_d.r = 1'b1;
          // 602 ITLB NE: an ISI before the PP check (602UM Table 5-2).
          if (!request_q.bank && selected_ne) response_d.no_execute = 1'b1;
          else if (protection_denied) response_d.protection_fault = 1'b1;
          else if (!request_q.bank && selected_entry.wimg[0]) response_d.guarded_fault = 1'b1;
          else if (request_q.write && !selected_entry.c) response_d.needs_changed = 1'b1;
          else begin
            response_d.allow_access = 1'b1;
            response_d.pa = {selected_entry.rpn, request_q.ea[11:0]};
            if (!request_q.bank && selected_se) response_d.esa = ESA_ALLOWED;
          end
        end
      end
      TLB_REFILL: begin
        if (request_q.pr) response_d.privileged = 1'b1;
        // The manual leaves duplicate tags undefined. A load replaces a
        // matching entry in the other way so a lookup never hits both.
        else fill_commit = lookup_q;
      end
      TLB_INVALIDATE_SET: begin
        if (request_q.pr) response_d.privileged = 1'b1;
        else invalidate_commit = lookup_q;
      end
      TLB_PREPARE_INVALIDATE: begin
        if (!ENABLE_RUNTIME_INVALIDATE) response_d.unsupported = 1'b1;
        else if (request_q.pr) response_d.privileged = 1'b1;
        else prepare_invalidate = !request_q.abort && !prepare_abort_i;
      end
      TLB_PREPARE_REFILL: begin
        if (!ENABLE_RUNTIME_REFILL) response_d.unsupported = 1'b1;
        else if (request_q.pr) response_d.privileged = 1'b1;
        else prepare_refill = !request_q.abort && !prepare_abort_i;
      end
      default: response_d.unsupported = 1'b1;
    endcase
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      valid_q <= '0;
      lru_q <= '0;
      response_valid_q <= 1'b0;
      response_q <= '0;
      request_q <= '0;
      lookup_q <= 1'b0;
      prepared_q <= 1'b0;
      prepared_is_refill_q <= 1'b0;
      prepared_bank_q <= 1'b0;
      prepared_way_q <= 1'b0;
      prepared_duplicate_q <= 1'b0;
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
            valid_q[prepared_bank_q][prepared_way_q][prepared_set_q] <= 1'b1;
            if (prepared_duplicate_q)
              valid_q[prepared_bank_q][!prepared_way_q][prepared_set_q] <= 1'b0;
            lru_q[prepared_bank_q][prepared_set_q] <= !prepared_way_q;
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
        lookup_q <= 1'b1;
        request_q.kind <= req_kind_i;
        request_q.bank <= req_bank_i;
        request_q.ea <= req_ea_i;
        request_q.vsid <= req_vsid_i;
        request_q.pr <= req_pr_i;
        request_q.ks <= req_ks_i;
        request_q.kp <= req_kp_i;
        request_q.n <= req_n_i;
        request_q.t <= req_t_i;
        request_q.write <= req_write_i;
        request_q.way <= req_way_i;
        request_q.rpn <= req_rpn_i;
        request_q.c <= req_c_i;
        request_q.wimg <= req_wimg_i;
        request_q.pp <= req_pp_i;
        request_q.po <= HAS_602 && req_po_i;
        request_q.ext <= HAS_602 ? req_ext_i : 5'b0;
        request_q.abort <= prepare_abort_i;
      end
      // Acceptance drained the response slot, so it is free here.
      if (lookup_q) begin
        lookup_q <= 1'b0;
        response_valid_q <= 1'b1;
        response_q <= response_d;
        if (ENABLE_RUNTIME_INVALIDATE && prepare_invalidate) begin
          prepared_q <= 1'b1;
          prepared_is_refill_q <= 1'b0;
          prepared_set_q <= set_index;
        end
        if (ENABLE_RUNTIME_REFILL && prepare_refill) begin
          prepared_q <= 1'b1;
          prepared_is_refill_q <= 1'b1;
          prepared_bank_q <= request_q.bank;
          prepared_way_q <= request_q.way;
          prepared_duplicate_q <= matched[!request_q.way];
          prepared_set_q <= set_index;
          prepared_entry_q <= refill_entry;
        end
        if (fill_commit) begin
          valid_q[request_q.bank][request_q.way][set_index] <= 1'b1;
          if (matched[!request_q.way])
            valid_q[request_q.bank][!request_q.way][set_index] <= 1'b0;
          lru_q[request_q.bank][set_index] <= !request_q.way;
        end
        if (response_d.hit && matched != 2'b00)
          lru_q[request_q.bank][set_index] <= !selected_way;
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
  always @(posedge clk_i) if (rst_ni) begin
    if (lookup_q) assert (!response_valid_q && !prepared_q && !commit_ack_q)
      else $error("TLB lookup overlaps a held response or reservation");
    if (ram_write) assert (!request_fire)
      else $error("TLB entry write coincides with a read");
    // Loads replace duplicates, so the invalid_input double hit is unreachable.
    if (lookup_q && (request_q.kind == TLB_LOOKUP)) assert (matched != 2'b11)
      else $error("TLB lookup hit both ways");
  end
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    rsp_valid_o && !rsp_ready_i |=>
      rsp_valid_o && $stable({rsp_kind_o, rsp_bank_o, rsp_ea_o,
        rsp_allow_o, rsp_hit_o, rsp_miss_o, rsp_protection_fault_o,
        rsp_guarded_fault_o, rsp_no_execute_o,
        rsp_direct_store_unsupported_o, rsp_needs_changed_o,
        rsp_privileged_o, rsp_refill_rejected_o, rsp_unsupported_o,
        rsp_invalid_input_o, rsp_match_o, rsp_way_o, rsp_pa_o,
        rsp_wimg_o, rsp_pp_o, rsp_c_o, rsp_r_o, rsp_esa_o}))
    else $error("held TLB response changed");
  // synthesis translate_on
endmodule
`default_nettype wire
