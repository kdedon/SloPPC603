// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Shared operation and result records for the micro-TLB equivalence bench.
package tb_micro_tlb_pkg;
  localparam int MAX_OPS = 1024;
  localparam int MAX_RECORDS = 4096;

  typedef enum logic [3:0] {
    OP_ACCESS,   // `count` fetches and `count2` data accesses, concurrently
    OP_BAT,      // runtime BAT SPR write
    OP_SR,       // segment register write
    OP_TLBIE,
    OP_TLBLD,
    OP_CONTEXT,
    OP_MGMT,     // management-port refill
    OP_STREAM    // back-to-back fetches with a zero-wait memory (timing only)
  } op_kind_t;

  typedef struct packed {
    op_kind_t kind;
    logic [31:0] ea;      // first fetch EA, BAT/SR data, TLB EA
    logic [31:0] ea2;     // first data EA
    logic [2:0] count;
    logic [2:0] count2;
    logic write;
    logic [9:0] spr;
    logic [3:0] index;
    logic bank;
    logic way;
    logic [23:0] vsid;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic ir, dr, pr;
  } op_t;

  // One architectural outcome: an access response or a CSR status.
  typedef struct packed {
    logic [3:0] op;          // op kind, plus 8 for a data access record
    logic [31:0] ea;
    logic offered;           // a physical request was issued
    logic [31:0] pa;
    logic [3:0] wimg;
    logic write;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic [2:0] fault;
    logic error;
    logic [31:0] data;
    logic [68:0] page_miss;
    logic [15:0] sticky;     // translation and page diagnostic outputs
  } record_t;
endpackage
