#!/usr/bin/env python3
"""Three focused CLI scenarios; native replies are synthetic, never Apple calls."""
import argparse, copy, hashlib, json, os, pathlib, shlex, subprocess, tempfile


def sha(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False) + '\n')
    path.chmod(0o600)


HELPER = '''#!/usr/bin/env python3
import json,os,pathlib,sys
p=pathlib.Path(os.environ['APW_TEST_STORE'])
for line in sys.stdin:
 q=json.loads(line);s=json.loads(p.read_text());op=q['op'];k=q.get('key');mode=s['mode']
 role='keeper' if k==s['keeper']['key'] else 'candidate'
 s['calls'].append([op,role]);r={'id':q['id'],'app_activated':False,'backend':'synthetic'}
 def fail(code):r.update(ok=False,error='maintenance_'+code)
 if op=='deleted-read':
  if s['direct']:fail('deleted_body_forbidden')
  elif mode=='legacy-full':r.update(ok=True,state=s['candidate'])
  elif mode=='legacy-timeout':fail('helper_timeout')
  else:fail('deleted_body_unverified')
 elif op=='deleted-location-read':
  s['locations']+=1
  if s['active_candidate']:fail('item_not_found')
  elif mode=='location-missing':fail('item_not_found')
  else:
   location={'category':'deleted','key':k,'native_title':s['candidate']['native_title'],
    'selected_exact':True,'title_matches':True,'recovery_unique':True,'frame_complete':True,
    'query_empty':True,'owner_unchanged':True,'stable_complete_frames':2}
   if mode=='location-incomplete':location['stable_complete_frames']=1
   r.update(ok=True,verification='deleted_note_location_only',body_verified=False,location=location)
 elif op=='read' and role=='keeper':
  s['keeper_reads']+=1;value=s['keeper'].copy()
  count=s['keeper_reads']-(1 if s['fresh'] else 0)
  if mode=='keeper-first-missing' and count==1:fail('item_not_found')
  elif mode=='keeper-first-partial' and count==1:
   value.pop('extra_fields');r.update(ok=True,state=value)
  else:
   if mode=='keeper-second-changed' and count==2:value['password']='WRONG_SYNTHETIC_SECRET'
   r.update(ok=True,state=value)
 elif op=='read':
  if s['active_candidate'] or mode=='active-present':r.update(ok=True,state=s['candidate'])
  elif mode=='active-timeout':fail('helper_timeout')
  else:fail('item_not_found')
 elif op=='delete-redundant-note':
  s['active_candidate']=False;s['deletes']+=1;r.update(ok=True,recoverable=True)
 else:fail('operation_unsupported')
 p.write_text(json.dumps(s,ensure_ascii=False));print(json.dumps(r,ensure_ascii=False),flush=True)
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bin', required=True)
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    candidate = {'key': {'title': 'synthetic direct-location note', 'username': ''},
                 'native_title': 'synthetic direct-location note',
                 'notes': 'PRIVATE_SYNTHETIC_NOTE_BODY\nsource-direct-location-001\n完整正文  ',
                 'password': '', 'sites': [], 'sharing': 'unshared', 'otp': 'absent',
                 'passkey': 'absent', 'extra_fields': []}
    keeper = {**candidate, 'key': {'title': 'synthetic direct-location keeper', 'username': 'test@example.invalid'},
              'native_title': 'synthetic direct-location keeper',
              'notes': 'KEEPER_PREFIX\n' + candidate['notes'], 'password': 'PRIVATE_SYNTHETIC_KEEPER_SECRET',
              'sites': ['https://keeper.invalid'], 'otp': 'present', 'passkey': 'present',
              'extra_fields': [{'identifier': 'synthetic-extra', 'value': 'retained'}]}
    results = []
    with tempfile.TemporaryDirectory(prefix='apw-delete-direct-location-') as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        helper = root / 'helper.py'
        helper.write_text(HELPER)
        helper.chmod(0o700)
        scenarios = [
            ('fresh_direct', [('fresh-success', True, True, True)]),
            ('resumed_direct_proofs', [(name, False, True, name == 'resume-success') for name in (
                'resume-success', 'location-missing', 'location-incomplete', 'keeper-first-missing',
                'keeper-first-partial', 'keeper-second-changed', 'active-present', 'active-timeout')]),
            ('legacy_contract', [('legacy-full', False, False, True),
                                 ('legacy-fallback', False, None, True),
                                 ('legacy-refused', False, False, False),
                                 ('legacy-timeout', False, None, False)])]
        for scenario, variants in scenarios:
            for name, fresh, preflight, success in variants:
                d = root / name
                d.mkdir(mode=0o700)
                op = {'id': 'direct-location-001', 'kind': 'delete-redundant-note', 'target': candidate['key'],
                      'before_sha256': sha(candidate), 'keeper': {'target': keeper['key'], 'before_sha256': sha(keeper)},
                      'preserve_text': candidate['notes'], 'source_ids': ['source-direct-location-001']}
                plan = {'format': 'apw-maintenance-v1', 'operations': [op]}
                planpath, journal, store = d / 'plan.json', d / 'journal.jsonl', d / 'store.json'
                write(planpath, plan)
                if not fresh:
                    intent = {'plan': sha(plan), 'id': op['id'], 'event': 'intent',
                              'before_sha256': sha(candidate), 'before_native_title': candidate['native_title'],
                              'at': '2026-10-13T00:00:00Z'}
                    if preflight is not None:
                        sidecar = pathlib.Path(str(journal) + '.' + op['id'] + '.before.json')
                        write(sidecar, {'format': 'apw-item-snapshot-v1', 'sha256': sha(candidate), 'state': candidate})
                        intent.update(deleted_preflight_absent=preflight, before_snapshot_path=str(sidecar))
                    journal.write_text(json.dumps(intent) + '\n' + json.dumps({**intent, 'event': 'uncertain'}) + '\n')
                    journal.chmod(0o600)
                write(store, {'candidate': candidate, 'keeper': keeper, 'mode': name,
                              'direct': preflight is True, 'fresh': fresh, 'active_candidate': fresh,
                              'keeper_reads': 0, 'locations': 0, 'deletes': 0, 'calls': []})
                env = {**os.environ, 'APW_MAINTENANCE_HELPER': str(helper), 'APW_TEST_STORE': str(store),
                       'APW_DATA_DIR': str(d)}
                cmd = [binary, 'batch', 'run', '--apply', '--plan', str(planpath), '--journal', str(journal)]
                run = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=20)
                current = json.loads(store.read_text())
                entries = [json.loads(line) for line in journal.read_text().splitlines()]
                calls = current['calls']
                checks = {'expected_outcome': (run.returncode == 0) == success,
                          'no_secret_output': all(value not in run.stdout + run.stderr for value in
                                                  (candidate['notes'], keeper['password'], candidate['key']['title'])),
                          'single_delete_only_when_fresh': current['deletes'] == (1 if fresh else 0),
                          'only_expected_operations': all(x[0] in ('read', 'deleted-read', 'deleted-location-read',
                                                                   'delete-redundant-note') for x in calls)}
                if preflight is True:
                    checks['no_hidden_body_request'] = all(x[0] != 'deleted-read' for x in calls)
                    checks['location_observed'] = current['locations'] == (2 if fresh else 1)
                else:
                    checks['legacy_body_requested_once'] = calls.count(['deleted-read', 'candidate']) == 1
                if success and preflight is True:
                    checks['complete_proof_order'] = calls[-4:] == [['deleted-location-read', 'candidate'],
                        ['read', 'keeper'], ['read', 'candidate'], ['read', 'keeper']]
                    checks['content_only_mode'] = entries[-1].get('deletion_verification') == 'content_preservation_deleted_location'
                    checks['full_content_not_body'] = entries[-1].get('content_preservation_verified') is True and entries[-1].get('deleted_body_verified') is False
                    # Actual repeated CLI reconciliation, not merely reading the previous flag.
                    previous_bytes = journal.read_bytes()
                    previous_calls = len(calls)
                    repeat = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=20)
                    after = json.loads(store.read_text())
                    checks['done_repeat_readonly'] = repeat.returncode == 0 and after['deletes'] == current['deletes'] and journal.read_bytes() == previous_bytes
                    checks['done_repeat_same_proof_no_body'] = after['calls'][previous_calls:] == [
                        ['deleted-location-read', 'candidate'], ['read', 'keeper'], ['read', 'candidate'], ['read', 'keeper']]
                if not success:
                    checks['failure_never_done'] = entries[-1]['event'] != 'done'
                if name == 'legacy-full':
                    checks['legacy_full_body_unchanged'] = entries[-1].get('deleted_body_verified') is True and calls[-3:] == [
                        ['deleted-read', 'candidate'], ['read', 'candidate'], ['read', 'keeper']]
                if name in ('legacy-refused', 'legacy-timeout'):
                    checks['legacy_no_wrong_fallback'] = all(x[0] != 'deleted-location-read' for x in calls)
                if name == 'legacy-fallback':
                    checks['legacy_precise_fallback_unchanged'] = entries[-1].get('deletion_verification') == 'legacy_pending_content_preservation_deleted_location'
                results.append({'scenario': scenario, 'variant': name, 'passed': all(checks.values()),
                                'checks': checks, 'command': shlex.join(cmd), 'native_operations': calls,
                                'exit_status': run.returncode})
    report = {'command': shlex.join(['python3', str(pathlib.Path(__file__).resolve()), '--bin', binary,
                                     '--report', str(pathlib.Path(args.report).resolve())]),
              'passed': all(x['passed'] for x in results),
              'failures': [x['variant'] for x in results if not x['passed']], 'results': results,
              'boundary': 'compiled public CLI + temporary synthetic helper; no Apple or customer access',
              'real_apple_verified': False, 'customer_writes': 0}
    dest = pathlib.Path(args.report)
    dest.parent.mkdir(parents=True, exist_ok=True)
    write(dest, report)
    print(json.dumps({'passed': report['passed'], 'failures': report['failures'], 'report': str(dest)}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
