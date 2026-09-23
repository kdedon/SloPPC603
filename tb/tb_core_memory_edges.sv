// External memory obligations and architectural side effects around recovery.
/* verilator lint_off BLKSEQ */
module tb_core_memory_edges;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr, re;
  logic [31:0] da, wd, rd;
  logic [3:0] st;
  logic tv, tr, halted;
  retire_packet_t retired;
  logic cut, cut_accepted;
  logic [31:0] target, first_word;
  logic ipending = 0;
  logic [31:0] iword = 0;
  int checks = 0, requests = 0, retires = 0;
  int expected_count = 0;
  logic [31:0] expected_pc[4], expected_word[4], expected_value[4];
  logic expected_gpr_write[4], expected_illegal[4];
  logic [4:0] expected_reg[4];
  logic [31:0] model_gpr[32], model_lr;
  logic [31:0] expected_lr[4];

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0)) dut (
    .tlb_inv_req_valid_o(unused_tlb_inv_core[0]),
    .tlb_inv_req_ready_i(1'b0),
    .tlb_inv_req_ea_o(unused_tlb_inv_core[32:1]),
    .tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(unused_tlb_inv_core[33]),
    .tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(unused_tlb_inv_core[34]),
    .tlb_inv_abort_o(unused_tlb_inv_core[35]),
    .tlb_inv_ack_valid_i(1'b0),
    .tlb_inv_ack_ready_o(unused_tlb_inv_core[36]),
    .tlb_inv_idle_i(1'b1),
    .tlb_fill_req_valid_o(unused_tlb_fill[89]),
    .tlb_fill_req_ready_i(1'b0),
    .tlb_fill_req_bank_o(unused_tlb_fill[88]),
    .tlb_fill_req_ea_o(unused_tlb_fill[87:56]),
    .tlb_fill_req_vsid_o(unused_tlb_fill[55:32]),
    .tlb_fill_req_way_o(unused_tlb_fill[31]),
    .tlb_fill_req_rpn_o(unused_tlb_fill[30:11]),
    .tlb_fill_req_c_o(unused_tlb_fill[10]),
    .tlb_fill_req_wimg_o(unused_tlb_fill[9:6]),
    .tlb_fill_req_pp_o(unused_tlb_fill[5:4]),
    .tlb_fill_rsp_valid_i(1'b0),
    .tlb_fill_rsp_ready_o(unused_tlb_fill[3]),
    .tlb_fill_rsp_error_i(1'b0),
    .tlb_fill_commit_o(unused_tlb_fill[2]),
    .tlb_fill_abort_o(unused_tlb_fill[1]),
    .tlb_fill_ack_valid_i(1'b0),
    .tlb_fill_ack_ready_o(unused_tlb_fill[0]),
    .tlb_fill_idle_i(1'b1),
    .bat_csr_req_valid_o(unused_bat_csr[47]), .bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]), .bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_csr[35:4]), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0), .bat_csr_rsp_error_i(1'b0),
    .bat_csr_commit_o(unused_bat_csr[2]), .bat_csr_abort_o(unused_bat_csr[1]),
    .bat_csr_ack_valid_i(1'b0), .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(unused_segment_csr[41]), .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[40]),
    .segment_csr_req_index_o(unused_segment_csr[39:36]),
    .segment_csr_req_data_o(unused_segment_csr[35:4]),
    .segment_csr_rsp_valid_i(1'b0), .segment_csr_rsp_ready_o(unused_segment_csr[3]),
    .segment_csr_rsp_data_i(32'b0), .segment_csr_rsp_error_i(1'b0),
    .segment_csr_commit_o(unused_segment_csr[2]),
    .segment_csr_abort_o(unused_segment_csr[1]),
    .segment_csr_ack_valid_i(1'b0), .segment_csr_ack_ready_o(unused_segment_csr[0]),
    .segment_csr_idle_i(1'b1),
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(cut), .redirect_all_i(1'b1), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(target), .redirect_accepted_o(cut_accepted)
  );
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case(pc)
      0: return first_word;
      4: return 32'h3900_0008; // addi r8,0,8
      32'h100: return 32'h38e0_004d; // addi r7,0,77
      32'h200: return 32'h38e0_0058; // addi r7,0,88
      default: return 0;
    endcase
  endfunction
  assign ir = rst_n && !ipending;
  assign sv = rst_n && ipending;
  assign iw = iword;
  task automatic require(input logic condition, input string message);
    checks++;
    assert(condition) else $fatal(1,"%s first=%08x retires=%0d requests=%0d",message,first_word,retires,requests);
  endtask
  always @(posedge clk) begin
    if(!rst_n) begin
      ipending <= 0; requests = 0; retires = 0; model_lr=0;
      for(int i=0;i<32;i++) model_gpr[i]=0;
    end else begin
      if(sv && sr) ipending <= 0;
      if(iv && ir) begin ipending<=1; iword<=instruction(ia); end
      if(dv && dr) requests++;
      if(tv && tr) begin
        require(retires < expected_count, "unexpected retirement");
        require(retired.pc == expected_pc[retires] && retired.insn == expected_word[retires], "wrong retirement path");
        require(retired.illegal == expected_illegal[retires] && retired.gpr_write == expected_gpr_write[retires], "wrong effects or fault");
        if(expected_gpr_write[retires]) begin
          require(retired.gpr == expected_reg[retires] && retired.value == expected_value[retires], "wrong GPR packet");
          model_gpr[expected_reg[retires]]=expected_value[retires];
        end
        model_lr=expected_lr[retires];
        retires++;
        #1;
        for(int i=0;i<32;i++) require(dut.regfile.gpr[i]==model_gpr[i], "unexpected GPR side effect");
        require(dut.cr==0 && dut.xer==0 && dut.lr==model_lr && dut.ctr==0, "unexpected special-state effect");
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));
  assert property(@(posedge clk) disable iff(!rst_n)
    tv && !tr |=> tv && $stable(retired));

  task automatic tick;
    @(posedge clk); #2; @(negedge clk); #1;
  endtask
  task automatic expect_packet(input logic [1:0] index, input logic [31:0] pc,
    input logic illegal, input logic writes, input logic [4:0] regno,
    input logic [31:0] value);
    expected_pc[index]=pc; expected_word[index]=instruction(pc);expected_lr[index]=0;
    expected_illegal[index]=illegal; expected_gpr_write[index]=writes;
    expected_reg[index]=regno; expected_value[index]=value;
  endtask
  task automatic reset_core(input logic [31:0] word);
    @(negedge clk); rst_n=0; first_word=word;
    cut=0; target=32'h100; dr=0; rv=0; re=0; rd=32'hdead_beef; tr=0;
    expected_count=0;
    tick();tick();rst_n=1;
  endtask
  task automatic wait_request;
    int n;
    n=0;while(!dv && n<100) begin tick();n++;end
    require(dv,"data request timeout");
  endtask
  task automatic answer(input logic error);
    dr=1;
    tick();dr=0;
    require(requests==1,"request not accepted exactly once");
    rv=1; re=error;
    while(!rr) tick();
    tick();rv=0;re=0;
  endtask
  task automatic await_halt;
    int n;
    n=0;while(!halted && n<200) begin tick();n++;end
    require(halted && retires==expected_count,"halt/retirement count mismatch");
  endtask
  initial begin
    // Halfword and word misalignment must fault before any external request.
    for(int kind=0;kind<4;kind++) begin
      case(kind)
        0: reset_core(32'h8060_1001); // lwz r3,4097(0)
        1: reset_core(32'ha060_1001); // lhz r3,4097(0)
        2: reset_core(32'h9000_1002); // stw r0,4098(0)
        default: reset_core(32'hb000_1001); // sth r0,4097(0)
      endcase
      expected_count=1;expect_packet(0,0,1,0,0,0);tr=1;
      await_halt();require(requests==0,"misaligned operation reached memory");
    end
    // Explicit failure acknowledgment: no destination write and no fallthrough.
    for(int store=0;store<2;store++) begin
      reset_core(store!=0 ? 32'h9000_1000 : 32'h8060_1000);
      expected_count=1;expect_packet(0,0,1,0,0,0);tr=1;
      wait_request();answer(1);await_halt();
      require(dut.regfile.gpr[3]==0,"failed load modified destination");
    end
    // Kill a load while its request is held, keep its offer stable and drain
    // even an error response. A second cut selects the latest fetch target.
    reset_core(32'h8060_1000);
    expected_count=2;expect_packet(0,32'h200,0,1,7,88);expect_packet(1,32'h204,1,0,0,0);
    wait_request();require(!dw && da==32'h1000,"load request fixture");
    cut=1;#1;require(cut_accepted,"held-load cut rejected");tick();cut=0;
    require(dv && !halted && !tv,"killed held request disappeared or produced effects");
    repeat(3) tick();
    target=32'h200;cut=1;#1;require(cut_accepted,"second drain redirect rejected");tick();cut=0;
    answer(1);tr=1;await_halt();
    require(requests==1 && dut.regfile.gpr[3]==0,"killed response was not discarded");
    // Accepted loads are cancellable too, including a coincident error reply.
    for(int coincident=0;coincident<2;coincident++) begin
      reset_core(32'h8060_1000);
      expected_count=2;expect_packet(0,32'h100,0,1,7,77);expect_packet(1,32'h104,1,0,0,0);
      wait_request();dr=1;tick();dr=0;
      require(requests==1 && rr,"accepted load did not await response");
      cut=1;rv=(coincident!=0);re=1;
      #1;require(cut_accepted,"accepted-load cut rejected");tick();cut=0;
      if(coincident==0) begin rv=1;while(!rr) tick();tick();end
      rv=0;re=0;tr=1;await_halt();
      require(requests==1 && dut.regfile.gpr[3]==0,"cancelled accepted response produced an effect");
    end
    // Store reservation is irrevocable from its first offer, through request
    // backpressure, response wait, and finished retirement backpressure.
    reset_core(32'h9000_1000);
    expected_count=3;expect_packet(0,0,0,0,0,0);expect_packet(1,4,0,1,8,8);expect_packet(2,8,1,0,0,0);
    repeat(20) begin tick();require(!dv,"store offered before retirement authorization");end
    tr=1;wait_request();tr=0;
    require(dw && da==32'h1000 && st==4'hf,"store request fixture");
    cut=1;#1;require(!cut_accepted,"offered store was cancellable");repeat(3) tick();
    dr=1;tick();dr=0;require(requests==1 && !cut_accepted,"accepted store was cancellable");
    repeat(3) begin tick();require(!cut_accepted,"waiting store was cancellable");end
    rv=1;re=0;while(!rr) tick();tick();rv=0;
    while(!tv) tick();
    require(!cut_accepted,"finished store was cancellable");repeat(3) tick();
    tr=1;#1;require(!cut_accepted,"store commit cut should reject");tick();cut=0;
    await_halt();require(requests==1,"store request duplicated");
    // A killed unfinished linking branch cannot update LR or redirect later.
    reset_core(32'h4800_0101); // bl 0x100
    expected_count=2;expect_packet(0,32'h200,0,1,7,88);expect_packet(1,32'h204,1,0,0,0);
    while(!dut.special.busy_o) tick();
    require(!tv && dut.lr==0,"branch committed before cancellation fixture");
    target=32'h200;cut=1;#1;require(cut_accepted,"unfinished branch cut rejected");tick();cut=0;
    tr=1;await_halt();require(dut.lr==0 && requests==0,"killed branch left effects");
    // A committing taken branch wins over an external redirect on that edge.
    reset_core(32'h4800_0101);
    expected_count=3;expect_packet(0,0,0,0,0,0);expect_packet(1,32'h100,0,1,7,77);expect_packet(2,32'h104,1,0,0,0);
    for(int i=0;i<3;i++) expected_lr[i]=4;
    while(!tv) tick();
    require(dut.lr==0,"stalled linking branch modified LR early");
    repeat(3) tick();
    target=32'h200;cut=1;tr=1;#1;
    require(!cut_accepted,"external target incorrectly reported accepted over branch");
    tick();cut=0;await_halt();require(dut.lr==4 && requests==0,"branch link/target effects wrong");
    $display("PASS memory edges: alignment/errors, load kill/drain, irrevocable store, branch kill/commit arbitration (%0d checks)",checks);
    $finish;
  end
  initial begin #100000;$fatal(1,"memory edge watchdog");end
endmodule
