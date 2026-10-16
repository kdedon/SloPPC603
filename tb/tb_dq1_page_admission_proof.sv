// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_dq1_page_admission_proof;
 logic[31:0]av,bv,arch_a1,arch_b1,imm,gpr_mapped;
 logic[4:0]ra,rb,rc;logic[2:0]dep;logic[1:0]size;logic[5:0]sop;
 logic za,im,dr,ar,br,upd,gw,gu,special_busy,sru_hold_q,lsu_empty,
 fp_unsafe_pending,msr_le,lsu_ready,lane_mem_idle;
 wire[103:0] o[8],n[8];
 genvar g;
 generate for(g=0;g<8;g=g+1)begin:p
 dq1_old #(.ENABLE_LSU_PIPE(g%2),.ENABLE_MISALIGNED_ACCESS((g/2)%2),.LSU_BASE_SNOOP(g/4)) x(.*, .result(o[g]));
 dq1_new #(.ENABLE_LSU_PIPE(g%2),.ENABLE_MISALIGNED_ACCESS((g/2)%2),.LSU_BASE_SNOOP(g/4)) y(.*, .result(n[g]));
 end endgenerate
 // Frozen original helper is independently checked by the full-core hash.
 function automatic logic sum12_ref(input logic[11:0] a,b,k);
 return (a ^ b ^ k) == {(a[10:0] & b[10:0]) | ((a[10:0] | b[10:0]) & ~k[10:0]), 1'b0};
 endfunction
 function automatic logic page_ref(input logic[11:0] a,b);
 return sum12_ref(a,b,12'hfff)||sum12_ref(a,b,12'hffe)||sum12_ref(a,b,12'hffd);
 endfunction
 function automatic logic f(input integer i);
 case(i%4)0:return 0;1:return 1;2:return 1'bx;default:return 1'bz;endcase
 endfunction
 integer samples,known0,known1,fallx,fallz,equalmerge,nonlinear;
 integer native_b_difference,native_cross_pipe_clear,native_clear_pipe_cross,native_unknown;
 integer native_ready_true[4],native_ready_false[4],pipe_ready_true[4],pipe_ready_false[4];
 logic [11:0] offsets[8];
 initial begin
 samples=0;known0=0;known1=0;fallx=0;fallz=0;equalmerge=0;nonlinear=0;
 native_b_difference=0;native_cross_pipe_clear=0;native_clear_pipe_cross=0;native_unknown=0;
 for(integer p=0;p<4;p=p+1)begin native_ready_true[p]=0;native_ready_false[p]=0;pipe_ready_true[p]=0;pipe_ready_false[p]=0;end
 offsets[0]=12'hfff;offsets[1]=12'hffe;offsets[2]=12'hffd;offsets[3]=12'hffc;
 offsets[4]=12'h000;offsets[5]=12'h001;offsets[6]=12'h7ff;offsets[7]=12'h800;
 for(integer c=0;c<1024;c=c+1)begin
 za=f(c);im=f(c/4);dr=f(c/16);size={f(c/256),f(c/64)};
 for(integer pat=0;pat<64;pat=pat+1)begin
 av=32'(pat<8 ? 0 : (pat%2 ? 1 : -1));bv={20'b0,offsets[pat%8]};imm={20'b0,offsets[(pat/8)%8]};
 if(pat>=32)begin av[(pat-32)%12]=f(pat/8);bv[(pat-32)%12]=f(pat/4);imm[(pat-32)%12]=f(pat/16);end
 // Independent architectural payloads: opposing page-end patterns when
 // A=0 make native/pipe register-B predicate differences nonvacuous.
 arch_a1=pat<8 ? 32'b0 : (av ^ 32'h12345678);
 arch_b1={20'hbad00,offsets[(pat+4)%8]};
 if(pat>=32)begin
 arch_a1[(pat+3)%12]=f(pat/4);
 arch_b1[(pat+7)%12]=f(pat/8);
 end
 // Independent qualification inputs include all four-state cases; native
 // mapping/dep controls are not inferred from the pipelined ready values.
 ar=f(pat);br=f(pat/4);dep={f(pat/16),f(pat/4),f(pat)};
 upd=f(pat+1);gw=f(pat+2);gu=f(pat+3);sop=6'(pat%16);
 if(pat>=32)sop[pat%6]=f(pat/8);
 special_busy=f(pat/2);sru_hold_q=f(pat/3);lsu_empty=f(pat/5);
 fp_unsafe_pending=f(pat/7);msr_le=f(pat/9);lsu_ready=f(pat/11);lane_mem_idle=f(pat/13);
 ra=5'(pat%32);rb=5'((pat+1)%32);rc=5'((pat+2)%32);
 gpr_mapped={32{f(pat/8)}};
 if(pat<8)begin
 ar=1;br=1;dep=0;upd=0;gw=1;gu=0;special_busy=0;sru_hold_q=0;
 lsu_empty=1;fp_unsafe_pending=0;msr_le=0;lsu_ready=1;lane_mem_idle=1;gpr_mapped=0;
 end
 #1;
 for(integer p=0;p<8;p=p+1)if(o[p]!==n[p])$fatal(1,"DQ1 mismatch c=%0d pat=%0d profile=%0d old=%h new=%h",c,pat,p,o[p],n[p]);
 samples=samples+1;
 for(integer p=0;p<4;p=p+1)begin
 if(o[p*2][4]===1'b1)native_ready_true[p]++;
 if(o[p*2][4]===1'b0)native_ready_false[p]++;
 if(o[p*2+1][3]===1'b1)pipe_ready_true[p]++;
 if(o[p*2+1][3]===1'b0)pipe_ready_false[p]++;
 end
 if(im===1'b0 && arch_b1[11:0]!==bv[11:0])native_b_difference++;
 if(im===1'b0 && dr===1'b1 && size===2'b10 &&
    (za===1'b0 || za===1'b1) && av[11:0]===12'b0 && arch_a1[11:0]===12'b0)begin
 if(o[6][5]===1'b1 && o[7][5]===1'b0)native_cross_pipe_clear++;
 if(o[6][5]===1'b0 && o[7][5]===1'b1)native_clear_pipe_cross++;
 end
 if((^arch_b1[11:0])===1'bx && arch_b1[11:0]!==bv[11:0])native_unknown++;
 case(im)0:known0++;1:known1++;1'bx:fallx++;1'bz:fallz++;endcase
 if((im===1'bx||im===1'bz)&&za===1'b0&&dr===1'b1&&size===2'b10&&
    (bv===imm)&&(o[7][5]===page_ref(av[11:0],bv[11:0])))equalmerge++;
 if((im===1'bx||im===1'bz)&&za===1'b0&&dr===1'b1&&size===2'b10&&
    (o[7][5]===page_ref(av[11:0],im?imm[11:0]:bv[11:0]))&&
    (page_ref(av[11:0],bv[11:0])===1'b1)&&
    (page_ref(av[11:0],imm[11:0])===1'b1)&&
    (page_ref(av[11:0],im?imm[11:0]:bv[11:0])!==1'b1))nonlinear++;
 end end
 if(samples!=65536||known0==0||known1==0||fallx==0||fallz==0||equalmerge==0||nonlinear==0||native_b_difference==0||native_cross_pipe_clear==0||native_clear_pipe_cross==0||native_unknown==0)$fatal(1,"coverage");
 for(integer p=0;p<4;p=p+1)begin
 if(native_ready_true[p]==0||native_ready_false[p]==0||pipe_ready_true[p]==0||pipe_ready_false[p]==0)$fatal(1,"admission coverage pair=%0d",p);
 $display("profile pair%0d nativeReady1/0=%0d/%0d pipeReady1/0=%0d/%0d",p,native_ready_true[p],native_ready_false[p],pipe_ready_true[p],pipe_ready_false[p]);
 end
 $display("PASS DQ1 samples=%0d comparisons=%0d useimm 0/1/X/Z=%0d/%0d/%0d/%0d equalmerge=%0d nonlinear=%0d",samples,samples*8,known0,known1,fallx,fallz,equalmerge,nonlinear);
 $display("native B difference=%0d cross/clear=%0d clear/cross=%0d unknown=%0d",native_b_difference,native_cross_pipe_clear,native_clear_pipe_cross,native_unknown);
 $finish;
 end
endmodule
`default_nettype wire
