"""All original register corpus plus aligned scalar memory instruction streams."""
from collections import Counter
from reference_program import corpus as register_corpus

# Names/encodings are independent of expected state and of the RTL decoder.
FORMS=[('lwz',32,23,4,True),('lbz',34,87,1,True),('stw',36,151,4,False),
       ('stb',38,215,1,False),('lhz',40,279,2,True),('lha',42,343,2,True),
       ('sth',44,407,2,False)]


def corpus():
    words,groups=register_corpus()
    groups=Counter(groups)
    def emit(word,name):
        words.append(word&0xffffffff);groups[name]+=1
    def d(op,rt,ra,imm,name):
        emit((op<<26)|(rt<<21)|(ra<<16)|(imm&65535),name)
    def const(reg,value):
        d(15,reg,0,value>>16,'addis');d(24,reg,reg,value,'ori')
    def x(xo,rt,ra,rb,name):
        emit((31<<26)|(rt<<21)|(ra<<16)|(rb<<11)|(xo<<1),name)
    # Fill every RAM word through original STW, with bytes/halfwords of both
    # signs. Data RAM and the immutable instruction image are separate spaces.
    for offset in range(0,256,4):
        const(3,0x80ff7f01 ^ (offset*0x01010101))
        d(36,3,0,0x1000+offset,'stw')
    for name,op,xo,size,load in FORMS:
        for update in range(2):
            for indexed in range(2):
                label=name+('u' if update else '')+('x' if indexed else '')
                for offset in range(0,8,size):
                    const(3,0xa580ff01 ^ offset)
                    # Negative D displacement and positive indexed count both
                    # reach the same aligned architectural byte address.
                    const(4,0x1000+offset+(4 if not indexed else -4))
                    const(5,4 if indexed else 0)
                    if indexed:
                        x(xo+32*update,3,4,5,label)
                    else:
                        d(op+update,3,4,-4,label)
                    # Both potential update destinations feed following work.
                    x(266,6,3,4,'add/oe0/rc0')
    # Explicit old-source alias patterns. Store-update source may equal RA;
    # indexed loads may have destination RB; RA and RB may be equal.
    for name,op,xo,size,load in FORMS:
        for update in range(2):
            label=name+('u' if update else '')
            if not load:
                const(4,0x1040)
                d(op+update,4,4,size,label)  # old rA is store data
                const(4,0x0820)
                x(xo+32*update,4,4,4,label+'x')  # old rS=rA=rB
            else:
                const(4,0x1040);const(5,size)
                x(xo+32*update,5,4,5,label+'x')  # rD=rB, legal update
                const(4,0x0820)
                x(xo+32*update,3,4,4,label+'x')  # old rA=rB
    # Signed halfword anchors for every D/indexed base/update spelling.
    const(3,0x80007fff);d(36,3,0,0x10e0,'stw')
    for update in range(2):
        for indexed in range(2):
            for offset in [0,2]:
                const(4,0x10e0);const(5,offset)
                label='lha'+('u' if update else '')+('x' if indexed else '')
                if indexed: x(343+32*update,7,4,5,label)
                else: d(42+update,7,4,offset,label)
    for name,op,xo,size,load in FORMS:
        if load:
            const(4,0x1050);d(op,4,4,0,name)
    # RA0 zero-base rule coexists with an ordinary nonzero r0 index/source.
    const(0,0x1080)
    x(23,7,0,0,'lwzx')
    d(36,0,0,0x1084,'stw')
    d(32,0,0,0x1084,'lwz')
    # Explicit upper/lower range boundaries, all alignment classes.
    d(34,7,0,0x1000,'lbz');d(34,7,0,0x10ff,'lbz')
    d(40,7,0,0x10fe,'lhz');d(32,7,0,0x10fc,'lwz')
    d(14,31,0,123,'addi')
    return words,dict(sorted(groups.items()))
