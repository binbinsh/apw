#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
good={'context_available':True,'owner_unchanged':True,'window_bound':True,'process_bound':True,'no_editor':True,'deadline_valid':True,'complete':True,'codes':[],'category_matches':True}
cases=[('first invalid frame then complete context',[{**good,'codes':[-25202]},good],'context'),('transient cannotComplete then complete category',[{**good,'codes':[-25204]},good],'category_true'),('complete false category is not incomplete',[{**good,'category_matches':False}],'category_false'),('persistent invalidUI refuses',[{**good,'codes':[-25202]}]*2,'unverified'),('expiry forbids later frame',[{**good,'deadline_valid':False},good],'unverified'),('owner change forbids later frame',[{**good,'owner_unchanged':False},good],'unverified')]
for flag in ['context_available','window_bound','process_bound','no_editor','complete']:
 cases.append((flag+' required',[{**good,flag:False}],'unverified'))
checks=[]
for name,frames,expect in cases:
 kind='category' if expect.startswith('category_') else 'context'
 run=subprocess.run([a.helper,'--policy-test'],input=json.dumps({'operation':'readonly-context-wait','kind':kind,'prior_incomplete':True,'frames':frames})+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 result=r.get('result') if isinstance(r,dict) else None
 checks.append({'name':name,'passed':run.returncode==0 and isinstance(result,dict) and result=={'outcome':expect,'prior_preserved':True} and r.get('apple_accessed') is False,'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);report={'passed':all(c['passed'] for c in checks),'checks':checks,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
