#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Native deleted-note verification requires two complete exact frames."""
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
good={k:True for k in ('selected_exact','title_matches','note_matches','recovery_unique','complete')}
cases=[('complete matching pair',[good,good],True),('single frame not proof',[good],False),('failed prior frame does not poison complete pair',[{**good,'complete':False},good,good],True)]
for flag in good:
 bad={**good,flag:False}
 cases.append((flag+' missing refuses',[good,bad],False))
 cases.append((flag+' mismatch resets pair',[good,bad,good],False))
checks=[];failures=[]
for name,frames,expected in cases:
 try:
  r=subprocess.run([a.helper,'--policy-test'],input=json.dumps({'operation':'deleted-frame-pair','frames':frames})+'\n',text=True,capture_output=True,timeout=5)
  d=json.loads(r.stdout);ok=r.returncode==0 and d.get('result') is expected and d.get('apple_accessed') is False
 except Exception as e:ok=False;d={'error':type(e).__name__}
 checks.append({'name':name,'passed':ok,'result':d})
 if not ok:failures.append(name)
report={'passed':not failures,'checks':checks,'failures':failures,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(pathlib.Path(a.report).resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'boundary':'early native deleted frame pair; no Apple/UI/auth/delete','apple_accessed':False,'customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'failures':len(failures)}));raise SystemExit(0 if report['passed'] else 1)
