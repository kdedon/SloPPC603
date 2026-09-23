"""Encoded corpus, without expected arithmetic/state copied from the RTL."""
from collections import Counter


def corpus():
    words, coverage = [], Counter()

    def emit(word, name):
        words.append(word & 0xffffffff)
        coverage[name] += 1

    def d(op, rt, ra, imm, name):
        emit((op << 26) | (rt << 21) | (ra << 16) | (imm & 65535), name)

    def const(reg, value):
        d(15, reg, 0, value >> 16, 'addis')
        d(24, reg, reg, value, 'ori')

    def x(xo, rd, ra, rb, oe, rc, name):
        emit((31 << 26) | (rd << 21) | (ra << 16) | (rb << 11) |
             (oe << 10) | (xo << 1) | rc, name)

    # Real instruction initialization; register zero becomes a nonzero source.
    d(14, 0, 0, 7, 'addi')
    pairs = [(0, 0), (0xffffffff, 1), (0x7fffffff, 1),
             (0x80000000, 0xffffffff), (0x80000000, 0),
             (0xffffffff, 0xffffffff), (0x80000000, 0x80000000)]
    arithmetic = [('add',266),('addc',10),('adde',138),('addme',234),
                  ('addze',202),('subf',40),('subfc',8),('subfe',136),
                  ('subfme',232),('subfze',200),('neg',104)]
    unary = {'addme','addze','subfme','subfze','neg'}
    for name, xo in arithmetic:
        for oe in range(2):
            for rc in range(2):
                for ca in range(2):
                    for a,b in pairs:
                        const(3,a); const(4,b)
                        const(5,0xffffffff if ca else 0)
                        d(12,5,5,1,'addic')  # committed CA, preserves sticky SO
                        x(xo,3,3,0 if name in unary else 4,oe,rc,f'{name}/oe{oe}/rc{rc}')
    for op,name in [(8,'subfic'),(12,'addic'),(13,'addic.'), (14,'addi'),(15,'addis'),
                    (24,'ori'),(25,'oris'),(26,'xori'),(27,'xoris'),(28,'andi.'),(29,'andis.')]:
        for imm in [0,1,0x8000,0xffff]:
            d(op,0,0,imm,name)
    for name,xo in [('and',28),('andc',60),('eqv',284),('nand',476),
                    ('nor',124),('or',444),('orc',412),('xor',316)]:
        for rc in range(2):
            const(3,0x81234567); const(4,0xa5a55a5a)
            x(xo,3,3,4,0,rc,f'{name}/rc{rc}')
    for name,xo in [('slw',24),('srw',536),('sraw',792),('srawi',824)]:
        for rc in range(2):
            for count in [0,1,15,31,32,63,64,255]:
                const(3,0x80010001); const(4,count)
                x(xo,3,3,count & 31 if name == 'srawi' else 4,0,rc,f'{name}/rc{rc}')
    for op,name in [(20,'rlwimi'),(21,'rlwinm'),(23,'rlwnm')]:
        for rc in range(2):
            for mb,me in [(0,31),(31,0),(15,15),(17,3)]:
                const(3,0x81234567); const(4,0xa5a55a5a); const(5,37)
                emit((op<<26)|(3<<21)|(4<<16)|((5 if op==23 else 17)<<11)|
                     (mb<<6)|(me<<1)|rc,f'{name}/rc{rc}')
    for bf in range(8):
        const(3,0x80000000); const(4,1)
        for op,name in [(10,'cmpli'),(11,'cmpi')]:
            emit((op<<26)|(bf<<23)|(3<<16)|0xffff,name)
        for xo,name in [(0,'cmp'),(32,'cmpl')]:
            emit((31<<26)|(bf<<23)|(3<<16)|(4<<11)|(xo<<1),name)
    for name,xo in [('crand',257),('crandc',129),('creqv',289),('crnand',225),
                    ('crnor',33),('cror',449),('crorc',417),('crxor',193)]:
        for bit in range(32):
            emit((19<<26)|(bit<<21)|(bit<<16)|(((bit+1)%32)<<11)|(xo<<1),name)
    for aa in range(2):
        for lk in range(2):
            pc=len(words)*4
            emit((18<<26)|((pc+4 if aa else 4)&0x3fffffc)|(aa<<1)|lk,f'b/aa{aa}/lk{lk}')
            for bo in [0,1,2,3,4,5,8,9,10,11,12,13,16,17,18,19,20]:
                pc=len(words)*4
                emit((16<<26)|(bo<<21)|((pc+4 if aa else 4)&0xfffc)|(aa<<1)|lk,
                     f'bc/aa{aa}/lk{lk}')
    # Calls execute out of address order, then return through the old LR.
    for lk in range(2):
        emit((18<<26)|8|1,'b/call')
        emit((18<<26)|8,'b/skip-return')
        emit((19<<26)|(20<<21)|(16<<1)|lk,f'bclr/lk{lk}')
    # Set CR[0]=0 with an actual original CR handler; BO12 is false.
    emit((19<<26)|(193<<1),'crxor')
    for lk in range(2):
        emit((19<<26)|(12<<21)|(528<<1)|lk,f'bcctr/lk{lk}')

    # Expanded register-only lane. Keep this after the absolute BC cases so
    # their positive signed-16 targets remain in range as the corpus grows.
    mult_pairs=[(0,1),(0xffffffff,2),(0x7fffffff,2),(0x80000000,0xffffffff),
                (0x80000000,0x80000000),(0x12345678,0x87654321)]
    div_pairs=[(0,1),(1,2),(0xffffffff,2),(0x80000000,1),
               (0x80000000,3),(0x7fffffff,0xfffffffd),(0xfffffff9,3),
               (0xfffffff9,0xfffffffd),(0xffffffff,0xffffffff)]
    for name,xo,operands in [('mullw',235,mult_pairs),('divw',491,div_pairs),('divwu',459,div_pairs)]:
        for oe in range(2):
            for rc in range(2):
                for a,b in operands:
                    # Seed actual SO/OV/CA, then prove each operation's masks.
                    const(6,0x80000000)
                    x(10,6,6,6,1,1,'addc/oe1/rc1')
                    const(3,a); const(4,b)
                    x(xo,3,3,4,oe,rc,f'{name}/oe{oe}/rc{rc}')
                    # Dependent consumer reads a result held by the divider.
                    d(14,7,3,-1,'addi')
    for name,xo in [('mulhw',75),('mulhwu',11)]:
        for rc in range(2):
            for a,b in mult_pairs:
                const(3,a); const(4,b)
                x(xo,4,3,4,0,rc,f'{name}/rc{rc}')
    for value in [0,1,0xffffffff,0x80000000,0x7fffffff]:
        for imm in [0,1,0xffff,0x8000,0x7fff]:
            const(0,value)
            d(7,0,0,imm,'mulli')
    for name,xo in [('cntlzw',26),('extsb',954),('extsh',922)]:
        for rc in range(2):
            for value in [0,1,0x7f,0x80,0xff,0x7fff,0x8000,0xffff,0x80000000,0xffffffff]:
                const(0,value)
                x(xo,0,0,0,0,rc,f'{name}/rc{rc}')

    def spr(number, reg, write):
        emit((31<<26)|(reg<<21)|((number&31)<<16)|((number>>5)<<11)|
             ((467 if write else 339)<<1),f'{"mtspr" if write else "mfspr"}/{number}')

    for number in [8,9]:
        for value in [0,1,0xffffffff,0x80000000,0x1234567b]:
            const(0,value); spr(number,0,True); spr(number,0,False)
            x(266,7,0,0,0,0,'add/oe0/rc0')
    # Every MTCRF field mask, followed immediately by architectural readback.
    for mask in range(256):
        const(0,(0x12345678 ^ (mask*0x01010101)) & 0xffffffff)
        emit((31<<26)|(mask<<12)|(144<<1),'mtcrf')
        emit((31<<26)|(0<<21)|(19<<1),'mfcr')
    for dst in range(8):
        for src in range(8):
            emit((19<<26)|(dst<<23)|(src<<18),'mcrf')
    for dst in range(8):
        for seed in range(3):
            # Three reachable flag states: E (SO/OV/CA), A (SO/CA), zero.
            const(3,0x80000000)
            x(10,3,3,3,1,1,'addc/oe1/rc1')
            if seed == 1:
                const(3,0xffffffff); const(4,1)
                x(10,3,3,4,1,0,'addc/oe1/rc0')
            if seed == 2:
                emit((31<<26)|(dst<<23)|(512<<1),'mcrxr')
            emit((31<<26)|(dst<<23)|(512<<1),'mcrxr')
            # Clear-CA/SO become inputs to subsequent actual arithmetic.
            x(138,3,3,3,0,1,'adde/oe0/rc1')
    # Actual taken BCTR/BCTRL to a nonsequential target, with discarded low
    # two CTR bits, LR writeback and a skipped legal instruction.
    for lk in range(2):
        target=(len(words)+5)*4
        const(0,target|3)
        spr(9,0,True)
        emit((19<<26)|(20<<21)|(528<<1)|lk,f'bcctr/lk{lk}')
        d(14,31,0,-321,'addi')  # skipped; comparison would catch its retirement
        spr(9,5,False); spr(8,6,False)
    d(14,31,0,123,'addi')
    return words, dict(sorted(coverage.items()))
