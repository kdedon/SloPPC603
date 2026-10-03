// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Compiled-firmware bench scaffolding, included in the bench module body.
// The bench declares, before this include:
//   localparam int FW_MEM_BYTES     physical RAM size from BASE
//   int cycles                      watchdog / diagnostic cycle count
//   retire_packet_t retired         retirement port
//   function string check_detail()  extra failure context, may return ""
// The 64 KiB image loads at BASE; TOHOST names the mailbox word, and the
// firmware reports success by storing word 1 there. Optional +TRACE=<file>
// records every retirement through the mailbox STW, and +MEMDUMP=<file> writes
// RAM when that STW retires, for comparison against a reference model. A bench
// whose bus model owns the RAM defines FW_DUMP_ARRAY to name that array.
`ifndef FW_DUMP_ARRAY
`define FW_DUMP_ARRAY mem
`endif
localparam logic [31:0] BASE = 32'hfff00000;
logic [7:0] mem [0:FW_MEM_BYTES-1];
logic [31:0] tohost_addr;
string image_path;
int checks = 0;
logic mailbox_written = 1'b0, mailbox_retired = 1'b0;
int trace_fd = 0;
string memdump_path;

function automatic logic [31:0] word_at(input logic [31:0] address);
  int o;
  o = int'(address - BASE);
  return {mem[o], mem[o+1], mem[o+2], mem[o+3]};
endfunction

task automatic check(input logic ok, input string message);
  checks++;
  if (!ok)
    $fatal(1, "%s cycle=%0d pc=%08x insn=%08x%s", message, cycles,
           retired.pc, retired.insn, check_detail());
endtask

task automatic load_image;
  if (!$value$plusargs("IMAGE=%s", image_path) ||
      !$value$plusargs("TOHOST=%h", tohost_addr))
    $fatal(1, "IMAGE and TOHOST plusargs required");
  check(tohost_addr >= BASE && tohost_addr <= BASE + 32'hfffc &&
        tohost_addr[1:0] == 0, "mailbox range");
  foreach (mem[i]) mem[i] = 8'h00;
  $readmemh(image_path, mem, 0, 65535);
  if ($value$plusargs("TRACE=%s", memdump_path)) begin
    trace_fd = $fopen(memdump_path, "w");
    if (trace_fd == 0) $fatal(1, "cannot open TRACE file");
  end
  if (!$value$plusargs("MEMDUMP=%s", memdump_path)) memdump_path = "";
endtask

// pc insn more faulted gpr-write gpr value update-write gpr value
task automatic trace_retire;
  if (trace_fd != 0)
    $fwrite(trace_fd, "%08x %08x %0d %0d %0d %0d %08x %0d %0d %08x\n",
            retired.pc, retired.insn, retired.seq_partial,
            retired.illegal || retired.alignment_exception ||
              (retired.data_fault != ppc_pkg::DATA_OK) ||
              (retired.fetch_fault != ppc_pkg::FETCH_OK),
            retired.gpr_write, retired.gpr, retired.value,
            retired.update_write, retired.update_gpr, retired.update_value);
endtask

// Call after a store has updated mem.
task automatic mailbox_store(input logic [31:0] address, input logic full_word);
  if (address == tohost_addr && word_at(address) != 0) begin
    check(full_word && word_at(address) == 1,
          $sformatf("firmware failure mailbox=%08x", word_at(address)));
    check(!mailbox_written, "duplicate mailbox");
    mailbox_written = 1'b1;
  end
endtask

// Call on each accepted retirement. Stores retire after their bus write, so the
// first retirement after the mailbox write is its STW.
task automatic mailbox_retire;
  if (!mailbox_retired) trace_retire();
  if (mailbox_written && !mailbox_retired) begin
    check(retired.insn[31:26] == 6'd36 && !retired.gpr_write &&
          !retired.update_write, "mailbox retirement must be STW");
    mailbox_retired = 1'b1;
    if (trace_fd != 0) $fclose(trace_fd);
    trace_fd = 0;
    if (memdump_path != "") $writememh(memdump_path, `FW_DUMP_ARRAY);
  end
endtask
`undef FW_DUMP_ARRAY
