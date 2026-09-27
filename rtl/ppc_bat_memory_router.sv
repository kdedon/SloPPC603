`default_nettype none
// Effective-to-physical instruction/data router: BAT translation with optional
// segment/TLB page fallback, committed MSR context and retirement-prepared
// BAT, segment and TLB updates. Instruction and data lanes each hold one
// request. A micro-TLB hit issues the physical request on the next edge; a
// miss queues for the one shared translation sequence.
module ppc_bat_memory_router #(
  parameter bit ENABLE_LIVE_CONTEXT = 1'b0,
  parameter bit ENABLE_RUNTIME_BAT = 1'b0,
  parameter bit ENABLE_SEGMENT_REGISTERS = 1'b0,
  parameter bit ENABLE_PAGE_TRANSLATION = 1'b0,
  parameter bit ENABLE_TLB_INVALIDATE = 1'b0,
  parameter bit ENABLE_TLB_LOAD = 1'b0,
  parameter bit ENABLE_DATA_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_PAGE_DATA_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_PAGE_INSTRUCTION_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_PAGE_MISS_RESULTS = 1'b0,
  parameter bit ENABLE_MICRO_TLB = 1'b1,
  parameter int MICRO_TLB_ENTRIES = 4
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic        bat_write_valid_i,
  output logic        bat_write_ready_o,
  input  logic [9:0]  bat_write_spr_i,
  input  logic [31:0] bat_write_data_i,
  output logic        bat_write_rsp_valid_o,
  input  logic        bat_write_rsp_ready_i,
  output logic        bat_write_rsp_rejected_o,
  output logic        bat_write_rsp_unsupported_o,
  output logic        bat_write_rsp_config_error_o,
  output logic        bat_write_rsp_overlap_o,
  output logic [3:0]  bat_write_rsp_invalid_entry_o,

  input  logic bat_csr_req_valid_i,
  output logic bat_csr_req_ready_o,
  input  logic bat_csr_req_write_i,
  input  logic [9:0] bat_csr_req_spr_i,
  input  logic [31:0] bat_csr_req_data_i,
  output logic bat_csr_rsp_valid_o,
  input  logic bat_csr_rsp_ready_i,
  output logic [31:0] bat_csr_rsp_data_o,
  output logic bat_csr_rsp_error_o,
  input  logic bat_csr_commit_i,
  input  logic bat_csr_abort_i,
  output logic bat_csr_ack_valid_o,
  input  logic bat_csr_ack_ready_i,
  output logic bat_csr_idle_o,

  input  logic segment_csr_req_valid_i,
  output logic segment_csr_req_ready_o,
  input  logic segment_csr_req_write_i,
  input  logic [3:0] segment_csr_req_index_i,
  input  logic [31:0] segment_csr_req_data_i,
  output logic segment_csr_rsp_valid_o,
  input  logic segment_csr_rsp_ready_i,
  output logic [31:0] segment_csr_rsp_data_o,
  output logic segment_csr_rsp_error_o,
  input  logic segment_csr_commit_i,
  input  logic segment_csr_abort_i,
  output logic segment_csr_ack_valid_o,
  input  logic segment_csr_ack_ready_i,
  output logic segment_csr_idle_o,

  input  logic tlb_inv_req_valid_i,
  output logic tlb_inv_req_ready_o,
  input  logic [31:0] tlb_inv_req_ea_i,
  output logic tlb_inv_rsp_valid_o,
  input  logic tlb_inv_rsp_ready_i,
  output logic tlb_inv_rsp_error_o,
  input  logic tlb_inv_commit_i,
  input  logic tlb_inv_abort_i,
  output logic tlb_inv_ack_valid_o,
  input  logic tlb_inv_ack_ready_i,
  output logic tlb_inv_idle_o,

  input  logic tlb_fill_req_valid_i,
  output logic tlb_fill_req_ready_o,
  input  logic tlb_fill_req_bank_i,
  input  logic [31:0] tlb_fill_req_ea_i,
  input  logic [23:0] tlb_fill_req_vsid_i,
  input  logic tlb_fill_req_way_i,
  input  logic [19:0] tlb_fill_req_rpn_i,
  input  logic tlb_fill_req_c_i,
  input  logic [3:0] tlb_fill_req_wimg_i,
  input  logic [1:0] tlb_fill_req_pp_i,
  output logic tlb_fill_rsp_valid_o,
  input  logic tlb_fill_rsp_ready_i,
  output logic tlb_fill_rsp_error_o,
  input  logic tlb_fill_commit_i,
  input  logic tlb_fill_abort_i,
  output logic tlb_fill_ack_valid_o,
  input  logic tlb_fill_ack_ready_i,
  output logic tlb_fill_idle_o,

  input  logic tlb_mgmt_req_valid_i,
  output logic tlb_mgmt_req_ready_o,
  input  logic [1:0] tlb_mgmt_req_kind_i,
  input  logic tlb_mgmt_req_bank_i,
  input  logic [31:0] tlb_mgmt_req_ea_i,
  input  logic [23:0] tlb_mgmt_req_vsid_i,
  input  logic tlb_mgmt_req_pr_i,
  input  logic tlb_mgmt_req_way_i,
  input  logic [19:0] tlb_mgmt_req_rpn_i,
  input  logic tlb_mgmt_req_c_i,
  input  logic [3:0] tlb_mgmt_req_wimg_i,
  input  logic [1:0] tlb_mgmt_req_pp_i,
  output logic tlb_mgmt_rsp_valid_o,
  input  logic tlb_mgmt_rsp_ready_i,
  output logic [1:0] tlb_mgmt_rsp_kind_o,
  output logic tlb_mgmt_rsp_bank_o,
  output logic [31:0] tlb_mgmt_rsp_ea_o,
  output logic tlb_mgmt_rsp_privileged_o,
  output logic tlb_mgmt_rsp_refill_rejected_o,
  output logic tlb_mgmt_rsp_unsupported_o,
  output logic tlb_mgmt_rsp_invalid_input_o,
  output logic tlb_mgmt_idle_o,

  input  logic start_valid_i,
  output logic start_ready_o,
  input  logic start_ir_i,
  input  logic start_dr_i,
  input  logic start_pr_i,
  output logic running_o,
  output logic context_ir_o,
  output logic context_dr_o,
  output logic context_pr_o,

  input  logic context_valid_i,
  output logic context_ready_o,
  input  logic context_ir_i,
  input  logic context_dr_i,
  input  logic context_pr_i,
  output logic quiescent_o,

  output logic        pimem_req_valid_o,
  input  logic        pimem_req_ready_i,
  output logic [31:0] pimem_req_addr_o,
  output logic [3:0]  pimem_req_wimg_o,
  input  logic        pimem_rsp_valid_i,
  output logic        pimem_rsp_ready_o,
  input  logic [31:0] pimem_rsp_insn_i,
  input  logic        pimem_rsp_error_i,

  output logic        pdmem_req_valid_o,
  input  logic        pdmem_req_ready_i,
  output logic        pdmem_req_write_o,
  output logic [31:0] pdmem_req_addr_o,
  output logic [31:0] pdmem_req_wdata_o,
  output logic [3:0]  pdmem_req_wstrb_o,
  output logic [3:0]  pdmem_req_wimg_o,
  input  logic        pdmem_rsp_valid_i,
  output logic        pdmem_rsp_ready_o,
  input  logic [31:0] pdmem_rsp_rdata_i,
  input  logic        pdmem_rsp_error_i,

  input  logic        imem_req_valid_i,
  output logic        imem_req_ready_o,
  input  logic [31:0] imem_req_addr_i,
  output logic        imem_rsp_valid_o,
  input  logic        imem_rsp_ready_i,
  output logic [31:0] imem_rsp_insn_o,
  output ppc_pkg::fetch_fault_t imem_rsp_fault_o,
  output ppc_pkg::page_miss_t imem_rsp_page_miss_o,
  input  logic        dmem_req_valid_i,
  output logic        dmem_req_ready_o,
  input  logic        dmem_req_write_i,
  input  logic [31:0] dmem_req_addr_i,
  input  logic [31:0] dmem_req_wdata_i,
  input  logic [3:0]  dmem_req_wstrb_i,
  output logic        dmem_rsp_valid_o,
  input  logic        dmem_rsp_ready_i,
  output logic [31:0] dmem_rsp_rdata_o,
  output logic        dmem_rsp_error_o,
  output ppc_pkg::data_fault_t dmem_rsp_fault_o,
  output ppc_pkg::page_miss_t dmem_rsp_page_miss_o,

  output logic       translation_fault_o,
  output logic       fault_instruction_o,
  output logic       fault_write_o,
  output logic [31:0] fault_ea_o,
  output logic       fault_miss_o,
  output logic       fault_protection_o,
  output logic       fault_guarded_o,
  output logic       fault_config_o,
  output logic       fault_invalid_input_o,
  output logic [3:0] fault_invalid_entry_o,
  output logic       page_fault_o,
  output logic       page_miss_o,
  output logic       page_protection_o,
  output logic       page_no_execute_o,
  output logic       page_guarded_o,
  output logic       page_direct_store_o,
  output logic       page_needs_changed_o,
  output logic       page_config_o,
  output logic       pimem_error_o,
  output logic       ifetch_fatal_o,
  output logic       busy_o
);
  import ppc_pkg::*;

  typedef enum logic [3:0] {
    ROUTE_IDLE,
    ROUTE_TRANSLATE_OFFER,
    ROUTE_TRANSLATE_RESPONSE,
    ROUTE_SEGMENT_OFFER,
    ROUTE_SEGMENT_RESPONSE,
    ROUTE_PAGE_OFFER,
    ROUTE_PAGE_RESPONSE,
    ROUTE_DATA_FAULT_RESPONSE,
    ROUTE_IFETCH_FAULT_RESPONSE,
    ROUTE_IFETCH_FATAL,
    ROUTE_INVALID
  } route_state_t;

  // A lane waits for the translation sequence, is owned by it, or carries
  // its translated request to the physical port.
  typedef enum logic [2:0] {
    LANE_IDLE,
    LANE_WAIT,
    LANE_SLOW,
    LANE_OFFER,
    LANE_RESPONSE,
    LANE_FATAL
  } lane_state_t;

  route_state_t state_q;
  lane_state_t i_state_q, d_state_q;
  logic [31:0] i_ea_q, d_ea_q, i_pa_q, d_pa_q, d_wdata_q;
  logic [3:0] i_wimg_q, d_wimg_q, d_wstrb_q;
  logic d_write_q;
  logic lanes_idle, lane_accept_ok, i_accept, d_accept, i_finish, d_finish;
  logic i_hit, d_hit, i_hit_raw, d_hit_raw;
  logic [19:0] i_hit_rpn, d_hit_rpn;
  logic [3:0] i_hit_wimg, d_hit_wimg;
  lane_state_t i_accept_state, d_accept_state;
  logic route_allow, route_from_tlb, route_set_touch;
  logic [31:0] route_pa;
  logic [3:0] route_wimg;
  logic utlb_flush;
  logic running_q, context_ir_q, context_dr_q, context_pr_q;
  // Private !running_q copy for the BAT request select, kept off the core's
  // high-fanout running net.
  (* dont_merge *) logic bat_setup_q;
  // Private running copy for running_o, which gates the core's reset.
  (* dont_merge *) logic running_out_q;
  logic request_ir_q, request_dr_q, request_pr_q;
  fetch_fault_t fetch_fault_q;
  data_fault_t data_fault_q;
  logic last_grant_data_q, owner_instruction_q, owner_write_q;
  logic [31:0] request_ea_q;
  logic [31:0] page_sr_q;
  page_miss_t page_miss_result_q;

  logic imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_req_addr, imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [31:0] dmem_rsp_rdata;
  logic choose_instruction, choose_data;

  logic bat_req_valid, bat_req_ready;
  bat_req_kind_t bat_req_kind;
  logic [31:0] bat_req_ea;
  logic [9:0] bat_req_spr;
  logic [31:0] bat_req_data;
  logic bat_rsp_valid, bat_rsp_ready;
  bat_req_kind_t bat_rsp_kind;
  logic [31:0] bat_rsp_ea, bat_rsp_data, bat_rsp_pa;
  logic [9:0] bat_rsp_spr;
  logic bat_rsp_privileged, bat_rsp_unsupported, bat_rsp_write_rejected;
  logic bat_rsp_allow, bat_rsp_bypass, bat_rsp_hit, bat_rsp_miss;
  logic bat_rsp_protection, bat_rsp_guarded, bat_rsp_config;
  logic bat_rsp_invalid_input, bat_rsp_overlap;
  logic [3:0] bat_rsp_invalid_entry, bat_rsp_match, bat_rsp_wimg;
  logic [1:0] bat_rsp_hit_index, bat_rsp_pp;

  logic fault_q, fault_instruction_q, fault_write_q;
  logic [31:0] fault_ea_q;
  logic fault_miss_q, fault_protection_q, fault_guarded_q;
  logic fault_config_q, fault_invalid_input_q;
  logic [3:0] fault_invalid_entry_q;
  logic pimem_error_q, ifetch_fatal_q;
  logic csr_owner, csr_offer, service_idle, service_ack;
  logic segment_owner, segment_offer, segment_service_idle;
  logic segment_req_valid, segment_req_ready;
  logic segment_rsp_valid, segment_rsp_ready;
  seg_req_kind_t segment_rsp_kind;
  logic [3:0] segment_rsp_index;
  logic [31:0] segment_rsp_address, segment_rsp_data;
  logic segment_rsp_privileged, segment_rsp_unsupported;
  logic segment_service_ack;
  logic service_pr;
  logic tlb_inv_owner, tlb_inv_offer;
  logic tlb_fill_owner, tlb_fill_offer;
  logic [31:0] tlb_fill_ea_q;
  logic tlb_fill_bank_q;
  logic tlb_commit_ack, tlb_transaction_idle;
  logic tlb_mgmt_owner, tlb_mgmt_offer;
  // One exclusive owner of the idle service slot. Offer and grant vectors are
  // indexed in priority order.
  typedef enum logic [2:0] {
    OWN_NONE, OWN_BAT_CSR, OWN_SEGMENT, OWN_TLB_INV, OWN_TLB_FILL, OWN_TLB_MGMT
  } owner_t;
  localparam int SLOT_BAT_CSR = 0, SLOT_SEGMENT = 1, SLOT_TLB_INV = 2,
                 SLOT_TLB_FILL = 3, SLOT_TLB_MGMT = 4, SLOT_COUNT = 5;
  owner_t owner_q;
  logic slot_free;
  logic [SLOT_COUNT-1:0] slot_eligible, slot_pending, slot_offer, slot_grant;
  logic tlb_req_valid, tlb_req_ready;
  tlb_req_kind_t tlb_req_kind;
  logic tlb_req_bank, tlb_req_pr, tlb_req_ks, tlb_req_kp;
  logic tlb_req_n, tlb_req_t, tlb_req_write, tlb_req_way, tlb_req_c;
  logic [31:0] tlb_req_ea;
  logic [23:0] tlb_req_vsid;
  logic [19:0] tlb_req_rpn;
  logic [3:0] tlb_req_wimg;
  logic [1:0] tlb_req_pp;
  logic tlb_rsp_valid, tlb_rsp_ready, tlb_rsp_bank;
  tlb_req_kind_t tlb_rsp_kind;
  logic [1:0] tlb_rsp_match, tlb_rsp_pp;
  logic [31:0] tlb_rsp_ea, tlb_rsp_pa;
  logic [3:0] tlb_rsp_wimg;
  logic tlb_rsp_allow, tlb_rsp_hit, tlb_rsp_miss;
  logic tlb_rsp_protection, tlb_rsp_guarded, tlb_rsp_no_execute;
  logic tlb_rsp_direct_store, tlb_rsp_needs_changed;
  logic tlb_rsp_privileged, tlb_rsp_refill_rejected;
  logic tlb_rsp_unsupported, tlb_rsp_invalid_input;
  logic tlb_rsp_way, tlb_rsp_c, tlb_rsp_r;
  logic page_reply_config, page_reply_allow, clean_bat_page_miss;
  logic clean_page_data_pp;
  logic clean_page_instruction_base;
  logic clean_page_instruction_pp, clean_page_instruction_guarded;
  logic clean_page_instruction_no_execute;
  logic clean_page_miss_base, clean_page_true_miss, clean_page_changed;
  logic bat_fetch_isi, bat_data_dsi, bat_typed_fault, page_typed_fault;
  logic page_fault_q, page_miss_q, page_protection_q;
  logic page_no_execute_q, page_guarded_q, page_direct_store_q;
  logic page_needs_changed_q, page_config_q;

  // The slot is free once memory has drained, no transaction owns it and
  // every service has released its response, proposal and ack. A slot is
  // offered to each eligible requester with no pending higher-priority peer:
  // BAT CSR, segment CSR, tlbie, TLB load, then management. Management alone
  // runs before start; startup BAT writes, running memory and context win.
  assign slot_free = rst_ni && state_q == ROUTE_IDLE && owner_q == OWN_NONE &&
    lanes_idle && service_idle && segment_service_idle &&
    tlb_transaction_idle && !imem_req_valid && !dmem_req_valid;
  assign slot_eligible[SLOT_BAT_CSR] = ENABLE_RUNTIME_BAT && running_q;
  assign slot_eligible[SLOT_SEGMENT] = ENABLE_SEGMENT_REGISTERS && running_q;
  assign slot_eligible[SLOT_TLB_INV] = ENABLE_TLB_INVALIDATE && running_q;
  assign slot_eligible[SLOT_TLB_FILL] = ENABLE_TLB_LOAD && running_q;
  assign slot_eligible[SLOT_TLB_MGMT] = ENABLE_PAGE_TRANSLATION &&
    !bat_write_valid_i && !bat_rsp_valid && !(running_q && context_valid_i);
  assign slot_pending[SLOT_BAT_CSR] = ENABLE_RUNTIME_BAT && bat_csr_req_valid_i;
  assign slot_pending[SLOT_SEGMENT] = ENABLE_SEGMENT_REGISTERS &&
    segment_csr_req_valid_i;
  assign slot_pending[SLOT_TLB_INV] = ENABLE_TLB_INVALIDATE &&
    tlb_inv_req_valid_i;
  assign slot_pending[SLOT_TLB_FILL] = ENABLE_TLB_LOAD && tlb_fill_req_valid_i;
  assign slot_pending[SLOT_TLB_MGMT] = ENABLE_PAGE_TRANSLATION &&
    tlb_mgmt_req_valid_i;
  always_comb begin
    logic higher_pending;
    higher_pending = 1'b0;
    for (int slot = 0; slot < SLOT_COUNT; slot++) begin
      slot_offer[slot] = slot_free && slot_eligible[slot] && !higher_pending;
      higher_pending = higher_pending || slot_pending[slot];
    end
  end
  assign slot_grant[SLOT_BAT_CSR] = slot_offer[SLOT_BAT_CSR] &&
    bat_csr_req_valid_i && bat_req_ready;
  assign slot_grant[SLOT_SEGMENT] = slot_offer[SLOT_SEGMENT] &&
    segment_csr_req_valid_i && segment_req_ready;
  assign slot_grant[SLOT_TLB_INV] = slot_offer[SLOT_TLB_INV] &&
    tlb_inv_req_valid_i && tlb_req_ready;
  assign slot_grant[SLOT_TLB_FILL] = slot_offer[SLOT_TLB_FILL] &&
    tlb_fill_req_valid_i && tlb_req_ready;
  assign slot_grant[SLOT_TLB_MGMT] = slot_offer[SLOT_TLB_MGMT] &&
    tlb_mgmt_req_valid_i && tlb_req_ready;
  assign csr_offer = slot_offer[SLOT_BAT_CSR];
  assign segment_offer = slot_offer[SLOT_SEGMENT];
  assign tlb_inv_offer = slot_offer[SLOT_TLB_INV];
  assign tlb_fill_offer = slot_offer[SLOT_TLB_FILL];
  assign tlb_mgmt_offer = slot_offer[SLOT_TLB_MGMT];
  assign csr_owner = owner_q == OWN_BAT_CSR;
  assign segment_owner = owner_q == OWN_SEGMENT;
  assign tlb_inv_owner = owner_q == OWN_TLB_INV;
  assign tlb_fill_owner = owner_q == OWN_TLB_FILL;
  assign tlb_mgmt_owner = owner_q == OWN_TLB_MGMT;

  // Memory drain excludes the caller's own CSR transport/reservation. CSR idle
  // separately tracks that ownership so waiting for a response cannot deadlock.
  assign bat_csr_req_ready_o = csr_offer && bat_req_ready;
  assign bat_csr_rsp_valid_o = ENABLE_RUNTIME_BAT && csr_owner && bat_rsp_valid;
  assign bat_csr_rsp_data_o = bat_rsp_data;
  assign bat_csr_rsp_error_o = bat_rsp_privileged || bat_rsp_unsupported ||
    bat_rsp_write_rejected || bat_rsp_config || bat_rsp_overlap ||
    bat_rsp_invalid_input || (|bat_rsp_invalid_entry);
  assign bat_csr_ack_valid_o = ENABLE_RUNTIME_BAT && csr_owner && service_ack;
  assign bat_csr_idle_o = rst_ni && (!ENABLE_RUNTIME_BAT || !csr_owner);
  assign segment_req_valid =
    (segment_offer && segment_csr_req_valid_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_SEGMENT_OFFER);
  assign segment_csr_req_ready_o = segment_offer && segment_req_ready;
  assign segment_csr_rsp_valid_o = ENABLE_SEGMENT_REGISTERS &&
    segment_owner && segment_rsp_valid;
  assign segment_csr_rsp_data_o = segment_rsp_data;
  assign segment_csr_rsp_error_o = segment_rsp_privileged ||
    segment_rsp_unsupported;
  assign segment_csr_ack_valid_o = ENABLE_SEGMENT_REGISTERS &&
    segment_owner && segment_service_ack;
  assign segment_csr_idle_o = rst_ni &&
    (!ENABLE_SEGMENT_REGISTERS || !segment_owner);
  assign segment_rsp_ready =
    (segment_owner && segment_csr_rsp_ready_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_SEGMENT_RESPONSE);

  assign tlb_inv_req_ready_o = tlb_inv_offer && tlb_req_ready;
  assign tlb_inv_rsp_valid_o = ENABLE_TLB_INVALIDATE &&
    tlb_inv_owner && tlb_rsp_valid;
  assign tlb_inv_rsp_error_o = tlb_rsp_privileged ||
    tlb_rsp_refill_rejected || tlb_rsp_unsupported ||
    tlb_rsp_invalid_input;
  assign tlb_inv_ack_valid_o = ENABLE_TLB_INVALIDATE &&
    tlb_inv_owner && tlb_commit_ack;
  assign tlb_inv_idle_o = rst_ni &&
    (!ENABLE_TLB_INVALIDATE || !tlb_inv_owner);

  assign tlb_fill_req_ready_o = tlb_fill_offer && tlb_req_ready;
  assign tlb_fill_rsp_valid_o = ENABLE_TLB_LOAD &&
    tlb_fill_owner && tlb_rsp_valid;
  assign tlb_fill_rsp_error_o = tlb_rsp_privileged ||
    tlb_rsp_refill_rejected || tlb_rsp_unsupported ||
    tlb_rsp_invalid_input || tlb_rsp_kind != TLB_PREPARE_REFILL ||
    tlb_rsp_bank != tlb_fill_bank_q || tlb_rsp_ea != tlb_fill_ea_q;
  assign tlb_fill_ack_valid_o = ENABLE_TLB_LOAD &&
    tlb_fill_owner && tlb_commit_ack;
  assign tlb_fill_idle_o = rst_ni &&
    (!ENABLE_TLB_LOAD || !tlb_fill_owner);

  assign tlb_mgmt_req_ready_o = tlb_mgmt_offer && tlb_req_ready;
  assign tlb_mgmt_rsp_valid_o = ENABLE_PAGE_TRANSLATION &&
    tlb_mgmt_owner && tlb_rsp_valid;
  assign tlb_mgmt_rsp_kind_o = tlb_rsp_kind[1:0];
  assign tlb_mgmt_rsp_bank_o = tlb_rsp_bank;
  assign tlb_mgmt_rsp_ea_o = tlb_rsp_ea;
  assign tlb_mgmt_rsp_privileged_o = tlb_rsp_privileged;
  assign tlb_mgmt_rsp_refill_rejected_o = tlb_rsp_refill_rejected;
  assign tlb_mgmt_rsp_unsupported_o = tlb_rsp_unsupported;
  assign tlb_mgmt_rsp_invalid_input_o = tlb_rsp_invalid_input;
  assign tlb_mgmt_idle_o = rst_ni &&
    (!ENABLE_PAGE_TRANSLATION || !tlb_mgmt_owner) &&
    (!ENABLE_TLB_INVALIDATE ||
     (!tlb_inv_owner && !tlb_inv_req_valid_i)) &&
    (!ENABLE_TLB_LOAD ||
     (!tlb_fill_owner && !tlb_fill_req_valid_i));

  assign tlb_req_valid =
    (tlb_mgmt_offer && tlb_mgmt_req_valid_i) ||
    (tlb_inv_offer && tlb_inv_req_valid_i) ||
    (tlb_fill_offer && tlb_fill_req_valid_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_PAGE_OFFER);
  assign tlb_req_kind = state_q == ROUTE_PAGE_OFFER ? TLB_LOOKUP :
    (tlb_inv_offer && tlb_inv_req_valid_i ? TLB_PREPARE_INVALIDATE :
      (tlb_fill_offer && tlb_fill_req_valid_i ? TLB_PREPARE_REFILL :
        (tlb_mgmt_req_kind_i == 2'd1 ? TLB_REFILL :
          (tlb_mgmt_req_kind_i == 2'd2 ? TLB_INVALIDATE_SET : TLB_RESERVED))));
  assign tlb_req_bank = state_q == ROUTE_PAGE_OFFER ?
    !owner_instruction_q :
    (tlb_inv_offer && tlb_inv_req_valid_i ? 1'b0 :
      (tlb_fill_offer && tlb_fill_req_valid_i ?
        tlb_fill_req_bank_i : tlb_mgmt_req_bank_i));
  assign tlb_req_ea = state_q == ROUTE_PAGE_OFFER ?
    request_ea_q : (tlb_inv_offer && tlb_inv_req_valid_i ?
      tlb_inv_req_ea_i : (tlb_fill_offer && tlb_fill_req_valid_i ?
        tlb_fill_req_ea_i : tlb_mgmt_req_ea_i));
  assign tlb_req_vsid = state_q == ROUTE_PAGE_OFFER ?
    page_sr_q[23:0] :
    (tlb_inv_offer && tlb_inv_req_valid_i ? 24'b0 :
      (tlb_fill_offer && tlb_fill_req_valid_i ?
        tlb_fill_req_vsid_i : tlb_mgmt_req_vsid_i));
  assign tlb_req_pr = state_q == ROUTE_PAGE_OFFER ?
    request_pr_q :
    ((tlb_inv_offer && tlb_inv_req_valid_i) ||
     (tlb_fill_offer && tlb_fill_req_valid_i)) ?
      context_pr_q : tlb_mgmt_req_pr_i;
  assign tlb_req_ks = state_q == ROUTE_PAGE_OFFER && page_sr_q[30];
  assign tlb_req_kp = state_q == ROUTE_PAGE_OFFER && page_sr_q[29];
  assign tlb_req_n = state_q == ROUTE_PAGE_OFFER && page_sr_q[28];
  assign tlb_req_t = state_q == ROUTE_PAGE_OFFER && page_sr_q[31];
  assign tlb_req_write = state_q == ROUTE_PAGE_OFFER && owner_write_q;
  assign tlb_req_way = (tlb_inv_offer && tlb_inv_req_valid_i) ?
    1'b0 : (tlb_fill_offer && tlb_fill_req_valid_i ?
      tlb_fill_req_way_i : tlb_mgmt_req_way_i);
  assign tlb_req_rpn = (tlb_inv_offer && tlb_inv_req_valid_i) ?
    20'b0 : (tlb_fill_offer && tlb_fill_req_valid_i ?
      tlb_fill_req_rpn_i : tlb_mgmt_req_rpn_i);
  assign tlb_req_c = (tlb_inv_offer && tlb_inv_req_valid_i) ?
    1'b0 : (tlb_fill_offer && tlb_fill_req_valid_i ?
      tlb_fill_req_c_i : tlb_mgmt_req_c_i);
  assign tlb_req_wimg = (tlb_inv_offer && tlb_inv_req_valid_i) ?
    4'b0 : (tlb_fill_offer && tlb_fill_req_valid_i ?
      tlb_fill_req_wimg_i : tlb_mgmt_req_wimg_i);
  assign tlb_req_pp = (tlb_inv_offer && tlb_inv_req_valid_i) ?
    2'b0 : (tlb_fill_offer && tlb_fill_req_valid_i ?
      tlb_fill_req_pp_i : tlb_mgmt_req_pp_i);
  assign tlb_rsp_ready = (tlb_mgmt_owner && tlb_mgmt_rsp_ready_i) ||
    (tlb_inv_owner && tlb_inv_rsp_ready_i) ||
    (tlb_fill_owner && tlb_fill_rsp_ready_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_PAGE_RESPONSE);

  assign clean_bat_page_miss = ENABLE_PAGE_TRANSLATION && bat_rsp_miss &&
    !bat_rsp_allow && !bat_rsp_bypass && !bat_rsp_hit &&
    !bat_rsp_protection && !bat_rsp_guarded && !bat_rsp_config &&
    !bat_rsp_invalid_input && !bat_rsp_overlap &&
    !(|bat_rsp_invalid_entry) && !bat_rsp_privileged &&
    !bat_rsp_unsupported && !bat_rsp_write_rejected &&
    (owner_instruction_q ? request_ir_q : request_dr_q);
  assign page_reply_config = tlb_rsp_kind != TLB_LOOKUP ||
    tlb_rsp_bank != !owner_instruction_q || tlb_rsp_ea != request_ea_q ||
    tlb_rsp_invalid_input || tlb_rsp_privileged ||
    tlb_rsp_refill_rejected || tlb_rsp_unsupported ||
    (tlb_rsp_allow && !tlb_rsp_hit) ||
    (tlb_rsp_allow && (tlb_rsp_miss || tlb_rsp_protection ||
      tlb_rsp_guarded || tlb_rsp_no_execute || tlb_rsp_direct_store ||
      tlb_rsp_needs_changed)) ||
    (!tlb_rsp_allow && !(tlb_rsp_miss || tlb_rsp_protection ||
      tlb_rsp_guarded || tlb_rsp_no_execute || tlb_rsp_direct_store ||
      tlb_rsp_needs_changed));
  assign page_reply_allow = tlb_rsp_allow && !page_reply_config;
  // Only an exact, unambiguous page hit denied solely by PP is a DSI.
  // The held data response carries the typed cause; sticky pins are diagnostics.
  assign clean_page_data_pp = ENABLE_PAGE_DATA_EXCEPTIONS &&
    !owner_instruction_q && !page_reply_config &&
    tlb_rsp_kind == TLB_LOOKUP && tlb_rsp_bank &&
    tlb_rsp_ea == request_ea_q && tlb_rsp_hit &&
    !tlb_rsp_allow && tlb_rsp_protection && !tlb_rsp_miss &&
    !tlb_rsp_guarded && !tlb_rsp_no_execute &&
    !tlb_rsp_direct_store && !tlb_rsp_needs_changed &&
    !tlb_rsp_privileged && !tlb_rsp_refill_rejected &&
    !tlb_rsp_unsupported && !tlb_rsp_invalid_input;
  // Instruction ISI classification uses the accepted SR snapshot. N rejects
  // before tag lookup, so only PP and G require a matching TLB entry.
  assign clean_page_instruction_base =
    ENABLE_PAGE_INSTRUCTION_EXCEPTIONS && owner_instruction_q &&
    !page_reply_config && !page_sr_q[31] &&
    tlb_rsp_kind == TLB_LOOKUP && !tlb_rsp_bank &&
    tlb_rsp_ea == request_ea_q && !tlb_rsp_allow && !tlb_rsp_miss &&
    !tlb_rsp_direct_store && !tlb_rsp_needs_changed &&
    !tlb_rsp_privileged && !tlb_rsp_refill_rejected &&
    !tlb_rsp_unsupported && !tlb_rsp_invalid_input;
  assign clean_page_instruction_pp = clean_page_instruction_base &&
    !page_sr_q[28] && tlb_rsp_hit && tlb_rsp_protection &&
    !tlb_rsp_guarded && !tlb_rsp_no_execute;
  assign clean_page_instruction_guarded = clean_page_instruction_base &&
    !page_sr_q[28] && tlb_rsp_hit && tlb_rsp_guarded &&
    !tlb_rsp_protection && !tlb_rsp_no_execute;
  assign clean_page_instruction_no_execute = clean_page_instruction_base &&
    page_sr_q[28] && tlb_rsp_no_execute &&
    !tlb_rsp_protection && !tlb_rsp_guarded;
  // Typed miss diagnostics require one exact lookup result and one cause.
  // The service checks protection before a store's C bit, so a PP denial
  // cannot be recast as a changed-bit request.
  assign clean_page_miss_base = ENABLE_PAGE_MISS_RESULTS &&
    !page_reply_config && !page_sr_q[31] &&
    tlb_rsp_kind == TLB_LOOKUP && tlb_rsp_bank == !owner_instruction_q &&
    tlb_rsp_ea == request_ea_q && !tlb_rsp_allow &&
    !tlb_rsp_protection && !tlb_rsp_guarded &&
    !tlb_rsp_no_execute && !tlb_rsp_direct_store &&
    !tlb_rsp_privileged && !tlb_rsp_refill_rejected &&
    !tlb_rsp_unsupported && !tlb_rsp_invalid_input;
  assign clean_page_true_miss = clean_page_miss_base &&
    (!owner_instruction_q || !page_sr_q[28]) &&
    tlb_rsp_miss && !tlb_rsp_hit && !tlb_rsp_needs_changed &&
    tlb_rsp_match == 2'b00 && !tlb_rsp_c && !tlb_rsp_r;
  assign clean_page_changed = clean_page_miss_base &&
    !owner_instruction_q && owner_write_q &&
    tlb_rsp_hit && !tlb_rsp_miss && tlb_rsp_needs_changed &&
    (tlb_rsp_match == 2'b01 || tlb_rsp_match == 2'b10) &&
    tlb_rsp_way == tlb_rsp_match[1] &&
    !tlb_rsp_c && tlb_rsp_r;
  // Typed faults return to the core as resumable exceptions. Only the
  // remaining diagnostic outcomes set the sticky fault and page outputs.
  // Protection outranks guarded, matching the page path.
  assign bat_fetch_isi = ENABLE_LIVE_CONTEXT && !bat_rsp_miss &&
    !bat_rsp_config && !bat_rsp_invalid_input &&
    (bat_rsp_protection || bat_rsp_guarded);
  assign bat_data_dsi = ENABLE_DATA_EXCEPTIONS && bat_rsp_hit &&
    bat_rsp_protection && !bat_rsp_miss && !bat_rsp_config &&
    !bat_rsp_invalid_input && !(|bat_rsp_invalid_entry) && !bat_rsp_guarded;
  assign bat_typed_fault = owner_instruction_q ? bat_fetch_isi : bat_data_dsi;
  assign page_typed_fault = owner_instruction_q ?
    (clean_page_true_miss || clean_page_instruction_pp ||
     clean_page_instruction_guarded || clean_page_instruction_no_execute) :
    (clean_page_data_pp || clean_page_true_miss || clean_page_changed);
  assign service_pr = !bat_setup_q &&
    ((csr_offer && bat_csr_req_valid_i) ? context_pr_q : request_pr_q);

  assign imem_req_valid = imem_req_valid_i;
  assign imem_req_addr = imem_req_addr_i;
  assign imem_req_ready_o = imem_req_ready;
  assign imem_rsp_valid_o = imem_rsp_valid;
  assign imem_rsp_page_miss_o = (ENABLE_PAGE_MISS_RESULTS &&
    imem_rsp_valid && imem_rsp_fault_o == FETCH_PAGE_MISS) ?
    page_miss_result_q : '0;
  assign imem_rsp_insn_o = imem_rsp_insn;
  assign imem_rsp_ready = imem_rsp_ready_i;
  assign dmem_req_valid = dmem_req_valid_i;
  assign dmem_req_write = dmem_req_write_i;
  assign dmem_req_addr = dmem_req_addr_i;
  assign dmem_req_wdata = dmem_req_wdata_i;
  assign dmem_req_wstrb = dmem_req_wstrb_i;
  assign dmem_req_ready_o = dmem_req_ready;
  assign dmem_rsp_valid_o = dmem_rsp_valid;
  assign dmem_rsp_page_miss_o = (ENABLE_PAGE_MISS_RESULTS &&
    dmem_rsp_valid && (dmem_rsp_fault_o == DATA_PAGE_MISS ||
                       dmem_rsp_fault_o == DATA_PAGE_CHANGED)) ?
    page_miss_result_q : '0;
  assign dmem_rsp_rdata_o = dmem_rsp_rdata;
  assign dmem_rsp_error_o = dmem_rsp_error;
  assign dmem_rsp_ready = dmem_rsp_ready_i;

  // Do not block a held old-context request merely because an update waits.
  // The core fences new offers and drains all old obligations before updating.
  assign quiescent_o = rst_ni && running_q && state_q == ROUTE_IDLE &&
                       lanes_idle &&
                       (!bat_rsp_valid || (ENABLE_RUNTIME_BAT && csr_owner)) &&
                       (!segment_rsp_valid || segment_owner) &&
                       (!tlb_rsp_valid || tlb_mgmt_owner ||
                        tlb_inv_owner || tlb_fill_owner) &&
                       !imem_req_valid && !dmem_req_valid;
  assign context_ready_o = ENABLE_LIVE_CONTEXT && quiescent_o &&
    (!ENABLE_RUNTIME_BAT || (!csr_owner && !bat_csr_req_valid_i)) &&
    (!ENABLE_SEGMENT_REGISTERS ||
     (!segment_owner && !segment_csr_req_valid_i)) &&
    (!ENABLE_PAGE_TRANSLATION || !tlb_mgmt_owner) &&
    (!ENABLE_TLB_INVALIDATE ||
     (!tlb_inv_owner && !tlb_inv_req_valid_i)) &&
    (!ENABLE_TLB_LOAD ||
     (!tlb_fill_owner && !tlb_fill_req_valid_i));

  // A lane accepts while it is idle or on the edge that returns its previous
  // response. No lane accepts while a service owns the slot.
  assign lanes_idle = i_state_q == LANE_IDLE && d_state_q == LANE_IDLE;
  assign lane_accept_ok = rst_ni && running_q && owner_q == OWN_NONE &&
                          !ifetch_fatal_q;
  assign i_finish = i_state_q == LANE_RESPONSE && pimem_rsp_valid_i &&
                    !pimem_rsp_error_i && imem_rsp_ready;
  assign d_finish = d_state_q == LANE_RESPONSE && pdmem_rsp_valid_i &&
                    dmem_rsp_ready;
  assign imem_req_ready = lane_accept_ok &&
    (i_state_q == LANE_IDLE || i_finish);
  assign dmem_req_ready = lane_accept_ok &&
    (d_state_q == LANE_IDLE || d_finish);
  assign i_accept = imem_req_valid && imem_req_ready;
  assign d_accept = dmem_req_valid && dmem_req_ready;
  assign i_hit = ENABLE_MICRO_TLB && i_hit_raw;
  assign d_hit = ENABLE_MICRO_TLB && d_hit_raw;

  // The translation sequence takes a waiting lane or a missing request on
  // its accepting edge, alternating when both compete.
  always_comb begin
    logic want_instruction, want_data;
    want_instruction = i_state_q == LANE_WAIT || (i_accept && !i_hit);
    want_data = d_state_q == LANE_WAIT || (d_accept && !d_hit);
    choose_instruction = 1'b0;
    choose_data = 1'b0;
    if (rst_ni && state_q == ROUTE_IDLE) begin
      if (want_instruction && want_data) begin
        choose_instruction = last_grant_data_q;
        choose_data = !last_grant_data_q;
      end else begin
        choose_instruction = want_instruction;
        choose_data = want_data;
      end
    end
    i_accept_state = i_hit ? LANE_OFFER :
      (choose_instruction ? LANE_SLOW : LANE_WAIT);
    d_accept_state = d_hit ? LANE_OFFER :
      (choose_data ? LANE_SLOW : LANE_WAIT);
  end

  assign route_allow =
    (state_q == ROUTE_TRANSLATE_RESPONSE && bat_rsp_valid && bat_rsp_allow) ||
    (state_q == ROUTE_PAGE_RESPONSE && tlb_rsp_valid && page_reply_allow);
  assign route_from_tlb = state_q == ROUTE_PAGE_RESPONSE;
  assign route_pa = route_from_tlb ? tlb_rsp_pa : bat_rsp_pa;
  assign route_wimg = route_from_tlb ? tlb_rsp_wimg : bat_rsp_wimg;
  // A TLB hit points its set's LRU bit away from the hit way.
  assign route_set_touch = state_q == ROUTE_PAGE_RESPONSE && tlb_rsp_valid &&
                           tlb_rsp_hit;
  // Flush on every commit that can change a translation: BAT, SR and TLB
  // updates, management, and every MSR/SDR1 context installation.
  assign utlb_flush = !running_q || (context_valid_i && context_ready_o) ||
    (ENABLE_RUNTIME_BAT && bat_csr_commit_i) ||
    (ENABLE_SEGMENT_REGISTERS && segment_owner && segment_csr_commit_i) ||
    (ENABLE_TLB_INVALIDATE && tlb_inv_owner && tlb_inv_commit_i) ||
    (ENABLE_TLB_LOAD && tlb_fill_owner && tlb_fill_commit_i) ||
    tlb_mgmt_owner;

  ppc_micro_tlb #(.ENTRIES(MICRO_TLB_ENTRIES)) i_utlb (
    .clk_i, .rst_ni,
    .flush_i(utlb_flush),
    .set_flush_i(route_set_touch && owner_instruction_q),
    .set_flush_index_i(request_ea_q[16:12]),
    .lookup_page_i(imem_req_addr[31:12]), .lookup_write_i(1'b0),
    .hit_o(i_hit_raw), .hit_rpn_o(i_hit_rpn), .hit_wimg_o(i_hit_wimg),
    .fill_i(ENABLE_MICRO_TLB && route_allow && owner_instruction_q),
    .fill_page_i(request_ea_q[31:12]), .fill_rpn_i(route_pa[31:12]),
    .fill_wimg_i(route_wimg), .fill_write_ok_i(1'b0),
    .fill_from_tlb_i(route_from_tlb)
  );

  ppc_micro_tlb #(.ENTRIES(MICRO_TLB_ENTRIES)) d_utlb (
    .clk_i, .rst_ni,
    .flush_i(utlb_flush),
    .set_flush_i(route_set_touch && !owner_instruction_q),
    .set_flush_index_i(request_ea_q[16:12]),
    .lookup_page_i(dmem_req_addr[31:12]), .lookup_write_i(dmem_req_write),
    .hit_o(d_hit_raw), .hit_rpn_o(d_hit_rpn), .hit_wimg_o(d_hit_wimg),
    .fill_i(ENABLE_MICRO_TLB && route_allow && !owner_instruction_q),
    .fill_page_i(request_ea_q[31:12]), .fill_rpn_i(route_pa[31:12]),
    .fill_wimg_i(route_wimg), .fill_write_ok_i(owner_write_q),
    .fill_from_tlb_i(route_from_tlb)
  );

  // Setup writes and running translations serialize through the committed
  // BAT service.  A setup response must be consumed before start is accepted.
  always_comb begin
    bat_req_valid = 1'b0;
    bat_req_kind = BAT_SPR_WRITE;
    bat_req_ea = 32'b0;
    bat_req_spr = bat_write_spr_i;
    bat_req_data = bat_write_data_i;
    if (bat_setup_q) begin
      bat_req_valid = bat_write_valid_i && !tlb_mgmt_owner;
    end else if (state_q == ROUTE_TRANSLATE_OFFER) begin
      bat_req_valid = 1'b1;
      bat_req_kind = owner_instruction_q ? BAT_TRANSLATE_I :
                     (owner_write_q ? BAT_TRANSLATE_WRITE : BAT_TRANSLATE_READ);
      bat_req_ea = request_ea_q;
      bat_req_spr = 10'b0;
      bat_req_data = 32'b0;
    end else if (csr_offer) begin
      bat_req_valid = bat_csr_req_valid_i;
      bat_req_kind = bat_csr_req_write_i ? BAT_PREPARE_WRITE : BAT_SPR_READ;
      bat_req_spr = bat_csr_req_spr_i;
      bat_req_data = bat_csr_req_data_i;
    end

    bat_write_ready_o = rst_ni && bat_setup_q && !tlb_mgmt_owner &&
                        bat_req_ready;
    bat_write_rsp_valid_o = rst_ni && bat_setup_q && bat_rsp_valid;
    bat_rsp_ready = bat_setup_q ? bat_write_rsp_ready_i :
                    (csr_owner ? bat_csr_rsp_ready_i :
                     (state_q == ROUTE_TRANSLATE_RESPONSE));
    start_ready_o = rst_ni && bat_setup_q && !bat_write_valid_i &&
                    !bat_rsp_valid && bat_req_ready && !tlb_mgmt_owner &&
                    !(ENABLE_PAGE_TRANSLATION && tlb_mgmt_req_valid_i);
  end

  ppc_segment_registers #(
    .ENABLE_RUNTIME_SEGMENT(ENABLE_SEGMENT_REGISTERS)
  ) segment_bank (
    .clk_i, .rst_ni,
    .prepare_commit_i(ENABLE_SEGMENT_REGISTERS && running_q &&
                      segment_owner && segment_csr_commit_i),
    .prepare_abort_i(ENABLE_SEGMENT_REGISTERS && running_q &&
                     segment_owner && segment_csr_abort_i),
    .commit_ack_valid_o(segment_service_ack),
    .commit_ack_ready_i(ENABLE_SEGMENT_REGISTERS && segment_owner &&
                        segment_csr_ack_ready_i),
    .transaction_idle_o(segment_service_idle),
    .req_valid_i(segment_req_valid), .req_ready_o(segment_req_ready),
    .req_kind_i(state_q == ROUTE_SEGMENT_OFFER ? SEG_SNAPSHOT :
                (segment_csr_req_write_i ? SEG_PREPARE : SEG_READ)),
    .req_indexed_i(1'b0),
    .req_index_i(state_q == ROUTE_SEGMENT_OFFER ? request_ea_q[31:28] :
                 segment_csr_req_index_i),
    .req_address_i(state_q == ROUTE_SEGMENT_OFFER ? request_ea_q : 32'b0),
    .req_data_i(segment_csr_req_data_i),
    .req_pr_i(state_q == ROUTE_SEGMENT_OFFER ? request_pr_q : context_pr_q),
    .rsp_valid_o(segment_rsp_valid), .rsp_ready_i(segment_rsp_ready),
    .rsp_kind_o(segment_rsp_kind), .rsp_index_o(segment_rsp_index),
    .rsp_address_o(segment_rsp_address), .rsp_data_o(segment_rsp_data),
    .rsp_privileged_o(segment_rsp_privileged),
    .rsp_unsupported_o(segment_rsp_unsupported)
  );

  // One shared instruction/data TLB service. Management refills and indexed
  // invalidations commit at acceptance; CPU page lookups only observe it.
  ppc_tlb_service #(
    .ENABLE_RUNTIME_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_RUNTIME_REFILL(ENABLE_TLB_LOAD)
  ) tlb (
    .clk_i, .rst_ni,
    .prepare_commit_i(running_q &&
      ((ENABLE_TLB_INVALIDATE && tlb_inv_owner && tlb_inv_commit_i) ||
       (ENABLE_TLB_LOAD && tlb_fill_owner && tlb_fill_commit_i))),
    .prepare_abort_i(running_q &&
      ((ENABLE_TLB_INVALIDATE && tlb_inv_abort_i &&
        (tlb_inv_owner ||
         (tlb_inv_req_valid_i && tlb_inv_req_ready_o))) ||
       (ENABLE_TLB_LOAD && tlb_fill_abort_i &&
        (tlb_fill_owner ||
         (tlb_fill_req_valid_i && tlb_fill_req_ready_o))))),
    .commit_ack_valid_o(tlb_commit_ack),
    .commit_ack_ready_i(
      (ENABLE_TLB_INVALIDATE && tlb_inv_owner && tlb_inv_ack_ready_i) ||
      (ENABLE_TLB_LOAD && tlb_fill_owner && tlb_fill_ack_ready_i)),
    .transaction_idle_o(tlb_transaction_idle),
    .req_valid_i(tlb_req_valid), .req_ready_o(tlb_req_ready),
    .req_kind_i(tlb_req_kind), .req_bank_i(tlb_req_bank),
    .req_ea_i(tlb_req_ea), .req_vsid_i(tlb_req_vsid),
    .req_pr_i(tlb_req_pr), .req_ks_i(tlb_req_ks),
    .req_kp_i(tlb_req_kp), .req_n_i(tlb_req_n),
    .req_t_i(tlb_req_t), .req_write_i(tlb_req_write),
    .req_way_i(tlb_req_way), .req_rpn_i(tlb_req_rpn),
    .req_c_i(tlb_req_c), .req_wimg_i(tlb_req_wimg),
    .req_pp_i(tlb_req_pp),
    .rsp_valid_o(tlb_rsp_valid), .rsp_ready_i(tlb_rsp_ready),
    .rsp_kind_o(tlb_rsp_kind), .rsp_bank_o(tlb_rsp_bank),
    .rsp_ea_o(tlb_rsp_ea), .rsp_allow_o(tlb_rsp_allow),
    .rsp_hit_o(tlb_rsp_hit), .rsp_miss_o(tlb_rsp_miss),
    .rsp_protection_fault_o(tlb_rsp_protection),
    .rsp_guarded_fault_o(tlb_rsp_guarded),
    .rsp_no_execute_o(tlb_rsp_no_execute),
    .rsp_direct_store_unsupported_o(tlb_rsp_direct_store),
    .rsp_needs_changed_o(tlb_rsp_needs_changed),
    .rsp_privileged_o(tlb_rsp_privileged),
    .rsp_refill_rejected_o(tlb_rsp_refill_rejected),
    .rsp_unsupported_o(tlb_rsp_unsupported),
    .rsp_invalid_input_o(tlb_rsp_invalid_input),
    .rsp_match_o(tlb_rsp_match), .rsp_way_o(tlb_rsp_way),
    .rsp_pa_o(tlb_rsp_pa), .rsp_wimg_o(tlb_rsp_wimg),
    .rsp_pp_o(tlb_rsp_pp), .rsp_c_o(tlb_rsp_c), .rsp_r_o(tlb_rsp_r)
  );

  ppc_bat_service #(.ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT)) bat (
    .clk_i, .rst_ni,
    .prepare_commit_i(ENABLE_RUNTIME_BAT && running_q && bat_csr_commit_i),
    .prepare_abort_i(ENABLE_RUNTIME_BAT && running_q && bat_csr_abort_i),
    .commit_ack_valid_o(service_ack),
    .commit_ack_ready_i(ENABLE_RUNTIME_BAT && csr_owner && bat_csr_ack_ready_i),
    .transaction_idle_o(service_idle),
    .req_valid_i(bat_req_valid), .req_ready_o(bat_req_ready),
    .req_kind_i(bat_req_kind), .req_ea_i(bat_req_ea),
    .req_spr_i(bat_req_spr), .req_data_i(bat_req_data),
    .req_ir_i(request_ir_q), .req_dr_i(request_dr_q),
    .req_pr_i(service_pr),
    .rsp_valid_o(bat_rsp_valid), .rsp_ready_i(bat_rsp_ready),
    .rsp_kind_o(bat_rsp_kind), .rsp_ea_o(bat_rsp_ea),
    .rsp_spr_o(bat_rsp_spr), .rsp_data_o(bat_rsp_data),
    .rsp_privileged_o(bat_rsp_privileged),
    .rsp_unsupported_o(bat_rsp_unsupported),
    .rsp_write_rejected_o(bat_rsp_write_rejected),
    .rsp_allow_o(bat_rsp_allow), .rsp_bypass_o(bat_rsp_bypass),
    .rsp_hit_o(bat_rsp_hit), .rsp_miss_o(bat_rsp_miss),
    .rsp_protection_fault_o(bat_rsp_protection),
    .rsp_guarded_fault_o(bat_rsp_guarded),
    .rsp_config_error_o(bat_rsp_config),
    .rsp_invalid_input_o(bat_rsp_invalid_input),
    .rsp_overlap_o(bat_rsp_overlap),
    .rsp_invalid_entry_o(bat_rsp_invalid_entry),
    .rsp_match_o(bat_rsp_match), .rsp_hit_index_o(bat_rsp_hit_index),
    .rsp_pa_o(bat_rsp_pa), .rsp_wimg_o(bat_rsp_wimg),
    .rsp_pp_o(bat_rsp_pp)
  );

  assign bat_write_rsp_rejected_o = bat_rsp_write_rejected;
  assign bat_write_rsp_unsupported_o = bat_rsp_unsupported;
  assign bat_write_rsp_config_error_o = bat_rsp_config;
  assign bat_write_rsp_overlap_o = bat_rsp_overlap;
  assign bat_write_rsp_invalid_entry_o = bat_rsp_invalid_entry;

  always_comb begin
    pimem_req_valid_o = rst_ni && i_state_q == LANE_OFFER;
    pimem_req_addr_o = i_pa_q;
    pimem_req_wimg_o = i_wimg_q;
    pdmem_req_valid_o = rst_ni && d_state_q == LANE_OFFER;
    pdmem_req_write_o = d_write_q;
    pdmem_req_addr_o = d_pa_q;
    pdmem_req_wdata_o = d_wdata_q;
    pdmem_req_wstrb_o = d_wstrb_q;
    pdmem_req_wimg_o = d_wimg_q;

    imem_rsp_valid = 1'b0;
    imem_rsp_insn = pimem_rsp_insn_i;
    imem_rsp_fault_o = FETCH_OK;
    pimem_rsp_ready_o = 1'b0;
    if (rst_ni && i_state_q == LANE_RESPONSE) begin
      // A physical instruction error is consumed here and never returned.
      if (pimem_rsp_valid_i && pimem_rsp_error_i)
        pimem_rsp_ready_o = 1'b1;
      else begin
        imem_rsp_valid = pimem_rsp_valid_i;
        pimem_rsp_ready_o = imem_rsp_ready;
      end
    end else if (rst_ni && state_q == ROUTE_IFETCH_FAULT_RESPONSE) begin
      imem_rsp_valid = 1'b1;
      imem_rsp_insn = 32'b0;
      imem_rsp_fault_o = fetch_fault_q;
    end

    dmem_rsp_valid = 1'b0;
    dmem_rsp_rdata = pdmem_rsp_rdata_i;
    dmem_rsp_error = 1'b0;
    dmem_rsp_fault_o = DATA_OK;
    pdmem_rsp_ready_o = 1'b0;
    if (rst_ni && d_state_q == LANE_RESPONSE) begin
      dmem_rsp_valid = pdmem_rsp_valid_i;
      dmem_rsp_error = pdmem_rsp_error_i;
      pdmem_rsp_ready_o = dmem_rsp_ready;
    end else if (rst_ni && state_q == ROUTE_DATA_FAULT_RESPONSE) begin
      dmem_rsp_valid = 1'b1;
      dmem_rsp_rdata = 32'b0;
      dmem_rsp_error = data_fault_q == DATA_OK;
      dmem_rsp_fault_o = data_fault_q;
    end
  end

  // Quartus 17 rejects typed assignment patterns, so the capsule is built by field.
  page_miss_t page_miss_capture;
  always_comb begin
    page_miss_capture.ea = request_ea_q;
    page_miss_capture.sr = page_sr_q;
    page_miss_capture.pr = request_pr_q;
    page_miss_capture.ir = request_ir_q;
    page_miss_capture.dr = request_dr_q;
    page_miss_capture.write = owner_write_q;
    // A true miss carries the LRU replacement way; a C=0 store its matched way.
    page_miss_capture.way = tlb_rsp_way;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= ROUTE_IDLE;
      i_state_q <= LANE_IDLE;
      d_state_q <= LANE_IDLE;
      i_ea_q <= 32'b0;
      d_ea_q <= 32'b0;
      i_pa_q <= 32'b0;
      d_pa_q <= 32'b0;
      i_wimg_q <= 4'b0;
      d_wimg_q <= 4'b0;
      d_write_q <= 1'b0;
      d_wdata_q <= 32'b0;
      d_wstrb_q <= 4'b0;
      owner_q <= OWN_NONE;
      tlb_fill_ea_q <= 32'b0;
      tlb_fill_bank_q <= 1'b0;
      running_q <= 1'b0;
      running_out_q <= 1'b0;
      bat_setup_q <= 1'b1;
      context_ir_q <= 1'b0;
      context_dr_q <= 1'b0;
      context_pr_q <= 1'b0;
      request_ir_q <= 1'b0;
      request_dr_q <= 1'b0;
      request_pr_q <= 1'b0;
      fetch_fault_q <= FETCH_OK;
      data_fault_q <= DATA_OK;
      last_grant_data_q <= 1'b1;
      owner_instruction_q <= 1'b0;
      owner_write_q <= 1'b0;
      request_ea_q <= 32'b0;
      page_sr_q <= 32'b0;
      page_miss_result_q <= '0;
      fault_q <= 1'b0;
      fault_instruction_q <= 1'b0;
      fault_write_q <= 1'b0;
      fault_ea_q <= 32'b0;
      fault_miss_q <= 1'b0;
      fault_protection_q <= 1'b0;
      fault_guarded_q <= 1'b0;
      fault_config_q <= 1'b0;
      fault_invalid_input_q <= 1'b0;
      fault_invalid_entry_q <= 4'b0;
      page_fault_q <= 1'b0;
      page_miss_q <= 1'b0;
      page_protection_q <= 1'b0;
      page_no_execute_q <= 1'b0;
      page_guarded_q <= 1'b0;
      page_direct_store_q <= 1'b0;
      page_needs_changed_q <= 1'b0;
      page_config_q <= 1'b0;
      pimem_error_q <= 1'b0;
      ifetch_fatal_q <= 1'b0;
    end else begin
      unique case (owner_q)
        OWN_NONE: begin
          if (slot_grant[SLOT_BAT_CSR]) owner_q <= OWN_BAT_CSR;
          else if (slot_grant[SLOT_SEGMENT]) owner_q <= OWN_SEGMENT;
          else if (slot_grant[SLOT_TLB_INV]) owner_q <= OWN_TLB_INV;
          else if (slot_grant[SLOT_TLB_FILL]) owner_q <= OWN_TLB_FILL;
          else if (slot_grant[SLOT_TLB_MGMT]) owner_q <= OWN_TLB_MGMT;
        end
        OWN_BAT_CSR: if (service_idle) owner_q <= OWN_NONE;
        OWN_SEGMENT: if (segment_service_idle) owner_q <= OWN_NONE;
        default: if (tlb_transaction_idle) owner_q <= OWN_NONE;
      endcase
      if (slot_grant[SLOT_TLB_FILL]) begin
        tlb_fill_ea_q <= tlb_fill_req_ea_i;
        tlb_fill_bank_q <= tlb_fill_req_bank_i;
      end
      if (start_valid_i && start_ready_o) begin
        running_q <= 1'b1;
        running_out_q <= 1'b1;
        bat_setup_q <= 1'b0;
        context_ir_q <= start_ir_i;
        context_dr_q <= start_dr_i;
        context_pr_q <= start_pr_i;
      end
      if (context_valid_i && context_ready_o) begin
        context_ir_q <= context_ir_i;
        context_dr_q <= context_dr_i;
        context_pr_q <= context_pr_i;
      end

      if (i_accept) begin
        i_ea_q <= imem_req_addr;
        i_pa_q <= {i_hit_rpn, imem_req_addr[11:0]};
        i_wimg_q <= i_hit_wimg;
      end
      if (d_accept) begin
        d_ea_q <= dmem_req_addr;
        d_pa_q <= {d_hit_rpn, dmem_req_addr[11:0]};
        d_wimg_q <= d_hit_wimg;
        d_write_q <= dmem_req_write;
        d_wdata_q <= dmem_req_wdata;
        d_wstrb_q <= dmem_req_wstrb;
      end
      if (route_allow && owner_instruction_q) begin
        i_pa_q <= route_pa;
        i_wimg_q <= route_wimg;
      end
      if (route_allow && !owner_instruction_q) begin
        d_pa_q <= route_pa;
        d_wimg_q <= route_wimg;
      end

      unique case (i_state_q)
        LANE_IDLE: if (i_accept) i_state_q <= i_accept_state;
        LANE_WAIT: if (choose_instruction) i_state_q <= LANE_SLOW;
        LANE_SLOW: begin
          if (route_allow && owner_instruction_q) i_state_q <= LANE_OFFER;
          else if (state_q == ROUTE_IFETCH_FAULT_RESPONSE && imem_rsp_ready)
            i_state_q <= LANE_IDLE;
        end
        LANE_OFFER: if (pimem_req_ready_i) i_state_q <= LANE_RESPONSE;
        LANE_RESPONSE: begin
          if (pimem_rsp_valid_i && pimem_rsp_error_i) begin
            pimem_error_q <= 1'b1;
            ifetch_fatal_q <= 1'b1;
            i_state_q <= LANE_FATAL;
          end else if (i_accept) i_state_q <= i_accept_state;
          else if (i_finish) i_state_q <= LANE_IDLE;
        end
        LANE_FATAL: i_state_q <= LANE_FATAL;
        default: begin
          ifetch_fatal_q <= 1'b1;
          i_state_q <= LANE_FATAL;
        end
      endcase

      unique case (d_state_q)
        LANE_IDLE: if (d_accept) d_state_q <= d_accept_state;
        LANE_WAIT: if (choose_data) d_state_q <= LANE_SLOW;
        LANE_SLOW: begin
          if (route_allow && !owner_instruction_q) d_state_q <= LANE_OFFER;
          else if (state_q == ROUTE_DATA_FAULT_RESPONSE && dmem_rsp_ready)
            d_state_q <= LANE_IDLE;
        end
        LANE_OFFER: if (pdmem_req_ready_i) d_state_q <= LANE_RESPONSE;
        LANE_RESPONSE: begin
          if (d_accept) d_state_q <= d_accept_state;
          else if (d_finish) d_state_q <= LANE_IDLE;
        end
        default: begin
          ifetch_fatal_q <= 1'b1;
          d_state_q <= LANE_FATAL;
        end
      endcase

      unique case (state_q)
        ROUTE_IDLE: begin
          if (choose_instruction || choose_data) begin
            request_ir_q <= context_ir_q;
            request_dr_q <= context_dr_q;
            request_pr_q <= context_pr_q;
            owner_instruction_q <= choose_instruction;
            if (choose_instruction)
              request_ea_q <= i_state_q == LANE_WAIT ? i_ea_q : imem_req_addr;
            else
              request_ea_q <= d_state_q == LANE_WAIT ? d_ea_q : dmem_req_addr;
            owner_write_q <= choose_data &&
              (d_state_q == LANE_WAIT ? d_write_q : dmem_req_write);
            page_miss_result_q <= '0;
            last_grant_data_q <= choose_data;
            state_q <= ROUTE_TRANSLATE_OFFER;
          end
        end

        ROUTE_TRANSLATE_OFFER: begin
          if (bat_req_valid && bat_req_ready)
            state_q <= ROUTE_TRANSLATE_RESPONSE;
        end

        ROUTE_TRANSLATE_RESPONSE: begin
          if (bat_rsp_valid) begin
            if (bat_rsp_allow) begin
              state_q <= ROUTE_IDLE;
            end else if (clean_bat_page_miss) begin
              state_q <= ROUTE_SEGMENT_OFFER;
            end else begin
              if (!bat_typed_fault) begin
                fault_q <= 1'b1;
                fault_instruction_q <= owner_instruction_q;
                fault_write_q <= owner_write_q;
                fault_ea_q <= request_ea_q;
                fault_miss_q <= bat_rsp_miss;
                fault_protection_q <= bat_rsp_protection;
                fault_guarded_q <= bat_rsp_guarded;
                fault_config_q <= bat_rsp_config;
                fault_invalid_input_q <= bat_rsp_invalid_input;
                fault_invalid_entry_q <= bat_rsp_invalid_entry;
              end
              if (owner_instruction_q) begin
                if (bat_fetch_isi) begin
                  fetch_fault_q <= bat_rsp_protection ?
                    FETCH_ISI_PROTECTION : FETCH_ISI_GUARDED;
                  state_q <= ROUTE_IFETCH_FAULT_RESPONSE;
                end else begin
                  ifetch_fatal_q <= 1'b1;
                  state_q <= ROUTE_IFETCH_FATAL;
                end
              end else begin
                data_fault_q <= bat_data_dsi ? DATA_DSI_PROTECTION : DATA_OK;
                state_q <= ROUTE_DATA_FAULT_RESPONSE;
              end
            end
          end
        end

        ROUTE_SEGMENT_OFFER: begin
          if (segment_req_valid && segment_req_ready)
            state_q <= ROUTE_SEGMENT_RESPONSE;
        end

        ROUTE_SEGMENT_RESPONSE: begin
          if (segment_rsp_valid) begin
            if (segment_rsp_kind == SEG_SNAPSHOT &&
                segment_rsp_index == request_ea_q[31:28] &&
                segment_rsp_address == request_ea_q &&
                !segment_rsp_privileged && !segment_rsp_unsupported) begin
              page_sr_q <= segment_rsp_data;
              state_q <= ROUTE_PAGE_OFFER;
            end else begin
              // A malformed internal snapshot is an ordered diagnostic.
              fault_q <= 1'b1;
              fault_instruction_q <= owner_instruction_q;
              fault_write_q <= owner_write_q;
              fault_ea_q <= request_ea_q;
              fault_miss_q <= 1'b0;
              fault_protection_q <= 1'b0;
              fault_guarded_q <= 1'b0;
              fault_config_q <= 1'b1;
              fault_invalid_input_q <= 1'b0;
              fault_invalid_entry_q <= '0;
              page_fault_q <= 1'b1;
              page_config_q <= 1'b1;
              if (owner_instruction_q) begin
                ifetch_fatal_q <= 1'b1;
                state_q <= ROUTE_IFETCH_FATAL;
              end else begin
                data_fault_q <= DATA_OK;
                state_q <= ROUTE_DATA_FAULT_RESPONSE;
              end
            end
          end
        end

        ROUTE_PAGE_OFFER: begin
          if (tlb_req_valid && tlb_req_ready)
            state_q <= ROUTE_PAGE_RESPONSE;
        end

        ROUTE_PAGE_RESPONSE: begin
          if (tlb_rsp_valid) begin
            if (page_reply_allow) begin
              state_q <= ROUTE_IDLE;
            end else begin
              // Page misses and C=0 stores carry their request-time context
              // through the held response.
              page_miss_result_q <= (clean_page_true_miss ||
                                     clean_page_changed) ?
                page_miss_capture : '0;
              if (!page_typed_fault) begin
                fault_q <= 1'b1;
                fault_instruction_q <= owner_instruction_q;
                fault_write_q <= owner_write_q;
                fault_ea_q <= request_ea_q;
                fault_miss_q <= tlb_rsp_miss;
                fault_protection_q <= tlb_rsp_protection;
                fault_guarded_q <= tlb_rsp_guarded;
                fault_config_q <= page_reply_config;
                fault_invalid_input_q <= tlb_rsp_invalid_input;
                fault_invalid_entry_q <= '0;
                page_fault_q <= 1'b1;
                page_miss_q <= page_miss_q || tlb_rsp_miss;
                page_protection_q <= page_protection_q || tlb_rsp_protection;
                page_no_execute_q <= page_no_execute_q || tlb_rsp_no_execute;
                page_guarded_q <= page_guarded_q || tlb_rsp_guarded;
                page_direct_store_q <= page_direct_store_q ||
                                       tlb_rsp_direct_store;
                page_needs_changed_q <= page_needs_changed_q ||
                                        tlb_rsp_needs_changed;
                page_config_q <= page_config_q || page_reply_config;
              end
              if (owner_instruction_q) begin
                if (page_typed_fault) begin
                  fetch_fault_q <= clean_page_true_miss ? FETCH_PAGE_MISS :
                    (clean_page_instruction_pp ? FETCH_ISI_PROTECTION :
                                                 FETCH_ISI_GUARDED);
                  state_q <= ROUTE_IFETCH_FAULT_RESPONSE;
                end else begin
                  ifetch_fatal_q <= 1'b1;
                  state_q <= ROUTE_IFETCH_FATAL;
                end
              end else begin
                data_fault_q <= clean_page_data_pp ? DATA_DSI_PROTECTION :
                  (clean_page_true_miss ? DATA_PAGE_MISS :
                    (clean_page_changed ? DATA_PAGE_CHANGED : DATA_OK));
                state_q <= ROUTE_DATA_FAULT_RESPONSE;
              end
            end
          end
        end

        ROUTE_DATA_FAULT_RESPONSE: begin
          if (dmem_rsp_ready)
            state_q <= ROUTE_IDLE;
        end

        ROUTE_IFETCH_FAULT_RESPONSE: begin
          if (imem_rsp_ready) state_q <= ROUTE_IDLE;
        end

        ROUTE_IFETCH_FATAL: state_q <= ROUTE_IFETCH_FATAL;

        default: begin
          fault_q <= 1'b1;
          fault_instruction_q <= 1'b1;
          fault_config_q <= 1'b1;
          ifetch_fatal_q <= 1'b1;
          state_q <= ROUTE_INVALID;
        end
      endcase
    end
  end

  assign running_o = rst_ni && running_out_q;
  assign context_ir_o = context_ir_q;
  assign context_dr_o = context_dr_q;
  assign context_pr_o = context_pr_q;
  assign translation_fault_o = rst_ni && fault_q;
  assign fault_instruction_o = fault_instruction_q;
  assign fault_write_o = fault_write_q;
  assign fault_ea_o = fault_ea_q;
  assign fault_miss_o = fault_miss_q;
  assign fault_protection_o = fault_protection_q;
  assign fault_guarded_o = fault_guarded_q;
  assign fault_config_o = fault_config_q;
  assign fault_invalid_input_o = fault_invalid_input_q;
  assign fault_invalid_entry_o = fault_invalid_entry_q;
  assign page_fault_o = rst_ni && page_fault_q;
  assign page_miss_o = rst_ni && page_miss_q;
  assign page_protection_o = rst_ni && page_protection_q;
  assign page_no_execute_o = rst_ni && page_no_execute_q;
  assign page_guarded_o = rst_ni && page_guarded_q;
  assign page_direct_store_o = rst_ni && page_direct_store_q;
  assign page_needs_changed_o = rst_ni && page_needs_changed_q;
  assign page_config_o = rst_ni && page_config_q;
  assign pimem_error_o = rst_ni && pimem_error_q;
  assign ifetch_fatal_o = rst_ni && ifetch_fatal_q;
  assign busy_o = rst_ni && (owner_q != OWN_NONE || bat_rsp_valid ||
                              segment_rsp_valid || tlb_rsp_valid ||
                              state_q != ROUTE_IDLE || !lanes_idle ||
                              (running_q && (imem_req_valid ||
                                             dmem_req_valid)));

  // synthesis translate_off
  initial assert (!ENABLE_PAGE_INSTRUCTION_EXCEPTIONS ||
    ENABLE_PAGE_TRANSLATION)
    else $error("page instruction exceptions require page translation");
  initial assert (!ENABLE_PAGE_DATA_EXCEPTIONS ||
    (ENABLE_PAGE_TRANSLATION && ENABLE_DATA_EXCEPTIONS))
    else $error("page data exceptions require page translation and data exceptions");
  initial assert (!ENABLE_TLB_LOAD || ENABLE_PAGE_TRANSLATION)
    else $error("CPU TLB load requires page translation");
  initial assert (!ENABLE_PAGE_MISS_RESULTS || ENABLE_PAGE_TRANSLATION)
    else $error("page miss results require page translation");
  initial assert (!ENABLE_TLB_INVALIDATE || ENABLE_PAGE_TRANSLATION)
    else $error("CPU TLB invalidation requires page translation");
  initial assert (!ENABLE_PAGE_TRANSLATION ||
    (ENABLE_SEGMENT_REGISTERS && ENABLE_LIVE_CONTEXT))
    else $error("page translation requires segment registers and live context");
  initial assert (!ENABLE_SEGMENT_REGISTERS || ENABLE_LIVE_CONTEXT)
    else $error("runtime segment registers require live context");
  initial assert (!ENABLE_RUNTIME_BAT || ENABLE_LIVE_CONTEXT)
    else $error("runtime BAT requires live context");
  always @(posedge clk_i) if (rst_ni && ENABLE_RUNTIME_BAT) begin
    if (bat_csr_commit_i) assert (csr_owner && state_q == ROUTE_IDLE)
      else $error("runtime BAT commit without exclusive owner");
    if (csr_owner) assert (state_q == ROUTE_IDLE && !context_ready_o)
      else $error("runtime BAT ownership overlaps memory/context installation");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_SEGMENT_REGISTERS) begin
    if (segment_csr_commit_i) assert (segment_owner &&
      state_q == ROUTE_IDLE && !csr_owner)
      else $error("segment commit without exclusive owner");
    if (segment_owner) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner)
      else $error("segment ownership overlaps memory/context installation");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_TLB_INVALIDATE) begin
    if (tlb_inv_commit_i) assert (tlb_inv_owner &&
      state_q == ROUTE_IDLE && !tlb_mgmt_owner)
      else $error("TLB invalidate commit without exclusive owner");
    if (tlb_inv_owner) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner && !segment_owner &&
      !tlb_mgmt_owner)
      else $error("TLB invalidate owner overlaps memory/context");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_TLB_LOAD) begin
    if (tlb_fill_commit_i) assert (tlb_fill_owner &&
      state_q == ROUTE_IDLE && !tlb_mgmt_owner && !tlb_inv_owner)
      else $error("TLB fill commit without exclusive owner");
    if (tlb_fill_owner) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner && !segment_owner &&
      !tlb_mgmt_owner && !tlb_inv_owner)
      else $error("TLB fill owner overlaps memory/context");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_PAGE_TRANSLATION) begin
    if (tlb_mgmt_owner) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner && !segment_owner)
      else $error("TLB management overlaps memory, CSR or context");
    if (state_q == ROUTE_PAGE_RESPONSE && tlb_rsp_valid &&
        !page_reply_allow)
      assert (owner_instruction_q ? !pimem_req_valid_o : !pdmem_req_valid_o)
      else $error("denied page response offered physical memory");
  end
  assert property (@(posedge clk_i) disable iff (!rst_ni) $onehot0(slot_grant))
    else $error("service slot granted to more than one owner");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    context_valid_i && context_ready_o |->
      !imem_req_valid_i && !dmem_req_valid_i && state_q == ROUTE_IDLE);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    imem_rsp_valid_o && !imem_rsp_ready_i |=>
      imem_rsp_valid_o && $stable({imem_rsp_insn_o, imem_rsp_fault_o,
                                   imem_rsp_page_miss_o}));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    dmem_rsp_valid_o && !dmem_rsp_ready_i |=>
      dmem_rsp_valid_o &&
      $stable({dmem_rsp_rdata_o, dmem_rsp_error_o, dmem_rsp_fault_o,
               dmem_rsp_page_miss_o}));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    state_q == ROUTE_DATA_FAULT_RESPONSE |-> !pdmem_req_valid_o);
  // The translation sequence owns exactly the lane it serves.
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    state_q != ROUTE_IDLE |->
      (owner_instruction_q ? i_state_q == LANE_SLOW : d_state_q == LANE_SLOW));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    state_q == ROUTE_IDLE |-> i_state_q != LANE_SLOW && d_state_q != LANE_SLOW);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    owner_q != OWN_NONE |-> lanes_idle && !imem_req_ready_o && !dmem_req_ready_o);
  // synthesis translate_on

  // Service echo and attribute fields left unused here.
  logic _unused_response;
  assign _unused_response = ^{bat_rsp_kind, bat_rsp_ea, bat_rsp_spr,
    bat_rsp_match, bat_rsp_hit_index, bat_rsp_pp, tlb_rsp_pp};
endmodule
`default_nettype wire
