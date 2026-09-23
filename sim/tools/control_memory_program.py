#!/usr/bin/env python3
"""Generate a symbolic-program oracle independent of RTL decode/datapaths.

The interpreter executes operation names/arguments, not encoded instruction bits.
Output snapshots include the entire GPR/CR/XER/LR/CTR state and byte-memory hash.
"""
from pathlib import Path
import argparse

MASK = 0xffffffff
BASE = 0x1000
DOPS = {'lwz':32,'lbz':34,'stw':36,'stb':38,'lhz':40,'lha':42,'sth':44}
DOPS.update({op+'u':code+1 for op,code in list(DOPS.items())})
CROPS = {'crand':257,'crandc':129,'creqv':289,'crnand':225,'crnor':33,'cror':449,'crorc':417,'crxor':193}
XOPS = {'lwzx':23,'lbzx':87,'stwx':151,'stbx':215,'lhzx':279,'lhax':343,'sthx':407}
XOPS.update({op[:-1]+'ux':code+32 for op,code in list(XOPS.items())})

def signed(x, bits=32):
    x &= (1 << bits)-1
    return x-(1 << bits) if x & (1 << (bits-1)) else x

def digest(mem):
    h = 2166136261
    for byte in mem:
        h = ((h ^ byte)*16777619) & MASK
    return h

