#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
title='apw-deleted-arrival.invalid'
def frame(labels=None,**changes):
 labels=labels if labels is not None else [[title],['other']]
 return {'complete':True,'query_empty':True,'category_matches':True,'owner_unchanged':True,'window_bound':True,'raw_count':len(labels),'published_count':len(labels),'labels':labels,'deadline_valid':True,**changes}
good=frame();old=frame([['old'],['other']])
cases=[('old complete negative inventory is not absence',[old,old],'unverified'),('old inventory then published target pair',[old,old,good,good],'arrived'),('one positive frame cannot proceed',[old,good],'unverified'),('changed positive membership resets pair',[good,frame([[title],['new']])],'unverified'),('positive pair after interrupted transient',[good,frame(complete=False),good,good],'arrived'),('expired inner frame refuses arrival',[good,frame(deadline_valid=False)],'unverified'),('published duplicate target refuses',[frame([[title],[title]])]*2,'ambiguous'),('prefix does not satisfy exact arrival',[frame([[title+'-other']])]*2,'unverified'),('raw zero published positive refuses',[frame([],published_count=2)]*2,'unverified')]
for flag in ['complete','query_empty','category_matches','owner_unchanged','window_bound']:
 cases.append((flag+' interruption resets pair',[good,frame(**{flag:False}),good],'unverified'))
checks=[]
for name,frames,expect in cases:
 run=subprocess.run([a.helper,'--policy-test'],input=json.dumps({'operation':'deleted-expected-arrival','title':title,'frames':frames})+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 checks.append({'name':name,'passed':run.returncode==0 and isinstance(r,dict) and r.get('result')==expect and r.get('apple_accessed') is False,'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);report={'passed':all(c['passed'] for c in checks),'checks':checks,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
