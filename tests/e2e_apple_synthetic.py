#!/usr/bin/env python3
"""One explicit, bounded live trial on two already imported synthetic fixtures.

Never activates/unlocks an app, exports CSV, imports, creates a record, or retries.
Real accounts cannot pass the fixture identity/content guard.
"""
import argparse, hashlib, json, pathlib, shlex, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);p.add_argument('--run',action='store_true');p.add_argument('--wait-unlocked-seconds',type=int,default=0);a=p.parse_args()
checks=[];failure=None;mutations_started=False
def sha(x): return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def check(name,ok):
    checks.append({'name':name,'passed':bool(ok)});assert ok,name
def call(*args):
    r=subprocess.run([a.bin,*args],capture_output=True,text=True,timeout=100)
    if r.returncode: raise RuntimeError(json.loads(r.stderr.strip().splitlines()[-1]).get('error','command_failed'))
    return json.loads(r.stdout)
if not a.run: raise SystemExit('Use --run for this two-fixture live trial.')
if not 0<=a.wait_unlocked_seconds<=120: raise SystemExit('Wait must be bounded to 0..120 seconds.')
with tempfile.TemporaryDirectory(prefix='apw-apple-synthetic-') as tmp:
    root=pathlib.Path(tmp);root.chmod(0o700)
    try:
        if a.wait_unlocked_seconds:
            until=time.monotonic()+a.wait_unlocked_seconds
            while True:
                doctor=call('item','doctor')
                if doctor.get('window_state')=='unlocked_list_available' and doctor.get('passwords_frontmost') is False: break
                if time.monotonic()>=until: raise RuntimeError('maintenance_unlock_wait_expired')
                time.sleep(3)
        targets=root/'targets.json'
        targets.write_text(json.dumps({'format':'apw-maintenance-targets-v1','targets':[{'title':'apw API 测试 · 独立备注','username':''},{'title':'apw API 测试 · SSO 与备注','username':'synthetic-google@example.invalid'}]},ensure_ascii=False));targets.chmod(0o600)
        capture=root/'snapshots.json';call('batch','inspect','--targets',str(targets),'--output',str(capture))
        snapshots=json.loads(capture.read_text())['items']
        candidate,keeper=[x['state'] for x in snapshots]
        check('synthetic fixtures exclusively, full marker present',all('APW_EXCHANGE_SYNTHETIC_V1' in x['notes'] for x in [candidate,keeper]) and candidate['key']['username']=='' and candidate['password']=='' and candidate['sites']==[] and keeper['key']['username']=='synthetic-google@example.invalid' and keeper['password']=='' and all('.invalid' in s for s in keeper['sites']))
        after={**keeper,'notes':keeper['notes']+'\n\n'+candidate['notes']}
        ops=[{'id':'synthetic-notes-merge','kind':'notes-set','target':keeper['key'],'before_sha256':sha(keeper),'notes':after['notes']},
             {'id':'synthetic-redundant-note','kind':'delete-redundant-note','target':candidate['key'],'before_sha256':sha(candidate),'keeper':{'target':keeper['key'],'before_sha256':sha(after)},'preserve_text':candidate['notes'],'source_ids':['APW_EXCHANGE_SYNTHETIC_V1']}]
        f=root/'plan.json';f.write_text(json.dumps({'format':'apw-maintenance-v1','operations':ops},ensure_ascii=False));f.chmod(0o600)
        j=root/'journal.jsonl'
        mutations_started=True
        result=call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        check('real in-place merge plus recoverable deletion readback',result['completed']==2 and result['imports']==0 and result['exports']==0 and result['app_activated'] is False)
        result=call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        check('live resume verifies only, no repeated writes',result['completed']==2 and result['mutations']==0)
    except Exception as e: failure=type(e).__name__+': '+str(e)
    # Preserve trial inputs/journal on failure after intent so nothing is retried
    # with a fresh plan. Synthetic data only, no customer credential material.
    if mutations_started:
        dest=pathlib.Path(a.report).with_suffix('.trial')
        import shutil
        if dest.exists(): raise RuntimeError('trial_artifact_exists')
        shutil.copytree(root,dest);dest.chmod(0o700)
report={'passed':failure is None,'checks':checks,'error':failure,'mutations_started':mutations_started,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--bin',a.bin,'--report',a.report,'--run','--wait-unlocked-seconds',str(a.wait_unlocked_seconds)]),'boundary':'actual compiled apw + Apple Passwords; only two pre-existing synthetic fixtures','exports':0,'imports':0,'app_activated':False,'real_customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
