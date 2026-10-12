#!/usr/bin/env python3
"""Compiled apw entry point + isolated, stateful native-helper process."""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, tempfile

p = argparse.ArgumentParser()
p.add_argument('--bin', required=True)
p.add_argument('--report', required=True)
a = p.parse_args()
checks = []
failure = None

def sha(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def item(title, note, username='', password='', sites=None):
    return dict(key=dict(title=title, username=username), native_title=title, notes=note,
                password=password, sites=sites or [], sharing='unshared', otp='absent',
                passkey='absent', extra_fields=[])

with tempfile.TemporaryDirectory(prefix='apw-maintenance-e2e-') as tmp:
    root = pathlib.Path(tmp)
    root.chmod(0o700)
    statefile = root / 'state.json'
    source = 'APW_SYNTHETIC_NOTE\nsource-id-001\n保留空白  '
    keeper = item('synthetic keeper', 'original note\n' + source, 'alice@example.invalid', 'SYNTHETIC_PASSWORD', ['example.invalid'])
    redundant = item('synthetic companion', source)
    store = {'active': [keeper, redundant], 'deleted': [], 'writes': 0, 'mode': 'ok'}
    def write(path, value):
        path.write_text(json.dumps(value, ensure_ascii=False))
        path.chmod(0o600)
    def reset(mode='ok'):
        store.update(active=[keeper.copy(), redundant.copy()], deleted=[], writes=0, mode=mode)
        write(statefile, store)
    helper = root / 'helper.py'
    helper.write_text('''#!/usr/bin/env python3
import json, os, sys
p=os.environ['APW_TEST_STATE']
for line in sys.stdin:
    q=json.loads(line); s=json.load(open(p)); op=q['op']; k=q.get('key')
    records=s['deleted'] if op=='deleted-read' else s['active']
    found=[x for x in records if x['key']==k]
    r={'id':q['id'],'backend':'synthetic','app_activated':False}
    if op=='doctor': r.update(ok=True, capabilities=['read','notes-set','delete-redundant-note'], apple_live_verified=False)
    elif len(found)!=1: r.update(ok=False,error='maintenance_item_not_found' if not found else 'maintenance_item_ambiguous')
    elif s['mode']=='null': r.update(ok=True,state={**found[0],'password':None})
    elif op in ['read','deleted-read']:
        if op=='deleted-read' and s['mode']=='deleted_body_missing': r.update(ok=False,error='maintenance_deleted_body_unverified')
        else: r.update(ok=True,state=found[0])
    elif op=='notes-set':
        s['writes']+=1
        if s['mode']!='write_ignored': found[0]['notes']=q['notes']
        if s['mode']=='changed_password': found[0]['password']='CHANGED'
        r.update(ok=True)
    elif op=='delete-redundant-note':
        s['writes']+=1; s['active'].remove(found[0]); s['deleted'].append(found[0]); r.update(ok=True,recoverable=True)
    else: r.update(ok=False,error='maintenance_operation_unsupported')
    with open(p,'w') as f: json.dump(s,f,ensure_ascii=False)
    if op in ['notes-set','delete-redundant-note'] and s['mode']=='lost_reply': sys.exit(0)
    print(json.dumps(r,ensure_ascii=False),flush=True)
''')
    helper.chmod(0o700)
    env = {**os.environ, 'APW_MAINTENANCE_HELPER': str(helper), 'APW_TEST_STATE': str(statefile), 'APW_DATA_DIR': str(root)}
    def call(*args, ok=True):
        r = subprocess.run([a.bin, *args], env=env, capture_output=True, text=True, timeout=30)
        assert (r.returncode == 0) == ok, 'unexpected_command_status: ' + r.stdout + r.stderr
        assert source not in r.stdout + r.stderr and 'SYNTHETIC_PASSWORD' not in r.stdout + r.stderr, 'secret_in_output'
        return r
    def check(name, condition):
        checks.append(dict(name=name, passed=bool(condition)))
        assert condition, name
    def plan(*ops):
        f = root / 'plan.json'
        write(f, dict(format='apw-maintenance-v1', operations=list(ops)))
        return f
    def cleanup():
        return dict(id='cleanup-001', kind='delete-redundant-note', target=redundant['key'], before_sha256=sha(redundant),
                    keeper=dict(target=keeper['key'], before_sha256=sha(keeper)), preserve_text=source, source_ids=['source-id-001'])
    def merge():
        return dict(id='merge-001', kind='notes-set', target=keeper['key'], before_sha256=sha(keeper), notes=keeper['notes']+'\nadditional source-id-002')
    def journal(name): return root / (name + '.jsonl')
    try:
        reset()
        check('CLI exposes item and batch commands', 'batch' in call('--help').stdout and 'notes' in call('item', '--help').stdout)
        f=plan(cleanup()); j=journal('dry')
        r=call('batch','run','--plan',str(f),'--journal',str(j))
        check('default validation performs no reads or writes', json.loads(r.stdout)['dry_run'] and not j.exists() and json.loads(statefile.read_text())['writes']==0)
        capture=root/'snapshot.json'; call('item','read','--title',keeper['key']['title'],'--username',keeper['key']['username'],'--output',str(capture))
        check('private full snapshot with deterministic hash', json.loads(capture.read_text())['sha256']==sha(keeper) and capture.stat().st_mode & 0o077==0)
        targets=root/'targets.json'; write(targets,{'format':'apw-maintenance-targets-v1','targets':[keeper['key'],redundant['key']]}); captures=root/'snapshots.json'
        call('batch','inspect','--targets',str(targets),'--output',str(captures))
        check('bounded batch snapshots obtained in one native-helper session',len(json.loads(captures.read_text())['items'])==2 and json.loads(statefile.read_text())['writes']==0 and captures.stat().st_mode & 0o077==0)
        f=plan(cleanup()); j=journal('cleanup')
        r=call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        s=json.loads(statefile.read_text())
        check('redundant note removed with exact recoverable readback', len(s['active'])==1 and s['deleted']==[redundant] and s['active']==[keeper] and json.loads(r.stdout)['completed']==1)
        call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        check('resume never repeats a completed delete',json.loads(statefile.read_text())['writes']==1)
        reset(); f=plan(merge()); j=journal('merge')
        call('item','notes','set','--apply','--plan',str(f),'--journal',str(j))
        s=json.loads(statefile.read_text())
        check('notes updated in place, all other fields preserved', s['active'][0]=={**keeper,'notes':merge()['notes']} and len(s['active'])==2 and s['writes']==1)
        reset(); bad=cleanup(); bad['before_sha256']='0'*64; f=plan(bad)
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('changed')),ok=False)
        check('changed preimage blocks deletion',json.loads(statefile.read_text())['writes']==0)
        reset(); s=json.loads(statefile.read_text()); s['active'].append(redundant); write(statefile,s); f=plan(cleanup())
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('ambiguous')),ok=False)
        check('duplicate identities block deletion',json.loads(statefile.read_text())['writes']==0)
        reset('null'); f=plan(cleanup())
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('null')),ok=False)
        check('unreadable password never means empty',json.loads(statefile.read_text())['writes']==0)
        reset(); s=json.loads(statefile.read_text()); s['active'][1]['otp']='present'; write(statefile,s); bad=cleanup(); bad['before_sha256']=sha(s['active'][1]); f=plan(bad)
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('otp')),ok=False)
        check('OTP-bearing records cannot be deleted as redundant notes',json.loads(statefile.read_text())['writes']==0)
        reset(); bad=merge(); bad['notes']='replacement losing original'; f=plan(bad)
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('loss')),ok=False)
        check('notes replacement cannot drop original body',json.loads(statefile.read_text())['writes']==0)
        reset('changed_password'); f=plan(merge()); j=journal('corrupt')
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        check('bad readback stops without write retry',json.loads(statefile.read_text())['writes']==1 and 'uncertain' in j.read_text())
        reset('write_ignored'); f=plan(merge()); j=journal('ignored')
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        call('batch','review','--plan',str(f),'--journal',str(j),'--acknowledge-unchanged')
        check('explicit no-change review is read-only',json.loads(statefile.read_text())['writes']==1 and 'reviewed-no-change' in j.read_text())
        s=json.loads(statefile.read_text());s['mode']='ok';write(statefile,s)
        call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        check('review permits one new dispatch only after exact unchanged proof',json.loads(statefile.read_text())['writes']==2 and json.loads(statefile.read_text())['active'][0]['notes']==merge()['notes'])
        reset('lost_reply'); f=plan(merge()); j=journal('lost')
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        s=json.loads(statefile.read_text()); s['mode']='ok'; write(statefile,s)
        call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        check('lost acknowledgement recovered by read-only resume',json.loads(statefile.read_text())['writes']==1)
        changed=merge(); changed['notes']+='changed plan'; f=plan(changed)
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        check('journal cannot be reused for another plan',json.loads(statefile.read_text())['writes']==1)
        reset('deleted_body_missing'); f=plan(cleanup()); j=journal('deleted-body')
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        check('deletion without recoverable full-body proof is held',json.loads(statefile.read_text())['writes']==1 and 'uncertain' in j.read_text())
        reset(); f=plan(cleanup()); f.chmod(0o644)
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('permissions')),ok=False)
        check('unsafe plan rejected before dispatch',json.loads(statefile.read_text())['writes']==0)
        reset(); f=plan(cleanup(),cleanup())
        call('batch','run','--apply','--plan',str(f),'--journal',str(journal('ids')),ok=False)
        check('duplicate operation IDs rejected before dispatch',json.loads(statefile.read_text())['writes']==0)
        reset(); f=plan(cleanup()); j=journal('locked'); lock=pathlib.Path(str(j)+'.lock'); lock.mkdir(mode=0o700); write(lock/'owner.json',{'pid':os.getpid()})
        call('batch','run','--apply','--plan',str(f),'--journal',str(j),ok=False)
        check('concurrent executor refused',json.loads(statefile.read_text())['writes']==0)
        write(lock/'owner.json',{'pid':999999,'plan':sha({'format':'apw-maintenance-v1','operations':[cleanup()]})})
        call('batch','run','--apply','--plan',str(f),'--journal',str(j))
        check('dead executor lock reclaimed without losing journal protection',json.loads(statefile.read_text())['writes']==1 and not lock.exists())
    except Exception as exc:
        failure=type(exc).__name__+': '+str(exc)

report=dict(passed=failure is None,checks=checks,error=failure,
            command=shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--bin',a.bin,'--report',a.report]),
            boundary='actual compiled apw CLI + synthetic stateful helper',real_apple_verified=False)
pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(passed=report['passed'],checks=len(checks),error=failure)))
raise SystemExit(0 if report['passed'] else 1)
