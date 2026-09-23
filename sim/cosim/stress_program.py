"""Versioned seeded mixed PowerPC programs; no architectural state interpreter."""
from collections import Counter

GENERATOR_VERSION=1
MIN_BLOCKS=16
MAX_BLOCKS=512
KINDS=('carry_chain','logical_rotate','multiply_divide','memory_dependency',
       'update_alias','conditional','counted_loop','link_ctr','cr_transfer')


class Random32:
    def __init__(self,seed): self.state=(seed^0x9e3779b9) or 1
    def next(self):
        x=self.state
        x^=(x<<13)&0xffffffff;x^=x>>17;x^=(x<<5)&0xffffffff
        self.state=x&0xffffffff
        return self.state
    def pick(self,values): return values[self.next()%len(values)]
    def below(self,limit): return self.next()%limit


def generate(seed,blocks=120):
    if not isinstance(seed,int) or not 0<=seed<=0xffffffff: raise ValueError('seed must be uint32')
    if not isinstance(blocks,int) or not MIN_BLOCKS<=blocks<=MAX_BLOCKS:
        raise ValueError(f'blocks must be {MIN_BLOCKS}..{MAX_BLOCKS}')
    rng=Random32(seed);words=[];annotations=[];counts=Counter();block=-1;kind='initialize'
    def emit(word,name):
        annotations.append({'pc':len(words)*4,'word':f'{word&0xffffffff:08x}',
                            'block':block,'kind':kind,'operation':name})
        words.append(word&0xffffffff);counts[name]+=1
    def d(op,rt,ra,imm,name): emit((op<<26)|(rt<<21)|(ra<<16)|(imm&65535),name)
    def x(xo,rt,ra,rb,name,oe=0,rc=0):
        emit((31<<26)|(rt<<21)|(ra<<16)|(rb<<11)|(oe<<10)|(xo<<1)|rc,name)
    def const(reg,value):
        d(15,reg,0,value>>16,'addis');d(24,reg,reg,value,'ori')
    def spr(number,reg,write):
        emit((31<<26)|(reg<<21)|((number&31)<<16)|((number>>5)<<11)|
             ((467 if write else 339)<<1),f'{"mt" if write else "mf"}spr{number}')
    # Initialize data registers through real instructions. Registers15/20/21/22
    # are controlled scratch/address inputs, never assumptions about random ALU state.
    edges=[0,1,0xffffffff,0x7fffffff,0x80000000,0x80000001,0x000080ff]
    for reg in range(15): const(reg,rng.pick(edges) if reg<7 else rng.next())
    for offset in range(0,256,4):
        const(22,rng.next());d(36,22,0,0x1000+offset,'stw')
    # Every category occurs before later choices become fully randomized.
    for block in range(blocks):
        kind=KINDS[block] if block<len(KINDS) else rng.pick(KINDS)
        a=rng.below(15);b=rng.below(15);dst=rng.pick([a,b,rng.below(15)])
        rc=rng.below(2);oe=rng.below(2)
        if kind=='carry_chain':
            x(rng.pick([10,8]),dst,a,b,'carry-producer',oe=1,rc=1)
            x(rng.pick([138,136]),dst,dst,b,'carry-consumer-waw',oe=oe,rc=rc)
            unary=rng.pick([234,202,232,200])
            x(unary,dst,dst,0,'carry-unary',oe=oe,rc=1)
            x(316,dst,dst,a,'xor-dependent',rc=1)
        elif kind=='logical_rotate':
            x(rng.pick([28,60,284,476,124,444,412,316]),a,a,b,'logical-waw',rc=rc)
            mb=rng.below(32);me=rng.below(32);shift=rng.below(32)
            emit((20<<26)|(a<<21)|(dst<<16)|(shift<<11)|(mb<<6)|(me<<1)|1,'rlwimi-old-destination')
            x(rng.pick([24,536,792]),dst,dst,b,'shift-dependent',rc=1)
            x(rng.pick([26,954,922]),dst,dst,0,'unary-dependent',rc=rc)
        elif kind=='multiply_divide':
            multiply=rng.pick([235,75,11])
            x(multiply,dst,a,b,'multiply',oe=oe if multiply==235 else 0,rc=rc)
            # Positive known nonzero divisor prevents both divide exceptional
            # classes even though the numerator is an unknown prior result.
            const(15,rng.pick([1,3,7,31,65537,0x7fffffff]))
            x(rng.pick([459,491]),dst,dst,15,'divide-dependent',oe=oe,rc=1)
            x(266,dst,dst,b,'add-after-divide',rc=rc)
        elif kind=='memory_dependency':
            size=rng.pick([1,2,4]);offset=(rng.below(256)//size)*size
            store={1:38,2:44,4:36}[size];load={1:34,2:rng.pick([40,42]),4:32}[size]
            const(20,0x1000+offset)
            d(store,a,20,0,'store-random-data')
            d(load,dst,20,0,'load-after-store')
            x(266,dst,dst,b,'load-use')
            # Reuse this data in a different RAM word; preserve surrounding lanes.
            offset2=(offset+4)&255
            d(store,dst,0,0x1000+offset2,'store-load-result')
            d(load,a,0,0x1000+offset2,'alias-readback')
        elif kind=='update_alias':
            size=rng.pick([1,2,4]);offset=(rng.below(240)//size)*size
            store={1:39,2:45,4:37}[size];load={1:35,2:rng.pick([41,43]),4:33}[size]
            const(20,0x1000+offset-size)
            d(store,20,20,size,'store-update-old-ra')
            const(20,0x1000+offset-size)
            d(load,dst,20,size,'load-update-two-results')
            x(266,dst,dst,20,'consume-both-update-results')
            const(20,0x0800+offset//2) # old RA=RB sums to an aligned EA
            x({1:247,2:439,4:183}[size],20,20,20,'indexed-store-all-alias')
            const(20,0x1000+offset);const(21,size)
            x({1:119,2:375,4:55}[size],21,20,21,'indexed-load-rt-rb')
            x(316,a,21,20,'consume-indexed-update',rc=1)
        elif kind=='conditional':
            # Arbitrary current CR/CTR determine direction; every target is
            # forward and skips only one legal arithmetic instruction.
            emit((31<<26)|(rng.below(8)<<23)|(a<<16)|(b<<11),'cmp-field')
            bo=rng.pick([0,1,2,3,4,5,8,9,10,11,12,13,16,17,18,19,20])
            emit((16<<26)|(bo<<21)|(rng.below(32)<<16)|8|rc,'bc-forward')
            x(266,dst,a,b,'conditionally-skipped-add',oe=oe,rc=1)
            x(316,a,a,dst,'branch-dependent-join',rc=1)
        elif kind=='counted_loop':
            const(22,1+rng.below(5));spr(9,22,True)
            loop=len(words)*4
            x(266,a,a,b,'loop-accumulate',rc=rc)
            x(316,b,b,a,'loop-carried-dependency',rc=1)
            delta=loop-len(words)*4
            emit((16<<26)|(16<<21)|(delta&0xfffc),'bdnz-loop')
        elif kind=='link_ctr':
            # BL/BCLR single bounded return, then real MTCTR+BCCTR skips one
            # legal side-effecting arithmetic instruction. No random target.
            emit((18<<26)|8|1,'bl-call')
            emit((18<<26)|8,'b-return-join')
            emit((19<<26)|(20<<21)|(16<<1)|rc,'bclr-return')
            spr(8,a,False)
            target=(len(words)+5)*4
            const(22,target|rng.below(4));spr(9,22,True)
            emit((19<<26)|(20<<21)|(528<<1)|rc,'bcctr-forward')
            x(266,a,a,b,'ctr-skipped-add',rc=1)
            spr(9,b,False);spr(8,dst,False)
        else:
            emit((31<<26)|(a<<21)|(rng.below(256)<<12)|(144<<1),'mtcrf')
            emit((19<<26)|(rng.below(8)<<23)|(rng.below(8)<<18),'mcrf')
            emit((19<<26)|(rng.below(32)<<21)|(rng.below(32)<<16)|(rng.below(32)<<11)|
                 (rng.pick([257,129,289,225,33,449,417,193])<<1),'cr-logical')
            emit((31<<26)|(rng.below(8)<<23)|(512<<1),'mcrxr-clear')
            x(138,dst,a,b,'adde-after-clear',rc=1)
            emit((31<<26)|(dst<<21)|(19<<1),'mfcr-data')
    kind='finish';block=blocks
    # Read final RAM boundaries through real loads and leave one ordinary final
    # result; completion count, not an injected fault, terminates the RTL trace.
    d(32,0,0,0x1000,'final-load');d(34,1,0,0x10ff,'final-byte')
    x(266,2,0,1,'final-dependent-add',rc=1)
    if len(words)>16384: raise ValueError('generated instruction image exceeds bench limit')
    return words,{'generator_version':GENERATOR_VERSION,'seed':seed,'blocks':blocks,
                  'prng':'xorshift32(13,17,5), initial=(seed XOR 9e3779b9) or1',
                  'emitted_operations':dict(sorted(counts.items())),'instructions':annotations}
