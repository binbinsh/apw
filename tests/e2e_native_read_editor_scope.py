#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
f={'opened':True,'owner_unchanged':True,'fields_complete':True,'snapshot_complete':True,'codes':[]}
cases=[('prior error cannot poison complete current editor',True,[f],True),('ordinary complete editor',False,[f],True),('current invalidUI refuses',False,[{**f,'codes':[-25202]}],False),('current invalidUI with prior refuses',True,[{**f,'codes':[-25202]}],False),('fresh complete frame after transition',True,[{**f,'codes':[-25204]},f],True)]
for key in ['opened','owner_unchanged','fields_complete','snapshot_complete']:cases.append((key+' required',True,[{**f,key:False}],False))
results=[]
for name,prior,frames,expect in cases:
 run=subprocess.run([a.helper,'--read-editor-scope-replay-test'],input=json.dumps({'prior_incomplete':prior,'frames':frames})+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 ok=run.returncode==0 and isinstance(r,dict) and r.get('accepted') is expect and r.get('prior_preserved') is True and r.get('next_phase_incomplete') is (False if expect else prior) and r.get('apple_accessed') is False
 results.append({'name':name,'passed':ok,'result':r,'returncode':run.returncode})
for codes in [[],[-25202],[-25204]]:
 run=subprocess.run([a.helper,'--read-editor-scope-replay-test'],input=json.dumps({'prior_incomplete':True,'frames':[f],'post_codes':codes})+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 expect=bool(codes)
 results.append({'name':'new phase retains errors '+str(codes),'passed':run.returncode==0 and isinstance(r,dict) and r.get('accepted') is True and r.get('next_phase_incomplete') is expect and r.get('apple_accessed') is False,'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);report={'passed':all(r['passed'] for r in results),'checks':results,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(results)}));raise SystemExit(0 if report['passed'] else 1)
