// Startup-programmed BAT translation between abstract effective and physical
// instruction/data channels. Optional runtime context comes from committed MSR;
// Optional runtime CSR transactions reserve validated writes until retirement.
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
  parameter bit ENABLE_PAGE_MISS_RESULTS = 1'b0
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
  output logic [2:0] imem_rsp_fault_o,
  output logic [68:0] imem_rsp_page_miss_o,
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
  output logic [2:0]  dmem_rsp_fault_o,
  output logic [68:0] dmem_rsp_page_miss_o,

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
  // Wire encoding matches the abstract core's fetch_fault_t contract.
  localparam logic [2:0] FETCH_OK = 3'd0;
  localparam logic [2:0] FETCH_ISI_PROTECTION = 3'd1;
  localparam logic [2:0] FETCH_ISI_GUARDED = 3'd2;
  localparam logic [2:0] FETCH_PAGE_MISS = 3'd3;
  // Wire encoding matches the abstract core's data_fault_t contract.
  localparam logic [2:0] DATA_OK = 3'd0;
  localparam logic [2:0] DATA_DSI_PROTECTION = 3'd1;
  localparam logic [2:0] DATA_PAGE_MISS = 3'd2;
  localparam logic [2:0] DATA_PAGE_CHANGED = 3'd3;
  localparam logic [2:0] TRANSLATE_I = 3'd0;
  localparam logic [2:0] TRANSLATE_READ = 3'd1;
  localparam logic [2:0] TRANSLATE_WRITE = 3'd2;
  localparam logic [2:0] SPR_WRITE = 3'd4;
  localparam logic [2:0] SPR_READ = 3'd3;
  localparam logic [2:0] PREPARE_WRITE = 3'd5;

  typedef enum logic [3:0] {
    ROUTE_IDLE,
    ROUTE_TRANSLATE_OFFER,
    ROUTE_TRANSLATE_RESPONSE,
    ROUTE_SEGMENT_OFFER,
    ROUTE_SEGMENT_RESPONSE,
    ROUTE_PAGE_OFFER,
    ROUTE_PAGE_RESPONSE,
    ROUTE_PHYSICAL_OFFER,
    ROUTE_PHYSICAL_RESPONSE,
    ROUTE_DATA_FAULT_RESPONSE,
    ROUTE_IFETCH_FAULT_RESPONSE,
    ROUTE_IFETCH_FATAL,
    ROUTE_INVALID
  } route_state_t;

  route_state_t state_q;
  logic running_q, context_ir_q, context_dr_q, context_pr_q;
  logic request_ir_q, request_dr_q, request_pr_q;
  logic [2:0] fetch_fault_q;
  logic [2:0] data_fault_q;
  logic last_grant_data_q, owner_instruction_q, owner_write_q;
  logic [31:0] request_ea_q, request_wdata_q;
  logic [3:0] request_wstrb_q;
  logic [31:0] page_sr_q;
  logic [68:0] page_miss_result_q;
  logic [31:0] physical_addr_q;
  logic [3:0] physical_wimg_q;

  logic imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_req_addr, imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [31:0] dmem_rsp_rdata;
  logic choose_instruction, choose_data;

  logic bat_req_valid, bat_req_ready;
  logic [2:0] bat_req_kind;
  logic [31:0] bat_req_ea;
  logic [9:0] bat_req_spr;
  logic [31:0] bat_req_data;
  logic bat_rsp_valid, bat_rsp_ready;
  logic [2:0] bat_rsp_kind;
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
  logic csr_owner_q, csr_offer, service_idle, service_ack;
  logic segment_owner_q, segment_offer, segment_service_idle;
  logic segment_req_valid, segment_req_ready;
  logic segment_rsp_valid, segment_rsp_ready;
  logic [2:0] segment_rsp_kind;
  logic [3:0] segment_rsp_index;
  logic [31:0] segment_rsp_address, segment_rsp_data;
  logic segment_rsp_privileged, segment_rsp_unsupported;
  logic segment_service_ack;
  logic service_pr;
  logic tlb_inv_owner_q, tlb_inv_offer;
  logic tlb_fill_owner_q, tlb_fill_offer;
  logic [31:0] tlb_fill_ea_q;
  logic tlb_fill_bank_q;
  logic tlb_commit_ack, tlb_transaction_idle;
  logic tlb_mgmt_owner_q, tlb_mgmt_offer;
  logic tlb_req_valid, tlb_req_ready;
  logic [2:0] tlb_req_kind;
  logic tlb_req_bank, tlb_req_pr, tlb_req_ks, tlb_req_kp;
  logic tlb_req_n, tlb_req_t, tlb_req_write, tlb_req_way, tlb_req_c;
  logic [31:0] tlb_req_ea;
  logic [23:0] tlb_req_vsid;
  logic [19:0] tlb_req_rpn;
  logic [3:0] tlb_req_wimg;
  logic [1:0] tlb_req_pp;
  logic tlb_rsp_valid, tlb_rsp_ready, tlb_rsp_bank;
  logic [2:0] tlb_rsp_kind;
  logic [1:0] tlb_rsp_match, tlb_rsp_pp;
  logic [31:0] tlb_rsp_ea, tlb_rsp_pa;
  logic [3:0] tlb_rsp_wimg;
  logic tlb_rsp_allow, tlb_rsp_hit, tlb_rsp_miss;
  logic tlb_rsp_protection, tlb_rsp_guarded, tlb_rsp_no_execute;
  logic tlb_rsp_direct_store, tlb_rsp_needs_changed;
  logic tlb_rsp_privileged, tlb_rsp_refill_rejected;
  logic tlb_rsp_unsupported, tlb_rsp_invalid_input;
  logic tlb_rsp_way, tlb_rsp_c, tlb_rsp_r;
  logic tlb_mgmt_service_idle;
  logic page_reply_config, page_reply_allow, clean_bat_page_miss;
  logic clean_page_data_pp;
  logic clean_page_instruction_base;
  logic clean_page_instruction_pp, clean_page_instruction_guarded;
  logic clean_page_instruction_no_execute;
  logic clean_page_miss_base, clean_page_true_miss, clean_page_changed;
  logic page_fault_q, page_miss_q, page_protection_q;
  logic page_no_execute_q, page_guarded_q, page_direct_store_q;
  logic page_needs_changed_q, page_config_q;

  // Memory drain excludes the caller's own CSR transport/reservation. CSR idle
  // separately tracks that ownership so waiting for a response cannot deadlock.
  assign csr_offer = ENABLE_RUNTIME_BAT && rst_ni && running_q &&
    state_q == ROUTE_IDLE && !csr_owner_q && !segment_owner_q &&
    !tlb_mgmt_owner_q && !tlb_inv_owner_q && !tlb_fill_owner_q &&
    service_idle && segment_service_idle &&
    tlb_mgmt_service_idle && !imem_req_valid && !dmem_req_valid;
  assign bat_csr_req_ready_o = csr_offer && bat_req_ready;
  assign bat_csr_rsp_valid_o = ENABLE_RUNTIME_BAT && csr_owner_q && bat_rsp_valid;
  assign bat_csr_rsp_data_o = bat_rsp_data;
  assign bat_csr_rsp_error_o = bat_rsp_privileged || bat_rsp_unsupported ||
    bat_rsp_write_rejected || bat_rsp_config || bat_rsp_overlap ||
    bat_rsp_invalid_input || (|bat_rsp_invalid_entry);
  assign bat_csr_ack_valid_o = ENABLE_RUNTIME_BAT && csr_owner_q && service_ack;
  assign bat_csr_idle_o = rst_ni && (!ENABLE_RUNTIME_BAT || !csr_owner_q);
  // Both CSR transports require a drained memory path. BAT wins a
  // simultaneous CSR offer; neither request can overtake the other owner.
  assign segment_offer = ENABLE_SEGMENT_REGISTERS && rst_ni && running_q &&
    state_q == ROUTE_IDLE && !csr_owner_q && !segment_owner_q &&
    !tlb_mgmt_owner_q && !tlb_inv_owner_q && !tlb_fill_owner_q &&
    service_idle && segment_service_idle &&
    tlb_mgmt_service_idle &&
    !(ENABLE_RUNTIME_BAT && bat_csr_req_valid_i) &&
    !imem_req_valid && !dmem_req_valid;
  assign segment_req_valid =
    (segment_offer && segment_csr_req_valid_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_SEGMENT_OFFER);
  assign segment_csr_req_ready_o = segment_offer && segment_req_ready;
  assign segment_csr_rsp_valid_o = ENABLE_SEGMENT_REGISTERS &&
    segment_owner_q && segment_rsp_valid;
  assign segment_csr_rsp_data_o = segment_rsp_data;
  assign segment_csr_rsp_error_o = segment_rsp_privileged ||
    segment_rsp_unsupported;
  assign segment_csr_ack_valid_o = ENABLE_SEGMENT_REGISTERS &&
    segment_owner_q && segment_service_ack;
  assign segment_csr_idle_o = rst_ni &&
    (!ENABLE_SEGMENT_REGISTERS || !segment_owner_q);
  assign segment_rsp_ready =
    (segment_owner_q && segment_csr_rsp_ready_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_SEGMENT_RESPONSE);

  // CPU tlbie reserves the shared TLB service. The request is accepted only
  // after old memory drains; held responses/proposals/acks exclude all peers.
  assign tlb_inv_offer = ENABLE_TLB_INVALIDATE && rst_ni && running_q &&
    state_q == ROUTE_IDLE && !csr_owner_q && !segment_owner_q &&
    !tlb_mgmt_owner_q && !tlb_inv_owner_q && !tlb_fill_owner_q &&
    service_idle &&
    segment_service_idle && tlb_transaction_idle &&
    !(ENABLE_RUNTIME_BAT && bat_csr_req_valid_i) &&
    !segment_csr_req_valid_i && !imem_req_valid && !dmem_req_valid;
  assign tlb_inv_req_ready_o = tlb_inv_offer && tlb_req_ready;
  assign tlb_inv_rsp_valid_o = ENABLE_TLB_INVALIDATE &&
    tlb_inv_owner_q && tlb_rsp_valid;
  assign tlb_inv_rsp_error_o = tlb_rsp_privileged ||
    tlb_rsp_refill_rejected || tlb_rsp_unsupported ||
    tlb_rsp_invalid_input;
  assign tlb_inv_ack_valid_o = ENABLE_TLB_INVALIDATE &&
    tlb_inv_owner_q && tlb_commit_ack;
  assign tlb_inv_idle_o = rst_ni &&
    (!ENABLE_TLB_INVALIDATE || !tlb_inv_owner_q);

  // CPU TLB loads use the same service reservation as tlbie. An accepted
  // request owns the slot through response, proposal and held commit ack.
  assign tlb_fill_offer = ENABLE_TLB_LOAD && rst_ni && running_q &&
    state_q == ROUTE_IDLE && !csr_owner_q && !segment_owner_q &&
    !tlb_mgmt_owner_q && !tlb_inv_owner_q && !tlb_fill_owner_q &&
    service_idle && segment_service_idle && tlb_transaction_idle &&
    !(ENABLE_RUNTIME_BAT && bat_csr_req_valid_i) &&
    !segment_csr_req_valid_i &&
    !(ENABLE_TLB_INVALIDATE && tlb_inv_req_valid_i) &&
    !imem_req_valid && !dmem_req_valid;
  assign tlb_fill_req_ready_o = tlb_fill_offer && tlb_req_ready;
  assign tlb_fill_rsp_valid_o = ENABLE_TLB_LOAD &&
    tlb_fill_owner_q && tlb_rsp_valid;
  assign tlb_fill_rsp_error_o = tlb_rsp_privileged ||
    tlb_rsp_refill_rejected || tlb_rsp_unsupported ||
    tlb_rsp_invalid_input || tlb_rsp_kind != 3'd5 ||
    tlb_rsp_bank != tlb_fill_bank_q || tlb_rsp_ea != tlb_fill_ea_q;
  assign tlb_fill_ack_valid_o = ENABLE_TLB_LOAD &&
    tlb_fill_owner_q && tlb_commit_ack;
  assign tlb_fill_idle_o = rst_ni &&
    (!ENABLE_TLB_LOAD || !tlb_fill_owner_q);

  // Test/control TLB management has lowest idle-transport priority. Startup
  // BAT writes win before start; running memory, CPU CSR and context win after.
  assign tlb_mgmt_service_idle = tlb_transaction_idle;
  assign tlb_mgmt_offer = ENABLE_PAGE_TRANSLATION && rst_ni &&
    state_q == ROUTE_IDLE && !tlb_mgmt_owner_q && !tlb_inv_owner_q &&
    !tlb_fill_owner_q &&
    !csr_owner_q && !segment_owner_q && service_idle && segment_service_idle &&
    tlb_mgmt_service_idle && !bat_write_valid_i && !bat_rsp_valid &&
    !(ENABLE_RUNTIME_BAT && bat_csr_req_valid_i) &&
    !segment_csr_req_valid_i &&
    !(ENABLE_TLB_INVALIDATE && tlb_inv_req_valid_i) &&
    !(ENABLE_TLB_LOAD && tlb_fill_req_valid_i) &&
    !(running_q && context_valid_i) &&
    !imem_req_valid && !dmem_req_valid;
  assign tlb_mgmt_req_ready_o = tlb_mgmt_offer && tlb_req_ready;
  assign tlb_mgmt_rsp_valid_o = ENABLE_PAGE_TRANSLATION &&
    tlb_mgmt_owner_q && tlb_rsp_valid;
  assign tlb_mgmt_rsp_kind_o = tlb_rsp_kind[1:0];
  assign tlb_mgmt_rsp_bank_o = tlb_rsp_bank;
  assign tlb_mgmt_rsp_ea_o = tlb_rsp_ea;
  assign tlb_mgmt_rsp_privileged_o = tlb_rsp_privileged;
  assign tlb_mgmt_rsp_refill_rejected_o = tlb_rsp_refill_rejected;
  assign tlb_mgmt_rsp_unsupported_o = tlb_rsp_unsupported;
  assign tlb_mgmt_rsp_invalid_input_o = tlb_rsp_invalid_input;
  assign tlb_mgmt_idle_o = rst_ni &&
    (!ENABLE_PAGE_TRANSLATION || !tlb_mgmt_owner_q) &&
    (!ENABLE_TLB_INVALIDATE ||
     (!tlb_inv_owner_q && !tlb_inv_req_valid_i)) &&
    (!ENABLE_TLB_LOAD ||
     (!tlb_fill_owner_q && !tlb_fill_req_valid_i));

  assign tlb_req_valid =
    (tlb_mgmt_offer && tlb_mgmt_req_valid_i) ||
    (tlb_inv_offer && tlb_inv_req_valid_i) ||
    (tlb_fill_offer && tlb_fill_req_valid_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_PAGE_OFFER);
  assign tlb_req_kind = state_q == ROUTE_PAGE_OFFER ? 3'd0 :
    (tlb_inv_offer && tlb_inv_req_valid_i ? 3'd4 :
      (tlb_fill_offer && tlb_fill_req_valid_i ? 3'd5 :
        ((tlb_mgmt_req_kind_i == 2'd1 || tlb_mgmt_req_kind_i == 2'd2) ?
          {1'b0, tlb_mgmt_req_kind_i} : 3'd3)));
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
  assign tlb_rsp_ready = (tlb_mgmt_owner_q && tlb_mgmt_rsp_ready_i) ||
    (tlb_inv_owner_q && tlb_inv_rsp_ready_i) ||
    (tlb_fill_owner_q && tlb_fill_rsp_ready_i) ||
    (ENABLE_PAGE_TRANSLATION && state_q == ROUTE_PAGE_RESPONSE);

  assign clean_bat_page_miss = ENABLE_PAGE_TRANSLATION && bat_rsp_miss &&
    !bat_rsp_allow && !bat_rsp_bypass && !bat_rsp_hit &&
    !bat_rsp_protection && !bat_rsp_guarded && !bat_rsp_config &&
    !bat_rsp_invalid_input && !bat_rsp_overlap &&
    !(|bat_rsp_invalid_entry) && !bat_rsp_privileged &&
    !bat_rsp_unsupported && !bat_rsp_write_rejected &&
    (owner_instruction_q ? request_ir_q : request_dr_q);
  assign page_reply_config = tlb_rsp_kind != 3'd0 ||
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
    tlb_rsp_kind == 3'd0 && tlb_rsp_bank &&
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
    tlb_rsp_kind == 3'd0 && !tlb_rsp_bank &&
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
    tlb_rsp_kind == 3'd0 && tlb_rsp_bank == !owner_instruction_q &&
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
  assign service_pr = running_q &&
    ((csr_offer && bat_csr_req_valid_i) ? context_pr_q : request_pr_q);

  assign imem_req_valid = imem_req_valid_i;
  assign imem_req_addr = imem_req_addr_i;
  assign imem_req_ready_o = imem_req_ready;
  assign imem_rsp_valid_o = imem_rsp_valid;
  assign imem_rsp_page_miss_o = (ENABLE_PAGE_MISS_RESULTS &&
    imem_rsp_valid && imem_rsp_fault_o == FETCH_PAGE_MISS) ?
    page_miss_result_q : 69'b0;
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
    page_miss_result_q : 69'b0;
  assign dmem_rsp_rdata_o = dmem_rsp_rdata;
  assign dmem_rsp_error_o = dmem_rsp_error;
  assign dmem_rsp_ready = dmem_rsp_ready_i;

  // Do not block a held old-context request merely because an update waits.
  // The core fences new offers and drains all old obligations before updating.
  assign quiescent_o = rst_ni && running_q && state_q == ROUTE_IDLE &&
                       (!bat_rsp_valid || (ENABLE_RUNTIME_BAT && csr_owner_q)) &&
                       (!segment_rsp_valid || segment_owner_q) &&
                       (!tlb_rsp_valid || tlb_mgmt_owner_q ||
                        tlb_inv_owner_q || tlb_fill_owner_q) &&
                       !imem_req_valid && !dmem_req_valid;
  assign context_ready_o = ENABLE_LIVE_CONTEXT && quiescent_o &&
    (!ENABLE_RUNTIME_BAT || (!csr_owner_q && !bat_csr_req_valid_i)) &&
    (!ENABLE_SEGMENT_REGISTERS ||
     (!segment_owner_q && !segment_csr_req_valid_i)) &&
    (!ENABLE_PAGE_TRANSLATION || !tlb_mgmt_owner_q) &&
    (!ENABLE_TLB_INVALIDATE ||
     (!tlb_inv_owner_q && !tlb_inv_req_valid_i)) &&
    (!ENABLE_TLB_LOAD ||
     (!tlb_fill_owner_q && !tlb_fill_req_valid_i));

  always_comb begin
    choose_instruction = 1'b0;
    choose_data = 1'b0;
    if (rst_ni && running_q && state_q == ROUTE_IDLE &&
        !csr_owner_q && !segment_owner_q && !tlb_mgmt_owner_q &&
        !tlb_inv_owner_q && !tlb_fill_owner_q) begin
      if (imem_req_valid && dmem_req_valid) begin
        choose_instruction = last_grant_data_q;
        choose_data = !last_grant_data_q;
      end else begin
        choose_instruction = imem_req_valid;
        choose_data = dmem_req_valid;
      end
    end
    imem_req_ready = choose_instruction;
    dmem_req_ready = choose_data;
  end

  // Setup writes and running translations serialize through the committed
  // BAT service.  A setup response must be consumed before start is accepted.
  always_comb begin
    bat_req_valid = 1'b0;
    bat_req_kind = SPR_WRITE;
    bat_req_ea = 32'b0;
    bat_req_spr = bat_write_spr_i;
    bat_req_data = bat_write_data_i;
    if (!running_q) begin
      bat_req_valid = bat_write_valid_i && !tlb_mgmt_owner_q;
    end else if (state_q == ROUTE_TRANSLATE_OFFER) begin
      bat_req_valid = 1'b1;
      bat_req_kind = owner_instruction_q ? TRANSLATE_I :
                     (owner_write_q ? TRANSLATE_WRITE : TRANSLATE_READ);
      bat_req_ea = request_ea_q;
      bat_req_spr = 10'b0;
      bat_req_data = 32'b0;
    end else if (csr_offer) begin
      bat_req_valid = bat_csr_req_valid_i;
      bat_req_kind = bat_csr_req_write_i ? PREPARE_WRITE : SPR_READ;
      bat_req_spr = bat_csr_req_spr_i;
      bat_req_data = bat_csr_req_data_i;
    end

    bat_write_ready_o = rst_ni && !running_q && !tlb_mgmt_owner_q &&
                        bat_req_ready;
    bat_write_rsp_valid_o = rst_ni && !running_q && bat_rsp_valid;
    bat_rsp_ready = !running_q ? bat_write_rsp_ready_i :
                    (csr_owner_q ? bat_csr_rsp_ready_i :
                     (state_q == ROUTE_TRANSLATE_RESPONSE));
    start_ready_o = rst_ni && !running_q && !bat_write_valid_i &&
                    !bat_rsp_valid && bat_req_ready && !tlb_mgmt_owner_q &&
                    !(ENABLE_PAGE_TRANSLATION && tlb_mgmt_req_valid_i);
  end

  ppc_segment_registers #(
    .ENABLE_RUNTIME_SEGMENT(ENABLE_SEGMENT_REGISTERS)
  ) segment_bank (
    .clk_i, .rst_ni,
    .prepare_commit_i(ENABLE_SEGMENT_REGISTERS && running_q &&
                      segment_owner_q && segment_csr_commit_i),
    .prepare_abort_i(ENABLE_SEGMENT_REGISTERS && running_q &&
                     segment_owner_q && segment_csr_abort_i),
    .commit_ack_valid_o(segment_service_ack),
    .commit_ack_ready_i(ENABLE_SEGMENT_REGISTERS && segment_owner_q &&
                        segment_csr_ack_ready_i),
    .transaction_idle_o(segment_service_idle),
    .req_valid_i(segment_req_valid), .req_ready_o(segment_req_ready),
    .req_kind_i(state_q == ROUTE_SEGMENT_OFFER ? 3'd2 :
                (segment_csr_req_write_i ? 3'd4 : 3'd0)),
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
      ((ENABLE_TLB_INVALIDATE && tlb_inv_owner_q && tlb_inv_commit_i) ||
       (ENABLE_TLB_LOAD && tlb_fill_owner_q && tlb_fill_commit_i))),
    .prepare_abort_i(running_q &&
      ((ENABLE_TLB_INVALIDATE && tlb_inv_abort_i &&
        (tlb_inv_owner_q ||
         (tlb_inv_req_valid_i && tlb_inv_req_ready_o))) ||
       (ENABLE_TLB_LOAD && tlb_fill_abort_i &&
        (tlb_fill_owner_q ||
         (tlb_fill_req_valid_i && tlb_fill_req_ready_o))))),
    .commit_ack_valid_o(tlb_commit_ack),
    .commit_ack_ready_i(
      (ENABLE_TLB_INVALIDATE && tlb_inv_owner_q && tlb_inv_ack_ready_i) ||
      (ENABLE_TLB_LOAD && tlb_fill_owner_q && tlb_fill_ack_ready_i)),
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
    .commit_ack_ready_i(ENABLE_RUNTIME_BAT && csr_owner_q && bat_csr_ack_ready_i),
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
    pimem_req_valid_o = rst_ni && state_q == ROUTE_PHYSICAL_OFFER &&
                         owner_instruction_q;
    pimem_req_addr_o = physical_addr_q;
    pimem_req_wimg_o = physical_wimg_q;
    pdmem_req_valid_o = rst_ni && state_q == ROUTE_PHYSICAL_OFFER &&
                         !owner_instruction_q;
    pdmem_req_write_o = owner_write_q;
    pdmem_req_addr_o = physical_addr_q;
    pdmem_req_wdata_o = request_wdata_q;
    pdmem_req_wstrb_o = request_wstrb_q;
    pdmem_req_wimg_o = physical_wimg_q;

    imem_rsp_valid = 1'b0;
    imem_rsp_insn = pimem_rsp_insn_i;
    imem_rsp_fault_o = FETCH_OK;
    pimem_rsp_ready_o = 1'b0;
    dmem_rsp_valid = 1'b0;
    dmem_rsp_rdata = pdmem_rsp_rdata_i;
    dmem_rsp_error = 1'b0;
    dmem_rsp_fault_o = DATA_OK;
    pdmem_rsp_ready_o = 1'b0;
    if (rst_ni && state_q == ROUTE_PHYSICAL_RESPONSE) begin
      if (owner_instruction_q) begin
        if (pimem_rsp_valid_i && pimem_rsp_error_i)
          pimem_rsp_ready_o = 1'b1;
        else begin
          imem_rsp_valid = pimem_rsp_valid_i;
          pimem_rsp_ready_o = imem_rsp_ready;
        end
      end else begin
        dmem_rsp_valid = pdmem_rsp_valid_i;
        dmem_rsp_error = pdmem_rsp_error_i;
        pdmem_rsp_ready_o = dmem_rsp_ready;
      end
    end else if (rst_ni && state_q == ROUTE_DATA_FAULT_RESPONSE) begin
      dmem_rsp_valid = 1'b1;
      dmem_rsp_rdata = 32'b0;
      dmem_rsp_error = data_fault_q == DATA_OK;
      dmem_rsp_fault_o = data_fault_q;
    end else if (rst_ni && state_q == ROUTE_IFETCH_FAULT_RESPONSE) begin
      imem_rsp_valid = 1'b1;
      imem_rsp_insn = 32'b0;
      imem_rsp_fault_o = fetch_fault_q;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= ROUTE_IDLE;
      csr_owner_q <= 1'b0;
      segment_owner_q <= 1'b0;
      tlb_inv_owner_q <= 1'b0;
      tlb_fill_owner_q <= 1'b0;
      tlb_fill_ea_q <= 32'b0;
      tlb_fill_bank_q <= 1'b0;
      tlb_mgmt_owner_q <= 1'b0;
      running_q <= 1'b0;
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
      request_wdata_q <= 32'b0;
      request_wstrb_q <= 4'b0;
      page_sr_q <= 32'b0;
      page_miss_result_q <= 69'b0;
      physical_addr_q <= 32'b0;
      physical_wimg_q <= 4'b0;
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
      if (csr_owner_q && service_idle) csr_owner_q <= 1'b0;
      if (bat_csr_req_valid_i && bat_csr_req_ready_o) csr_owner_q <= 1'b1;
      if (segment_owner_q && segment_service_idle) segment_owner_q <= 1'b0;
      if (segment_csr_req_valid_i && segment_csr_req_ready_o)
        segment_owner_q <= 1'b1;
      if (tlb_inv_owner_q && tlb_transaction_idle)
        tlb_inv_owner_q <= 1'b0;
      if (tlb_inv_req_valid_i && tlb_inv_req_ready_o)
        tlb_inv_owner_q <= 1'b1;
      if (tlb_fill_owner_q && tlb_transaction_idle)
        tlb_fill_owner_q <= 1'b0;
      if (tlb_fill_req_valid_i && tlb_fill_req_ready_o) begin
        tlb_fill_owner_q <= 1'b1;
        tlb_fill_ea_q <= tlb_fill_req_ea_i;
        tlb_fill_bank_q <= tlb_fill_req_bank_i;
      end
      if (tlb_mgmt_owner_q && tlb_mgmt_service_idle)
        tlb_mgmt_owner_q <= 1'b0;
      if (tlb_mgmt_req_valid_i && tlb_mgmt_req_ready_o)
        tlb_mgmt_owner_q <= 1'b1;
      if (start_valid_i && start_ready_o) begin
        running_q <= 1'b1;
        context_ir_q <= start_ir_i;
        context_dr_q <= start_dr_i;
        context_pr_q <= start_pr_i;
      end
      if (context_valid_i && context_ready_o) begin
        context_ir_q <= context_ir_i;
        context_dr_q <= context_dr_i;
        context_pr_q <= context_pr_i;
      end

      unique case (state_q)
        ROUTE_IDLE: begin
          if (choose_instruction || choose_data) begin
            request_ir_q <= context_ir_q;
            request_dr_q <= context_dr_q;
            request_pr_q <= context_pr_q;
            owner_instruction_q <= choose_instruction;
            owner_write_q <= choose_data && dmem_req_write;
            request_ea_q <= choose_instruction ? imem_req_addr :
                                                  dmem_req_addr;
            page_miss_result_q <= 69'b0;
            request_wdata_q <= choose_data ? dmem_req_wdata : 32'b0;
            request_wstrb_q <= choose_data ? dmem_req_wstrb : 4'b1111;
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
              physical_addr_q <= bat_rsp_pa;
              physical_wimg_q <= bat_rsp_wimg;
              state_q <= ROUTE_PHYSICAL_OFFER;
            end else if (clean_bat_page_miss) begin
              state_q <= ROUTE_SEGMENT_OFFER;
            end else begin
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
              if (owner_instruction_q) begin
                // The narrow typed carrier represents exactly one cause.
                // Miss/configuration/combined causes remain diagnostics.
                if (ENABLE_LIVE_CONTEXT && !bat_rsp_miss && !bat_rsp_config &&
                    !bat_rsp_invalid_input &&
                    (bat_rsp_protection ^ bat_rsp_guarded)) begin
                  fetch_fault_q <= bat_rsp_protection ?
                    FETCH_ISI_PROTECTION : FETCH_ISI_GUARDED;
                  state_q <= ROUTE_IFETCH_FAULT_RESPONSE;
                end else begin
                  ifetch_fatal_q <= 1'b1;
                  state_q <= ROUTE_IFETCH_FATAL;
                end
              end else begin
                // Only a valid BAT hit denied by PP is a resumable DSI.
                // Misses and malformed configurations remain diagnostics.
                data_fault_q <= (ENABLE_DATA_EXCEPTIONS && bat_rsp_hit &&
                                 bat_rsp_protection && !bat_rsp_miss &&
                                 !bat_rsp_config && !bat_rsp_invalid_input &&
                                 !(|bat_rsp_invalid_entry) &&
                                 !bat_rsp_guarded) ?
                  DATA_DSI_PROTECTION : DATA_OK;
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
            if (segment_rsp_kind == 3'd2 &&
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
              physical_addr_q <= tlb_rsp_pa;
              physical_wimg_q <= tlb_rsp_wimg;
              state_q <= ROUTE_PHYSICAL_OFFER;
            end else begin
              // Exact page misses and C=0 stores carry their request-time
              // context through the held response; all other failures remain
              // the existing typed exception or ordered diagnostic.
              page_miss_result_q <= (clean_page_true_miss ||
                                     clean_page_changed) ?
                {request_ea_q, page_sr_q, request_pr_q, request_ir_q,
                 request_dr_q, owner_write_q,
                 (clean_page_changed && tlb_rsp_way)} : 69'b0;
              fault_q <= 1'b1;
              fault_instruction_q <= owner_instruction_q;
              fault_write_q <= owner_write_q;
              fault_ea_q <= request_ea_q;
              fault_miss_q <= 1'b0;
              fault_protection_q <= 1'b0;
              fault_guarded_q <= 1'b0;
              fault_config_q <= page_reply_config;
              fault_invalid_input_q <= tlb_rsp_invalid_input;
              fault_invalid_entry_q <= '0;
              page_fault_q <= 1'b1;
              page_miss_q <= page_miss_q || tlb_rsp_miss;
              page_protection_q <= page_protection_q || tlb_rsp_protection;
              page_no_execute_q <= page_no_execute_q || tlb_rsp_no_execute;
              page_guarded_q <= page_guarded_q || tlb_rsp_guarded;
              page_direct_store_q <= page_direct_store_q || tlb_rsp_direct_store;
              page_needs_changed_q <= page_needs_changed_q ||
                                      tlb_rsp_needs_changed;
              page_config_q <= page_config_q || page_reply_config;
              if (owner_instruction_q) begin
                if (clean_page_true_miss || clean_page_instruction_pp ||
                    clean_page_instruction_guarded ||
                    clean_page_instruction_no_execute) begin
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

        ROUTE_PHYSICAL_OFFER: begin
          if ((owner_instruction_q && pimem_req_valid_o &&
               pimem_req_ready_i) ||
              (!owner_instruction_q && pdmem_req_valid_o &&
               pdmem_req_ready_i))
            state_q <= ROUTE_PHYSICAL_RESPONSE;
        end

        ROUTE_PHYSICAL_RESPONSE: begin
          if (owner_instruction_q) begin
            if (pimem_rsp_valid_i && pimem_rsp_ready_o) begin
              if (pimem_rsp_error_i) begin
                pimem_error_q <= 1'b1;
                ifetch_fatal_q <= 1'b1;
                state_q <= ROUTE_IFETCH_FATAL;
              end else begin
                state_q <= ROUTE_IDLE;
              end
            end
          end else if (pdmem_rsp_valid_i && pdmem_rsp_ready_o) begin
            state_q <= ROUTE_IDLE;
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

  assign running_o = rst_ni && running_q;
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
  assign busy_o = rst_ni && (csr_owner_q || segment_owner_q ||
                              tlb_inv_owner_q || tlb_fill_owner_q ||
                              tlb_mgmt_owner_q || bat_rsp_valid ||
                              segment_rsp_valid || tlb_rsp_valid ||
                              state_q != ROUTE_IDLE ||
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
    if (bat_csr_commit_i) assert (csr_owner_q && state_q == ROUTE_IDLE)
      else $error("runtime BAT commit without exclusive owner");
    if (csr_owner_q) assert (state_q == ROUTE_IDLE && !context_ready_o)
      else $error("runtime BAT ownership overlaps memory/context installation");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_SEGMENT_REGISTERS) begin
    if (segment_csr_commit_i) assert (segment_owner_q &&
      state_q == ROUTE_IDLE && !csr_owner_q)
      else $error("segment commit without exclusive owner");
    if (segment_owner_q) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner_q)
      else $error("segment ownership overlaps memory/context installation");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_TLB_INVALIDATE) begin
    if (tlb_inv_commit_i) assert (tlb_inv_owner_q &&
      state_q == ROUTE_IDLE && !tlb_mgmt_owner_q)
      else $error("TLB invalidate commit without exclusive owner");
    if (tlb_inv_owner_q) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner_q && !segment_owner_q &&
      !tlb_mgmt_owner_q)
      else $error("TLB invalidate owner overlaps memory/context");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_TLB_LOAD) begin
    if (tlb_fill_commit_i) assert (tlb_fill_owner_q &&
      state_q == ROUTE_IDLE && !tlb_mgmt_owner_q && !tlb_inv_owner_q)
      else $error("TLB fill commit without exclusive owner");
    if (tlb_fill_owner_q) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner_q && !segment_owner_q &&
      !tlb_mgmt_owner_q && !tlb_inv_owner_q)
      else $error("TLB fill owner overlaps memory/context");
  end
  always @(posedge clk_i) if (rst_ni && ENABLE_PAGE_TRANSLATION) begin
    if (tlb_mgmt_owner_q) assert (state_q == ROUTE_IDLE &&
      !context_ready_o && !csr_owner_q && !segment_owner_q)
      else $error("TLB management overlaps memory, CSR or context");
    if (state_q == ROUTE_PAGE_RESPONSE && tlb_rsp_valid &&
        !page_reply_allow) assert (!pimem_req_valid_o && !pdmem_req_valid_o)
      else $error("denied page response offered physical memory");
  end
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
  // synthesis translate_on

  // Keep service response fields visible to lint while the wrapper consumes
  // only the authorization, PA, WIMG, and fault subset.
  logic _unused_segment_response;
  assign _unused_segment_response = ^{segment_rsp_kind,
    segment_rsp_index, segment_rsp_address};
  logic _unused_tlb_response;
  assign _unused_tlb_response = ^{page_sr_q[27:24], tlb_rsp_hit, tlb_rsp_match, tlb_rsp_way,
    tlb_rsp_pp, tlb_rsp_c, tlb_rsp_r};
  logic _unused_bat_response;
  assign _unused_bat_response = ^{bat_rsp_kind, bat_rsp_ea, bat_rsp_spr,
    bat_rsp_data, bat_rsp_privileged, bat_rsp_unsupported,
    bat_rsp_write_rejected, bat_rsp_bypass, bat_rsp_hit, bat_rsp_overlap,
    bat_rsp_match, bat_rsp_hit_index, bat_rsp_pp};
endmodule
