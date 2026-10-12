#!/usr/bin/env python3
"""Actual CLI batch-inspect observability, isolated synthetic helper only."""
import argparse,hashlib,json,os,pathlib,shlex,subprocess,tempfile

SECRET='SYNTHETIC_BATCH_INSPECT_PRIVATE_83c9ea'
def sha(v):return hashlib.sha256(json.dumps(v,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False)+'\n');p.chmod(0o600)
def main():
    p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
    binary=str(pathlib.Path(a.bin).resolve());results=[]
    with tempfile.TemporaryDirectory(prefix='apw-inspect-progress-') as tmp:
        root=pathlib.Path(tmp);root.chmod(0o700);helper=root/'synthetic-helper.py'
        helper.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
calls=pathlib.Path(os.environ['APW_TEST_CALLS']);secret=os.environ['APW_TEST_SECRET'];n=0
for line in sys.stdin:
 q=json.loads(line);n+=1
 with calls.open('a') as f:f.write(json.dumps({'op':q['op'],'index':n})+'\\n')
 state={'key':q['key'],'native_title':q['key']['title'],'notes':secret,'password':secret,'sites':['https://synthetic.invalid'],
        'sharing':'unshared','otp':'unknown','passkey':'unknown','extra_fields':[]}
 r={'id':q['id'],'ok':True,'app_activated':False,'state':state}
 if n==int(os.environ['APW_TEST_FAIL_INDEX']):
  mode=os.environ['APW_TEST_MODE']
  if mode=='native':r={'id':q['id'],'ok':False,'app_activated':False,'error':'maintenance_native_read_editor_open_unverified',
      'diagnostics':{'target_index':secret,'completed_reads':49,'failure_stage':'editor_open_unverified','notes':secret,'password':secret,'key':q['key'],'unknown':secret}}
  elif mode=='state':r['state']['password']=None
  elif mode=='protocol':r['id']=900+r['id']
  elif mode=='unknown-error':r={'id':q['id'],'ok':False,'app_activated':False,'error':secret,'diagnostics':{'notes':secret}}
 print(json.dumps(r),flush=True)
''');helper.chmod(0o700)
        cases=[('first-native',1,'native','maintenance_native_read_editor_open_unverified'),
               ('third-native',3,'native','maintenance_native_read_editor_open_unverified'),
               ('third-state',3,'state','maintenance_snapshot_incomplete'),
               ('third-protocol',3,'protocol','maintenance_helper_reply_invalid'),
               ('third-unknown',3,'unknown-error','maintenance_native_operation_failed'),
               ('success',0,'native',None),('invalid-input',0,'native','maintenance_targets_invalid')]
        for name,fail_index,mode,error in cases:
            d=root/name;d.mkdir(mode=0o700);calls=d/'calls.jsonl';targets=d/'targets.json';output=d/'snapshots.json'
            calls.write_text('');calls.chmod(0o600)
            keys=[{'title':SECRET+'-target-'+str(i),'username':SECRET+'-user-'+str(i)} for i in range(1,5)]
            write(targets,{'format':'wrong' if name=='invalid-input' else 'apw-maintenance-targets-v1','targets':keys})
            env={**os.environ,'APW_DATA_DIR':str(d),'APW_MAINTENANCE_HELPER':str(helper),'APW_TEST_CALLS':str(calls),
                 'APW_TEST_SECRET':SECRET,'APW_TEST_FAIL_INDEX':str(fail_index),'APW_TEST_MODE':mode}
            cmd=[binary,'batch','inspect','--targets',str(targets),'--output',str(output)]
            r=subprocess.run(cmd,env=env,capture_output=True,text=True,timeout=15);observed=[json.loads(x) for x in calls.read_text().splitlines()]
            try:ack=json.loads(r.stderr if error else r.stdout)
            except Exception:ack={}
            check={'entry_outcome':(r.returncode!=0)==bool(error),'no_public_private_content':SECRET not in r.stdout+r.stderr,
                   'readonly_operations':all(x['op']=='read' for x in observed)}
            if error:
                check.update(safe_error=ack.get('error')==error,no_following_read=len(observed)==fail_index,
                    no_partial_snapshot=not output.exists() or output.stat().st_size==0)
                diag=ack.get('diagnostics',{})
                if fail_index:
                    check.update(exact_failed_index=type(diag.get('target_index')) is int and diag['target_index']==fail_index,
                                 completed_full_reads=type(diag.get('completed_reads')) is int and diag['completed_reads']==fail_index-1,
                                 no_unfiltered_native_fields=set(diag)<=({'failure_stage','target_index','completed_reads'} if mode=='native' else {'target_index','completed_reads'}))
                    if mode=='native':check['safe_native_diagnostic_retained']=diag.get('failure_stage')=='editor_open_unverified'
                else:check['no_invented_target_index']='target_index' not in diag and 'completed_reads' not in diag
            else:
                stored=json.loads(output.read_text()) if output.exists() else {}
                check.update(success_ack=ack.get('read') is True and ack.get('count')==4 and ack.get('app_activated') is False,
                    complete_unchanged_snapshot_schema=set(stored)=={'format','items'} and stored.get('format')=='apw-item-snapshots-v1' and
                       len(stored.get('items',[]))==4 and all(set(x)=={'state','sha256'} and x['sha256']==sha(x['state']) and x['state']['key']==key for x,key in zip(stored['items'],keys)),
                    private_snapshot=output.stat().st_mode&0o077==0,all_reads_once=len(observed)==4,success_stderr_unchanged=r.stderr=='')
            results.append({'case':name,'passed':all(check.values()),'checks':check,'command':shlex.join(cmd),'exit_status':r.returncode,
                            'read_indices':[x['index'] for x in observed],'public_error':ack if error else None})
    report={'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--bin',binary,'--report',str(pathlib.Path(a.report).resolve())]),
        'passed':all(x['passed'] for x in results),'failures':[x['case'] for x in results if not x['passed']],'results':results,
        'boundary':'actual compiled CLI plus isolated synthetic native helper','real_apple_verified':False,'customer_writes':0}
    destination=pathlib.Path(a.report);destination.parent.mkdir(parents=True,exist_ok=True);write(destination,report)
    print(json.dumps({'passed':report['passed'],'failures':report['failures'],'report':str(destination)}));return 0 if report['passed'] else 1
if __name__=='__main__':raise SystemExit(main())
