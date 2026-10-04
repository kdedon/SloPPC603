// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Included in a bench module body. A branch the core may remove at
// dispatch: b, bc, bclr or bcctr without LK and without a CTR decrement
// (UM 6.3.1). Such a branch retires without a packet; the next packet's
// removed_branches counts it.
function automatic logic removable_branch(input logic [31:0] insn);
  logic branch;
  branch = (insn[31:26] == 6'd18) || (insn[31:26] == 6'd16) ||
           ((insn[31:26] == 6'd19) && ((insn[10:1] == 10'd16) || (insn[10:1] == 10'd528)));
  return branch && !insn[0] && ((insn[31:26] == 6'd18) || insn[23]);
endfunction
