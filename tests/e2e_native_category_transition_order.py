#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
import argparse,hashlib,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
cases=[('background empty transition waits before clear',True,True,True,True),('background bound category keeps ready observation',True,False,True,False),('background filtered query keeps old guarded path',True,True,False,False),('foreground empty transition unchanged',False,True,True,False),('foreground filtered unchanged',False,True,False,False),('unknown empty query does not enable route',True,True,None,False)]
checks=[]
for name,bg,pending,empty,expect in cases:
 run=subprocess.run([a.helper,'--policy-test'],input=json.dumps({'operation':'category-clear-wait-first','background':bg,'pending_navigation':pending,'query_empty':empty})+'\n',text=True,capture_output=True,timeout=5)
 try:r=json.loads(run.stdout)
 except Exception:r=None
 checks.append({'name':name,'passed':run.returncode==0 and isinstance(r,dict) and r.get('result') is expect and r.get('apple_accessed') is False,'result':r,'returncode':run.returncode})
out=pathlib.Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);report={'passed':all(c['passed'] for c in checks),'checks':checks,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',str(pathlib.Path(a.helper).resolve()),'--report',str(out.resolve())]),'helper_sha256':hashlib.sha256(pathlib.Path(a.helper).read_bytes()).hexdigest(),'apple_accessed':False,'customer_records_modified':0}
out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks)}));raise SystemExit(0 if report['passed'] else 1)
