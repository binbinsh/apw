#!/usr/bin/env python3
"""Runner CLI + compiled apw, isolated owner/native boundaries; no Apple access."""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, sys, tempfile, time

p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
runner=pathlib.Path(__file__).with_name('e2e_apple_notes_probe.py').resolve()
checks=[];invocations=[];error=None
def check(name,ok):checks.append({'name':name,'passed':bool(ok)})
with tempfile.TemporaryDirectory(prefix='apw-probe-runner-e2e-') as tmp:
    root=pathlib.Path(tmp);root.chmod(0o700)
    secret='APW_RUNNER_SYNTHETIC_SECRET'
    snapshot=root/'snapshot.json'
    state={'key':{'title':'apw API 测试 · runner','username':'synthetic@example.invalid'},'native_title':'apw API 测试 · runner','notes':'APW_EXCHANGE_SYNTHETIC_V1 '+secret,'password':'','sites':['https://synthetic.invalid'],'sharing':'unshared','otp':'unknown','passkey':'unknown','extra_fields':[]}
    snapshot.write_text(json.dumps({'format':'apw-item-snapshot-v1','sha256':hashlib.sha256(json.dumps(state,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest(),'state':state},ensure_ascii=False));snapshot.chmod(0o600)
    owner=root/'owner.py';owner.write_text('''import json,pathlib,sys,time
c=json.loads(pathlib.Path(sys.argv[1]).read_text()); counter=pathlib.Path(sys.argv[2]); n=int(counter.read_text()) if counter.exists() else 0; counter.write_text(str(n+1)); mode=c['frames'][min(n,len(c['frames'])-1)]
if mode=='timeout':time.sleep(2)
if mode=='exit':sys.stderr.write('APW_RUNNER_SYNTHETIC_SECRET permission (-1743)');sys.exit(1)
if mode=='malformed':print('APW_RUNNER_SYNTHETIC_SECRET');sys.exit(0)
print(json.dumps({'ok':True,'owner_known':mode!='unknown','is_passwords':mode=='target','pid_positive':mode!='unknown'}))
''')
    helper=root/'helper.py';helper.write_text('''#!/usr/bin/env python3
import json,os,sys
for line in sys.stdin:
 q=json.loads(line)
 with open(os.environ['APW_RUNNER_CALLS'],'a') as f:f.write(json.dumps({'op':q['op'],'foreground_focus':q.get('foreground_focus')})+'\\n')
 if q['op']=='doctor' and os.environ.get('APW_RUNNER_DOCTOR_REFUSE'):r={'ok':False,'error':'maintenance_test_doctor_refused'}
 elif q['op']=='doctor':r={'ok':True,'accessibility_trusted':True,'apple_running':True,'window_state':'unlocked_list_available','apple_live_verified':False}
 elif q['op']=='notes-editor-probe':r={'ok':True,'probed':True,'synthetic_only':True,'mutation_authorized':False,'current_cohort_only':True,'credentials_changed':0,'journal_modified':False,'foreground_focus':q['foreground_focus'],'diagnostics':{'notes_probe_stage':'complete','focus_requested':q['foreground_focus'],'focus_verified':q['foreground_focus']}}
 else:r={'ok':False,'error':'maintenance_test_unexpected_operation'}
 r.update(id=q['id'],app_activated=False);print(json.dumps(r),flush=True)
''');helper.chmod(0o700)
    def run(name,frames,extra=(),missing_helper=False,private=True,implicit_override=False,alias=None):
        directory=root/name;directory.mkdir(mode=0o700)
        config=directory/'owner.json';config.write_text(json.dumps({'frames':frames}));config.chmod(0o600)
        seam=directory/'seam.json';seam.write_text(json.dumps({'format':'apw-notes-probe-isolated-v1','owner_command':[sys.executable,str(owner),str(config),str(directory/'count')],'helper_path':str(directory/'missing' if missing_helper else helper),'owner_query_timeout_seconds':0.1}));seam.chmod(0o600)
        result_path=directory/'result.json';calls=directory/'calls.jsonl';requested_ready=None
        snapshot.chmod(0o600 if private else 0o644)
        if alias=='dotdot':
            nesting=directory/'nested';nesting.mkdir();result_path=nesting/'..'/'..'/'snapshot.json'
        elif alias=='parent-symlink':
            link=directory/'linked';link.symlink_to(root,target_is_directory=True);result_path=link/'snapshot.json'
        elif alias=='hardlink':result_path.hardlink_to(snapshot)
        elif alias=='ready-helper':
            link=directory/'linked';link.symlink_to(root,target_is_directory=True);requested_ready=link/'helper.py'
        elif alias=='ready-owner-config':requested_ready=config
        elif alias=='ready-owner-script':requested_ready=owner
        elif alias=='ready-owner-script-parent-alias':
            link=directory/'linked';link.symlink_to(root,target_is_directory=True);requested_ready=link/'owner.py'
        elif alias=='ready-owner-config-dotdot':
            nesting=directory/'nested';nesting.mkdir();requested_ready=nesting/'..'/'owner.json'
        protected={str(path):path.read_bytes() for path in (snapshot,helper,seam,owner,config)}
        if alias=='hardlink':protected[str(result_path)]=result_path.read_bytes()
        command=[sys.executable,str(runner),'--bin',str(pathlib.Path(a.bin).resolve()),'--snapshot',str(snapshot),'--report',str(result_path),'--foreground-focus','--wait-foreground-seconds','1','--total-deadline-seconds','4']
        if not implicit_override:command.extend(['--isolated-test-seam',str(seam)])
        if requested_ready:command.extend(['--ready-file',str(requested_ready)])
        command.extend(extra)
        env={**os.environ,'APW_DATA_DIR':str(directory),'APW_RUNNER_CALLS':str(calls)}
        if implicit_override:env.update(APW_MAINTENANCE_HELPER=str(helper),APW_RUNNER_DOCTOR_REFUSE='1')
        started=time.monotonic();result=subprocess.run(command,env=env,capture_output=True,text=True,timeout=8);elapsed=time.monotonic()-started
        events=[]
        for line in result.stdout.splitlines():
            try:events.append(json.loads(line))
            except json.JSONDecodeError:pass
        actual=pathlib.Path(events[-1].get('report',str(result_path))) if events else result_path
        report=json.loads(actual.read_text()) if actual.exists() else {}
        native=[json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
        invocations.append({'command':shlex.join(command),'exit_status':result.returncode,'elapsed_seconds':round(elapsed,3),'report':report})
        check(name+': no secret in public output or stored report',secret not in result.stdout+result.stderr+json.dumps(report))
        check(name+': isolated run never certifies Apple writes or reads',report.get('real_apple_verified') is False and report.get('apple_notes_write_verified') is False and report.get('apple_delete_verified') is False)
        check(name+': executable hashes never substitute for independently verified provenance',report.get('provenance_unverified') is True and report.get('backend_probe_completed') is (result.returncode==0))
        if alias:
            check(name+': every protected input and alias retained byte for byte',all(pathlib.Path(path).read_bytes()==data for path,data in protected.items()))
            for path,data in protected.items():pathlib.Path(path).write_bytes(data)
            helper.chmod(0o700)
        return result,report,events,native,elapsed
    try:
        r,v,events,native,_=run('ready-then-target',['other','target'])
        check('ready is emitted before probe result',len(events)>=2 and events[0].get('event')=='ready' and events[0].get('tool_ready') is True)
        check('ready does not certify backend completion or provenance',events and events[0].get('real_apple_verified') is False and events[0].get('provenance_unverified') is True and events[0].get('backend_probe_completed') is False)
        check('ready has a repeatable artifact',pathlib.Path(v.get('ready_artifact','/missing')).exists())
        check('preflight and one compiled CLI probe succeed',r.returncode==0 and v.get('passed') is True and [x['op'] for x in native]==['doctor','notes-editor-probe'])
        check('ready owner observer and helper limits are explicit',v.get('preflight',{}).get('owner_observer_ready') is True and v.get('bounds',{}).get('total_seconds')==4 and v.get('probe_invocations')==1)
        for mode,classification in [('exit','owner_query_permission_denied'),('malformed','owner_query_invalid_response'),('timeout','owner_query_timeout'),('unknown','owner_metadata_unavailable')]:
            r,v,events,native,_=run('initial-'+mode,[mode])
            check(mode+': observer failure is classified before ready',r.returncode!=0 and v.get('error')==classification and not any(e.get('event')=='ready' for e in events) and not any(x['op']=='notes-editor-probe' for x in native))
        r,v,events,native,_=run('poll-failure',['other','malformed'])
        check('failure after ready cannot become person-did-not-switch claim',r.returncode!=0 and v.get('error')=='owner_query_invalid_response' and v.get('preflight',{}).get('tool_ready') is True and v.get('probe_invocations')==0 and v.get('person_action_inferred') is False)
        r,v,events,native,_=run('already-target',['target'])
        check('initial positive owner is consumed without another query',r.returncode==0 and len(v.get('owner_observations',[]))==1 and v.get('probe_invocations')==1)
        r,v,events,native,_=run('healthy-no-target',['other'])
        check('healthy absence is distinct from observer failure',r.returncode!=0 and v.get('error')=='target_owner_not_observed' and all(x.get('query_ok') is True for x in v.get('owner_observations',[])) and v.get('person_action_inferred') is False)
        r,v,events,native,elapsed=run('total-bound',['other'],extra=('--total-deadline-seconds','0.35'))
        check('one total deadline bounds waiting and never launches late probe',r.returncode!=0 and elapsed<1.5 and v.get('error')=='total_deadline_exceeded' and v.get('probe_invocations')==0)
        r,v,events,native,_=run('missing-helper',['target'],missing_helper=True)
        check('missing helper still yields a preflight report',r.returncode!=0 and v.get('error')=='preflight_helper_unavailable' and native==[])
        r,v,events,native,_=run('public-snapshot',['target'],private=False)
        check('unsafe snapshot never reaches owner query or helper',r.returncode!=0 and v.get('error')=='preflight_snapshot_unsafe' and native==[] and v.get('owner_observations')==[])
        r,v,events,native,_=run('implicit-helper-override',['target'],implicit_override=True)
        check('implicit helper override is refused before any process or Apple query',r.returncode!=0 and v.get('error')=='helper_override_requires_isolated' and native==[] and v.get('owner_observations')==[])
        for alias in ('dotdot','parent-symlink','hardlink','ready-helper','ready-owner-config','ready-owner-script','ready-owner-script-parent-alias','ready-owner-config-dotdot'):
            r,v,events,native,_=run('artifact-'+alias,['target'],alias=alias)
            check(alias+': canonical/inode input conflict is refused before helper or owner query',r.returncode!=0 and v.get('error')=='artifact_path_conflict' and native==[] and v.get('owner_observations')==[])
    except Exception as exc:error=type(exc).__name__
passed=error is None and all(x['passed'] for x in checks)
report={'passed':passed,'checks':checks,'error':error,'command':shlex.join([sys.executable,str(pathlib.Path(__file__).resolve()),*sys.argv[1:]]),'invocations':invocations,'boundary':'runner public CLI + actual compiled apw; explicit isolated OS owner/native helper adapters','real_apple_verified':False,'real_customer_records_modified':0}
pathlib.Path(a.report).parent.mkdir(parents=True,exist_ok=True);pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':passed,'checks':len(checks),'failed_checks':[x['name'] for x in checks if not x['passed']],'error':error}));raise SystemExit(0 if passed else 1)
