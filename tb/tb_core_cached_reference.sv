// Original-handler trace export through cached CPU and independent physical RAM.
// Bus data is selected solely from pins; core taps only count handshakes/state.
/* verilator lint_off BLKSEQ */
module tb_core_cached_reference;
  import ppc_pkg::*;
`ifdef REFERENCE_CACHE_DISABLED
  localparam bit CACHE_ENABLED = 1'b0;
`else
  localparam bit CACHE_ENABLED = 1'b1;
`endif
`ifdef REFERENCE_MANAGED_CACHE
  logic maintenance_ready, maintenance_done, cache_enabled, maintenance_busy;
`endif
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic tv,tr,halted,redirect_accepted;
  retire_packet_t retired;
  logic [7:0] ram[256];
  logic [31:0] memory[16384];
  logic committed_this_edge=0;
  logic [31:0] architectural_gpr[32];
  logic [127:0] architectural_flags;
  int cycle_count=0,commits=0,words,expected_commits,trace_file;
  int expected_memory_requests,expected_memory_writes;
  int memory_requests=0,memory_writes=0,request_stalls=0,retire_stalls=0;
  int instruction_requests=0,instruction_bursts=0,cache_hits=0,cache_misses=0;
  int bus_beats=0,bus_waits=0,instruction_scalar=0;
  string program_path,trace_path;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,addr_oe;
  logic dbb_n,dbb_oe,d_oe,aack_n,dbg_n,ta_n;
  logic tbst_n,ci_n,wt_n,gbl_n,bus_busy,bus_error,ifetch_error;
  logic icache_hit,icache_miss,icache_busy;
  logic [31:0] bus_addr;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic [63:0] bus_di,bus_do;
  logic address_pending=0,transfer_pending=0,transfer_write=0,transfer_instruction=0,transfer_burst=0;
  logic [31:0] transfer_addr=0;
  int address_delay=0,data_delay=0,transfer_size=0,beat=0;

`ifdef REFERENCE_MANAGED_CACHE
  ppc_core_cached_bus60x_managed #(.RESET_PC(32'b0), .RESET_CACHE_ENABLE(CACHE_ENABLED)) dut (
    .maintenance_valid_i(1'b0), .maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(1'b0), .maintenance_cache_enable_i(CACHE_ENABLED),
    .maintenance_done_valid_o(maintenance_done), .maintenance_done_ready_i(1'b1),
    .cache_enabled_o(cache_enabled), .maintenance_busy_o(maintenance_busy),
`else
  ppc_core_cached_bus60x #(.RESET_PC(32'b0)) dut (
`endif
    .clk_i(clk),.rst_ni(rst_n),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),.redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0),.redirect_target_i('0),.redirect_accepted_o(redirect_accepted),
    .ifetch_error_o(ifetch_error),.bus_protocol_error_o(bus_error),.bus_busy_o(bus_busy),
    .icache_hit_o(icache_hit),.icache_miss_o(icache_miss),.icache_busy_o(icache_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),
    .abb_n_i(abb_oe?abb_n:1'b1),.abb_n_o(abb_n),.abb_oe_o(abb_oe),
    .ts_n_o(ts_n),.ts_oe_o(ts_oe),.a_o(bus_addr),.tt_o(tt),.tbst_n_o(tbst_n),
    .tsiz_o(tsiz),.tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),.artry_n_i(1'b1),
    .dbg_n_i(dbg_n),.dbb_n_i(dbb_oe?dbb_n:1'b1),.dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(bus_di),.d_o(bus_do),.d_oe_o(d_oe),.ta_n_i(ta_n),.drtry_n_i(1'b1),.tea_n_i(1'b1)
  );
  function automatic int slot(input int start,input int n);
    case(start)
      0: case(n) 0:return 0;1:return 1;2:return 2;default:return 3;endcase
      1: case(n) 0:return 1;1:return 2;2:return 3;default:return 0;endcase
      2: case(n) 0:return 2;1:return 3;2:return 0;default:return 1;endcase
      default: case(n) 0:return 3;1:return 0;2:return 1;default:return 2;endcase
    endcase
  endfunction
  assign bg_n=!(rst_n && !br_n && cycle_count%3!=0);
  assign aack_n=!(address_pending && address_delay==0);
  assign dbg_n=!(transfer_pending && !address_pending && cycle_count%4!=1);
  assign ta_n=!(transfer_pending && dbb_oe && !dbb_n && data_delay==0);
  assign tr=rst_n && cycle_count>30 && cycle_count%7!=2 && cycle_count%7!=3;
  always @(negedge clk) cycle_count++;
  always_comb begin
    bus_di='0;
    if(transfer_pending && transfer_instruction && transfer_burst) begin
      bus_di={memory[int'((transfer_addr & 32'hffffffe0)>>2)+2*slot(int'(transfer_addr[4:3]),beat)],
              memory[int'((transfer_addr & 32'hffffffe0)>>2)+2*slot(int'(transfer_addr[4:3]),beat)+1]};
    end else if(transfer_pending && transfer_instruction) begin
      bus_di={memory[int'((transfer_addr & 32'hfffffff8)>>2)],
              memory[int'((transfer_addr & 32'hfffffff8)>>2)+1]};
    end else if(transfer_pending && !transfer_write && transfer_addr>=32'h1000 && transfer_addr<32'h1100)
      for(int lane=0;lane<8;lane++)
        bus_di[63-8*lane -:8]=ram[int'((transfer_addr & 32'hfffffff8)-32'h1000)+lane];
  end
  always @(posedge clk) begin
    if(!rst_n) begin
      address_pending<=0;transfer_pending<=0;address_delay<=0;data_delay<=0;beat<=0;
    end else begin
      assert(!bus_error && !ifetch_error && !halted && !redirect_accepted)
        else $fatal(1,"cached reference transport/core diagnostic");
      if((!br_n && bg_n) || (address_pending && address_delay>0) ||
         (transfer_pending && data_delay>0)) bus_waits++;
      if(icache_hit) cache_hits++;
      if(icache_miss) cache_misses++;
      if(dut.core.imem_req_valid_o && dut.core.imem_req_ready_i) instruction_requests++;
      if(dut.core.imem_req_valid_o && !dut.core.imem_req_ready_i) request_stalls++;
      if(tv && !tr) retire_stalls++;
      if(address_delay>0) address_delay<=address_delay-1;
      if(data_delay>0 && dbb_oe && !dbb_n) data_delay<=data_delay-1;
      if(!aack_n) address_pending<=0;
      if(ts_oe && !ts_n) begin
        assert(addr_oe && abb_oe && !abb_n && !transfer_pending)
          else $fatal(1,"overlapping physical transaction");
        assert(gbl_n && wt_n && cse==0) else $fatal(1,"unexpected memory attributes");
        if(tc==2 && !tbst_n) begin
          assert(CACHE_ENABLED && !tbst_n && ci_n && tt==5'b01110 && tsiz==2 && bus_addr[2:0]==0 && bus_addr<65536)
            else $fatal(1,"instruction request is not cacheable 4-beat burst");
          instruction_bursts++;
        end else if(tc==2) begin
          assert(!CACHE_ENABLED && tbst_n && !ci_n && tt==5'b01010 && tsiz==4 && bus_addr[1:0]==0 && bus_addr<65536)
            else $fatal(1,"invalid uncached scalar instruction transaction");
          instruction_scalar++;
        end else begin
          assert(tc==0 && tbst_n && !ci_n && (tt==5'b01010 || tt==5'b00010) &&
                 (tsiz==1 || tsiz==2 || tsiz==4) && bus_addr>=32'h1000 && bus_addr+32'(tsiz)<=32'h1100)
            else $fatal(1,"invalid scalar data transaction");
          memory_requests++;
        end
        address_pending<=1;transfer_pending<=1;address_delay<=1+cycle_count%3;
        data_delay<=2+cycle_count%4;transfer_addr<=bus_addr;transfer_write<=tt==5'b00010;
        transfer_instruction<=tc==2;transfer_burst<=!tbst_n;transfer_size<=int'(tsiz);beat<=0;
      end
      if(!ta_n) begin
        bus_beats++;
        if(transfer_write) begin
          assert(d_oe) else $fatal(1,"write without output enable");
          memory_writes++;
          for(int byte_index=0;byte_index<4;byte_index++)
            if(byte_index<transfer_size)
              ram[int'(transfer_addr-32'h1000)+byte_index] <= bus_do[63-8*(int'(transfer_addr[2:0])+byte_index) -:8];
        end else assert(!d_oe) else $fatal(1,"read drives data pins");
        if(transfer_burst && beat<3) begin
          beat<=beat+1;data_delay<=cycle_count%3;
        end else transfer_pending<=0;
      end
    end
  end
  logic unused_diagnostics;
`ifdef REFERENCE_MANAGED_CACHE
  assign unused_diagnostics=^{bus_busy,icache_busy,maintenance_ready};
  assert property (@(posedge clk) disable iff(!rst_n)
    cache_enabled == CACHE_ENABLED && !maintenance_done && !maintenance_busy);
`else
  assign unused_diagnostics=^{bus_busy,icache_busy};
`endif
  always @(posedge clk) begin
    committed_this_edge=rst_n && tv && tr;
    if(committed_this_edge) begin
      assert(!retired.illegal && !$isunknown(retired)) else $fatal(1,"illegal/unknown cached retirement");
      $fwrite(trace_file,"%08x %08x ",retired.pc,retired.insn);
      #1;
      for(int r=0;r<32;r++) $fwrite(trace_file,"%08x ",dut.core.regfile.gpr[r]);
      $fwrite(trace_file,"%08x %08x %08x %08x ",dut.core.cr,dut.core.xer,dut.core.lr,dut.core.ctr);
      for(int offset=0;offset<256;offset+=4)
        $fwrite(trace_file,"%08x ",{ram[offset],ram[offset+1],ram[offset+2],ram[offset+3]});
      $fwrite(trace_file,"\n");commits++;
      if(commits==expected_commits) begin
        assert(memory_requests==expected_memory_requests && memory_writes==expected_memory_writes)
          else $fatal(1,"cached physical memory access count mismatch");
        $display("COVERAGE hits=%0d misses=%0d bursts=%0d requests=%0d request_stalls=%0d retire_stalls=%0d",cache_hits,cache_misses,instruction_bursts,instruction_requests,request_stalls,retire_stalls);
        if(CACHE_ENABLED) begin
        assert(instruction_scalar==0 && cache_hits>0 && cache_misses>0 && instruction_bursts<instruction_requests &&
               instruction_bursts<=cache_misses && cache_misses<=instruction_bursts+1 && bus_waits>0 && retire_stalls>0)
          else $fatal(1,"missing cache savings/backpressure coverage");
        end else begin
          assert(cache_hits==0 && cache_misses==0 && instruction_bursts==0 &&
                 instruction_scalar>0 && instruction_scalar<=instruction_requests &&
                 instruction_requests<=instruction_scalar+1 && bus_waits>0 && retire_stalls>0)
            else $fatal(1,"missing uncached scalar/backpressure coverage");
        end
        $fclose(trace_file);
        $display("PASS cached reference RTL: retire=%0d instruction_requests=%0d bursts=%0d hits=%0d misses=%0d data=%0d stores=%0d beats=%0d waits=%0d instruction_scalar=%0d",commits,instruction_requests,instruction_bursts,cache_hits,cache_misses,memory_requests,memory_writes,bus_beats,bus_waits,instruction_scalar);
        $finish;
      end
    end
  end
  // Every architectural register must change only at an accepted retirement.
  // RAM may change earlier at a reserved store request, per the core contract.
  always @(negedge clk) begin
    if (!rst_n) begin
      for (int r=0;r<32;r++) architectural_gpr[r] = 0;
      architectural_flags = 0;
    end else if (committed_this_edge) begin
      for (int r=0;r<32;r++) architectural_gpr[r] = dut.core.regfile.gpr[r];
      architectural_flags = {dut.core.cr,dut.core.xer,dut.core.lr,dut.core.ctr};
    end else begin
      for (int r=0;r<32;r++)
        assert (architectural_gpr[r] == dut.core.regfile.gpr[r]) else $fatal(1,"GPR changed before retirement");
      assert (architectural_flags == {dut.core.cr,dut.core.xer,dut.core.lr,dut.core.ctr}) else $fatal(1,"flags/SPR changed before retirement");
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    tv && !tr |=> tv && $stable(retired));
  initial begin
    assert ($value$plusargs("PROGRAM=%s", program_path) &&
            $value$plusargs("TRACE=%s", trace_path) &&
            $value$plusargs("WORDS=%d", words) &&
            $value$plusargs("COMMITS=%d", expected_commits) &&
            $value$plusargs("MEMORY_REQUESTS=%d", expected_memory_requests) &&
            $value$plusargs("MEMORY_WRITES=%d", expected_memory_writes))
      else $fatal(1, "missing reference runner arguments");
    assert (words > 0 && words <= 16384 && expected_commits > 0)
      else $fatal(1, "invalid reference runner limits");
    for (int i = 0; i < 256; i++) ram[i] = 0;
    for (int i = 0; i < 16384; i++) memory[i] = 0;
    $readmemh(program_path, memory, 0, words - 1);
    trace_file = $fopen(trace_path, "w");
    assert (trace_file != 0) else $fatal(1, "cannot open reference RTL trace");
    $fwrite(trace_file, "#ppc-reference-v2 ram_base=00001000 ram_bytes=00000100\n");
    repeat (3) @(negedge clk);
    rst_n = 1;
  end
  initial begin
    #5000000;
    $fatal(1, "reference RTL watchdog");
  end
endmodule
