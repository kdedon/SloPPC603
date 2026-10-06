// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Full retirement trace for whole-machine reference comparison, included in a
// bench module body after `define MT_CORE <ppc_core instance path>,
// `define MT_BAT <ppc_core_bat instance path> and `define MT_CLK <clock>.
// +RETIRE_TRACE=<file> writes one line per retirement edge:
//   <pc> <insn> <count> <fault> [name=value ...] [st=addr,strobe,data ...]
// count is 2 when CQ[1] retires beside the head. rb=<n0>,<n1>, when either is
// nonzero, counts branches removed at dispatch (no record of their own) just
// before the head and just before CQ[1]. Registers appear when they
// differ from the previous line; r0-r31 exclude the TGPRs, t0-t3. st lists
// physical stores accepted since the previous line, strobe bit 3 being the
// byte at addr; cache operations such as dcbz are not listed.
int mt_fd = 0;
logic [31:0] mt_prev [49];
logic mt_first = 1'b1;
string mt_stores = "";
int mt_removed = 0;

function automatic logic [31:0] mt_value(input int i);
  if (i < 32)
    return (`MT_CORE.update_pending_q && i == int'(`MT_CORE.update_reg_q)) ?
           `MT_CORE.update_value_q : `MT_CORE.regfile.gpr[i];
  case (i)
    32: return `MT_CORE.cr;
    33: return `MT_CORE.xer;
    34: return `MT_CORE.lr;
    35: return `MT_CORE.ctr;
    36: return `MT_CORE.msr;
    37: return `MT_CORE.srr0;
    38: return `MT_CORE.srr1;
    39: return `MT_CORE.special.dar_q;
    40: return `MT_CORE.special.dsisr_q;
    41: return `MT_CORE.special.sprg_q[0];
    42: return `MT_CORE.special.sprg_q[1];
    43: return `MT_CORE.special.sprg_q[2];
    44: return `MT_CORE.special.sprg_q[3];
    45, 46, 47, 48: return `MT_CORE.regfile.tgpr_enabled.tgpr[i - 45];
    default: return '0;
  endcase
endfunction

function automatic string mt_name(input int i);
  string names [17] = '{"cr", "xer", "lr", "ctr", "msr", "srr0", "srr1", "dar",
                        "dsisr", "sprg0", "sprg1", "sprg2", "sprg3", "t0", "t1", "t2", "t3"};
  return i < 32 ? $sformatf("r%0d", i) : names[i - 32];
endfunction

initial begin
  string path;
  if ($value$plusargs("RETIRE_TRACE=%s", path)) begin
    mt_fd = $fopen(path, "w");
    if (mt_fd == 0) $fatal(1, "cannot open RETIRE_TRACE %s", path);
  end
end

// A store retires after its request is accepted, so a store seen on a
// retirement edge belongs to a later line.
always @(posedge `MT_CLK) begin
  automatic string store = "";
  if (mt_fd != 0 && `MT_BAT.pdmem_req_valid_o && `MT_BAT.pdmem_req_ready_i &&
      `MT_BAT.pdmem_req_write_o && (|`MT_BAT.pdmem_req_wstrb_o) &&
      `MT_BAT.pdmem_req_attr_o.kind != ppc_pkg::DMEM_CACHE) begin
    // A doubleword store fills all eight lanes, its high word at the address.
    automatic logic [63:0] wdata = 64'(`MT_BAT.pdmem_req_wdata_o);
    automatic logic [7:0] wstrb = 8'(`MT_BAT.pdmem_req_wstrb_o);
    if (|wstrb[7:4])
      store = $sformatf(" st=%08x,%0x,%08x st=%08x,%0x,%08x", `MT_BAT.pdmem_req_addr_o,
                        wstrb[7:4], wdata[63:32], `MT_BAT.pdmem_req_addr_o + 32'd4,
                        wstrb[3:0], wdata[31:0]);
    else
      store = $sformatf(" st=%08x,%0x,%08x", `MT_BAT.pdmem_req_addr_o, wstrb[3:0], wdata[31:0]);
  end
  if (mt_fd != 0 && `MT_CORE.rst_ni && `MT_CORE.retire_valid_o && `MT_CORE.retire_ready_i &&
      `MT_CORE.retire_o.seq_partial)
    mt_removed += int'(`MT_CORE.retire_o.removed_branches);
  if (mt_fd != 0 && `MT_CORE.rst_ni && `MT_CORE.retire_valid_o && `MT_CORE.retire_ready_i &&
      !`MT_CORE.retire_o.seq_partial) begin
    automatic int count = 1 + int'(`MT_CORE.commit1);
    automatic logic fault = `MT_CORE.retire_o.illegal || `MT_CORE.retire_o.alignment_exception ||
                            (`MT_CORE.retire_o.data_fault != ppc_pkg::DATA_OK) ||
                            (`MT_CORE.retire_o.fetch_fault != ppc_pkg::FETCH_OK);
    automatic string line = $sformatf("%08x %08x %0d %0d",
                                      `MT_CORE.retire_o.pc, `MT_CORE.retire_o.insn, count, fault);
    automatic string stores = mt_stores;
    automatic int rb0 = mt_removed + int'(`MT_CORE.retire_o.removed_branches);
    automatic int rb1 = `MT_CORE.commit1 ? int'(`MT_CORE.retire1_o.removed_branches) : 0;
    if (rb0 != 0 || rb1 != 0) line = {line, $sformatf(" rb=%0d,%0d", rb0, rb1)};
    mt_removed = 0;
    mt_stores = store;
    #1;
    for (int i = 0; i < 49; i++) begin
      automatic logic [31:0] v = mt_value(i);
      if (mt_first || v != mt_prev[i]) line = {line, $sformatf(" %s=%08x", mt_name(i), v)};
      mt_prev[i] = v;
    end
    mt_first = 1'b0;
    $fwrite(mt_fd, "%s%s\n", line, stores);
  end else mt_stores = {mt_stores, store};
end

// Stores accepted after the last retirement (the store queue drains after
// completion) go on a final record with pc ffffffff and count 0.
final if (mt_fd != 0) begin
  if (mt_stores != "") $fwrite(mt_fd, "ffffffff 00000000 0 0%s\n", mt_stores);
  $fclose(mt_fd);
end
