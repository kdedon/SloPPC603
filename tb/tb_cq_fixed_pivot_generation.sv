// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_cq_fixed_pivot_generation;
  logic [4:0] active, matched;
  logic [7:0] generations[5];
  logic [2:0] index, indices[16];
  logic [7:0] generation;
  logic pivot, all_entries, age_guard;
  logic states[4];
  logic old_owner, new_owner, old_hit, new_hit;
  bit check_events[$];
  always_comb begin
    for (int s=0;s<5;s++)
      matched[s]=active[s] && generation==generations[s];
    old_owner=active[index] && generation==generations[index];
    new_owner=matched[index];
    old_hit=pivot && !all_entries && index<3'd5 && age_guard && old_owner;
    new_hit=pivot && !all_entries && index<3'd5 && age_guard && new_owner;
  end
  task automatic compare;
    #1;
    assert(old_owner===new_owner && old_hit===new_hit)
      else $fatal(1,"pivot compare mismatch idx=%b gen=%h active=%b old=%b/%b new=%b/%b",
                  index,generation,active,old_owner,old_hit,new_owner,new_hit);
    check_events.push_back(1'b1);
  endtask
  initial begin
    states[0]=0;states[1]=1;states[2]=1'bx;states[3]=1'bz;
    assert($isunknown(states[2])) else $fatal(1,"four-state simulator required");
    for(int i=0;i<8;i++) indices[i]=3'(i);
    indices[8]=3'bx00;indices[9]=3'b0x0;indices[10]=3'b00x;indices[11]=3'bx11;
    indices[12]=3'bzzz;indices[13]=3'bxxx;indices[14]=3'bz01;indices[15]=3'b10z;
    pivot=1;all_entries=0;age_guard=1;
    // All eight codepoints,256 generations,32 active masks,live/stale cases.
    for(int a=0;a<32;a++) for(int idx=0;idx<8;idx++)
      for(int gen=0;gen<256;gen++) for(int stale=0;stale<2;stale++) begin
        active=5'(a);index=3'(idx);generation=8'(gen);
        for(int s=0;s<5;s++) generations[s]=8'(gen+s*37);
        if(idx<5) generations[idx]=8'(gen+stale);
        compare();
      end
    // Unknown generation bits at each fixed entry; active/guards may beX/Z.
    for(int idx=0;idx<16;idx++) for(int slot=0;slot<5;slot++)
      for(int bitno=0;bitno<8;bitno++) for(int unknown_kind=2;unknown_kind<4;unknown_kind++)
        for(int guard=0;guard<4;guard++) begin
          index=indices[idx];active=5'b11111;generation=8'h5a;
          for(int s=0;s<5;s++) generations[s]=8'h5a;
          generations[slot][bitno]=states[unknown_kind];
          active[slot]=states[guard];
          pivot=states[guard];all_entries=0;age_guard=1;
          compare();
          pivot=1;all_entries=states[guard];age_guard=states[guard];
          generation[bitno]=states[unknown_kind];
          compare();
        end
    assert(check_events.size()==141312) else $fatal(1,"missing generation cases");
    $display("PASS fixed pivot generation: %0d comparisons",check_events.size());
    $finish;
  end
endmodule
`default_nettype wire
