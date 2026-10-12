#!/usr/bin/env python3
"""One read-only probe of an existing saved synthetic preimage, without export.

The native failure specification is docs/native-maintenance-repair-failure-spec.md.
This is not note-writing or deletion acceptance. A failed probe is not retried.
"""
import argparse,hashlib,json,pathlib,shlex,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--snapshot',required=True);p.add_argument('--report',required=True);p.add_argument('--foreground-focus',action='store_true');p.add_argument('--wait-foreground-seconds',type=int,default=0);a=p.parse_args()
if not 0<=a.wait_foreground_seconds<=180 or (a.wait_foreground_seconds and not a.foreground_focus):p.error('bounded foreground wait requires --foreground-focus')
checks=[];failure=None;observations=[];exit_status=None
cmd=[str(pathlib.Path(a.bin).resolve()),'item','probe-notes','--snapshot',str(pathlib.Path(a.snapshot).resolve())]
if a.foreground_focus:cmd.append('--foreground-focus')
def check(name,value):checks.append({'name':name,'passed':bool(value)});assert value,name
try:
    if a.wait_foreground_seconds:
        until=time.monotonic()+a.wait_foreground_seconds;seen=False
        while time.monotonic()<until:
            owner=subprocess.run(['/usr/bin/osascript','-l','JavaScript','-e','ObjC.import("AppKit"); $.NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier.js'],capture_output=True,text=True,timeout=3)
            if owner.returncode==0 and owner.stdout.strip()=='com.apple.Passwords':seen=True;break
            time.sleep(0.4)
        check('person independently brought Passwords foreground; no activation attempted',seen)
    result=subprocess.run(cmd,text=True,capture_output=True,timeout=110);exit_status=result.returncode
    for line in (result.stdout+'\n'+result.stderr).splitlines():
        try:observations.append(json.loads(line))
        except json.JSONDecodeError:pass
    check('actual compiled entry point completed',exit_status==0)
    v=json.loads(result.stdout)
    check('whole original state preserved and both editors canceled',v.get('probed') is True and v.get('credentials_changed')==0)
    check('cohort observation never authorizes a mutation',v.get('synthetic_only') is True and v.get('current_cohort_only') is True and v.get('mutation_authorized') is False)
    check('no journal modification or application activation',v.get('journal_modified') is False and v.get('app_activated') is False)
    check('internal field-focus mode matches explicit request',v.get('foreground_focus',False) is a.foreground_focus)
    check('complete diagnostic stage reached',v.get('diagnostics',{}).get('notes_probe_stage')=='complete')
except Exception as e:failure=type(e).__name__+': '+str(e)
binary=pathlib.Path(a.bin).resolve();helper=binary.with_name('apw-maintenance')
artifacts={'cli_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'helper_sha256':hashlib.sha256(helper.read_bytes()).hexdigest()}
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),*__import__('sys').argv[1:]]),'entry_point_command':shlex.join(cmd),'exit_status':exit_status,'artifacts':artifacts,'observations':observations,'boundary':'actual Apple Passwords, existing synthetic preimage only; no query or field writes','apple_notes_write_verified':False,'apple_delete_verified':False,'exports':0,'imports':0,'real_customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
