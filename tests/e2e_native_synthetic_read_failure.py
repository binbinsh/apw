#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""One native policy entry proves post-input incomplete reads cannot recover."""
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
base={'operation':'notes-probe-read-cleanup','returned_complete':False,'opened_by_read':True,'owner_unchanged':True,'expected_complete':True,'list_available':False,'input_attempted':True}
cases=[('post-input partial owned read never enters recovery',{},'requires_review'),('post-input unavailable model remains review',{'opened_by_read':False},'requires_review'),('post-input owner changed never recovers',{'owner_unchanged':False},'requires_review'),('post-input even list-visible failure stays review',{'opened_by_read':False,'list_available':True},'requires_review'),('post-input missing whole expected stays review',{'expected_complete':False},'requires_review'),('complete successful reread registers before snapshot',{'returned_complete':True},'register_before_snapshot'),('pre-input partial owned read can use full-state recovery',{'input_attempted':False},'recover_expected_once'),('pre-input verified list has no owned editor',{'input_attempted':False,'opened_by_read':False,'list_available':True},'no_owned_editor')]
checks=[];failure=None
try:
 for name,changes,expected in cases:
  run=subprocess.run([a.helper,'--policy-test'],input=json.dumps({**base,**changes})+'\n',text=True,capture_output=True,timeout=5)
  d=json.loads(run.stdout);ok=run.returncode==0 and d.get('result')==expected and d.get('apple_accessed') is False
  checks.append({'name':name,'passed':ok});assert ok,name
except Exception as e:failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(pathlib.Path(a.report).resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'boundary':'actual early native policy entry used by owned read recovery; no Apple/UI/auth/input','apple_accessed':False,'customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
