#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Actual self-owned fixture entry; no Apple target and no global input."""
import argparse,hashlib,json,pathlib,shlex,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--report',required=True);p.add_argument('--allow-own-pid-input',action='store_true');a=p.parse_args()
if not a.allow_own_pid_input:p.error('explicit --allow-own-pid-input is required; fixture only, never Apple')
source=pathlib.Path(a.source).resolve()
workspace=tempfile.TemporaryDirectory(prefix='apw-own-notes-input-')
fixture=pathlib.Path(workspace.name)/'fixture'
compile_command=['swiftc',str(source),'-o',str(fixture),'-framework','SwiftUI','-framework','AppKit','-framework','ApplicationServices']
compile_result=subprocess.run(compile_command,capture_output=True,text=True,timeout=60)
if compile_result.returncode!=0:raise SystemExit('fixture_compile_failed')
checks=[];observed={};failure=None
try:
 run=subprocess.run([str(fixture),'--self-owned-input-fixture'],capture_output=True,text=True,timeout=10)
 observed=json.loads(run.stdout)
 def check(name,value):
  checks.append({'name':name,'passed':bool(value)});assert value,name
 check('actual fixture entry returned structured observation',observed.get('fixture_only') is True)
 check('no application activation/global input/clipboard/other-app AX access',observed.get('app_activated') is False and observed.get('global_input_events_sent')==0 and observed.get('clipboard_used') is False and observed.get('other_app_ax_accessed') is False)
 check('original foreground owner retained',observed.get('owner_preserved') is True and observed.get('foreground_before',0)>0 and observed.get('foreground_before')==observed.get('foreground_after') and observed.get('foreground_before')!=observed.get('fixture_pid'))
 check('events only target own exact process',observed.get('pid_targeted') in [0,observed.get('fixture_pid')] and 0<=observed.get('input_events_sent',-1)<=2)
 check('nonkey window and original first responder selection are proved',observed.get('window_became_key') is False and observed.get('internal_first_responder_exact') is True and observed.get('selection_verified') is True)
 check('real Binding persisted model and fresh decoded readback match',run.returncode==0 and observed.get('model_committed') is True and observed.get('persisted_readback_exact') is True and observed.get('binding_change_count',0)>0 and observed.get('input_events_sent')==2)
except Exception as e:failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'observation':observed,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--source',str(source),'--allow-own-pid-input','--report',str(pathlib.Path(a.report).resolve())]),'fixture_sha256':hashlib.sha256(fixture.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'compile_command':shlex.join(compile_command),'boundary':'self-owned prohibited SwiftUI fixture with ordinary dispatch; original owner retained; never Apple or customer data','apple_notes_write_verified':False,'customer_records_modified':0}
workspace.cleanup()
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure,'observation':observed}));raise SystemExit(0 if report['passed'] else 1)
