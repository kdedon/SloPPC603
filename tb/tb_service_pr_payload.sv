// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
module tb_service_pr_payload #(parameter bit HAS_602=0, parameter bit ENABLE_RUNTIME_BAT=1);
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
  typedef enum logic [2:0] {
    LANE_IDLE,
    LANE_WAIT,
    LANE_SLOW,
    LANE_OFFER,
    LANE_RESPONSE,
    LANE_FATAL
  } lane_state_t;
  typedef enum logic [2:0] {
    OWN_NONE, OWN_BAT_CSR, OWN_SEGMENT, OWN_TLB_INV, OWN_TLB_FILL, OWN_TLB_MGMT
  } owner_t;
  localparam int SLOT_BAT_CSR = 0, SLOT_SEGMENT = 1, SLOT_TLB_INV = 2,
                 SLOT_TLB_FILL = 3, SLOT_TLB_MGMT = 4, SLOT_COUNT = 5;

  localparam bit ENABLE_SEGMENT_REGISTERS=1,ENABLE_TLB_INVALIDATE=1,ENABLE_TLB_LOAD=1,ENABLE_PAGE_TRANSLATION=1;
  logic clk_i,rst_ni,bat_setup_q,running_q,context_pr_q,request_pr_q;
  // Width-identical raw state carriers permit X/Z enum encodings. Constants
  // above are extracted actual enum values; no enum/control equations rewritten.
  logic[3:0] state_q;
  logic[2:0] i_state_q,d_state_q,owner_q;
  logic lanes_idle,service_idle,segment_service_idle,tlb_transaction_idle;
  logic imem_req_valid,dmem_req_valid,context_valid_i;
  logic bat_csr_rsp_ready_i;
  assign bat_csr_rsp_ready_i=rsp_ready;
  logic bat_write_valid_i,bat_write_rsp_ready_i,bat_write_ready_o,bat_write_rsp_valid_o,start_ready_o;
  logic[9:0]bat_write_spr_i,bat_csr_req_spr_i;
  logic[31:0]bat_write_data_i,bat_csr_req_data_i,request_ea_q;
  logic bat_csr_req_valid_i,bat_csr_req_write_i,segment_csr_req_valid_i,tlb_inv_req_valid_i,tlb_fill_req_valid_i,tlb_mgmt_req_valid_i;
  logic tlb_mgmt_owner,csr_owner,csr_offer,bat_req_valid,bat_req_ready,bat_rsp_valid,bat_rsp_ready;
  logic owner_instruction_q,owner_write_q,request_ir_q,request_dr_q;
  logic slot_free;
  logic[SLOT_COUNT-1:0]slot_eligible,slot_pending,slot_offer;
  logic [2:0] bat_req_kind; // width-identical raw enum carrier
  logic[31:0]bat_req_ea,bat_req_data;
  logic[9:0]bat_req_spr;
  logic service_pr,old_pr,rsp_ready,prepare_commit,prepare_abort,ack_ready;
  logic old_ready,new_ready,old_valid,new_valid,old_idle,new_idle,old_ack,new_ack;
  logic service_idle_mask;
  assign service_idle=old_idle&&service_idle_mask;
  assign bat_req_ready=old_ready;
  assign bat_rsp_valid=old_valid;
  assign csr_owner=owner_q==OWN_BAT_CSR;
  assign tlb_mgmt_owner=owner_q==OWN_TLB_MGMT;
  assign lanes_idle=i_state_q==LANE_IDLE&&d_state_q==LANE_IDLE;
  assign csr_offer=slot_offer[SLOT_BAT_CSR];
  // Frozen independent legacy equation, not extracted from candidate.
  assign old_pr=!bat_setup_q&&((csr_offer&&bat_csr_req_valid_i)?context_pr_q:request_pr_q);
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
    end else begin
      bat_req_valid = csr_offer && bat_csr_req_valid_i;
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

  // PR follows the registered request source, like the other BAT payload.
  // CSR arbitration qualifies valid; it need not select translation data.
  always_comb begin
    // Preserve the original merge when the request source is unknown.
    service_pr = !bat_setup_q &&
      ((csr_offer && bat_csr_req_valid_i) ? context_pr_q : request_pr_q);
    case (bat_setup_q)
      1'b1: service_pr = 1'b0;
      1'b0: begin
        case (state_q == ROUTE_TRANSLATE_OFFER)
          1'b1: service_pr = 1'b1 && request_pr_q;
          1'b0: service_pr = 1'b1 && context_pr_q;
          default: begin end // service_pr unknown route-state fallback
        endcase
      end
      default: begin end // service_pr unknown setup-state fallback
    endcase
  end


  logic prepared_q,ack_q,write_q,write_store_q,response_valid_q;
  logic req_ready_o,req_valid_i,request_fire,rsp_ready_i,transaction_idle_o;
  assign req_valid_i=bat_req_valid;
  assign rsp_ready_i=rsp_ready;
  assign old_ready=req_ready_o;
  assign old_idle=transaction_idle_o;
  assign old_valid=rst_ni&&response_valid_q;
  assign req_ready_o = rst_ni && !prepared_q && !ack_q && !write_q &&
                       !write_store_q && (!response_valid_q || rsp_ready_i);
  assign request_fire = req_valid_i && req_ready_o;
  assign transaction_idle_o = rst_ni && !response_valid_q && !prepared_q &&
                              !ack_q && !write_q && !write_store_q;
  logic [83:0] old_tuple,new_tuple,old_capture,new_capture;
  assign old_tuple={bat_req_kind,bat_req_ea,bat_req_spr,bat_req_data,request_ir_q,request_dr_q,old_pr,4'b1010};
  assign new_tuple={bat_req_kind,bat_req_ea,bat_req_spr,bat_req_data,request_ir_q,request_dr_q,service_pr,4'b1010};
  always @(posedge clk_i) begin
    if(!rst_ni)begin old_capture<='0;new_capture<='0;end
    else if(request_fire)begin old_capture<=old_tuple;new_capture<=new_tuple;end
  end

  integer vectors=0,captures=0,setup_caps=0,translate_caps=0,csr_caps=0;
  integer invalid_differences=0,setup_fallback=0,state_fallback=0,held_edges=0;
  integer user_caps=0,supervisor_caps=0,unknown_valid=0,ready_unknown=0;
  function automatic logic four(input integer v);
    case(v&3)0:four=0;1:four=1;2:four=1'bx;default:four=1'bz;endcase
  endfunction
  function automatic logic[3:0] state_pattern(input integer n);
    if(n<16)state_pattern=4'(n);
    else case(n)
      16:state_pattern=4'b000x;17:state_pattern=4'b000z;
      18:state_pattern=4'bx001;19:state_pattern=4'bz001;
      20:state_pattern=4'b10xx;21:state_pattern=4'b10zz;
      22:state_pattern=4'bxxxx;default:state_pattern=4'bzzzz;
    endcase
  endfunction

  task automatic tick;
    #1;
    if(rst_ni&&request_fire)begin
      if(old_tuple!==new_tuple)$fatal(1,"accepted complete payload mismatch vector %0d",vectors);
      captures++;
      if(bat_setup_q)setup_caps++;else if(state_q==ROUTE_TRANSLATE_OFFER)translate_caps++;else csr_caps++;
      if(old_pr===0)supervisor_caps++;if(old_pr===1)user_caps++;
    end
    if(req_ready_o!==0&&req_ready_o!==1)ready_unknown++;
    clk_i=1;#1;
    if(old_capture!==new_capture)$fatal(1,"captured complete input tuple mismatch vector %0d",vectors);
    clk_i=0;#1;
  endtask
  task automatic defaults;
    rst_ni=0;bat_setup_q=0;running_q=1;context_pr_q=0;request_pr_q=1;
    state_q=ROUTE_IDLE;i_state_q=LANE_IDLE;d_state_q=LANE_IDLE;owner_q=OWN_NONE;
    service_idle_mask=1;segment_service_idle=1;tlb_transaction_idle=1;
    imem_req_valid=0;dmem_req_valid=0;context_valid_i=0;
    bat_write_valid_i=0;bat_write_rsp_ready_i=1;bat_write_spr_i=528;bat_write_data_i=32'h01230003;
    bat_csr_req_valid_i=0;bat_csr_req_write_i=0;bat_csr_req_spr_i=528;bat_csr_req_data_i=32'h45670003;
    segment_csr_req_valid_i=0;tlb_inv_req_valid_i=0;tlb_fill_req_valid_i=0;tlb_mgmt_req_valid_i=0;
    owner_instruction_q=0;owner_write_q=0;request_ir_q=1;request_dr_q=1;request_ea_q=32'h12345678;
    rsp_ready=1;prepare_commit=0;prepare_abort=0;ack_ready=1;
    prepared_q=0;ack_q=0;write_q=0;write_store_q=0;response_valid_q=0;
    tick();rst_ni=1;
  endtask

  task automatic sample;
    #1;vectors++;
    if(!(bat_req_valid===1'b1)&&(old_pr!==service_pr))invalid_differences++;
    if(bat_setup_q!==0&&bat_setup_q!==1)begin
      setup_fallback++;if(old_pr!==service_pr)$fatal(1,"setup fallback");
    end
    if(bat_setup_q===0&&(state_q==ROUTE_TRANSLATE_OFFER)!==0&&(state_q==ROUTE_TRANSLATE_OFFER)!==1)begin
      state_fallback++;if(old_pr!==service_pr)$fatal(1,"state fallback");
    end
    if(bat_req_valid!==0&&bat_req_valid!==1)unknown_valid++;
    tick();
    // Held response slot forbids request capture despite changing context.
    response_valid_q=1;rsp_ready=0;context_pr_q=~context_pr_q;tick();held_edges++;
    rsp_ready=1;tick();
    // Unknown readiness cannot capture through a procedural IF.
    prepared_q=1'bx;tick();prepared_q=1'bz;tick();
    prepared_q=0;rst_ni=0;tick();
  endtask
  initial begin
    clk_i=0;rst_ni=0;
    for(integer a=0;a<4;a++)for(integer s=0;s<24;s++)for(integer p=0;p<16;p++)
      for(integer c=0;c<4;c++)for(integer m=0;m<16;m++)begin
        defaults();bat_setup_q=four(a);state_q=state_pattern(s);
        context_pr_q=four(p);request_pr_q=four(p>>2);bat_csr_req_valid_i=four(c);
        imem_req_valid=m[0];dmem_req_valid=m[1];bat_write_valid_i=m[2];
        bat_csr_req_write_i=m[3];owner_instruction_q=m[0];owner_write_q=m[1];
        request_ir_q=m[2];request_dr_q=m[3];sample();
      end
    for(integer mode=0;mode<4;mode++)for(integer q=0;q<4096;q++)begin
      defaults();state_q=mode[0]?ROUTE_TRANSLATE_OFFER:ROUTE_IDLE;
      bat_setup_q=mode[1];bat_write_valid_i=1;bat_csr_req_valid_i=1;
      imem_req_valid=four(q);dmem_req_valid=four(q>>2);service_idle_mask=four(q>>4);
      segment_service_idle=four(q>>6);tlb_transaction_idle=four(q>>8);running_q=four(q>>10);
      sample();
    end
    for(integer o=0;o<10;o++)for(integer i=0;i<10;i++)for(integer d=0;d<10;d++)
      for(integer c=0;c<4;c++)for(integer mode=0;mode<2;mode++)begin
        defaults();state_q=mode?ROUTE_TRANSLATE_OFFER:ROUTE_IDLE;
        owner_q=o<8?3'(o):(o==8?3'bxxx:3'bzzz);
        i_state_q=i<8?3'(i):(i==8?3'bxxx:3'bzzz);
        d_state_q=d<8?3'(d):(d==8?3'bxxx:3'bzzz);
        bat_csr_req_valid_i=four(c);sample();
      end

    // Real startup input valid may be X/Z in the raw four-state domain even
    // with runtime CSR disabled. No internal request-valid override occurs.
    for(integer u=2;u<4;u++)begin
      defaults();bat_setup_q=1;bat_write_valid_i=four(u);sample();
    end
    $display("COVERAGE BEFORE ASSERT runtime=%0d vectors=%0d captures=%0d setup=%0d translate=%0d CSR=%0d invaliddiff=%0d setupXZ=%0d stateXZ=%0d held=%0d readyXZ=%0d validXZ=%0d user=%0d supervisor=%0d",ENABLE_RUNTIME_BAT,vectors,captures,setup_caps,translate_caps,csr_caps,invalid_differences,setup_fallback,state_fallback,held_edges,ready_unknown,unknown_valid,user_caps,supervisor_caps);
    if(vectors!=122690||captures==0||setup_caps==0||translate_caps==0||
       (ENABLE_RUNTIME_BAT&&csr_caps==0)||invalid_differences==0||setup_fallback==0||state_fallback==0||
       held_edges!=vectors||ready_unknown==0||unknown_valid==0||user_caps==0||supervisor_caps==0)
      $fatal(1,"vacuous payload proof vectors %0d",vectors);
    $display("PASS INPUT ONLY runtime=%0d vectors=%0d captures=%0d setup=%0d translate=%0d CSR=%0d invaliddiff=%0d setupXZ=%0d stateXZ=%0d held=%0d readyXZ=%0d validXZ=%0d",ENABLE_RUNTIME_BAT,vectors,captures,setup_caps,translate_caps,csr_caps,invalid_differences,setup_fallback,state_fallback,held_edges,ready_unknown,unknown_valid);
    $finish;
  end
endmodule
