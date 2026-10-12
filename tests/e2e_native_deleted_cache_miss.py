#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
title='apw-deleted-cache-target.invalid';cached=[['apw-old.invalid'],['other']]
def frame(labels=None,**changes):
 labels=labels if labels is not None else [[title],['other']]
 return {'complete':True,'query_empty':True,'category_matches':True,'owner_unchanged':True,'window_bound':True,'raw_count':len(labels),'published_count':len(labels),'labels':labels,**changes}
good=frame()
cases=[('same-count missing cached title found live',[good,good],'present',cached),('current complete absence',[frame(cached),frame(cached)],'absent',cached),('single frame cannot prove anything',[good],'hold',cached),('changed same-count membership refuses',[frame(cached),good],'hold',cached),('changed order refuses',[good,frame(list(reversed(good['labels'])))],'hold',cached),('fresh duplicate titles remain ambiguous',[frame([[title],[title]])]*2,'ambiguous',cached),('cached hit retains only routing',[],'route-cached',[[title],['other']]),('independent pair after incomplete frame',[frame(complete=False),good,good],'present',cached),('zero rows positive published refuses',[frame([],published_count=2)]*2,'hold',cached)]
for flag in ['complete','query_empty','category_matches','owner_unchanged','window_bound']:
 cases.append((flag+' interruption resets pair',[good,frame(**{flag:False}),good],'hold',cached))
checks=[]
for name,frames,expect,cache in cases:
 q={'operation':'deleted-cache-miss','title':title,'cached_labels':cache,'frames':frames}
 run=subprocess.run([a.helper,'--policy-test'],input=json.dumps(q)+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 ok=run.returncode==0 and isinstance(r,dict) and r.get('result')==expect and r.get('apple_accessed') is False
 checks.append({'name':name,'passed':ok,'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);report={'passed':all(c['passed'] for c in checks),'checks':checks,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
