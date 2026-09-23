/* verilator lint_off BLKSEQ */
module tb_recovery_storage;
  import ppc_pkg::*;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic clear, push, push_ready, pop, pop_valid;
  logic [7:0] data_in, data_out;
  logic alloc, alloc_ready, wake_valid, recovery, release_slot;
  completion_tag_t release_owner;
  rename_tag_t alloc_tag, first_tag, second_tag;
  logic [4:0] alloc_reg, read_reg;
  completion_tag_t producer;
  wake_packet_t wake;
  operand_t operand_a, operand_b;
  logic [$clog2(CQ_DEPTH+1)-1:0] survivors;
  retire_packet_t packets[CQ_DEPTH];
  completion_tag_t tags[CQ_DEPTH];
  int checks=0;
  ppc_fifo #(.WIDTH(8),.DEPTH(IQ_DEPTH)) fifo (
    .clk_i(clk),.rst_ni(rst_n),.clear_i(clear),.push_valid_i(push),
    .push_ready_o(push_ready),.push_data_i(data_in),.pop_valid_o(pop_valid),
    .pop_ready_i(pop),.pop_data_o(data_out));
  ppc_rename rename_unit (
    .clk_i(clk),.rst_ni(rst_n),.read_a_i(read_reg),.read_b_i(read_reg),
    .arch_a_i(32'habcd),.arch_b_i(32'habcd),.read_a_o(operand_a),.read_b_o(operand_b),
    .alloc_ready_o(alloc_ready),.alloc_tag_o(alloc_tag),.alloc_i(alloc),
    .alloc_reg_i(alloc_reg),.alloc_producer_i(producer),.wake_valid_i(wake_valid),.wake_i(wake),
    .release_i(release_slot),.release_reg_i(5'd4),.release_tag_i(second_tag),
    .release_producer_i(release_owner),.recovery_i(recovery),
    .recovery_survivor_count_i(survivors),.recovery_survivor_packet_i(packets),
    .recovery_survivor_tag_i(tags));
  task automatic check(input logic yes,input string msg);
    if (!yes) $fatal(1,"%s",msg);
    checks++;
  endtask
  task automatic tick;
    @(posedge clk); #1; @(negedge clk);
  endtask
  task automatic check_operand(input logic ready,input logic[31:0] value);
    #1;
    check(operand_a==operand_b && operand_a.ready==ready && operand_a.value==value,
          "rename operand visibility violated");
  endtask
  initial begin
    clear=0;push=0;pop=0;data_in=0;alloc=0;alloc_reg=3;read_reg=3;
    producer='0;wake_valid=0;wake='0;recovery=0;survivors=0;release_slot=0;release_owner='0;second_tag='0;
    foreach(packets[i]) begin packets[i]='0; tags[i]='0; end
    tick(); rst_n=1;
    check(!pop_valid && data_out==0,"reset FIFO must be empty/zero");
    push=1;data_in=8'h11;tick();data_in=8'h22;tick();push=0;
    #1;check(pop_valid && data_out==8'h11,"held FIFO head changed");
    clear=1;push=1;pop=1;data_in=8'hff;
    #1;check(!push_ready && !pop_valid && data_out==8'h11,"clear must withdraw both handshakes");
    tick();clear=0;push=0;pop=0;
    #1;check(!pop_valid && data_out==0,"clear edge retained offered transaction");
    push=1;data_in=8'h33;tick();data_in=8'h44;pop=1;
    #1;check(pop_valid && data_out==8'h33,"concurrent push/pop head wrong");
    tick();push=0;pop=0;
    #1;check(pop_valid && data_out==8'h44,"concurrent push/pop lost replacement");
    pop=1;tick();pop=0;
    #1;check(!pop_valid && data_out==0,"drained FIFO not empty");

    // Surviving exact-owner wake and recovery on the same edge.
    #1;check(alloc_ready,"rename allocation not ready");first_tag=alloc_tag;
    producer=completion_tag_t'(1);alloc=1;tick();alloc=0;
    check_operand(0,0);
    packets[0].gpr_write=1;packets[0].gpr=3;packets[0].tag=first_tag;
    tags[0]=completion_tag_t'(1);survivors=1;
    wake_valid=1;wake.tag=first_tag;wake.producer=completion_tag_t'(1);wake.value=32'h12345678;
    recovery=1;tick();recovery=0;wake_valid=0;
    check_operand(1,32'h12345678);

    // Killed owner's simultaneous wake cannot leak through later slot reuse.
    alloc_reg=4;read_reg=4;producer=completion_tag_t'(2);
    #1;second_tag=alloc_tag;check(alloc_ready,"second allocation not ready");
    alloc=1;tick();alloc=0;check_operand(0,0);
    wake_valid=1;wake.tag=second_tag;wake.producer=completion_tag_t'(2);wake.value=32'hdeadbeef;
    recovery=1;tick();wake_valid=0;recovery=0;
    check_operand(1,32'habcd);
    producer=completion_tag_t'(3);
    #1;check(alloc_ready && alloc_tag==second_tag,"killed slot not reclaimed");
    // The old owner is invalid before this allocation edge: its retained
    // identity must not make a simultaneous stale wake ready the new owner.
    wake_valid=1;alloc=1;tick();alloc=0;wake_valid=0;check_operand(0,0);
    wake_valid=1; // stale owner wake against reused slot
    tick();wake_valid=0;check_operand(0,0);
    wake.producer=completion_tag_t'(3);wake.value=32'hcafebabe;wake_valid=1;
    tick();wake_valid=0;check_operand(1,32'hcafebabe);
    // A stale release must not invalidate a reused slot or its latest map.
    release_slot=1;release_owner=completion_tag_t'(2);tick();release_slot=0;
    check_operand(1,32'hcafebabe);
    // Exact release removes validity; retained owner bits cannot forward a
    // later stale wake into the architectural fallback or a new allocation.
    release_slot=1;release_owner=completion_tag_t'(3);tick();release_slot=0;
    check_operand(1,32'habcd);
    wake_valid=1;tick();wake_valid=0;check_operand(1,32'habcd);
    producer=completion_tag_t'(4);alloc=1;wake_valid=1;tick();alloc=0;wake_valid=0;
    check_operand(0,0);
    wake.producer=completion_tag_t'(4);wake.value=32'h4444aaaa;wake_valid=1;
    tick();wake_valid=0;check_operand(1,32'h4444aaaa);
    read_reg=3;check_operand(1,32'h12345678);
    $display("tb_recovery_storage: PASS (%0d checks)",checks);$finish;
  end
endmodule
