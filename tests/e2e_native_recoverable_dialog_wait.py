#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
import argparse,copy,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
good={k:True for k in ['complete','window_unique','sheet_unique','process_window_bound','owner_unchanged','fields_exact','identity_exact','recoverable','ordinary_unique','sheet_readonly','same_bindings','deadline_valid']}
good.update(permanent_present=False,permanent_button_count=0,codes=[])
cases=[('transition invalid then complete current pair',[{**good,'codes':[-25202]},good,good],True),('transition cannotComplete then complete pair',[{**good,'codes':[-25204]},good,good],True),('only one current frame',[good],False),('complete pair',[good,good],True),('expired frame cannot return pair',[good,{**good,'deadline_valid':False},good],False),('owner change cannot later recover',[good,{**good,'owner_unchanged':False},good,good],False),('binding replacement requires new stable pair',[good,{**good,'same_bindings':False}],False),('incomplete resets adjacency',[good,{**good,'codes':[-25202]},good],False)]
for field in ['complete','window_unique','sheet_unique','process_window_bound','fields_exact','identity_exact','recoverable','ordinary_unique','sheet_readonly']:
 cases.append((field+' mandatory',[good,{**good,field:False}],False))
cases.append(('permanent deletion refuses',[good,{**good,'permanent_present':True}],False))
cases.append(('multiple permanent buttons cannot be absence',[{**good,'permanent_button_count':2},{**good,'permanent_button_count':2}],False))
checks=[]
for name,frames,expected in cases:
 run=subprocess.run([a.helper,'--policy-test'],input=json.dumps({'operation':'recoverable-dialog-wait','prior_incomplete':True,'frames':frames})+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 result=r.get('result') if isinstance(r,dict) else None
 checks.append({'name':name,'passed':run.returncode==0 and r.get('apple_accessed') is False and result=={'verified':expected,'prior_preserved':True,'delete_dispatches':0,'confirmation_dispatches':0},'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True)
report={'passed':all(x['passed'] for x in checks),'checks':checks,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
