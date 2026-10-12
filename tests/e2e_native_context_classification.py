#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Native classification entry; pure and isolated, never accesses Apple."""
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
cases=[('context absence proves unavailable, not locking',{},'unavailable'),('unlocked is not evidence of locked',{'labels':['unlocked']},'unavailable'),('customer note containing unlock is not lock evidence',{'labels':['Please unlock deployment']},'unavailable'),('Touch ID in a note is not lock evidence',{'labels':['Touch ID setup notes']},'unavailable'),('Chinese 解锁 in a note is not lock evidence',{'labels':['解锁恢复步骤']},'unavailable'),('Locked as arbitrary row title is not lock evidence',{'labels':['Locked']},'unavailable'),('even an unbound unlock caption does not establish lock screen',{'labels':['解锁','已锁定']},'unavailable'),('owned or user editor is structurally different',{'editor':True},'user_editor_open'),('incomplete discovery never asserts locked',{'incomplete':True,'labels':['locked']},'incomplete_window_observation'),('incomplete discovery takes precedence over editor label',{'incomplete':True,'editor':True},'incomplete_window_observation')]
checks=[];failure=None
try:
 for name,changes,expected in cases:
  command=[a.helper,'--policy-test'];run=subprocess.run(command,input=json.dumps({'operation':'unavailable-context-policy','editor':False,'incomplete':False,**changes})+'\n',text=True,capture_output=True,timeout=5)
  d=json.loads(run.stdout);ok=run.returncode==0 and d.get('result')==expected and d.get('apple_accessed') is False
  checks.append({'name':name,'passed':ok});assert ok,name
except Exception as e:failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(pathlib.Path(a.report).resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'boundary':'pure native early policy entry; no Apple process, UI, input or authentication','apple_accessed':False,'customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
