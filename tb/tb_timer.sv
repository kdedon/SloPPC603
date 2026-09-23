// Literal architectural/collision anchors, independent of implementation helpers.
/* verilator lint_off BLKSEQ */
module tb_timer;
  logic clk=0,rst_n=0,tick=0,tben=0,write_valid=0,accept=0;
  logic [9:0] spr=0;
  logic [31:0] value=0,dec;
  logic [63:0] tb;
  logic pending;
  int checks=0;
  always #5 clk=~clk;
  ppc_timer dut(.clk_i(clk),.rst_ni(rst_n),.timer_tick_i(tick),
    .timebase_enable_i(tben),.write_valid_i(write_valid),.write_spr_i(spr),
    .write_value_i(value),.decrementer_accept_i(accept),
    .timebase_o(tb),.decrementer_o(dec),.decrementer_pending_o(pending));
  task automatic check(input bit ok,input string why);
    checks++;if(!ok)$fatal(1,"timer check%0d: %s TB=%h DEC=%h P=%b",checks,why,tb,dec,pending);
  endtask
  task automatic step(input bit do_tick,en,wr,input logic[9:0] selector,
                      input logic[31:0] data,input bit ack,
                      input logic[63:0] expected_tb,input logic[31:0] expected_dec,
                      input bit expected_pending);
    logic[63:0] old_tb;
    logic[31:0] old_dec;
    @(negedge clk);
    old_tb=tb;old_dec=dec;
    tick=do_tick;tben=en;write_valid=wr;spr=10'(selector);value=data;accept=ack;
    #1;check(tb==old_tb&&dec==old_dec,"writes/ticks do not change pre-edge read data");
    @(posedge clk);#1;
    check(tb==expected_tb,"TB anchor");check(dec==expected_dec,"DEC anchor");
    check(pending==expected_pending,"pending/coalescing anchor");
  endtask
  initial begin
    // Reset dominates tick, write, and even an otherwise-invalid acknowledgment.
    tick=1;tben=1;write_valid=1;spr=22;value=0;accept=1;
    repeat(2)@(posedge clk);#1;
    check(tb==0&&dec==32'hffffffff&&!pending,"reset is not a sign transition");
    @(negedge clk);tick=0;write_valid=0;accept=0;rst_n=1;
    if ($test$plusargs("NEGATIVE_WRITE") || $test$plusargs("NEGATIVE_ACK")) begin
      write_valid=$test$plusargs("NEGATIVE_WRITE");spr=10'd23;
      accept=$test$plusargs("NEGATIVE_ACK");
      @(posedge clk);#1;$fatal(1,"negative timer contract test did not assert");
    end
    step(0,0,0,0,0,0,64'h0,32'hffffffff,0);
    for(int n=1;n<=4;n++)
      step(1,1,0,0,0,0,64'(n),32'hffffffff-32'(n),0);
    step(1,1,1,285,32'h11223344,0,64'h1122334400000004,32'hfffffffa,0);
    step(1,1,1,284,32'hffffffff,0,64'h11223344ffffffff,32'hfffffff9,0);
    step(1,1,0,0,0,0,64'h1122334500000000,32'hfffffff8,0);
    step(1,0,0,0,0,0,64'h1122334500000000,32'hfffffff7,0);
    step(0,1,0,0,0,0,64'h1122334500000000,32'hfffffff7,0);
    step(1,1,1,22,0,0,64'h1122334500000001,32'h0,0);
    step(1,1,0,0,0,0,64'h1122334500000002,32'hffffffff,1);
    step(1,1,0,0,0,0,64'h1122334500000003,32'hfffffffe,1);
    step(1,1,1,22,32'h80000000,0,64'h1122334500000004,32'h80000000,1);
    step(0,1,1,22,4,0,64'h1122334500000004,32'h4,1);
    // Old pending survives positive writes; acknowledge beats a new write edge.
    step(1,1,1,22,32'h80000001,1,64'h1122334500000005,32'h80000001,0);
    step(0,1,1,22,32'h80000002,0,64'h1122334500000005,32'h80000002,0);
    step(0,1,1,22,0,0,64'h1122334500000005,32'h0,0);
    step(1,1,0,0,0,0,64'h1122334500000006,32'hffffffff,1);
    step(0,1,1,22,0,0,64'h1122334500000006,32'h0,1);
    step(1,1,0,0,0,1,64'h1122334500000007,32'hffffffff,0);
    // Running-counter recommended three-write sequence, with intervening ticks.
    step(1,1,1,284,0,0,64'h1122334500000000,32'hfffffffe,0);
    step(1,1,0,0,0,0,64'h1122334500000001,32'hfffffffd,0);
    step(1,1,1,285,32'haabbccdd,0,64'haabbccdd00000001,32'hfffffffc,0);
    step(1,1,0,0,0,0,64'haabbccdd00000002,32'hfffffffb,0);
    step(1,1,1,284,32'h12345678,0,64'haabbccdd12345678,32'hfffffffa,0);
    // TB wraps modulo64; disabled TB still accepts software half writes.
    step(0,0,1,285,32'hffffffff,0,64'hffffffff12345678,32'hfffffffa,0);
    step(0,0,1,284,32'hffffffff,0,64'hffffffffffffffff,32'hfffffffa,0);
    step(1,1,0,0,0,0,64'h0,32'hfffffff9,0);
    // A software-only positive-to-negative transition requests DEC.
    step(0,0,1,22,32'h7fffffff,0,64'h0,32'h7fffffff,0);
    step(0,0,1,22,32'h80000000,0,64'h0,32'h80000000,1);
    for(int n=1;n<=16;n++)
      step(0,0,0,0,0,0,64'h0,32'h80000000,1);
    step(1,0,0,0,0,0,64'h0,32'h7fffffff,1);
    step(0,0,1,22,32'hffffffff,0,64'h0,32'hffffffff,1);
    step(0,0,0,0,0,1,64'h0,32'hffffffff,0);
    // A later transition, strictly after acknowledge, creates another request.
    step(0,0,1,22,0,0,64'h0,32'h0,0);
    step(0,0,1,22,32'h80000000,0,64'h0,32'h80000000,1);
    @(negedge clk);rst_n=0;tick=1;write_valid=1;spr=285;value='1;accept=1;
    @(posedge clk);#1;check(tb==0&&dec==32'hffffffff&&!pending,"reset clears active pending and writes");
    $display("PASS timer unit: %0d checks",checks);$finish;
  end
endmodule
