module tb_bat_runtime_service;
  logic prepare_commit=0, prepare_abort=0, ack_valid, ack_ready=0, idle;
  logic [31:0] model[16];
  logic clk = 0;
  always #5 clk <= !clk;
  logic rst_n = 0;
  logic req_valid, req_ready, rsp_valid, rsp_ready;
  logic [2:0] req_kind, rsp_kind;
  logic [31:0] req_ea, req_data, rsp_ea, rsp_data, rsp_pa;
  logic [9:0] req_spr, rsp_spr;
  logic req_ir, req_dr, req_pr;
  logic rsp_privileged, rsp_unsupported, rsp_rejected;
  logic [8:0] rsp_status;
  logic [3:0] rsp_bad, rsp_match, rsp_wimg;
  logic [1:0] rsp_index, rsp_pp;
  logic [136:0] observed;
  integer checks = 0;
  assign observed = {rsp_kind, rsp_ea, rsp_spr, rsp_data,
                     rsp_privileged, rsp_unsupported, rsp_rejected,
                     rsp_status, rsp_bad, rsp_match, rsp_index,
                     rsp_pa, rsp_wimg, rsp_pp};

  ppc_bat_service #(.ENABLE_RUNTIME_BAT(1'b1)) dut (
    .prepare_commit_i(prepare_commit), .prepare_abort_i(prepare_abort), .commit_ack_ready_i(ack_ready),
    .commit_ack_valid_o(ack_valid), .transaction_idle_o(idle),
    .clk_i(clk), .rst_ni(rst_n), .req_valid_i(req_valid), .req_ready_o(req_ready),
    .req_kind_i(req_kind), .req_ea_i(req_ea), .req_spr_i(req_spr),
    .req_data_i(req_data), .req_ir_i(req_ir), .req_dr_i(req_dr), .req_pr_i(req_pr),
    .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
    .rsp_kind_o(rsp_kind), .rsp_ea_o(rsp_ea), .rsp_spr_o(rsp_spr), .rsp_data_o(rsp_data),
    .rsp_privileged_o(rsp_privileged), .rsp_unsupported_o(rsp_unsupported),
    .rsp_write_rejected_o(rsp_rejected),
    .rsp_allow_o(rsp_status[8]), .rsp_bypass_o(rsp_status[7]),
    .rsp_hit_o(rsp_status[6]), .rsp_miss_o(rsp_status[5]),
    .rsp_protection_fault_o(rsp_status[4]), .rsp_guarded_fault_o(rsp_status[3]),
    .rsp_config_error_o(rsp_status[2]), .rsp_invalid_input_o(rsp_status[1]),
    .rsp_overlap_o(rsp_status[0]), .rsp_invalid_entry_o(rsp_bad),
    .rsp_match_o(rsp_match), .rsp_hit_index_o(rsp_index), .rsp_pa_o(rsp_pa),
    .rsp_wimg_o(rsp_wimg), .rsp_pp_o(rsp_pp)
  );

  task automatic check(input logic good, input string message_text);
    checks++;
    if (!good) $fatal(1, "BAT service check %0d: %s observed=%h", checks, message_text, observed);
  endtask

  task automatic reset_service;
    @(negedge clk);
    rst_n = 0; req_valid = 0; rsp_ready = 0; prepare_commit=0; prepare_abort=0; ack_ready=0;
    req_kind = 0; req_ea = 0; req_spr = 0; req_data = 0;
    req_ir = 1; req_dr = 1; req_pr = 0;
    #1;
    check(!req_ready && !rsp_valid, "reset immediately gates handshakes");
    @(posedge clk); #1;
    @(negedge clk); rst_n = 1; #1;
    check(req_ready && !rsp_valid, "reset returns empty service");
  endtask

  task automatic send(
    input logic [2:0] kind, input logic [31:0] address,
    input logic [9:0] spr, input logic [31:0] data,
    input logic problem, input logic instruction_translation, input logic data_translation
  );
    @(negedge clk);
    req_kind = kind; req_ea = address; req_spr = spr; req_data = data;
    req_pr = problem; req_ir = instruction_translation; req_dr = data_translation;
    req_valid = 1; rsp_ready = 0;
    #1; check(req_ready, "new request admitted in empty slot");
    @(posedge clk); #1;
    check(rsp_valid && rsp_kind == kind && rsp_ea == address && rsp_spr == spr,
          "accepted request context captured");
    @(negedge clk); req_valid = 0;
  endtask

  task automatic consume;
    @(negedge clk); rsp_ready = 1; req_valid = 0;
    @(posedge clk); #1;
    check(!rsp_valid, "response consumed once");
    @(negedge clk); rsp_ready = 0;
  endtask

  task automatic put(input logic [9:0] spr, input logic [31:0] data, input logic reject);
    send(3'd4, 32'h11223344, spr, data, 0, 0, 0);
    check(!rsp_privileged && !rsp_unsupported && rsp_rejected == reject && rsp_data == 0,
          "CSR write result class");
    if (!reject) check(observed[56:0] == 0, "successful write has no translation result");
    else check(rsp_status[2] && !rsp_status[8], "rejected write gives local config error");
    consume();
  endtask

  task automatic get(input logic [9:0] spr, input logic [31:0] data);
    send(3'd3, 32'h55667788, spr, 32'hffffffff, 0, 1, 1);
    check(rsp_data == data && observed[59:0] == 0, "exact accepted CSR readback");
    consume();
  endtask

  task automatic translated(
    input logic [2:0] kind, input logic [31:0] address, input logic problem,
    input logic [8:0] status, input logic [31:0] physical,
    input logic [3:0] attrs, input logic [1:0] prot,
    input logic [3:0] matched, input logic [1:0] index_value
  );
    send(kind, address, 10'd31, 32'h98765432, problem, 1, 1);
    check(!rsp_privileged && !rsp_unsupported && !rsp_rejected && rsp_data == 0,
          "translation is separate from CSR result");
    check(observed[56:0] == {status, 4'b0, matched, index_value, physical, attrs, prot},
          "literal translation, permissions and bank selection");
    consume();
  endtask


  task automatic prepare(input logic [9:0] selector,input logic[31:0] data,input bit reject);
    send(5,0,selector,data,0,0,0);
    check(rsp_rejected==reject&&!rsp_privileged&&!rsp_unsupported,"prepare result class");
    check(!ack_valid&&!idle,"prepare is not a committed write");
    repeat(3)begin
      @(posedge clk);#1;
      check(rsp_valid&&!req_ready&&!ack_valid,"held prepare response permitted reuse/ack");
    end
    consume();
    check(idle==reject,"successful prepare must retain reservation after response");
  endtask
  task automatic commit_prepared;
    @(negedge clk);prepare_commit=1;
    #1;check(!idle&&!ack_valid,"commit acknowledgment appeared before edge");
    @(posedge clk);#1;prepare_commit=0;
    check(ack_valid&&!idle&&!req_ready,"commit must register held acknowledgment");
    repeat(3)begin @(posedge clk);#1;check(ack_valid&&!idle&&!req_ready,"acknowledgment was lost or allowed reuse");end
    @(negedge clk);ack_ready=1;@(posedge clk);#1;ack_ready=0;
    check(!ack_valid&&idle&&req_ready,"ack did not release transaction");
  endtask
  task automatic abort_prepared;
    @(negedge clk);prepare_abort=1;@(posedge clk);#1;prepare_abort=0;
    check(!ack_valid,"abort fabricated write acknowledgment");
  endtask
  task automatic committed(input logic [9:0] selector,input logic[31:0] data);
    prepare(selector,data,0);commit_prepared();model[selector-528]=data;get(selector,data);
  endtask
  initial begin
    logic[136:0] held_response;
    foreach(model[i])model[i]=0;
    reset_service();
    // Every architectural half has exact readback; prepared values are private
    // and are discarded by abort before any public read can observe them.
    for(int i=0;i<16;i++)begin
      logic[31:0] value;
      value=(32'(i+1)<<17)|(i%2==1?32'd2:0);
      prepare(10'(528+i),value,0);abort_prepared();check(idle,"abort did not release reservation");get(10'(528+i),0);
      committed(10'(528+i),value);
    end
    for(int i=0;i<16;i++)get(10'(528+i),model[i]);
    // Hold response across abort; request/result ownership must drain before reuse.
    send(5,0,528,32'h00800000,0,0,0);held_response=observed;abort_prepared();
    repeat(3)begin @(posedge clk);#1;check(rsp_valid&&observed==held_response&&!idle&&!req_ready,"abort withdrew or changed held response");end
    consume();check(idle,"aborted held response leaked ownership");get(528,model[0]);
    // Cancellation coincident with accepting a new prepare wins over reservation.
    @(negedge clk);prepare_abort=1;
    req_kind=5;req_spr=528;req_data=32'h00800000;req_valid=1;req_pr=0;
    #1;check(req_ready,"abort/prepare handshake unavailable");
    @(posedge clk);#1;req_valid=0;prepare_abort=0;
    check(rsp_valid&&!ack_valid,"same-edge abort lost required response");consume();
    check(idle,"same-edge abort retained proposal");get(528,model[0]);
    // Local rejections do not mutate any bank half.
    prepare(528,32'h00000014,1);get(528,model[0]); // malformed inactive BL
    prepare(528,32'h00002000,1);get(528,model[0]); // reserved upper bit
    prepare(529,32'h00000004,1);get(529,model[1]); // reserved lower bit
    send(5,0,528,0,1,0,0);check(rsp_privileged&&!rsp_rejected,"user prepare must reject privilege");consume();check(idle,"privileged rejection reserved bank");
    send(5,0,527,0,0,0,0);check(rsp_unsupported,"out-of-range prepare selector accepted");consume();
    // Disable/lower/upper staging; active overlap and alignment reject only
    // activation, while safe inactive intermediate addresses remain legal.
    reset_service();foreach(model[i])model[i]=0;
    committed(529,32'h00020002);committed(528,32'h00000002);
    send(0,32'h1000,0,0,0,1,0);check(rsp_status[8]&&rsp_status[6]&&rsp_pa==32'h21000,"committed instruction translation");consume();
    committed(531,32'h00060002);prepare(530,32'h00000002,1);get(530,0);get(528,2);
    committed(528,0);committed(529,32'h00040002);committed(528,32'h00020002);
    send(0,32'h21000,0,0,0,1,0);check(rsp_status[8]&&rsp_pa==32'h41000,"replacement translation used mixed bank halves");consume();
    committed(528,0);committed(529,32'h00020002);prepare(528,32'h0000000e,1);get(528,0);
    // Reset clears proposal/response/ack plus the documented reset-zero bank.
    for(int phase=0;phase<3;phase++)begin
      if(phase==0)send(5,0,528,32'h00080000,0,0,0);
      else begin prepare(528,32'h00080000,0);if(phase==2)begin
        @(negedge clk);prepare_commit=1;@(posedge clk);#1;prepare_commit=0;check(ack_valid,"reset ack fixture");
      end end
      reset_service();check(idle&&!ack_valid,"reset retained transaction state");
      for(int i=0;i<16;i++)get(10'(528+i),0);
    end
    $display("PASS runtime BAT service: %0d checks",checks);$finish;
  end
  initial begin #200000;$fatal(1,"runtime BAT service watchdog");end
endmodule
