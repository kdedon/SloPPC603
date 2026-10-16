#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Guard one existing Dhrystone image and compare matched observer outputs.

No benchmark engine, source compilation or simulator invocation. The optional
Make target owns serialized builds/runs. Ratios print only after checksum,
configuration, existing firmware correctness and meaningful path coverage pass.
"""
from pathlib import Path
import argparse,hashlib,json,re,shutil
IMAGE_SHA='9e8788c32815aec52ebbad8ea913ecc3afebf8f242ae3ab2663cf04db4eef2a6'
DUMP_SHA='3fc726a3853abb0ace9794ed3dfaac2087cc90b54a90c801bd298dac5124a6cb'
LANDMARKS={'start_pc':'fff03ecc','start_word':'80810058','stop_pc':'fff03ff8','stop_word':'48000c55'}
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def require(ok,message):
    if not ok:raise ValueError(message)
def sources(root):
    files=[p for base in (root/'rtl',root/'tb'/'soc') for p in base.rglob('*') if p.suffix in ('.sv','.svh')]
    files.extend([root/'tb/machine_trace.svh',root/'sim/Makefile',root/'sim/tools/integer_branch_pair.mk',root/'sim/tools/integer_branch_pair.py'])
    require(bool(files) and all(p.is_file() for p in files),'missing canonical source files; apply adapter first')
    return {str(p.relative_to(root)):digest(p) for p in sorted(set(files))}
def source_guard(out):
    data=json.loads((out/'input.json').read_text());root=Path(data['repo_root'])
    require(sources(root)==data['sources'],'source changed within paired run')
def prepare(image,dump,out,root):
    require(digest(image)==IMAGE_SHA,'image differs from reviewed benchmark; review/rederive landmarks before changing pins')
    require(digest(dump)==DUMP_SHA,'dump differs from reviewed benchmark')
    text=dump.read_text()
    for prefix in ('start','stop'):
        pc=LANDMARKS[prefix+'_pc'];word=LANDMARKS[prefix+'_word']
        bytes_pattern=r'\s+'.join(word[i:i+2] for i in range(0,8,2))
        require(re.search(r'^'+pc+r':\s*'+bytes_pattern+r'\b',text,re.M),'guarded landmark instruction missing: '+pc)
    fingerprints=sources(root)
    out.mkdir(parents=True,exist_ok=True)
    for name in ('fpu0.log','fpu1.log','fpu0.tuples','fpu1.tuples','fpu0.digest.json','fpu1.digest.json','comparison.json'):
        (out/name).unlink(missing_ok=True)
    shutil.copyfile(image,out/'frozen.hex')
    (out/'input.json').write_text(json.dumps({'image_sha256':IMAGE_SHA,'dump_sha256':DUMP_SHA,'landmarks':LANDMARKS,'required_initial_ram':{'plusarg':'INTEGER_PAIR_ZERO_RAM','words':32768,'bits_per_word':64,'fill':0,'before_image':True,'runtime_certificate_required':True},'repo_root':str(root.resolve()),'sources':fingerprints},indent=2)+'\n')
    print('Prepared fixed Dhrystone image/landmarks; no model executed.')
def tuples(path):
    h=hashlib.sha256();count=0;partial=0;branches=0
    with path.open() as stream:
        for line in stream:
            if line.startswith('#'):continue
            parts=line.split()
            require(len(parts)==27 and all(re.fullmatch('[0-9a-fA-F]+',x) for x in parts),'malformed/unknown retirement tuple')
            h.update((' '.join(x.lower() for x in parts)+'\n').encode());count+=1
            require(parts[2] in ('0','1') and parts[22] in ('0','1'),'invalid partial/branch permission')
            partial+=int(parts[2],16);branches+=int(parts[22],16)
    require(count>0,'empty retirement tuple stream')
    return {'count':count,'sha256':h.hexdigest(),'partial':partial,'macros':count-partial,'branches':branches}
def profile(path):
    text=path.read_text(errors='replace')
    require(not re.search(r'\b(?:FAIL|MISMATCH|Error|Fatal)\b',text),'failure in '+str(path))
    # Require actual loader certification, not just the requested plusarg.
    init_rows=re.findall(r'^INTEGER_PAIR_RAM_INIT.*$',text,re.M)
    require(init_rows==['INTEGER_PAIR_RAM_INIT words=32768 bits=64 fill=0 before_image=1'],
            'missing/duplicate/wrong architectural RAM initialization certificate')
    require(re.search(r'checks:\s*(\d+), mismatches\s+0',text),'missing Dhrystone checks')
    checks=int(re.search(r'checks:\s*(\d+), mismatches\s+0',text)[1]);require(checks>=20,'too few firmware checks')
    require(re.search(r'PASS dhrystone-fpu[01]: exit=00000000',text),'missing existing benchmark pass')
    rows=re.findall(r'^INTEGER_PAIR (.*)$',text,re.M);require(len(rows)==1,'missing/duplicate observer report')
    result={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',rows[0])}
    fw=re.search(r'perf dhrystone: cycles\s+(\d+) retired\s+(\d+)',text)
    require(fw,'missing firmware timed performance counters')
    result['firmware_cycles']=int(fw[1]);result['firmware_packets']=int(fw[2])
    require(re.search(r'cycles/run:\s*\d+\.\d+',text),'missing cycles/run')
    result['cycles_per_run']=re.search(r'cycles/run:\s*(\d+\.\d+)',text)[1]
    require(all(result.get(k,0)>0 for k in ('cycles','packets','macros','branches','spec','resolve','miss')),'vacuous branch/window metrics')
    require(result.get('fp')==0 and result.get('anchor')==0 and result.get('removed')==0,'noninteger/anchored profile')
    return result

def save_digest(out,profile_id,keep):
    source_guard(out)
    path=out/f'fpu{profile_id}.tuples'
    info=tuples(path);count=info['count']
    (out/f'fpu{profile_id}.digest.json').write_text(json.dumps(info)+'\n')
    if not keep:path.unlink()
    print(f'Prepared retirement digest fpu{profile_id}: {count} tuples; raw tuple file '+('retained' if keep else 'removed'))
def compare(out):
    source_guard(out)
    require(digest(out/'frozen.hex')==IMAGE_SHA,'paired image changed')
    inputs=json.loads((out/'input.json').read_text());require(inputs['image_sha256']==IMAGE_SHA and inputs['landmarks']==LANDMARKS,'input manifest drift')
    a,b=profile(out/'fpu0.log'),profile(out/'fpu1.log')
    expected={'dcache':0,'dmem':32,'width':2,'fetch':2,'lsu':1,'removal':0,'fdreg':0,'now':1,'full':1,'anchor':0,'iq':6,'cq':5,'rename':5}
    for k,v in expected.items():require(a.get(k)==v and b.get(k)==v,'incorrect matched setting '+k)
    for k in ('sq','snoop','basewait','cpumodel','ce','mhz','icsets','icways'):
        require(k in a and a[k]==b.get(k),'effective profile mismatch '+k)
    require(a['fpu']==0 and b['fpu']==1 and a['early']==1 and b['early']==0,'wrong FPU/early pair')
    require(a['fast']>0 and a['slow']==0 and a['slow_origin']==0 and b['fast']==0 and b['slow']>0 and b['slow_origin']>0,'missing meaningful fast/slow accepted recovery')
    da=json.loads((out/'fpu0.digest.json').read_text());db=json.loads((out/'fpu1.digest.json').read_text())
    ta,tb=(da['count'],da['sha256']),(db['count'],db['sha256'])
    require(da==db,'normalized active architectural retire stream differs')
    for key in ('macros','partial','branches'):
        require(da[key]==a[key] and db[key]==b[key],'public tuple/observer count mismatch '+key)
    require(ta[0]==a['packets']==b['packets'],'tuple/packet counts differ')
    require(a['macros']==b['macros'] and a['partial']==b['partial'],'macro/partial populations differ')
    result={'scope':'uncached32 integer modeled throughput; not production cached64 or Fmax','fpu0':a,'fpu1':b,'tuples':ta[0],'sha256':ta[1],
            'public_loop_ratio':b['cycles']/a['cycles'],'firmware_ratio':b['firmware_cycles']/a['firmware_cycles']}
    (out/'comparison.json').write_text(json.dumps(result,indent=2)+'\n')
    print(f"PASS matched integer pair: tuples={ta[0]} sha256={ta[1]}")
    print(f"loop cycles off={a['cycles']} on={b['cycles']} ratio={result['public_loop_ratio']:.6f}; firmware ratio={result['firmware_ratio']:.6f}")

def main():
    ap=argparse.ArgumentParser(description=__doc__);sub=ap.add_subparsers(dest='command',required=True)
    p=sub.add_parser('prepare');p.add_argument('--image',type=Path,required=True);p.add_argument('--dump',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--repo-root',type=Path,default=Path.cwd().parent)
    p=sub.add_parser('digest');p.add_argument('--out',type=Path,required=True);p.add_argument('--profile',type=int,choices=(0,1),required=True);p.add_argument('--keep-tuples',action='store_true')
    p=sub.add_parser('compare');p.add_argument('--out',type=Path,required=True)
    a=ap.parse_args()
    if a.command=='prepare':prepare(a.image,a.dump,a.out,a.repo_root.resolve())
    elif a.command=='digest':save_digest(a.out,a.profile,a.keep_tuples)
    else:compare(a.out)
if __name__=='__main__':main()
