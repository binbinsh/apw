#!/usr/bin/env python3
"""Compiled CLI probe routing, private preimage and synthetic-only boundaries.

Failure specification: reject customer records, invalid/private hashes,
incomplete state, leaking diagnostics, unconfirmed cancel and retry. This
synthetic-helper run is not a real Apple probe or mutation acceptance.
"""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
checks=[];commands=[];failure=None
def check(name,value):checks.append({'name':name,'passed':bool(value)})
with tempfile.TemporaryDirectory(prefix='apw-notes-probe-e2e-') as tmp:
    root=pathlib.Path(tmp);root.chmod(0o700);calls=root/'calls.jsonl';reply=root/'reply.json'
    secret='APW_SYNTHETIC_PROBE_SECRET'
    helper=root/'helper.py';helper.write_text('''#!/usr/bin/env python3
import json,os,sys
for line in sys.stdin:
 q=json.loads(line)
 with open(os.environ['APW_TEST_CALLS'],'a') as f:f.write(json.dumps(q)+'\\n')
 r=json.load(open(os.environ['APW_TEST_REPLY']));r['id']=q['id'];print(json.dumps(r),flush=True)
''');helper.chmod(0o700)
    env={**os.environ,'APW_DATA_DIR':str(root),'APW_MAINTENANCE_HELPER':str(helper),'APW_TEST_CALLS':str(calls),'APW_TEST_REPLY':str(reply)}
    state={'key':{'title':'apw API 测试 · 合成备注','username':'synthetic@example.invalid'},'native_title':'apw API 测试 · 合成备注','notes':'APW_EXCHANGE_SYNTHETIC_V1 '+secret,'password':'','sites':['https://synthetic.example.invalid'],'sharing':'unshared','otp':'unknown','passkey':'unknown','extra_fields':[]}
    good={'ok':True,'app_activated':False,'probed':True,'synthetic_only':True,'mutation_authorized':False,'current_cohort_only':True,'credentials_changed':0,'journal_modified':False,'foreground_focus':False,'diagnostics':{'notes_role':'AXTextField','notes_text_settable':False,'notes_text_code':0,'notes':secret}}
    def run(name,st=state,mode=0o600,bad_hash=False,response=good,foreground=False):
        digest=hashlib.sha256(json.dumps(st,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        snapshot=root/(name+'.json');snapshot.write_text(json.dumps({'format':'apw-item-snapshot-v1','sha256':'0'*64 if bad_hash else digest,'state':st},ensure_ascii=False));snapshot.chmod(mode)
        reply.write_text(json.dumps(response));reply.chmod(0o600)
        cmd=[str(pathlib.Path(a.bin).resolve()),'item','probe-notes','--snapshot',str(snapshot)]
        if foreground:cmd.append('--foreground-focus')
        commands.append(shlex.join(cmd))
        r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=8)
        check(name+': no note plaintext in public streams',secret not in r.stdout+r.stderr)
        return r
    try:
        r=run('synthetic');v=json.loads(r.stdout or '{}')
        check('single safe probe accepted',r.returncode==0 and v.get('probed') is True and v.get('mutation_authorized') is False and v.get('credentials_changed')==0)
        check('public diagnostic response drops secret-bearing keys',v.get('diagnostics')=={'notes_role':'AXTextField','notes_text_settable':False,'notes_text_code':0})
        rows=[json.loads(x) for x in calls.read_text().splitlines()] if calls.exists() else []
        check('whole original state and explicit synthetic limit route once',len(rows)==1 and rows[0].get('op')=='notes-editor-probe' and rows[0].get('expected')==state and rows[0].get('synthetic_only') is True)
        check('default never requests foreground field focus',len(rows)==1 and rows[0].get('foreground_focus') is False and v.get('foreground_focus') is False)
        r=run('explicit-foreground',foreground=True,response={**good,'foreground_focus':True});v=json.loads(r.stdout or '{}')
        check('explicit foreground mode routes without pretending activation',r.returncode==0 and v.get('foreground_focus') is True and v.get('app_activated') is False)
        rows=[json.loads(x) for x in calls.read_text().splitlines()] if calls.exists() else []
        check('only opt-in command requests internal field focus',len(rows)==2 and rows[-1].get('foreground_focus') is True and rows[-1].get('expected')==state)
        before=len(rows)
        cases=[('customer-title',{**state,'key':{**state['key'],'title':'Customer account'}},{}),('customer-account',{**state,'key':{**state['key'],'username':'customer@example.com'}},{}),('real-site',{**state,'sites':['https://example.com']},{}),('real-password',{**state,'password':secret},{}),('missing-marker',{**state,'notes':secret},{}),('bad-hash',state,{'bad_hash':True}),('public-file',state,{'mode':0o644})]
        for name,st,kwargs in cases:
            r=run(name,st,**kwargs);check(name+': rejected before native',r.returncode!=0)
        check('invalid targets never dispatched',calls.exists() and len(calls.read_text().splitlines())==before)
        r=run('unconfirmed-cancel',response={**good,'probed':False});check('unconfirmed native completion refused',r.returncode!=0)
        check('unconfirmed completion has no automatic retry',len(calls.read_text().splitlines())==before+1)
        check('no mutation checkpoint journal created',not any('journal' in x.name for x in root.iterdir()))
    except Exception as e:failure=type(e).__name__+': '+str(e)
report={'passed':failure is None and all(x['passed'] for x in checks),'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),*__import__('sys').argv[1:]]),'entry_point_commands':commands,'boundary':'compiled CLI and isolated synthetic native helper; no Apple access','real_customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
