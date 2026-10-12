#!/usr/bin/env python3
"""Actual CLI recovery routing and preimage protection; synthetic helper only.

Failure specification: recovery must never silently mutate values, accept an
incorrect/incomplete/unprotected snapshot, modify a journal, print secrets or
retry an uncertain native outcome. Native Apple acceptance is a separate run.
"""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
checks=[];failure=None;commands=[]
def check(name,value):checks.append({'name':name,'passed':bool(value)})
with tempfile.TemporaryDirectory(prefix='apw-editor-recovery-e2e-') as tmp:
    root=pathlib.Path(tmp);root.chmod(0o700);calls=root/'calls.jsonl'
    helper=root/'helper.py';helper.write_text('''#!/usr/bin/env python3
import json,os,sys
for line in sys.stdin:
 q=json.loads(line)
 with open(os.environ['APW_TEST_CALLS'],'a') as f:f.write(json.dumps(q)+'\\n')
 print(json.dumps({'id':q['id'],'ok':True,'app_activated':False,'recovered':True,'credentials_changed':0,'journal_modified':False}),flush=True)
''');helper.chmod(0o700)
    env={**os.environ,'APW_DATA_DIR':str(root),'APW_MAINTENANCE_HELPER':str(helper),'APW_TEST_CALLS':str(calls)}
    secret='APW_SYNTHETIC_RECOVERY_SECRET'
    state={'key':{'title':'synthetic recovery','username':''},'native_title':'synthetic recovery','notes':secret,'password':'','sites':[],'sharing':'unshared','otp':'absent','passkey':'absent','extra_fields':[]}
    digest=hashlib.sha256(json.dumps(state,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    def run(name,value,mode=0o600):
        snapshot=root/(name+'.json');snapshot.write_text(json.dumps(value));snapshot.chmod(mode)
        cmd=[str(pathlib.Path(a.bin).resolve()),'item','recover-editor','--snapshot',str(snapshot)];commands.append(shlex.join(cmd))
        r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=8)
        check(name+': secret state stays off stdout/stderr',secret not in r.stdout+r.stderr)
        return r
    try:
        payload={'format':'apw-item-snapshot-v1','sha256':digest,'state':state}
        r=run('correct',payload);check('verified snapshot routes a single recovery',r.returncode==0 and json.loads(r.stdout).get('recovered') is True)
        rows=[json.loads(x) for x in calls.read_text().splitlines()] if calls.exists() else []
        check('native receives the complete unchanged preimage',len(rows)==1 and rows[0].get('op')=='recover-readonly-editor' and rows[0].get('expected')==state)
        r=run('incorrect-hash',{**payload,'sha256':'0'*64});check('incorrect hash refused before native dispatch',r.returncode!=0)
        incomplete={**state};incomplete.pop('password');r=run('incomplete',{**payload,'state':incomplete});check('unavailable password is refused before native dispatch',r.returncode!=0)
        r=run('public-file',payload,0o644);check('unprotected snapshot refused before native dispatch',r.returncode!=0)
        check('failures never dispatch or retry native recovery',calls.exists() and len(calls.read_text().splitlines())==1)
        check('no checkpoint journal created or modified',not any('journal' in x.name for x in root.iterdir()))
    except Exception as e:failure=type(e).__name__+': '+str(e)
report={'passed':failure is None and all(x['passed'] for x in checks),'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),*__import__('sys').argv[1:]]),'entry_point_commands':commands,'boundary':'compiled CLI and isolated synthetic native helper, not Apple acceptance','real_customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
