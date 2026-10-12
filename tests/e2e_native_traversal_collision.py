#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Force identity/hash collisions through the actual early native entry."""
import argparse, hashlib, json, pathlib, shlex, subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
def node(i,h,children=()):return {'id':i,'hash':h,'children':list(children)}
cases=[
 ('colliding toolbar subtree survives',[node(1,9,[2,3]),node(2,9),node(3,9,[4]),node(4,9)],1,24,6000,[1,2,3,4],True),
 ('noncolliding baseline',[node(1,1,[2,3]),node(2,2),node(3,3)],1,24,6000,[1,2,3],True),
 ('duplicate equal reference deduplicates',[node(1,9,[2,2]),node(2,9)],1,24,6000,[1,2],True),
 ('cycle terminates with collisions',[node(1,9,[2]),node(2,9,[1])],1,24,6000,[1,2],True),
 ('unique count rather than hash buckets bounds walk',[node(1,9,[2,3]),node(2,9),node(3,9)],1,24,2,[1,2],False),
 ('depth remains bounded',[node(1,9,[2]),node(2,9,[3]),node(3,9)],1,2,6000,[1,2],False),
 ('ancestry distinct collisions reach terminal',[node(1,4,[2]),node(2,4,[3]),node(3,4)],1,16,100,[1,2,3],True),
 ('child identities stay distinct',[node(1,4,[2,3,4]),node(2,4),node(3,4),node(4,4)],1,4,16,[1,2,3,4],True),
 ('same identity not same bucket new child',[node(1,0,[2,3]),node(2,0,[4]),node(3,0,[4]),node(4,0)],1,24,6000,[1,2,4,3],True),
]
checks=[]
for name,nodes,root,depth,limit,visited,complete in cases:
 q={'operation':'collision-safe-traversal','nodes':nodes,'root':root,'max_depth':depth,'max_nodes':limit}
 run=subprocess.run([a.helper,'--policy-test'],input=json.dumps(q)+'\n',capture_output=True,text=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 result=r.get('result') if isinstance(r,dict) else None
 ok=run.returncode==0 and isinstance(result,dict) and result=={'visited':visited,'unique_count':len(visited),'complete':complete} and r.get('apple_accessed') is False
 checks.append({'name':name,'passed':ok,'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True)
report={'passed':all(c['passed'] for c in checks),'checks':checks,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
