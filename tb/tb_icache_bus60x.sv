// Independent pin-level line consumer. No shared BFM or DUT state references.
/* verilator lint_off BLKSEQ */
module tb_icache_bus60x;
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

  logic fv,fr,fsv,fsr,fse,kill,invalidate,invalidate_done;
  logic [31:0] fa,insn;
  logic cache_busy,hit,miss,cache_error;
  ppc_icache cache (
    .clk_i(clk),.rst_ni(rst_n),.fetch_valid_i(fv),.fetch_ready_o(fr),.fetch_addr_i(fa),
    .fetch_rsp_valid_o(fsv),.fetch_rsp_ready_i(fsr),.fetch_rsp_insn_o(insn),
    .fetch_rsp_error_o(fse),.kill_i(kill),.invalidate_i(invalidate),
    .invalidate_done_o(invalidate_done),.line_req_valid_o(qv),.line_req_ready_i(qr),
    .line_req_line_addr_o(line_addr),.line_req_critical_dw_o(critical),.line_req_instruction_o(qi),
    .line_rsp_valid_i(rv),.line_rsp_ready_o(rr),.line_rsp_line_i(line_data),
    .line_rsp_error_i(error),.busy_o(cache_busy),.hit_o(hit),.miss_o(miss),
    .protocol_error_o(cache_error)
  );
  ppc_bus60x_line_read bus (
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

  always @(posedge clk) if(rst_n) begin
    check(!d_oe && dout==0,"read master drove data");
    check(!protocol_error && !cache_error,"unexpected protocol diagnostic");
    check(!(hit && miss),"simultaneous hit and miss");
    if(invalidate_done) check(!fsv,"invalidation retained fetch response");
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

  function automatic logic [31:0] expected_word(input logic [31:0] addr);
    logic [63:0] dw;
    if(addr[1:0]!=0) $fatal(1,"unaligned expected instruction");
    dw=ram_dw({addr[31:5],5'b0},int'(addr[4:3]));
    return addr[2] ? dw[31:0] : dw[63:32];
  endfunction
  task automatic reset_all;
    @(negedge clk);rst_n=0;fv=0;fsr=0;kill=0;invalidate=0;fa=0;
    bg_n=1;aack_n=1;artry_n=1;dbg_n=1;ta_n=1;drtry_n=1;tea_n=1;di=0;
    wanted_base=0;wanted_critical=0;wanted_instruction=1;
    repeat(3) @(negedge clk);
    rst_n=1;
  endtask
  task automatic fetch_request(input logic [31:0] addr);
    @(negedge clk);
    while(!fr) @(negedge clk);
    wanted_base={addr[31:5],5'b0};wanted_critical=addr[4:3];
    fv=1;fa=addr;
    @(posedge clk);#1;
    @(negedge clk);fv=0;fa=32'hffff_fffc;
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
  task automatic fill(input logic [31:0] addr);
    check(addr[2:0]==3'b000 || addr[2:0]==3'b100,"aligned fill address");
    address_phase(0);data_grant();
    for(int beat=0;beat<4;beat++) begin
      cycle(1,0,0,ram_dw({addr[31:5],5'b0},order(int'(addr[4:3]),beat)));
      check(!fsv,"fetch escaped before full-line confirmation");
    end
    cycle(0,0,0,0);
  endtask
  task automatic fetch_response(input logic [31:0] addr,input logic failed);
    while(!fsv) begin @(posedge clk);#1;end
    check(fse==failed,"fetch error mismatch");
    if(!failed) check(insn==expected_word(addr),"wrong big-endian instruction word");
    repeat(3) begin
      @(posedge clk);#1;
      check(fsv && fse==failed,"held fetch response lost");
      if(!failed) check(insn==expected_word(addr),"held instruction changed");
    end
    @(negedge clk);fsr=1;
    @(posedge clk);#1;responses++;
    @(negedge clk);fsr=0;
  endtask
  task automatic miss_fetch(input logic [31:0] addr);
    int before_addresses;
    before_addresses=addresses;
    fetch_request(addr);fill(addr);fetch_response(addr,0);
    check(addresses==before_addresses+1,"miss did not produce exactly one burst");
  endtask
  task automatic hit_fetch(input logic [31:0] addr);
    int before_addresses;
    before_addresses=addresses;
    fetch_request(addr);fetch_response(addr,0);
    check(addresses==before_addresses,"cache hit accessed external bus");
  endtask
  task automatic drain_killed;
    repeat(12) begin @(posedge clk);#1;check(!fsv,"killed refill returned fetch");end
    check(!cache_busy && !busy,"killed refill did not drain");
  endtask
  initial begin
    reset_all();
    // Every word position can trigger a miss, then all eight positions hit.
    for(int word=0;word<8;word++) begin
      miss_fetch(32'h2000+32'(word*32+word*4));
      for(int lane=0;lane<8;lane++) hit_fetch(32'h2000+32'(word*32+lane*4));
    end
    // Same-set conflicts exercise storage tags and strict LRU through pins.
    miss_fetch(32'h4000);miss_fetch(32'h5000);miss_fetch(32'h6000);miss_fetch(32'h7000);
    hit_fetch(32'h4000);miss_fetch(32'h8000);
    hit_fetch(32'h6000);hit_fetch(32'h7000);hit_fetch(32'h4000);
    miss_fetch(32'h5000);
    // Kill after a physical address was accepted: finish bus tenure, discard line.
    fetch_request(32'h9014);address_phase(0);data_grant();
    cycle(1,0,0,ram_dw(32'h9000,2));
    @(negedge clk);kill=1;ta_n=1;
    @(negedge clk);kill=0;
    for(int beat=1;beat<4;beat++) cycle(1,0,0,ram_dw(32'h9000,order(2,beat)));
    cycle(0,0,0,0);drain_killed();miss_fetch(32'h9014);
    // Invalidate during an accepted refill likewise prevents installation.
    fetch_request(32'ha008);address_phase(0);data_grant();
    @(negedge clk);invalidate=1;
    @(negedge clk);invalidate=0;
    for(int beat=0;beat<4;beat++) cycle(1,0,0,ram_dw(32'ha000,order(1,beat)));
    cycle(0,0,0,0);drain_killed();miss_fetch(32'ha008);
    // A failed bus fill must become a fetch error and cannot poison a later hit.
    fetch_request(32'hb01c);address_phase(0);data_grant();
    cycle(1,0,0,ram_dw(32'hb000,3));cycle(0,0,1,0);cycle(0,0,0,0);
    fetch_response(32'hb01c,1);miss_fetch(32'hb01c);hit_fetch(32'hb000);
    // Kill and ready together cannot accept a stale held hit.
    fetch_request(32'hb008);
    while(!fsv) begin @(posedge clk);#1;end
    @(negedge clk);kill=1;fsr=1;#1;
    check(!fsv,"kill edge exposed stale response to ready consumer");
    @(negedge clk);kill=0;fsr=0;
    hit_fetch(32'hb008);
    // A held hit is dropped by invalidation; the next fetch must refill.
    fetch_request(32'hb004);
    while(!fsv) begin @(posedge clk);#1;end
    @(negedge clk);invalidate=1;fsr=1;#1;
    check(!fsv,"invalidate edge exposed stale response to ready consumer");
    @(negedge clk);invalidate=0;fsr=0;
    repeat(3) begin @(posedge clk);#1;check(!fsv,"invalidate kept held hit");end
    miss_fetch(32'hb004);
    $display("PASS cache + physical burst: %0d checks, %0d fetch responses, %0d bursts",checks,responses,addresses);
    $finish;
  end
  initial begin #200000; $fatal(1,"cache/bus watchdog");end
endmodule
/* verilator lint_on BLKSEQ */
