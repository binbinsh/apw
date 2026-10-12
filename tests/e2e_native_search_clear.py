#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""The native early clear policy refuses a visibly empty, stale zero model."""
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
base={'operation':'search-clear-initial','complete':True,'query_empty':True,'category_matches':True,'owner_unchanged':True,'raw_count':2024,'published_count':2019,'cached_raw_count':-1,'model_needs_proof':False}
cases=[('normal initial complete full rows remain usable',{},True),('empty visible query with gone target is not empty library',{'raw_count':0,'published_count':2018},False),('known empty complete raw cache remains usable',{'raw_count':0,'published_count':0,'cached_raw_count':0},True),('positive published count contradicts cached empty list',{'raw_count':0,'published_count':2018,'cached_raw_count':0},False),('nonempty query must submit clear',{'query_empty':False},False),('own unproved value submission cannot exploit visible empty query',{'model_needs_proof':True},False),('known full raw cache proves positive count',{'model_needs_proof':True,'cached_raw_count':2024},True),('unknown zero list holds',{'raw_count':0,'published_count':-1},False),('incomplete initial frame holds',{'complete':False},False),('category mismatch holds',{'category_matches':False},False),('owner mismatch holds',{'owner_unchanged':False},False)]
checks=[];failures=[]
for name,changes,expected in cases:
 try:
  r=subprocess.run([a.helper,'--policy-test'],input=json.dumps({**base,**changes})+'\n',text=True,capture_output=True,timeout=5)
  d=json.loads(r.stdout);ok=r.returncode==0 and d.get('result') is expected and d.get('apple_accessed') is False
 except Exception as e:ok=False;d={'error':type(e).__name__}
 checks.append({'name':name,'passed':ok,'result':d})
 if not ok:failures.append(name)
report={'passed':not failures,'checks':checks,'failures':failures,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(pathlib.Path(a.report).resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'boundary':'early native complete initial clear policy; no Apple/UI/auth/delete','apple_accessed':False,'customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'failures':len(failures)}));raise SystemExit(0 if report['passed'] else 1)