class Program:
    def __init__(self):
        self.ops=[]
        self.labels={}
    def emit(self, op, *args):
        self.ops.append((op,args))
    def label(self, name):
        assert name not in self.labels
        self.labels[name]=len(self.ops)*4
    def address(self, target):
        return self.labels[target] if isinstance(target,str) else target
    def encode(self, pc, op, a):
        if op=='divw':return (31<<26)|(a[0]<<21)|(a[1]<<16)|(a[2]<<11)|(a[3]<<10)|(491<<1)|a[4]
        if op=='divwu':return (31<<26)|(a[0]<<21)|(a[1]<<16)|(a[2]<<11)|(a[3]<<10)|(459<<1)|a[4]
        if op in ('mulhw','mulhwu'):return (31<<26)|(a[0]<<21)|(a[1]<<16)|(a[2]<<11)|((75 if op=='mulhw' else 11)<<1)|a[3]
        if op=='mulli':return (7<<26)|(a[0]<<21)|(a[1]<<16)|(a[2]&65535)
        if op=='mullw':return (31<<26)|(a[0]<<21)|(a[1]<<16)|(a[2]<<11)|(a[3]<<10)|(235<<1)|a[4]
        if op=='mcrf':return (19<<26)|(a[0]<<23)|(a[1]<<18)
        if op=='mcrxr':return (31<<26)|(a[0]<<23)|(512<<1)
        if op in CROPS:
            d,r,b=a
            return (19<<26)|(d<<21)|(r<<16)|(b<<11)|(CROPS[op]<<1)
        if op=='mfcr':return (31<<26)|(a[0]<<21)|(19<<1)
        if op=='mtcrf':return (31<<26)|(a[1]<<21)|(a[0]<<12)|(144<<1)
        if op=='illegal': return 0
        if op in ('addi','addis'):
            d,r,imm=a
            imm=self.address(imm)
            return ((14 if op=='addi' else 15)<<26)|(d<<21)|(r<<16)|(imm&65535)
        if op=='ori':
            d,r,imm=a
            return (24<<26)|(r<<21)|(d<<16)|(imm&65535)
        if op in ('add','addco','adde'):
            d,r,b=a
            return (31<<26)|(d<<21)|(r<<16)|(b<<11)|(({'add':266,'addco':522,'adde':138}[op])<<1)
        if op in ('cntlzw','extsb','extsh'):
            d,r,rc=a
            return (31<<26)|(r<<21)|(d<<16)|({'cntlzw':26,'extsb':954,'extsh':922}[op]<<1)|rc
        if op in ('slw','srw','sraw','srawi'):
            d,r,b,rc=a
            return (31<<26)|(r<<21)|(d<<16)|(b<<11)|({'slw':24,'srw':536,'sraw':792,'srawi':824}[op]<<1)|rc
        if op in ('subf','subfc','subfe','subfme','subfze','neg'):
            if op in ('subf','subfc','subfe'):d,r,b,oe,rc=a
            else:d,r,oe,rc=a;b=0
            return (31<<26)|(d<<21)|(r<<16)|(b<<11)|(oe<<10)|(({'subf':40,'subfc':8,'subfe':136,'subfme':232,'subfze':200,'neg':104}[op])<<1)|rc
        if op in ('addic','addic.'):
            d,r,imm=a
            return ((12 if op=='addic' else 13)<<26)|(d<<21)|(r<<16)|(imm&65535)
        if op in ('andi.','andis.'):
            d,r,imm=a
            return ((28 if op=='andi.' else 29)<<26)|(r<<21)|(d<<16)|(imm&65535)
        if op=='subfic':
            d,r,imm=a
            return (8<<26)|(d<<21)|(r<<16)|(imm&65535)
        if op=='rlwimi':
            d,r,sh,mb,me,rc=a
            return (20<<26)|(r<<21)|(d<<16)|(sh<<11)|(mb<<6)|(me<<1)|rc
        if op in DOPS:
            d,r,disp=a
            return (DOPS[op]<<26)|(d<<21)|(r<<16)|(disp&65535)
        if op in XOPS:
            d,r,b=a
            return (31<<26)|(d<<21)|(r<<16)|(b<<11)|(XOPS[op]<<1)
        if op in ('cmp','cmpl','cmpi','cmpli'):
            bf,r,rhs=a
            if op.endswith('i'):
                return ((11 if op=='cmpi' else 10)<<26)|(bf<<23)|(r<<16)|(rhs&65535)
            return (31<<26)|(bf<<23)|(r<<16)|(rhs<<11)|((32 if op=='cmpl' else 0)<<1)
        if op in ('mflr','mfctr','mtlr','mtctr'):
            spr=8 if op.endswith('lr') else 9
            return (31<<26)|(a[0]<<21)|((spr&31)<<16)|((spr>>5)<<11)|((339 if op.startswith('mf') else 467)<<1)
        if op=='b':
            target,aa,lk=a
            disp=self.address(target)-(0 if aa else pc)
            return (18<<26)|(disp&0x3fffffc)|(aa<<1)|lk
        if op=='bc':
            bo,bi,target,aa,lk=a
            disp=self.address(target)-(0 if aa else pc)
            return (16<<26)|(bo<<21)|(bi<<16)|(disp&0xfffc)|(aa<<1)|lk
        if op in ('bclr','bcctr'):
            bo,bi,lk=a
            return (19<<26)|(bo<<21)|(bi<<16)|((16 if op=='bclr' else 528)<<1)|lk
        raise ValueError(op)

    def simulate(self, limit=2000):
        regs=[0]*32
        cr=xer=lr=ctr=pc=0
        mem=[((i*37)^0xa5)&255 for i in range(256)]
        snapshots=[]
        counts={}
        for _ in range(limit):
            assert pc%4==0 and 0<=pc//4<len(self.ops),hex(pc)
            op,a=self.ops[pc//4]
            word=self.encode(pc,op,a)
            next_pc=pc+4
            counts[op]=counts.get(op,0)+1
            if op=='divw':
                d,r,b,oe,rc=a
                av,bv=signed(regs[r]),signed(regs[b])
                exceptional=(bv==0 or (av==-(1<<31) and bv==-1))
                # Deterministic policy for architecture-undefined outputs.
                magnitude=0 if exceptional else abs(av)//abs(bv)
                value=(-magnitude if (av<0)!=(bv<0) else magnitude)&MASK
                regs[d]=value
                if oe:
                    xer=(xer&0x3fffffff)|(int(exceptional)<<30)|(int(bool(xer>>31) or exceptional)<<31)
                if rc:
                    cr=(cr&0x0fffffff)|(((8 if value&0x80000000 else 4 if value else 2)|(xer>>31))<<28)
            elif op=='divwu':
                d,r,b,oe,rc=a
                dividend,divisor=regs[r],regs[b]
                # Zero is the scaffold's deterministic undefined-result policy,
                # not an architectural requirement of DIVWU.
                value=dividend//divisor if divisor else 0
                regs[d]=value
                if oe:
                    ov=divisor==0
                    xer=(xer&0x3fffffff)|(int(ov)<<30)|(int(bool(xer>>31) or ov)<<31)
                if rc:
                    cr=(cr&0x0fffffff)|(((8 if value&0x80000000 else 4 if value else 2)|(xer>>31))<<28)
            elif op in ('mulhw','mulhwu'):
                d,r,b,rc=a
                av,bv=regs[r],regs[b]
                product=(signed(av)*signed(bv)) if op=='mulhw' else av*bv
                value=(product//(1<<32))&MASK
                regs[d]=value
                if rc:
                    cr=(cr&0x0fffffff)|(((8 if value&0x80000000 else 4 if value else 2)|(xer>>31))<<28)
            elif op in ('mullw','mulli'):
                d,r,b=a[:3]
                product=signed(regs[r])*(signed(b,16) if op=='mulli' else signed(regs[b]))
                regs[d]=product&MASK
                if op=='mullw':
                    oe,rc=a[3:]
                    if oe:
                        overflow=not(-(1<<31)<=product<(1<<31))
                        xer=(xer&0x3fffffff)|(int(overflow)<<30)|((int(bool(xer>>31) or overflow))<<31)
                    if rc:
                        value=regs[d]
                        cr=(cr&0x0fffffff)|(((8 if value&0x80000000 else 4 if value else 2)|(xer>>31))<<28)
            elif op=='mcrf':
                dest,source=a
                nibble=(cr>>((7-source)*4))&15
                shift=(7-dest)*4
                cr=(cr & ~(15<<shift)) | (nibble<<shift)
            elif op=='mcrxr':
                shift=(7-a[0])*4
                cr=(cr & ~(15<<shift)) | (((xer>>28)&14)<<shift)
                xer &= 0x1fffffff
            elif op in CROPS:
                d,r,b=a
                av=bool(cr & (1<<(31-r))); bv=bool(cr & (1<<(31-b)))
                value={'crand':av and bv,'crandc':av and not bv,'creqv':av==bv,
                       'crnand':not(av and bv),'crnor':not(av or bv),'cror':av or bv,
                       'crorc':av or not bv,'crxor':av!=bv}[op]
                cr=(cr & ~(1<<(31-d))) | (int(value)<<(31-d))
            elif op=='mfcr':regs[a[0]]=cr
            elif op=='mtcrf':
                fields,r=a
                for field in range(8):
                    if fields & (128>>field):
                        shift=(7-field)*4
                        cr=(cr & ~(15<<shift)) | (((regs[r]>>shift)&15)<<shift)
            elif op in ('addi','addis'):
                d,r,imm=a
                val=signed(self.address(imm),16)
                regs[d]=((regs[r] if r else 0)+(val if op=='addi' else val<<16))&MASK
            elif op=='ori':
                d,r,imm=a; regs[d]=regs[r]|imm
            elif op in ('add','addco','adde'):
                d,r,b=a; av,bv=regs[r],regs[b]
                carry=(xer>>29)&1 if op=='adde' else 0
                regs[d]=(av+bv+carry)&MASK
                if op=='adde':xer=(xer&~(1<<29))|(int(av+bv+carry>MASK)<<29)
                if op=='addco':
                    ov=not(-(1<<31)<=signed(av)+signed(bv)<(1<<31))
                    so=bool(xer>>31) or ov
                    xer=(xer&0x1fffffff)|(int(so)<<31)|(int(ov)<<30)|(int(av+bv>MASK)<<29)
            elif op in ('cntlzw','extsb','extsh'):
                d,r,rc=a
                value=32-regs[r].bit_length() if op=='cntlzw' else signed(regs[r],8 if op=='extsb' else 16)&MASK
                regs[d]=value
                if rc:
                    field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                    cr=(cr&0x0fffffff)|(field<<28)
            elif op in ('slw','srw'):
                d,r,b,rc=a
                source=regs[r]
                count=regs[b]%64
                # Select bits rather than duplicating the RTL shift expression.
                value=0
                for dest in range(32):
                    origin=dest-count if op=='slw' else dest+count
                    if 0<=origin<32: value|=((source>>origin)&1)<<dest
                regs[d]=value
                if rc:
                    field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                    cr=(cr&0x0fffffff)|(field<<28)
            elif op in ('sraw','srawi'):
                d,r,b,rc=a
                source=regs[r]; count=b if op=='srawi' else regs[b]%64
                negative=(source>>31)&1
                value=0
                for dest in range(32):
                    origin=dest+count
                    value|=(((source>>origin)&1) if origin<32 else negative)<<dest
                discarded=any((source>>bit)&1 for bit in range(min(count,32)))
                xer=(xer&~(1<<29))|(int(negative and discarded)<<29)
                regs[d]=value
                if rc:
                    field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                    cr=(cr&0x0fffffff)|(field<<28)
            elif op in ('subf','subfc','subfe','subfme','subfze','neg'):
                if op in ('subf','subfc','subfe'):d,r,b,oe,rc=a;rhs=regs[b]
                else:d,r,oe,rc=a;rhs=MASK if op=='subfme' else 0
                borrow=1-((xer>>29)&1) if op in ('subfe','subfme','subfze') else 0
                if op in ('subfc','subfe','subfme','subfze'):xer=(xer&~(1<<29))|(int(rhs>=regs[r]+borrow)<<29)
                mathematical=signed(rhs)-signed(regs[r])-borrow
                value=mathematical&MASK
                if oe:
                    overflow=not(-(1<<31)<=mathematical<(1<<31))
                    xer=(xer&0x3fffffff)|(int(bool(xer>>31) or overflow)<<31)|(int(overflow)<<30)
                regs[d]=value
                if rc:
                    field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                    cr=(cr&0x0fffffff)|(field<<28)
            elif op in ('addic','addic.'):
                d,r,imm=a
                total=regs[r]+(signed(imm,16)&MASK)
                value=total&MASK
                regs[d]=value
                xer=(xer&~(1<<29))|(int(total>MASK)<<29)
                if op=='addic.':
                    field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                    cr=(cr&0x0fffffff)|(field<<28)
            elif op in ('andi.','andis.'):
                d,r,imm=a
                mask=(imm&65535) << (16 if op=='andis.' else 0)
                value=regs[r]&mask
                regs[d]=value
                field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                cr=(cr&0x0fffffff)|(field<<28)
            elif op=='subfic':
                d,r,imm=a
                rhs=signed(imm,16)&MASK
                source=regs[r]
                regs[d]=(rhs-source)&MASK
                xer=(xer&~(1<<29))|(int(rhs>=source)<<29)
            elif op=='rlwimi':
                d,r,sh,mb,me,rc=a
                source,old=regs[r],regs[d]
                value=old
                # Walk architectural bits, choose source or retained old destination.
                for bit in range(32):
                    if (bit-mb)%32 <= (me-mb)%32:
                        selected=(source>>(31-(bit+sh)%32))&1
                        value=(value&~(1<<(31-bit)))|(selected<<(31-bit))
                regs[d]=value
                if rc:
                    field=(8 if value&0x80000000 else 4 if value else 2)|(xer>>31)
                    cr=(cr&0x0fffffff)|(field<<28)
            elif op in DOPS or op in XOPS:
                d,r,off=a
                ea=((regs[r] if r else 0)+(regs[off] if op in XOPS else signed(off,16)))&MASK
                update=op.endswith(('u','ux'))
                family=op.removesuffix('x').removesuffix('u')
                if update:
                    assert r != 0 and (family.startswith('st') or r != d), 'invalid update form'
                size=4 if family in ('lwz','stw') else 1 if family in ('lbz','stb') else 2
                assert ea%size==0 and BASE<=ea and ea+size<=BASE+len(mem),(op,hex(ea))
                off=ea-BASE
                if family.startswith('st'):
                    value=regs[d]&((1<<(8*size))-1)
                    mem[off:off+size]=value.to_bytes(size,'big')
                else:
                    value=int.from_bytes(bytes(mem[off:off+size]),'big')
                    regs[d]=(signed(value,16) if family=='lha' else value)&MASK
                if update: regs[r]=ea
            elif op in ('cmp','cmpl','cmpi','cmpli'):
                bf,r,rhs=a
                left=regs[r]
                right=(signed(rhs,16) if op=='cmpi' else rhs&65535) if op.endswith('i') else regs[rhs]
                if op in ('cmp','cmpi'): left,right=signed(left),signed(right)
                field=(8 if left<right else 4 if left>right else 2)|(xer>>31)
                shift=28-4*bf
                cr=(cr&~(15<<shift))|(field<<shift)
            elif op in ('mflr','mfctr'): regs[a[0]]=lr if op=='mflr' else ctr
            elif op in ('mtlr','mtctr'):
                if op=='mtlr': lr=regs[a[0]]
                else: ctr=regs[a[0]]
            elif op=='b':
                target,aa,lk=a; next_pc=self.address(target)
                if lk: lr=pc+4
            elif op in ('bc','bclr','bcctr'):
                bo,bi=a[:2]
                lk=a[-1]
                # Test-side PowerPC BO definition; registers update even if not taken.
                target=self.address(a[2]) if op=='bc' else (lr if op=='bclr' else ctr)&~3
                if not (bo&4): ctr=(ctr-1)&MASK
                count_ok=bool(bo&4) or (bool(ctr)!=bool(bo&2))
                condition_ok=bool(bo&16) or bool((cr>>(31-bi))&1)==bool(bo&8)
                if count_ok and condition_ok: next_pc=target
                if lk: lr=pc+4
            elif op!='illegal': raise ValueError(op)
            snapshots.append([pc,word,*regs,cr,xer,lr,ctr,digest(mem)])
            if op=='illegal': return snapshots,counts
            pc=next_pc
        raise AssertionError('program oracle did not terminate')

def make_program():
    p=Program();e=p.emit
    e('addi',1,0,BASE); e('addi',0,0,19)
    e('addi',2,0,8); e('mtctr',2); e('addi',3,0,0); e('addi',4,0,0)
    p.label('sumloop')
    e('lwzx',5,1,3); e('add',4,4,5); e('stwx',4,1,3)
    e('addi',3,3,4); e('bc',16,0,'sumloop',0,0)
    e('mfctr',6)
    # Every scalar lane and sign-extension, D and indexed; stores overlap.
    for off in range(4):
        e('lbz',7,1,off);e('addi',8,0,off);e('lbzx',9,1,8)
        e('stb',0,1,64+off);e('addi',8,0,68+off);e('stbx',0,1,8)
    for off in (0,2):
        e('lhz',10,1,off);e('lha',11,1,off)
        e('addi',8,0,off);e('lhzx',12,1,8);e('lhax',13,1,8)
        e('sth',10,1,72+off);e('addi',8,0,76+off);e('sthx',11,1,8)
    e('lwz',14,1,4);e('stw',14,1,80)
    e('lha',14,1,32);e('stw',1,1,88) # positive halfword and store rS=rA
    e('addi',30,0,0xffff);e('lwz',14,30,BASE+1) # 32-bit EA wrap
    # Zero base means literal zero; an indexed rB=0 still reads nonzero r0.
    e('lwz',15,0,BASE);e('addi',0,0,BASE);e('lbzx',0,0,0)
    # Negative displacement and destination/base/count alias reads.
    e('addi',16,1,4);e('lwz',16,16,-4)
    e('addi',17,0,8);e('lwzx',17,1,17)
    # Nonzero XER flags must survive all selected-field comparisons.
    e('addis',18,0,0x7fff);e('ori',18,18,0xffff);e('addi',19,0,1);e('addco',20,18,19)
    for bf in range(8):
        e('cmp',bf,20,19);e('cmpl',bf,20,19)
        e('cmpi',bf,19,0xffff);e('cmpli',bf,19,0xffff)
    e('cmpi',3,19,1)
    e('bc',12,14,'equal',0,1);e('illegal')
    p.label('equal');e('mflr',21)
    e('bc',4,14,'bad',0,1);e('mflr',22) # not taken but LK still writes
    e('b','subroutine',0,1)
    p.label('returned');e('addi',24,0,'ctr_target');e('mtctr',24);e('bcctr',20,0,1)
    e('illegal')
    p.label('ctr_target');e('mflr',26);e('mfctr',27)
    e('b','absolute',1,0);e('illegal')
    p.label('absolute');e('bc',12,14,'absolute_cond',1,0);e('illegal')
    p.label('absolute_cond');e('addi',28,0,0x55);e('b','end',0,0)
    p.label('subroutine');e('mflr',25);e('addi',23,0,0x123);e('bclr',20,0,0)
    p.label('bad');e('illegal')
    p.label('end')
    # Exercise decrement/zero/condition truth tables independently of BO decode.
    for bo in (0,2,4,8,10,12,16,18,20):
        for count in (0,1,2):
            for condition in (0,1):
                tag=f'bo{bo}_{count}_{condition}'
                e('addi',29,0,count);e('mtctr',29)
                e('addi',30,0,0xffff if condition else 1)
                e('cmpi',0,30,0)
                e('bc',bo,0,tag+'_taken',0,1)
                e('addi',29,0,0x11);e('b',tag+'_join',0,0)
                p.label(tag+'_taken');e('addi',29,0,0x22)
                p.label(tag+'_join');e('mfctr',31)
    # bclrl must use old LR as target while installing a new link, aligned down.
    e('addi',29,0,'lr_target');e('addi',29,29,3);e('mtlr',29)
    e('bclr',20,0,1);e('illegal')
    p.label('lr_target');e('mflr',30)
    # Branch-to-CTR also aligns its old target and does not decrement CTR.
    e('addi',29,0,'ctr_aligned');e('addi',29,29,3);e('mtctr',29)
    e('bcctr',20,0,1);e('illegal')
    p.label('ctr_aligned');e('mfctr',31)
    e('b','abs_link',1,1);e('illegal')
    p.label('abs_link');e('mflr',21)
    e('cmpi',7,19,1)
    e('bc',12,30,'abs_cond_link',1,1);e('illegal')
    p.label('abs_cond_link');e('mflr',22)
    e('cmpi',7,0,0) # comparison rA0 is a real source register
    e('illegal')
    return p

def make_shifts():
    p=make_program()
    # Prefix real SO=0 record shifts; relocation uses symbolic labels.
    prefix=[('addi',(9,0,1)),('addi',(10,0,31)),('slw',(11,9,10,1)),('srw',(12,11,10,1))]
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop() # extend the ordinary program before its terminal diagnostic
    e=p.emit
    for source in (0,1,0x80000000,0xffffffff,0x89abcdef):
        e('addis',9,0,source>>16);e('ori',9,9,source&65535)
        for count in range(64):
            e('addi',10,0,count)
            for op in ('slw','srw'):
                for rc in (0,1):e(op,11,9,10,rc)
    for count in (64,65,0x80000000,0x80000001,0x8000001f,0x80000020,0x8000003f,0xffffffff):
        e('addis',10,0,count>>16);e('ori',10,10,count&65535)
        for op in ('slw','srw'):
            for rc in (0,1):e(op,11,9,10,rc)
    # Nonzero r0 and destination/source/count alias cases.
    e('addi',0,0,1);e('slw',0,0,0,1);e('srw',0,0,0,0)
    e('addi',10,0,1);e('slw',9,9,10,0);e('srw',10,9,10,1)
    e('illegal')
    return p

def make_arithmetic_shifts():
    p=make_program()
    prefix=[('addi',(9,0,-7)),('srawi',(11,9,1,1)),('srawi',(12,11,0,0))]
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop(); e=p.emit
    for source in (0,1,0x7fffffff,0x80000000,0xffffffff,0xfffffff8,0xfffffff9,0x89abcdef):
        e('addis',9,0,source>>16);e('ori',9,9,source&65535)
        for count in range(64):
            e('addi',10,0,count)
            for rc in (0,1):
                e('sraw',11,9,10,rc)
                if count<32: e('srawi',12,9,count,rc)
    for count in (64,65,0x80000000,0x80000001,0x8000001f,0x80000020,0x8000003f,0xffffffff):
        e('addis',10,0,count>>16);e('ori',10,10,count&65535)
        for rc in (0,1):e('sraw',11,9,10,rc)
    e('addi',0,0,-7);e('srawi',0,0,1,1)
    e('addi',10,0,1);e('sraw',9,9,10,0);e('sraw',10,9,10,1)
    e('sraw',0,0,0,1);e('illegal')
    return p

def make_insert():
    p=make_program()
    prefix=[('addi',(9,0,-1)),('addi',(11,0,0)),('rlwimi',(11,9,0,31,31,1)),
            ('rlwimi',(9,11,31,0,31,0))]
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit
    e('addis',9,0,0x1234);e('ori',9,9,0x5678)
    e('addis',11,0,0xa5a5);e('ori',11,11,0x5a5a)
    for mb in range(32):
        for me in range(32):
            for rc in (0,1):e('rlwimi',11,9,(mb+me)%32,mb,me,rc)
    for source in (0,0xffffffff,0x80000001):
        e('addis',9,0,source>>16);e('ori',9,9,source&65535)
        for sh in range(32):
            e('rlwimi',9,9,sh,28,3,sh%2) # same renamed producer on both sources
            e('rlwimi',11,9,sh,8,15,(sh+1)%2)
    e('addi',0,0,-1);e('rlwimi',0,0,1,31,31,1)
    e('addi',9,0,0);e('rlwimi',0,9,0,0,31,1) # full replacement -> zero CR0
    e('addi',0,0,1);e('rlwimi',11,0,31,0,0,1)
    e('illegal');return p

def make_subtract():
    p=make_program()
    prefix=[('addi',(9,0,1)),('addi',(10,0,0))]
    for oe in (0,1):
        for rc in (0,1):prefix.extend([('subf',(11,9,10,oe,rc)),('neg',(12,9,oe,rc))])
    prefix.extend([('addis',(9,0,0x8000)),('neg',(12,9,1,1))])
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit
    values=(0,1,2,0x7fffffff,0x80000000,0x80000001,0xfffffffe,0xffffffff)
    for ca in (0,1):
        e('addis',18,0,0x8000 if ca else 0);e('addco',20,18,18)
        for a in values:
            e('addis',9,0,a>>16);e('ori',9,9,a&65535)
            for oe in (0,1):
                for rc in (0,1):e('neg',12,9,oe,rc)
            for b in values:
                e('addis',10,0,b>>16);e('ori',10,10,b&65535)
                for oe in (0,1):
                    for rc in (0,1):e('subf',11,9,10,oe,rc)
    e('addi',0,0,-1);e('subf',0,0,0,1,1)
    e('addi',0,0,-1);e('neg',0,0,1,1)
    e('subf',9,9,10,0,0);e('subf',10,9,10,1,1)
    e('illegal');return p

def make_subcarry():
    p=make_program()
    prefix=[('addi',(9,0,1)),('addi',(10,0,0))]
    for oe in (0,1):
        for rc in (0,1):prefix.append(('subfc',(11,9,10,oe,rc)))
    prefix.extend([('addis',(9,0,0x8000)),('subfc',(11,9,10,1,1))])
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit;e('addi',0,0,0)
    values=(0,1,2,0x7fffffff,0x80000000,0x80000001,0xfffffffe,0xffffffff)
    for ca in (0,1):
        e('addis',18,0,0x8000 if ca else 0)
        for a in values:
            e('addis',9,0,a>>16);e('ori',9,9,a&65535)
            for b in values:
                e('addis',10,0,b>>16);e('ori',10,10,b&65535)
                for oe in (0,1):
                    for rc in (0,1):
                        e('addco',20,18,18) # seed incoming CA independently for each form
                        e('subfc',11,9,10,oe,rc)
                        e('adde',13,0,0) # consumes new no-borrow CA immediately
    e('addi',0,0,-1);e('subfc',0,0,0,1,1)
    e('addi',0,0,1);e('subfc',9,0,9,0,0)
    e('subfc',9,9,10,0,1);e('subfc',10,9,10,1,0)
    e('illegal');return p

def make_subextend():
    p=make_subcarry()
    p.ops=[('subfe' if op=='subfc' else op,args) for op,args in p.ops]
    return p

def make_subunary():
    p=make_program()
    prefix=[('addi',(9,0,1)),('addi',(10,0,0)),('addi',(11,0,1))]
    for ci in (0,1):
        for op in ('subfme','subfze'):
            for oe in (0,1):
                for rc in (0,1):
                    prefix.extend([('subfc',(18,10 if ci else 11,10,0,0)),(op,(12,9,oe,rc))])
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit;e('addi',0,0,0)
    values=(0,1,2,0x7ffffffe,0x7fffffff,0x80000000,0x80000001,0xfffffffe,0xffffffff)
    for ci in (0,1):
        e('addis',18,0,0x8000 if ci else 0)
        for a in values:
            e('addis',9,0,a>>16);e('ori',9,9,a&65535)
            for op in ('subfme','subfze'):
                for oe in (0,1):
                    for rc in (0,1):
                        e('addco',20,18,18)
                        e(op,12,9,oe,rc)
                        e('adde',13,0,0)
    for i in range(64):
        e('subfme' if i%2 else 'subfze',9,9,(i//2)%2,i%2)
    e('addi',0,0,-1);e('subfme',0,0,1,1);e('subfze',0,0,1,1)
    e('illegal');return p

def make_subimmediate():
    p=make_program()
    prefix=[('addi',(0,0,1)),('subfic',(11,0,0)),('subfic',(0,0,0xffff)),('subfic',(11,0,0x8000))]
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit;e('addi',0,0,0)
    values=(0,1,2,0x7fffffff,0x80000000,0x80000001,0xffff8000,0xfffffffe,0xffffffff)
    immediates=sorted(set((0,1,2,0x7fff,0x8000,0xffff,0x8001,0xfffe,0x0401,0x5555,0xaaaa)+tuple(1<<i for i in range(16))))
    for ci in (0,1):
        e('addis',18,0,0x8000 if ci else 0)
        for a in values:
            e('addis',9,0,a>>16);e('ori',9,9,a&65535)
            for imm in immediates:
                e('addco',20,18,18)
                e('subfic',12,9,imm)
                e('adde',13,0,0)
    for i in range(32):e('subfic',9,9,1<< (i%16))
    e('addi',0,0,-1);e('subfic',0,0,0xffff);e('subfic',12,0,0x0401)
    e('illegal');return p

def make_addimmediate():
    p=make_subimmediate()
    expanded=[];relocation={}
    for i,(op,args) in enumerate(p.ops):
        relocation[i*4]=len(expanded)*4
        if op=='subfic':expanded.extend([('addic',args),('addic.',args)])
        else:expanded.append((op,args))
    p.ops=expanded
    p.labels={name:relocation[address] for name,address in p.labels.items()}
    return p

def make_andimmediate():
    p=make_subimmediate()
    expanded=[];relocation={}
    for i,(op,args) in enumerate(p.ops):
        relocation[i*4]=len(expanded)*4
        if op=='subfic':expanded.extend([('andi.',args),('andis.',args)])
        else:expanded.append((op,args))
    p.ops=expanded
    p.labels={name:relocation[address] for name,address in p.labels.items()}
    return p

def make_unarylogical():
    p=make_program()
    # Exercise SO=0 before the baseline program establishes sticky SO=1.
    prefix=[('addi',(0,0,-1))]
    for op in ('cntlzw','extsb','extsh'):
        for rc in (0,1):prefix.append((op,(11,0,rc)))
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit
    values=sorted(set([0,0xffffffff,0x7fffffff,0x80000000,0x7fff,0x8000,0xffff,0xffff0000]+[1<<i for i in range(32)]+[0xa55a0000|i for i in range(256)]+[0x5a5a0000|(i<<8)|0xa5 for i in range(0,256,4)]))
    for a in values:
        e('addis',9,0,a>>16);e('ori',9,9,a&65535)
        for op in ('cntlzw','extsb','extsh'):
            for rc in (0,1):e(op,12,9,rc)
    for op in ('cntlzw','extsb','extsh'):
        e('addi',0,0,-128)
        for rc in (0,1):e(op,0,0,rc)
    e('illegal');return p

def make_crtransfer():
    p=make_program()
    prefix=[('mfcr',(0,)),('addis',(0,0,0x1234)),('ori',(0,0,0x5678)),
            ('mtcrf',(255,0)),('mfcr',(0,)),('mtcrf',(0,0)),('mfcr',(11,))]
    p.ops=prefix+p.ops
    p.labels={name:address+4*len(prefix) for name,address in p.labels.items()}
    p.ops.pop();e=p.emit
    for mask in range(256):
        e('addis',9,0,0x1234);e('ori',9,9,0x5678);e('mtcrf',255,9)
        e('addis',9,0,0xedcb);e('ori',9,9,0xa987)
        e('mtcrf',mask,9);e('mfcr',9)
        e('cmpi',mask%8,20,0);e('mfcr',10)
    for field in range(8):
        e('addi',0,0,-1);e('mtcrf',128>>field,0);e('mfcr',0)
    e('illegal');return p

def make_crlogical():
    p=make_program();p.ops.pop();e=p.emit
    for truth in range(4):
        seed=0x55555554 | ((truth>>1)<<31) | (truth&1)
        e('addis',8,0,seed>>16);e('ori',8,8,seed&65535)
        for op in CROPS:
            for dest in range(32):
                e('mtcrf',255,8);e(op,dest,0,31);e('mfcr',9)
    for i in range(64):
        e(tuple(CROPS)[i%8],i%32,(i*7)%32,(i*13+1)%32);e('mfcr',9)
    for i in range(32):
        e(tuple(CROPS)[i%8],i,i,i);e('mfcr',9)
    e('illegal');return p

def make_crstate():
    p=make_program();p.ops.pop();e=p.emit
    for seed in (0x01234567,0x89abcdef):
        e('addis',8,0,seed>>16);e('ori',8,8,seed&65535)
        for source in range(8):
            for dest in range(8):
                e('mtcrf',255,8);e('mcrf',dest,source);e('mfcr',9)
    e('addi',0,0,0);e('addis',18,0,0x8000)
    e('addis',19,0,0x7fff);e('ori',19,19,0xffff);e('addi',17,0,1)
    for dest in range(8):
        for state in range(6):
            e('mcrxr',7)
            if state in (2,3,5):e('addco',20,18,18)
            if state in (0,2,3):e('addco',20,0,0)
            if state in (1,3):e('subfic',20,0,0)
            if state==4:e('addco',20,19,17)
            e('mtcrf',255,8);e('mcrxr',dest);e('mfcr',9)
            e('mcrxr',(dest+1)%8);e('mfcr',10)
            e('adde',13,0,0);e('andi.',14,17,1)
    for i in range(32):e('mcrf',i%8,(i+1)%8)
    e('illegal');return p

def make_multiply():
    p=make_program();p.ops.pop();e=p.emit
    values=[0,1,0xffffffff,2,0x7fffffff,0x80000000,0x10000,0xffff0000]
    def load(r,v):
        e('addis',r,0,v>>16);e('ori',r,r,v&65535)
    for oe in range(2):
        for rc in range(2):
            for av in values:
                for bv in values:
                    load(4,av);load(6,bv)
                    e('mullw',4,4,6,oe,rc)
    for av in values:
        for imm in [0,1,-1,2,-32768,32767]:
            load(0,av);e('mulli',0,0,imm)
    e('addi',0,0,0);e('addis',18,0,0x8000)
    for seed in range(2):
        for oe in range(2):
            for rc in range(2):
                e('mcrxr',7)
                if seed:e('addco',20,18,18)
                load(4,0x80000000);load(6,0xffffffff)
                e('mullw',7,4,6,oe,rc)
                e('addi',6,0,1);e('mullw',7,4,6,oe,rc)
                e('adde',13,0,0)
    e('addi',4,0,3)
    for _ in range(32):e('mulli',4,4,3)
    e('illegal');return p

def make_multiply_high():
    p=make_program();p.ops.pop();e=p.emit
    values=[0,1,0xffffffff,2,0x7fffffff,0x80000000,0x10000,0xffff0000]
    def load(r,v):
        e('addis',r,0,v>>16);e('ori',r,r,v&65535)
    for op in ('mulhw','mulhwu'):
        for rc in range(2):
            for av in values:
                for bv in values:
                    load(4,av);load(6,bv);e(op,4,4,6,rc)
            for av in values:
                load(0,av);load(6,0xffffffff);e(op,0,0,6,rc)
    e('addi',0,0,0)
    for seed in range(2):
        e('mcrxr',7)
        if seed:
            e('addis',18,0,0x8000);e('addco',20,18,18)
        load(4,0xffffffff);load(6,0xffffffff)
        for op in ('mulhw','mulhwu'):
            for rc in range(2):e(op,7,4,6,rc)
        e('adde',13,0,0)
    load(4,0xffffffff)
    for i in range(32):e('mulhw' if i%2 else 'mulhwu',4,4,6,i%2)
    e('illegal');return p

def make_divide_unsigned():
    p=make_program();p.ops.pop();e=p.emit
    values=[0,1,2,3,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]
    def load(r,v):
        e('addis',r,0,v>>16);e('ori',r,r,v&65535)
    for oe in range(2):
        for rc in range(2):
            for av in values:
                for bv in values:
                    load(4,av);load(6,bv);e('divwu',4,4,6,oe,rc)
            load(0,0xffffffff);e('divwu',0,0,0,oe,rc)
    e('addi',0,0,0)
    for seed in range(2):
        for oe in range(2):
            for rc in range(2):
                e('mcrxr',7)
                if seed:
                    e('addis',18,0,0x8000);e('addco',20,18,18)
                load(4,0xffffffff);e('addi',6,0,0)
                e('divwu',7,4,6,oe,rc)
                e('addi',6,0,3);e('divwu',7,4,6,oe,rc)
                e('adde',13,0,0)
    load(4,0xffffffff);e('addi',6,0,2)
    for _ in range(32):e('divwu',4,4,6,0,0)
    e('illegal');return p

def make_divide_signed():
    p=make_program();p.ops.pop();e=p.emit
    values=[0,1,2,3,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]
    def load(r,v):
        e('addis',r,0,v>>16);e('ori',r,r,v&65535)
    for oe in range(2):
        for rc in range(2):
            for av in values:
                for bv in values:
                    load(4,av);load(6,bv);e('divw',4,4,6,oe,rc)
            load(0,0xffffffff);e('divw',0,0,0,oe,rc)
    e('addi',0,0,0)
    for seed in range(2):
        for oe in range(2):
            for rc in range(2):
                e('mcrxr',7)
                if seed:
                    e('addis',18,0,0x8000);e('addco',20,18,18)
                load(4,0xffffffff);e('addi',6,0,0)
                e('divw',7,4,6,oe,rc)
                e('addi',6,0,3);e('divw',7,4,6,oe,rc)
                e('adde',13,0,0)
    load(4,0xffffffff);e('addi',6,0,2)
    for _ in range(32):e('divw',4,4,6,0,0)
    e('illegal');return p

def make_lsu_update():
    p=make_program();p.ops.pop();e=p.emit
    # All sizes/forms with signed displacements, each legal lane and immediate
    # consumers of both architectural destinations. Data and base are distinct.
    for stem,size in [('lbz',1),('lhz',2),('lha',2),('lwz',4),('stb',1),('sth',2),('stw',4)]:
        for indexed in (False,True):
            for lane in range(0,4,size):
                for displacement in (-16,0,16):
                    e('addi',4,0,BASE+96+lane-displacement)
                    e('addis',6,0,0x89ab);e('ori',6,6,0xcdef)
                    if indexed:e('addi',7,0,displacement)
                    e(stem+('ux' if indexed else 'u'),6,4,7 if indexed else displacement)
                    e('addi',8,4,0);e('addi',9,6,0)
                    e('lwz',10,0,BASE+96)
    # Store source aliases base: memory receives the old base, then EA replaces it.
    for stem in ('stb','sth','stw'):
        e('addi',4,0,BASE+128);e(stem+'u',4,4,4)
        e('addi',4,0,BASE+128);e('addi',7,0,8);e(stem+'ux',4,4,7)
    # Index aliases the loaded destination; r0 is a real index/destination.
    for stem in ('lbz','lhz','lha','lwz'):
        e('addi',4,0,BASE+128);e('addi',6,0,4);e(stem+'ux',6,4,6)
        e('addi',4,0,BASE+128);e('addi',0,0,8);e(stem+'ux',0,4,0)
        e('addi',4,0,(BASE+128)//2);e(stem+'ux',6,4,4)
    # Store source aliases index and all operands can name the same register.
    e('addi',4,0,BASE+128);e('addi',7,0,4);e('stwux',7,4,7)
    e('addi',4,0,(BASE+128)//2);e('stwux',4,4,4)
    # Wrapped effective address and repeated pointer increments.
    e('addi',4,0,-4);e('lwzu',6,4,BASE+4)
    e('addi',4,0,BASE+160)
    for _ in range(8):e('lwzu',6,4,4);e('add',7,6,4)
    e('illegal');return p

def write(output, shifts=False, arithmetic_shifts=False, insert=False, subtract=False, subcarry=False, subextend=False, subunary=False, subimmediate=False, addimmediate=False, andimmediate=False, unarylogical=False, crtransfer=False, crlogical=False, crstate=False, multiply=False, multiply_high=False, divide_unsigned=False, divide_signed=False, lsu_update=False):
    output.mkdir(parents=True,exist_ok=True)
    p=make_lsu_update() if lsu_update else make_divide_signed() if divide_signed else make_divide_unsigned() if divide_unsigned else make_multiply_high() if multiply_high else make_multiply() if multiply else make_crstate() if crstate else make_crlogical() if crlogical else make_crtransfer() if crtransfer else make_unarylogical() if unarylogical else make_andimmediate() if andimmediate else make_addimmediate() if addimmediate else make_subimmediate() if subimmediate else make_subunary() if subunary else make_subextend() if subextend else make_subcarry() if subcarry else make_subtract() if subtract else make_insert() if insert else make_arithmetic_shifts() if arithmetic_shifts else make_shifts() if shifts else make_program()
    assert p.encode(0,'mflr',(3,))==0x7c6802a6
    assert p.encode(0,'mtctr',(3,))==0x7c6903a6
    assert p.encode(0,'bclr',(20,0,0))==0x4e800020
    assert p.encode(0,'lwz',(3,4,8))==0x80640008
    assert p.encode(0,'sraw',(4,1,6,1))==0x7c243631
    assert p.encode(0,'srawi',(4,1,1,1))==0x7c240e71
    assert p.encode(0,'rlwimi',(13,7,29,28,3,1))==0x50edef07
    assert p.encode(0,'subf',(4,1,6,1,1))==0x7c813451
    assert p.encode(0,'neg',(4,1,1,1))==0x7c8104d1
    assert p.encode(0,'subfc',(4,1,6,1,1))==0x7c813411
    assert p.encode(0,'adde',(13,0,0))==0x7da00114
    assert p.encode(0,'subfe',(4,1,6,1,1))==0x7c813511
    assert p.encode(0,'subfme',(4,1,1,1))==0x7c8105d1
    assert p.encode(0,'subfze',(4,1,1,1))==0x7c810591
    assert p.encode(0,'subfic',(4,1,1))==0x20810001
    assert p.encode(0,'addic',(4,1,1))==0x30810001
    assert p.encode(0,'addic.',(4,1,1))==0x34810001
    assert p.encode(0,'andi.',(4,6,1))==0x70c40001
    assert p.encode(0,'andis.',(4,1,0x8000))==0x74248000
    assert p.encode(0,'cntlzw',(4,6,1))==0x7cc40035
    assert p.encode(0,'extsb',(4,6,1))==0x7cc40775
    assert p.encode(0,'extsh',(4,6,1))==0x7cc40735
    assert p.encode(0,'mfcr',(4,))==0x7c800026
    assert p.encode(0,'mtcrf',(0xa5,6))==0x7cca5120
    assert p.encode(0,'crand',(7,3,4))==0x4ce32202
    assert p.encode(0,'crxor',(7,3,4))==0x4ce32182
    assert p.encode(0,'mcrf',(5,2))==0x4e880000
    assert p.encode(0,'mcrxr',(5,))==0x7e800400
    snapshots,counts=p.simulate(limit=10000)
    (output/'program.hex').write_text('\n'.join(f'{p.encode(i*4,*op):08x}' for i,op in enumerate(p.ops))+'\n')
    (output/'expected.txt').write_text('\n'.join(' '.join(f'{x:08x}' for x in row) for row in snapshots)+'\n')
    (output/'manifest.txt').write_text(f'words={len(p.ops)} retirements={len(snapshots)}\n'+str(counts)+'\n')
    print(f'Generated memory/control program: {len(p.ops)} words, {len(snapshots)} expected retirements, {len(counts)} operation kinds')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,default=Path('build/control-memory'))
    ap.add_argument('--shifts',action='store_true')
    ap.add_argument('--arithmetic-shifts',action='store_true')
    ap.add_argument('--insert',action='store_true')
    ap.add_argument('--subtract',action='store_true')
    ap.add_argument('--subcarry',action='store_true')
    ap.add_argument('--subextend',action='store_true')
    ap.add_argument('--subunary',action='store_true')
    ap.add_argument('--subimmediate',action='store_true')
    ap.add_argument('--addimmediate',action='store_true')
    ap.add_argument('--andimmediate',action='store_true')
    ap.add_argument('--unarylogical',action='store_true')
    ap.add_argument('--crtransfer',action='store_true')
    ap.add_argument('--crlogical',action='store_true')
    ap.add_argument('--crstate',action='store_true')
    ap.add_argument('--multiply',action='store_true')
    ap.add_argument('--multiply-high',action='store_true')
    ap.add_argument('--divide-unsigned',action='store_true')
    ap.add_argument('--divide-signed',action='store_true')
    ap.add_argument('--lsu-update',action='store_true')
    # Both fixtures fit signed D-form immediates; 0x6000 separates unified
    # bus data RAM from the instruction image below 0x4000.
    ap.add_argument('--memory-base',type=lambda x:int(x,0),choices=(0x1000,0x6000),default=BASE)
    args=ap.parse_args()
    BASE=args.memory_base
    write(args.output,args.shifts,args.arithmetic_shifts,args.insert,args.subtract,args.subcarry,args.subextend,args.subunary,args.subimmediate,args.addimmediate,args.andimmediate,args.unarylogical,args.crtransfer,args.crlogical,args.crstate,args.multiply,args.multiply_high,args.divide_unsigned,args.divide_signed,args.lsu_update)
