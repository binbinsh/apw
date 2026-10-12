#!/usr/bin/env python3
"""Actual CLI + isolated synthetic helper. No Apple/native UI is invoked."""
import argparse, copy, hashlib, json, os, pathlib, shlex, subprocess, tempfile

def sha(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def write(p,x):p.write_text(json.dumps(x,ensure_ascii=False)+'\n');p.chmod(0o600)
def main():
    p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
    binary=str(pathlib.Path(a.bin).resolve());results=[]
    candidate={'key':{'title':'synthetic conservation note','username':''},'native_title':'synthetic conservation note',
        'notes':'SYNTHETIC_CONSERVATION_PRIVATE_BODY\nsource-conservation-001\n原样保留  ',
        'password':'','sites':[],'sharing':'unshared','otp':'absent','passkey':'absent','extra_fields':[]}
    keeper={**candidate,'key':{'title':'synthetic keeper','username':'synthetic@example.invalid'},'native_title':'synthetic keeper',
        'notes':'original keeper\n'+candidate['notes'],'password':'SYNTHETIC_KEEPER_SECRET','sites':['https://keeper.invalid'],
        'otp':'present','passkey':'present','extra_fields':[{'identifier':'synthetic-extra','value':'retained'}]}
    with tempfile.TemporaryDirectory(prefix='apw-delete-conservation-') as tmp:
        root=pathlib.Path(tmp);root.chmod(0o700);helper=root/'helper.py'
        helper.write_text('''#!/usr/bin/env python3
import hashlib,json,os,pathlib,sys
def sha(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
p=pathlib.Path(os.environ['APW_TEST_STORE'])
for line in sys.stdin:
 q=json.loads(line);s=json.loads(p.read_text());op=q['op'];mode=s['mode'];k=q.get('key');s['calls'].append(op)
 r={'id':q['id'],'app_activated':False,'backend':'synthetic'}
 def failure(code):r.update(ok=False,error='maintenance_'+code)
 rows=s['deleted'] if op in ['deleted-read','deleted-location-read'] else s['active'];found=[v for v in rows if v['key']==k]
 if op=='read' and k==s['keeper']['key']:
  s['keeper_reads']+=1;value=s['keeper'].copy()
  field_modes={'keeper-password':('password','wrong'),'keeper-sites':('sites',['https://wrong.invalid']),'keeper-otp':('otp','unknown'),
    'keeper-passkey':('passkey','unknown'),'keeper-sharing':('sharing','unknown'),'keeper-extra':('extra_fields',[]),
    'keeper-title':('native_title','wrong'),'keeper-body':('notes','SYNTHETIC_CONSERVATION_PRIVATE_BODY')}
  if mode in field_modes:field,val=field_modes[mode];value[field]=val
  if mode=='keeper-second-changed' and s['keeper_reads']>=2:value['password']='wrong'
  if mode=='keeper-partial':value.pop('extra_fields')
  if mode=='keeper-timeout':failure('helper_timeout')
  else:r.update(ok=True,state=value)
 elif op=='read' and k==s['candidate']['key'] and not found:
  s['absence_reads']+=1
  if mode=='active-reappears' and s['absence_reads']>=2:r.update(ok=True,state=s['candidate'])
  elif mode=='active-timeout':failure('helper_timeout')
  else:failure('item_not_found')
 elif op=='deleted-location-read':
  if mode.startswith('unsupported-'):failure('operation_unsupported')
  elif not found:failure('item_not_found')
  elif len(found)!=1:failure('item_ambiguous')
  else:
   location={'category':'deleted','key':k,'native_title':found[0]['native_title'],'selected_exact':True,'title_matches':True,
     'recovery_unique':True,'frame_complete':True,'query_empty':True,'owner_unchanged':True,'stable_complete_frames':2}
   r.update(ok=True,verification='deleted_note_location_only',body_verified=False,location=location)
   variants={'location-owner':('owner_unchanged',False),'location-query':('query_empty',False),'location-frames':('stable_complete_frames',1),
      'location-bool-frames':('stable_complete_frames',True),'location-title':('native_title','wrong'),'location-selected':('selected_exact',False),
      'location-category':('category','all'),'location-unknown':('unknown','secret')}
   if mode in variants:field,value=variants[mode];location[field]=value
   if mode=='location-spoof-state':r['state']=found[0]
   if mode=='location-spoof-body':r['body_verified']=True
 elif not found:failure('item_not_found')
 elif len(found)!=1:failure('item_ambiguous')
 elif op=='read':r.update(ok=True,state=found[0])
 elif op=='deleted-read':
  if mode in ['full-body','unsupported-full-body']:r.update(ok=True,state=found[0])
  elif mode.startswith('deleted-error-'):failure(mode[len('deleted-error-'):])
  else:failure('deleted_body_unverified')
 elif op=='delete-redundant-note':
  entries=[json.loads(x) for x in pathlib.Path(os.environ['APW_TEST_JOURNAL']).read_text().splitlines()];intent=entries[-1]
  try:
   path=pathlib.Path(intent['before_snapshot_path']);pre=json.loads(path.read_text());f=path.lstat()
   s['snapshot_before_dispatch']=pre=={'format':'apw-item-snapshot-v1','sha256':sha(found[0]),'state':found[0]} and f.st_mode&0o077==0 and f.st_nlink==1
  except Exception:s['snapshot_before_dispatch']=False
  s['active'].remove(found[0]);s['deleted'].append(found[0]);s['writes']+=1;r.update(ok=True,recoverable=True)
 else:failure('operation_unsupported')
 p.write_text(json.dumps(s,ensure_ascii=False));print(json.dumps(r,ensure_ascii=False),flush=True)
''');helper.chmod(0o700)
        cases=[('legacy-success',True,False),('fresh-success',True,True),('full-body',True,False),('unsupported-full-body',True,True),
            ('unsupported-no-body',False,True),('preexisting-deleted',False,True),('active-timeout',False,False),('active-reappears',False,False),
            ('keeper-password',False,False),('keeper-sites',False,False),('keeper-otp',False,False),('keeper-passkey',False,False),
            ('keeper-sharing',False,False),('keeper-extra',False,False),('keeper-title',False,False),('keeper-body',False,False),
            ('keeper-partial',False,False),('keeper-timeout',False,False),('keeper-second-changed',False,False),
            ('location-owner',False,False),('location-query',False,False),('location-frames',False,False),('location-bool-frames',False,False),
            ('location-title',False,False),('location-selected',False,False),('location-category',False,False),('location-unknown',False,False),
            ('location-spoof-state',False,False),('location-spoof-body',False,False),
            ('deleted-error-helper_timeout',False,False),('deleted-error-helper_reply_invalid',False,False),('deleted-error-item_ambiguous',False,False),
            ('deleted-error-item_not_found',False,False),('deleted-error-native_operation_failed',False,False),
            ('candidate-password',False,False),('candidate-otp',False,False),('candidate-passkey',False,False),('candidate-sharing',False,False),
            ('candidate-extra',False,False),('sidecar-corrupt',False,False)]
        for name,success,fresh in cases:
            d=root/name;d.mkdir(mode=0o700);c=copy.deepcopy(candidate);keep=copy.deepcopy(keeper)
            if name.startswith('candidate-'):
                f=name[len('candidate-'):];c[f]={'password':'wrong','otp':'unknown','passkey':'unknown','sharing':'unknown','extra':[{'identifier':'x','value':'x'}]}[f] if f!='extra' else c.get(f)
                if f=='extra':c.pop('extra',None);c['extra_fields']=[{'identifier':'x','value':'x'}]
            op={'id':'conservation-001','kind':'delete-redundant-note','target':c['key'],'before_sha256':sha(c),
                'keeper':{'target':keep['key'],'before_sha256':sha(keep)},'preserve_text':c['notes'],'source_ids':['source-conservation-001']}
            plan={'format':'apw-maintenance-v1','operations':[op]};planpath=d/'plan.json';journal=d/'journal.jsonl';store=d/'store.json'
            write(planpath,plan);intent={'plan':sha(plan),'id':op['id'],'event':'intent','before_sha256':sha(c),'before_native_title':c['native_title'],'at':'2026-10-12T00:00:00Z'}
            if not fresh:
                if name=='sidecar-corrupt':
                    sidecar=pathlib.Path(str(journal)+'.'+op['id']+'.before.json');write(sidecar,{'format':'apw-item-snapshot-v1','sha256':'0'*64,'state':c});intent['before_snapshot_path']=str(sidecar)
                journal.write_text(json.dumps(intent)+'\n'+json.dumps({**intent,'event':'uncertain'})+'\n');journal.chmod(0o600)
            write(store,{'candidate':c,'keeper':keep,'active':[keep,c] if fresh else [keep],'deleted':[c] if not fresh or name=='preexisting-deleted' else [],
                         'mode':name,'calls':[],'writes':0,'keeper_reads':0,'absence_reads':0,'snapshot_before_dispatch':False})
            env={**os.environ,'APW_MAINTENANCE_HELPER':str(helper),'APW_TEST_STORE':str(store),'APW_TEST_JOURNAL':str(journal),'APW_DATA_DIR':str(d)}
            cmd=[binary,'batch','run','--apply','--plan',str(planpath),'--journal',str(journal)]
            r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=20);s=json.loads(store.read_text());entries=[json.loads(x) for x in journal.read_text().splitlines()] if journal.exists() else []
            checks={'command_outcome':(r.returncode==0)==success,'no_private_output':candidate['notes'] not in r.stdout+r.stderr and keeper['password'] not in r.stdout+r.stderr,
                    'no_delete_replay':s['writes']==(1 if fresh and name!='preexisting-deleted' else 0),'no_unexpected_mutation':set(s['calls'])<={'read','deleted-read','deleted-location-read','delete-redundant-note'}}
            if success and name not in ['full-body','unsupported-full-body']:
                done=entries[-1];checks.update(keeper_twice=s['keeper_reads']>=(3 if fresh else 2),active_rechecked=s['absence_reads']>=2,
                    conservation_mode=done.get('deletion_verification')==('content_preservation_deleted_location' if fresh else 'legacy_pending_content_preservation_deleted_location'),
                    content_verified=done.get('content_preservation_verified') is True,body_not_faked=done.get('deleted_body_verified') is False)
            if success and fresh:checks['snapshot_precedes_dispatch']=s['snapshot_before_dispatch']
            if not success:checks['no_done']=not entries or entries[-1]['event']!='done'
            if name.startswith('deleted-error-'):checks['no_wrong_error_fallback']='deleted-location-read' not in s['calls']
            if name=='unsupported-no-body':checks['no_unsupported_fallback']=s['calls'].count('deleted-location-read')==1
            repeat=None
            if success:
                # Exercise the actual completed-journal CLI branch; neither a
                # mock assertion nor the previous done flag substitutes for it.
                before_repeat_journal=journal.read_bytes();before_repeat_calls=len(s['calls']);before_repeat_writes=s['writes']
                again=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=20);after=json.loads(store.read_text())
                new_calls=after['calls'][before_repeat_calls:]
                try:ack=json.loads(again.stdout)
                except Exception:ack={}
                checks.update(done_repeat_succeeds=again.returncode==0 and ack.get('completed')==1 and ack.get('mutations')==0,
                    done_repeat_zero_deletes=after['writes']==before_repeat_writes and 'delete-redundant-note' not in new_calls,
                    done_repeat_journal_unchanged=journal.read_bytes()==before_repeat_journal,
                    done_repeat_fresh_readonly_proof='read' in new_calls and 'deleted-read' in new_calls,
                    done_repeat_private_output_absent=candidate['notes'] not in again.stdout+again.stderr and keeper['password'] not in again.stdout+again.stderr)
                if name not in ['full-body','unsupported-full-body']:
                    checks.update(done_repeat_conservation_rechecked=ack.get('content_preservation_verifications')==1 and ack.get('deleted_body_verifications')==0 and
                        new_calls.count('read')>=4 and new_calls.count('deleted-location-read')==1)
                repeat={'command':shlex.join(cmd),'exit_status':again.returncode,'native_operations':new_calls,'journal_unchanged':journal.read_bytes()==before_repeat_journal}
            results.append({'case':name,'passed':all(checks.values()),'checks':checks,'command':shlex.join(cmd),'native_operations':s['calls'],'exit_status':r.returncode,'completed_journal_repeat':repeat})
    report={'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--bin',binary,'--report',str(pathlib.Path(a.report).resolve())]),
            'passed':all(r['passed'] for r in results),'failures':[r['case'] for r in results if not r['passed']],'results':results,
            'boundary':'actual compiled CLI plus synthetic helper; no native Apple access','real_apple_verified':False,'customer_writes':0}
    dest=pathlib.Path(a.report);dest.parent.mkdir(parents=True,exist_ok=True);write(dest,report)
    print(json.dumps({'passed':report['passed'],'failures':report['failures'],'report':str(dest)}));return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
