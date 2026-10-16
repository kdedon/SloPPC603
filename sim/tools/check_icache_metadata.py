#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Actual metadata-cache inverse/source guard. No HDL tool is invoked.

OFF/ON uses the same implementation. The inverse identifies its original
controller; independent public word/opaque-metadata tests are separate.
"""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
FIXED='5479704991cc547b01337fbe25446c7c5b216e718b01c1cbbc216892ade174c3'
METADATA='9d184d6a8f39214841e7322df20f1cd94338352df37619cc91a15ef07e09fa9c'
def sha(s):return hashlib.sha256(s.encode()).hexdigest()
INVERSE_EDITS=[("  parameter int FETCH_WIDTH = 1,\n  // Opaque metadata follows each word on the same RAM/read edge.\n  parameter bit ENABLE_METADATA = 1'b0,\n  parameter int WORD_META_BITS = 2\n", '  parameter int FETCH_WIDTH = 1\n'), ('  output logic [WORD_META_BITS*FETCH_WIDTH-1:0] fetch_rsp_meta_o,\n', ''), ('  // Word w uses [8*WORD_META_BITS-1-WORD_META_BITS*w -:WORD_META_BITS].\n  input  logic [8*WORD_META_BITS-1:0] line_rsp_meta_i,\n', ''), ('  localparam int HALF_META_BITS = 4*WORD_META_BITS;\n  localparam int ROW_BITS = HALF_BITS + (ENABLE_METADATA ? HALF_META_BITS : 0);\n', ''), ('  logic [WAY_COUNT-1:0][ROW_BITS-1:0] row_rdata;\n  logic [ROW_BITS-1:0] row_wdata;\n  logic [WORD_META_BITS-1:0] rsp_meta, ram_meta, ram_meta1;\n', ''), ('    ppc_ram_sdp #(.DEPTH(2*SET_COUNT), .WIDTH(ROW_BITS)) data_ram (\n      .clk_i, .we_i(data_we[way]), .waddr_i(data_waddr), .wdata_i(row_wdata),\n', '    ppc_ram_sdp #(.DEPTH(2*SET_COUNT), .WIDTH(HALF_BITS)) data_ram (\n      .clk_i, .we_i(data_we[way]), .waddr_i(data_waddr), .wdata_i(data_wdata),\n'), ('      .rdata_o(row_rdata[way])\n', '      .rdata_o(data_rdata[way])\n'), ('    assign data_rdata[way] = row_rdata[way][HALF_BITS-1:0];\n', ''), ("  end\n  endgenerate\n\n  // No separate metadata RAM or publication bit: the row owns word and metadata.\n  genvar meta_way;\n  generate\n  if (ENABLE_METADATA) begin : g_metadata\n    logic [HALF_META_BITS-1:0] line_meta_half1_q;\n    logic [WORD_META_BITS-1:0] rsp_meta_q;\n    logic [WAY_COUNT-1:0][HALF_META_BITS-1:0] half_meta;\n    assign row_wdata = {state_q == IC_INSTALL ? line_meta_half1_q : line_rsp_meta_i[8*WORD_META_BITS-1 -:HALF_META_BITS],\n                        data_wdata};\n    for (meta_way = 0; meta_way < WAY_COUNT; meta_way = meta_way + 1) begin : g_way\n      assign half_meta[meta_way] = row_rdata[meta_way][HALF_BITS +: HALF_META_BITS];\n    end\n    // These conditions mirror the existing line-half and scalar-word captures.\n    always_ff @(posedge clk_i) begin\n      if (state_q == IC_REFILL_WAIT && line_rsp_valid_i)\n        line_meta_half1_q <= line_rsp_meta_i[HALF_META_BITS-1:0];\n    end\n    always_ff @(posedge clk_i) begin\n      if (!rst_ni) rsp_meta_q <= '0;\n      else if (invalidate_i) begin end\n      else if (kill_i) begin end\n      else begin\n        case (state_q)\n          IC_IDLE: if (!rsp_valid_q || fetch_rsp_ready_i) rsp_meta_q <= '0;\n          IC_REFILL_WAIT: if (line_rsp_valid_i && line_rsp_ready_o) begin\n            if (line_rsp_error_i) rsp_meta_q <= '0;\n            else rsp_meta_q <= line_rsp_meta_i[8*WORD_META_BITS-1 - WORD_META_BITS*miss_word_q -: WORD_META_BITS];\n          end\n          default: begin end\n        endcase\n      end\n    end\n    assign rsp_meta = rsp_meta_q;\n    always_comb begin\n      ram_meta = '0;\n      ram_meta1 = '0;\n      for (int w = 0; w < WAY_COUNT; w++)\n        if (rsp_way_q[w]) begin\n          ram_meta = ram_meta | half_meta[w][HALF_META_BITS-1 - WORD_META_BITS*rsp_word_q -: WORD_META_BITS];\n          ram_meta1 = ram_meta1 | half_meta[w][HALF_META_BITS-1 - WORD_META_BITS*{rsp_word_q[1], 1'b1} -: WORD_META_BITS];\n        end\n    end\n  end else begin : g_no_metadata\n    assign row_wdata = data_wdata;\n    assign rsp_meta = '0;\n    assign ram_meta = '0;\n    assign ram_meta1 = '0;\n    logic unused_line_meta;\n    assign unused_line_meta = ^line_rsp_meta_i;\n  end\n  if (FETCH_WIDTH == 2) begin : g_meta_pair\n    assign fetch_rsp_meta_o = {ram_meta1, rsp_meta | ram_meta};\n  end else begin : g_meta_single\n    assign fetch_rsp_meta_o = rsp_meta | ram_meta;\n    logic unused_meta1;\n    assign unused_meta1 = ^ram_meta1;\n", '')]
def strip_metadata(actual):
    if sha(actual)==FIXED:return actual
    assert sha(actual)==METADATA,'cache is not reviewed metadata/default-controller source'
    original=actual
    for new,old in reversed(INVERSE_EDITS):
        assert original.count(new)==1,'metadata inverse fragment missing/ambiguous'
        original=original.replace(new,old,1)
    assert sha(original)==FIXED,'metadata inverse changed reviewed controller'
    return original

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    actual=(ROOT/'rtl/ppc_icache.sv').read_text()
    assert sha(actual)==METADATA,'metadata acceptance requires current generic source'
    original=strip_metadata(actual)
    a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'source.json').write_text(json.dumps({'actual':sha(actual),'inverse_fixed':sha(original),
        'scope':'source identity only; same-implementation OFF/ON and independent public word/metadata oracle require simulation'},indent=2)+'\n')
    print('PASS metadata source inverse to reviewed fixed controller; no HDL execution')
if __name__=='__main__':main()
