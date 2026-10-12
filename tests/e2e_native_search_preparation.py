#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Replay structural failures through the native early search entry."""
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
f={'query_matches':True,'category_matches':True,'owner_unchanged':True,'raw_count':0,'codes':[],'target_present':False,'labels':[]}
def frame(**changes):return {**f,**changes}
cases=[
 ('empty complete pair',{'stage':'empty_witness','frames':[frame(),frame()]},True),
 ('stale prior cannot poison fresh complete frames',{'stage':'empty_witness','prior_incomplete':True,'frames':[frame(codes=[-25202]),frame(),frame()]},True),
 ('incomplete frame cannot be accepted',{'stage':'empty_witness','frames':[frame(codes=[-25202]),frame(codes=[-25202])]},False),
 ('cannotComplete resets consecutive pair',{'stage':'empty_witness','frames':[frame(),frame(codes=[-25204]),frame()]},False),
 ('query mismatch resets pair',{'stage':'empty_witness','frames':[frame(),frame(query_matches=False),frame()]},False),
 ('category mismatch resets pair',{'stage':'empty_witness','frames':[frame(),frame(category_matches=False),frame()]},False),
 ('owner change refuses pair',{'stage':'empty_witness','frames':[frame(),frame(owner_unchanged=False)]},False),
 ('nonempty sentinel model unverified',{'stage':'empty_witness','frames':[frame(raw_count=2024),frame(raw_count=2024)]},False),
 ('optional noValue is not invalidUIElement',{'stage':'empty_witness','frames':[frame(codes=[-25212]),frame(codes=[-25212])]},True),
 ('bounded exact target stable',{'stage':'target_model','frames':[frame(raw_count=1,target_present=True,labels=[['synthetic']]),frame(raw_count=1,target_present=True,labels=[['synthetic']])]},True),
 ('changed label generation refuses target',{'stage':'target_model','frames':[frame(raw_count=1,target_present=True,labels=[['synthetic']]),frame(raw_count=1,target_present=True,labels=[['other']])]},False),
 ('target over bound refuses',{'stage':'target_model','frames':[frame(raw_count=101,target_present=True),frame(raw_count=101,target_present=True)]},False),
 ('zero target is not absence proof',{'stage':'target_model','frames':[frame(),frame()]},False),
 ('raw restoration after filtered model',{'stage':'clear_model','before_count':1,'frames':[frame(raw_count=2024,published_count=2019),frame(raw_count=2024,published_count=2019)]},True),
 ('maintenance5 mismatched count domains hold',{'stage':'clear_model','before_count':2024,'frames':[frame(raw_count=2024,published_count=2019),frame(raw_count=2024,published_count=2019)]},False),
 ('published count cannot masquerade as complete raw cache',{'stage':'clear_model','before_count':2019,'frames':[frame(raw_count=2019,published_count=2019),frame(raw_count=2019,published_count=2019)]},False),
 ('known complete raw cache proves unchanged count',{'stage':'clear_model','before_count':2024,'cached_raw_count':2024,'frames':[frame(raw_count=2024,published_count=2019),frame(raw_count=2024,published_count=2019)]},True),
 ('cached raw count mismatch holds',{'stage':'clear_model','before_count':2024,'cached_raw_count':2019,'frames':[frame(raw_count=2024),frame(raw_count=2024)]},False),
 ('clear category must match in same complete frame',{'stage':'clear_model','before_count':1,'frames':[frame(raw_count=2024,category_matches=False),frame(raw_count=2024,category_matches=False)]},False),
 ('known empty raw cache with zero published entries remains valid',{'stage':'clear_model','before_count':0,'cached_raw_count':0,'frames':[frame(raw_count=0,published_count=0),frame(raw_count=0,published_count=0)]},True),
 ('zero raw cache contradicted by positive inventory cannot clear',{'stage':'clear_model','before_count':0,'cached_raw_count':0,'frames':[frame(raw_count=0,published_count=2018),frame(raw_count=0,published_count=2018)]},False),
 ('clear stale frame cannot be treated stable',{'stage':'clear_model','before_count':1,'frames':[frame(raw_count=2024),frame(raw_count=2024,codes=[-25202])]},False),
]
checks=[];failures=[]
for name,q,expected in cases:
 try:
  run=subprocess.run([a.helper,'--search-replay-test'],input=json.dumps(q)+'\n',text=True,capture_output=True,timeout=5)
  d=json.loads(run.stdout)
  ok=run.returncode==0 and d.get('accepted') is expected and d.get('apple_accessed') is False and d.get('prior_preserved') is True
 except Exception as e:ok=False;d={'error':type(e).__name__}
 checks.append({'name':name,'passed':ok,'result':d})
 if not ok:failures.append(name)
report={'passed':not failures,'checks':checks,'failures':failures,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(pathlib.Path(a.report).resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'boundary':'early native entry shared with independent search frame scope/reducer; no Apple/UI/auth','apple_accessed':False,'customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'failures':len(failures)}));raise SystemExit(0 if report['passed'] else 1)
