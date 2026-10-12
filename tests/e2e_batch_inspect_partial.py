#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Actual CLI partial inspection, with an explicitly isolated synthetic helper.

Failure specification, written before production changes:
1. Explicit save-partial loses completed, validated snapshots on first failure.
2. The failed/incomplete state enters items or is mislabeled complete/success.
3. Error, missing reply, malformed reply, or unclosed editor causes another read.
4. Titles, accounts, notes, passwords, arbitrary errors/diagnostics reach stdout.
5. Default behavior changes, or full success changes the existing file schema.
6. Public/replaced/linked output or an unsafe parent receives cleartext partials.
7. An existing output is overwritten or triggers helper interaction.
8. Index/total/hash/mode are wrong, or a first failure invents verified items.

No real Apple process or credential is accessed. This verifies the compiled CLI
entry point and private-output contract, not successful native Apple reads.
"""
import argparse, hashlib, json, os, pathlib, shlex, subprocess, tempfile

SECRET = 'APW_PARTIAL_SYNTHETIC_PRIVATE_761cc6'
SENTINEL = 'APW_PARTIAL_UNRELATED_OUTPUT'

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                         separators=(',', ':')).encode()).hexdigest()

def private_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False) + '\n')
    path.chmod(0o600)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    results = []
    with tempfile.TemporaryDirectory(prefix='apw-inspect-partial-') as temporary:
        root = pathlib.Path(temporary); root.chmod(0o700)
        helper = root / 'synthetic-helper.py'
        helper.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
n=0; secret=os.environ['APW_TEST_SECRET']; calls=pathlib.Path(os.environ['APW_TEST_CALLS'])
for line in sys.stdin:
 q=json.loads(line); n+=1
 with calls.open('a') as f: f.write(json.dumps({'op':q['op'],'index':n})+'\\n')
 state={'key':q['key'],'native_title':q['key']['title'],'notes':secret,'password':secret,
        'sites':['https://synthetic.invalid'],'sharing':'unshared','otp':'unknown','passkey':'unknown','extra_fields':[]}
 r={'id':q['id'],'ok':True,'app_activated':False,'state':state}
 if n==int(os.environ['APW_TEST_FAIL_INDEX']):
  mode=os.environ['APW_TEST_MODE']; output=pathlib.Path(os.environ['APW_TEST_OUTPUT'])
  if mode=='missing': sys.exit(0)
  if mode=='malformed': print('not-json',flush=True); continue
  if mode=='bad-state': r['state']['password']=None
  elif mode=='wrong-id': r['id']+=90
  else:
   code={'ambiguous':'maintenance_item_ambiguous','missing-item':'maintenance_item_not_found',
         'unknown':secret}.get(mode,'maintenance_native_read_editor_snapshot_incomplete')
   if mode=='public': output.chmod(0o644)
   elif mode=='replacement':
    output.unlink(); output.write_text(os.environ['APW_TEST_SENTINEL']); output.chmod(0o600)
   elif mode=='symlink': output.unlink(); output.symlink_to(os.environ['APW_TEST_UNRELATED'])
   elif mode=='hardlink': os.link(output,os.environ['APW_TEST_ALIAS'])
   elif mode=='public-parent': output.parent.chmod(0o755)
   r={'id':q['id'],'ok':False,'app_activated':False,'error':code,
      'diagnostics':{'notes':secret,'key':q['key'],'error':secret,'target_index':secret,'completed_reads':49}}
 print(json.dumps(r),flush=True)
''')
        helper.chmod(0o700)
        cases = [
            ('third-editor-error', 3, 'editor', True),
            ('first-editor-error', 1, 'editor', True),
            ('third-missing-reply', 3, 'missing', True),
            ('third-malformed-reply', 3, 'malformed', True),
            ('third-wrong-id', 3, 'wrong-id', True),
            ('third-invalid-state', 3, 'bad-state', True),
            ('third-unknown-error', 3, 'unknown', True),
            ('missing-item-stops', 3, 'missing-item', True),
            ('ambiguous-item-stops', 3, 'ambiguous', True),
            ('default-failure-unchanged', 3, 'editor', False),
            ('success-with-flag', 0, 'editor', True),
            ('default-success-unchanged', 0, 'editor', False),
            ('public-output-refused', 3, 'public', True),
            ('replaced-output-refused', 3, 'replacement', True),
            ('symlink-output-refused', 3, 'symlink', True),
            ('hardlinked-output-refused', 3, 'hardlink', True),
            ('public-parent-refused', 3, 'public-parent', True),
            ('existing-output-refused', 3, 'existing', True),
        ]
        for name, failure_index, mode, enabled in cases:
            directory = root / name; directory.mkdir(mode=0o700)
            targets, output, calls = directory/'targets.json', directory/'snapshots.json', directory/'calls.jsonl'
            unrelated, alias = directory/'unrelated.json', directory/'alias.json'
            calls.write_text(''); calls.chmod(0o600)
            unrelated.write_text(SENTINEL); unrelated.chmod(0o600)
            if mode == 'existing': output.write_text(SENTINEL); output.chmod(0o600)
            keys = [{'title':SECRET+'-title-'+str(i), 'username':SECRET+'-account-'+str(i)} for i in range(4)]
            private_json(targets, {'format':'apw-maintenance-targets-v1','targets':keys})
            env = {**os.environ, 'APW_MAINTENANCE_HELPER':str(helper), 'APW_DATA_DIR':str(directory),
                   'APW_TEST_SECRET':SECRET, 'APW_TEST_CALLS':str(calls), 'APW_TEST_FAIL_INDEX':str(failure_index),
                   'APW_TEST_MODE':mode, 'APW_TEST_OUTPUT':str(output), 'APW_TEST_UNRELATED':str(unrelated),
                   'APW_TEST_ALIAS':str(alias), 'APW_TEST_SENTINEL':SENTINEL}
            command = [binary,'batch','inspect','--targets',str(targets),'--output',str(output)]
            if enabled: command += ['--save-partial']
            run = subprocess.run(command, env=env, text=True, capture_output=True, timeout=15)
            observed = [json.loads(line) for line in calls.read_text().splitlines()]
            try: public = json.loads(run.stderr if failure_index else run.stdout)
            except Exception: public = {}
            try: output_text = output.read_text()
            except Exception: output_text = ''
            try: stored = json.loads(output_text)
            except Exception: stored = {}
            checks = {'no_public_secret':SECRET not in run.stdout+run.stderr,
                      'readonly_only':all(call['op']=='read' for call in observed),
                      'original_input_unchanged':json.loads(targets.read_text())['targets']==keys,
                      'unrelated_unchanged':unrelated.read_text()==SENTINEL}
            unsafe = mode in ['public','replacement','symlink','hardlink','public-parent','existing']
            if mode == 'existing':
                checks.update(nonzero=run.returncode!=0, no_helper_read=not observed, existing_preserved=output_text==SENTINEL)
            elif failure_index:
                checks.update(nonzero=run.returncode!=0, no_later_read=len(observed)==failure_index, no_false_success=run.stdout=='')
                if unsafe:
                    checks.update(no_cleartext_into_unsafe_output=SECRET not in output_text,
                                  no_cleartext_alias=not alias.exists() or SECRET not in alias.read_text(),
                                  no_partial_ack=public.get('diagnostics',{}).get('partial_saved') is not True)
                    if mode=='replacement':checks['replacement_preserved']=output_text==SENTINEL
                elif enabled:
                    expected_error = {'missing':'maintenance_helper_reply_missing','malformed':'maintenance_helper_reply_invalid',
                                      'wrong-id':'maintenance_helper_reply_invalid','bad-state':'maintenance_snapshot_incomplete',
                                      'unknown':'maintenance_native_operation_failed','missing-item':'maintenance_item_not_found',
                                      'ambiguous':'maintenance_item_ambiguous'}.get(mode,'maintenance_native_read_editor_snapshot_incomplete')
                    items = stored.get('items',[])
                    diag = public.get('diagnostics',{})
                    checks.update(partial_schema=stored.get('format')=='apw-item-snapshots-v1' and stored.get('complete') is False,
                                  exact_failure=stored.get('failed_index')==failure_index and stored.get('failures')==[{'index':failure_index,'error':expected_error}],
                                  requested_count=stored.get('requested_count')==4,
                                  verified_prefix=len(items)==failure_index-1 and all(set(item)=={'state','sha256'} and
                                      item['state']['key']==key and item['sha256']==digest(item['state']) for item,key in zip(items,keys)),
                                  private_output=output.exists() and output.stat().st_mode&0o077==0,
                                  safe_ack=public.get('error')==expected_error and diag.get('partial_saved') is True and
                                      diag.get('target_index')==failure_index and diag.get('completed_reads')==failure_index-1)
                else:checks['default_empty_output']=output.exists() and output.stat().st_size==0
            else:
                checks.update(zero_exit=run.returncode==0, all_reads_once=len(observed)==4,
                              unchanged_success_schema=set(stored)=={'format','items'} and stored.get('format')=='apw-item-snapshots-v1',
                              all_verified=len(stored.get('items',[]))==4 and all(item['sha256']==digest(item['state']) for item in stored.get('items',[])),
                              normal_ack=public.get('read') is True and public.get('count')==4, private_output=output.exists() and output.stat().st_mode&0o077==0)
            results.append({'case':name,'checks':checks,'passed':all(checks.values()),'command':shlex.join(command),
                            'exit_status':run.returncode,'reads':len(observed)})
            directory.chmod(0o700)
    report = {'passed':all(result['passed'] for result in results), 'results':results,
              'failures':[result['case'] for result in results if not result['passed']],
              'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--bin',binary,'--report',str(pathlib.Path(args.report).resolve())]),
              'binary_sha256':hashlib.sha256(pathlib.Path(binary).read_bytes()).hexdigest(),
              'boundary':'actual compiled CLI plus isolated synthetic native helper; no Apple acceptance claim',
              'real_apple_verified':False,'customer_writes':0}
    destination=pathlib.Path(args.report);destination.parent.mkdir(parents=True,exist_ok=True);private_json(destination,report)
    print(json.dumps({'passed':report['passed'],'checks':sum(len(result['checks']) for result in results),'failures':report['failures']}))
    return 0 if report['passed'] else 1

if __name__=='__main__':raise SystemExit(main())
