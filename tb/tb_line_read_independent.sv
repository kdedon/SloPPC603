// Independent pin-level line consumer. No shared BFM or DUT state references.
/* verilator lint_off BLKSEQ */
module tb_line_read_independent;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic qv, qr, qi, rv, rr, error, busy, protocol_error;
  logic [31:0] line_addr;
  logic [1:0] critical;
  logic [255:0] line_data;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,addr_oe;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,d_oe,ta_n,drtry_n,tea_n;
  logic [31:0] a;
  logic [4:0] tt;
  logic [2:0] size;
  logic [1:0] tc,cse;
  logic tbst_n,ci_n,wt_n,gbl_n;
  logic [63:0] di,dout;
  int checks=0, responses=0, addresses=0;
  logic [31:0] wanted_base;
  logic [1:0] wanted_critical;
  logic wanted_instruction;

  ppc_bus60x_line_read dut (
    .clk_i(clk),.rst_ni(rst_n),
    .req_valid_i(qv),.req_ready_o(qr),.req_line_addr_i(line_addr),
    .req_critical_dw_i(critical),.req_instruction_i(qi),
    .rsp_valid_o(rv),.rsp_ready_i(rr),.rsp_line_o(line_data),.rsp_error_o(error),
    .busy_o(busy),.protocol_error_o(protocol_error),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(abb_oe ? abb_n : 1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(size),.tc_o(tc),
    .ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),.cse_o(cse),.addr_oe_o(addr_oe),
    .aack_n_i(aack_n),.artry_n_i(artry_n),.dbg_n_i(dbg_n),
    .dbb_n_i(dbb_oe ? dbb_n : 1'b1),.dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(di),.d_o(dout),.d_oe_o(d_oe),.ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n)
  );

  task automatic check(input logic ok,input string why);
    checks++;
    assert(ok) else $fatal(1,"%s checks=%0d responses=%0d",why,checks,responses);
  endtask
  function automatic logic [63:0] ram_dw(input logic [31:0] base,input int dw);
    logic [31:0] address;
    address=base+32'(8*dw);
    return {32'h13579bdf ^ address,32'h2468ace0 + address};
  endfunction
  // Literal UM Table8-2 columns; independent of the DUT's beat arithmetic.
  function automatic int order(input int start,input int beat);
    case(start)
      0: case(beat) 0:return 0; 1:return 1; 2:return 2; default:return 3; endcase
      1: case(beat) 0:return 1; 1:return 2; 2:return 3; default:return 0; endcase
      2: case(beat) 0:return 2; 1:return 3; 2:return 0; default:return 1; endcase
      default: case(beat) 0:return 3; 1:return 0; 2:return 1; default:return 2; endcase
    endcase
  endfunction
  function automatic logic [255:0] expected_line(input logic [31:0] base);
    return {ram_dw(base,0),ram_dw(base,1),ram_dw(base,2),ram_dw(base,3)};
  endfunction

  always @(posedge clk) if(rst_n) begin
    check(!d_oe && dout==0,"read master drove data");
    if(ts_oe && !ts_n) begin
      addresses++;
      check(addr_oe && abb_oe && !abb_n,"TS missing address ownership");
      check(a==wanted_base+32'(8*int'(wanted_critical)),"critical address mismatch");
      check(tt==5'b01110 && !tbst_n && size==3'b010,"not a real four-beat burst read");
      check(ci_n && wt_n && gbl_n && cse==0,"unexpected cacheable profile");
      check(tc==(wanted_instruction ? 2'b10 : 2'b00),"instruction/data attribute changed");
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    rv && !rr |=> rv && $stable({line_data,error}));

  task automatic reset_bus;
    @(negedge clk);
    rst_n=0; qv=0; rr=0; bg_n=1; aack_n=1; artry_n=1;
    dbg_n=1; ta_n=1; drtry_n=1; tea_n=1; di=0;
    line_addr=0;critical=0;qi=0;
    repeat(3) @(negedge clk);
    check(!rv && !busy && !abb_oe && !dbb_oe,"reset retained bus work");
    rst_n=1;
  endtask
  task automatic request(input logic [31:0] base,input int start,input logic insn);
    @(negedge clk);
    check(start>=0 && start<4,"invalid test critical doubleword");
    wanted_base=base;wanted_critical=2'(start);wanted_instruction=insn;
    qv=1;line_addr=base;critical=2'(start);qi=insn;
    do @(posedge clk); while(!qr);
    @(negedge clk);qv=0;
    // Changes after acceptance must not change pins or response ownership.
    line_addr=32'hffffffe0;critical=~critical;qi=~qi;
  endtask
  task automatic address_phase(input logic retry_request);
    @(negedge clk);
    while(br_n) @(negedge clk);
    bg_n=0;
    while(!(ts_oe && !ts_n)) @(negedge clk);
    @(negedge clk);bg_n=1;
    repeat(2) @(negedge clk);
    aack_n=0;
    @(negedge clk);aack_n=1;artry_n=!retry_request;
    @(negedge clk);artry_n=1;
  endtask
  task automatic data_grant;
    @(negedge clk);dbg_n=0;
    while(!(dbb_oe && !dbb_n)) @(negedge clk);
    @(negedge clk);dbg_n=1;
  endtask
  task automatic cycle(input logic ack,input logic retry_data,input logic fail,input logic [63:0] data);
    @(negedge clk);ta_n=!ack;drtry_n=!retry_data;tea_n=!fail;di=data;
    @(posedge clk);#1;
  endtask
  task automatic response(input logic failed,input logic [255:0] expected);
    while(!rv) begin @(posedge clk);#1; end
    check(error==failed,"wrong line error status");
    check(line_data==expected,"canonical line contains bad/retried/partial data");
    repeat(3) begin
      @(posedge clk);#1;
      check(rv && !qr && line_data==expected && error==failed,"held line changed or admitted overlap");
    end
    @(negedge clk);rr=1;
    @(posedge clk);#1;responses++;
    @(negedge clk);rr=0;
  endtask
  task automatic normal_line(input logic [31:0] base,input int start,input logic insn,input logic address_retry);
    request(base,start,insn);
    address_phase(address_retry);
    if(address_retry) begin
      check(!dbb_oe && !rv,"retried address started data or response");
      address_phase(0);
    end
    data_grant();
    for(int beat=0;beat<4;beat++) begin
      cycle(1,0,0,ram_dw(base,order(start,beat)));
      check(!rv,"line escaped before final confirmation");
    end
    cycle(0,0,0,0);
    response(0,expected_line(base));
  endtask

  initial begin
    reset_bus();
    for(int start=0;start<4;start++) begin
      normal_line(32'h2000+32'(start*32),start,0,0);
      normal_line(32'h3000+32'(start*32),start,1,start==2);
    end

    // A third beat is poisoned, replaced on its DRTRY edge, then followed by
    // the fourth beat without a bubble. Earlier confirmed data must survive.
    request(32'h4000,3,0);address_phase(0);data_grant();
    cycle(1,0,0,ram_dw(32'h4000,3));
    cycle(0,0,0,0);
    cycle(0,0,0,0);
    cycle(1,0,0,ram_dw(32'h4000,0));
    cycle(1,0,0,64'hbad0bad1bad2bad3);
    cycle(1,1,0,ram_dw(32'h4000,1));
    check(!rv,"retried third beat completed line");
    cycle(1,0,0,ram_dw(32'h4000,2));
    cycle(0,0,0,0);response(0,expected_line(32'h4000));

    // Final-beat retry extends past DBB release; replacement chains still
    // target DW0 for a start-at-DW1 line, never advance to another line.
    request(32'h5000,1,1);address_phase(0);data_grant();
    for(int beat=0;beat<3;beat++) cycle(1,0,0,ram_dw(32'h5000,order(1,beat)));
    cycle(1,0,0,64'hbad0bad1bad2bad3);
    cycle(0,1,0,0);check(!rv,"final retry escaped as valid response");
    cycle(0,1,0,0);check(!dbb_oe,"extended final retry reacquired DBB");
    cycle(1,1,0,64'h1111222233334444);
    cycle(1,1,0,ram_dw(32'h5000,0));
    cycle(0,0,0,0);response(0,expected_line(32'h5000));

    // A nonrecoverable middle-beat error returns no successful partial line.
    request(32'h6000,2,0);address_phase(0);data_grant();
    cycle(1,0,0,ram_dw(32'h6000,2));
    cycle(1,0,0,ram_dw(32'h6000,3));
    cycle(1,0,1,ram_dw(32'h6000,0));
    cycle(0,0,0,0);response(1,256'b0);
    check(!protocol_error,"ordinary TEA misclassified as malformed protocol");

    // Final confirmation also remains error-sensitive after DBB release.
    request(32'h7000,0,1);address_phase(0);data_grant();
    for(int beat=0;beat<4;beat++) cycle(1,0,0,ram_dw(32'h7000,beat));
    cycle(0,0,1,0);cycle(0,0,0,0);response(1,256'b0);
    check(!protocol_error,"late TEA misclassified as malformed protocol");

    // TA outside this completed data tenure cannot create a fictitious fifth
    // beat or invalidate the final candidate that DRTRY has confirmed.
    request(32'h7800,3,0);address_phase(0);data_grant();
    for(int beat=0;beat<4;beat++) cycle(1,0,0,ram_dw(32'h7800,order(3,beat)));
    cycle(1,0,0,64'hdeadbeefcafebabe);
    cycle(0,0,0,0);response(0,expected_line(32'h7800));
    check(!protocol_error,"unowned TA poisoned the completed line");

    request(32'h8000,0,0);address_phase(0);data_grant();
    cycle(1,0,0,ram_dw(32'h8000,0));
    reset_bus();
    repeat(8) begin @(posedge clk);#1;check(!rv,"reset allowed stale partial line"); end
    normal_line(32'h9000,2,1,0);
    check(responses==14,"missing line scenarios");
    $display("PASS independent line read: %0d checks, %0d responses, %0d addresses",checks,responses,addresses);
    $finish;
  end
  initial begin #200000; $fatal(1,"independent line read watchdog"); end
endmodule
