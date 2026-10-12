#!/usr/bin/env python3
"""Actual native helper entry point: no app activation and explicit capabilities."""
import argparse, json, pathlib, shlex, subprocess
p=argparse.ArgumentParser();p.add_argument('--helper',required=True);p.add_argument('--report',required=True);a=p.parse_args()
checks=[];failure=None
try:
    raw=subprocess.run([a.helper,'--serve'],input=json.dumps({'id':1,'op':'doctor'})+'\n',capture_output=True,text=True,timeout=10)
    result=json.loads(raw.stdout)
    checks.append({'name':'native entry point answers without activating or unlocking Apple', 'passed':raw.returncode==0 and result['ok'] and result['app_activated'] is False and result['backend']=='apple-passwords-accessibility'})
    checks.append({'name':'live write verification is not inferred from compilation', 'passed':result['apple_live_verified'] is False})
    checks.append({'name':'native backend declares precise read, note edit and recoverable deletion', 'passed':set(result['capabilities'])=={'read','notes-set','delete-redundant-note'}})
    checks.append({'name':'unavailable list has a concrete readiness reason, not unknown', 'passed':result['window_state'] in {'unlocked_list_available','locked','user_editor_open','no_standard_window','unsupported_window','incomplete_window_observation','access_unavailable'}})
    checks.append({'name':'readiness diagnostics expose structure and standard actions without secret values', 'passed':isinstance(result.get('window_observation_complete'),bool) and isinstance(result.get('editor_field_count'),int) and isinstance(result.get('search_field'),dict) and not {'title','username','password','notes','value'}.intersection(result['search_field'])})
    checks.append({'name':'static detail labels are not confused with an editable user form', 'passed':result.get('editor_field_count')==sum(1 for role in result.get('field_roles',{}).values() if role in {'AXTextField','AXTextArea','AXComboBox'}) and len(result.get('field_roles',{}))<=4})
    assert all(x['passed'] for x in checks)
except Exception as e: failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--helper',a.helper,'--report',a.report]),'boundary':'actual compiled Swift helper doctor; does not read or mutate Apple records','real_apple_mutations_verified':False}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
