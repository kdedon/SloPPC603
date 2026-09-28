// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Compiled-firmware bench scaffolding, included in the bench module body.
// The bench declares, before this include:
//   localparam int FW_MEM_BYTES     physical RAM size from BASE
//   int cycles                      watchdog / diagnostic cycle count
//   retire_packet_t retired         retirement port
//   function string check_detail()  extra failure context, may return ""
// The 64 KiB image loads at BASE; TOHOST names the mailbox word, and the
// firmware reports success by storing word 1 there.
localparam logic [31:0] BASE = 32'hfff00000;
logic [7:0] mem [0:FW_MEM_BYTES-1];
logic [31:0] tohost_addr;
string image_path;
int checks = 0;
logic mailbox_written = 1'b0, mailbox_retired = 1'b0;

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
  if (mailbox_written && !mailbox_retired) begin
    check(retired.insn[31:26] == 6'd36 && !retired.gpr_write &&
          !retired.update_write, "mailbox retirement must be STW");
    mailbox_retired = 1'b1;
  end
endtask
