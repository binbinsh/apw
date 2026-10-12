#!/usr/bin/env python3
"""Real CLI/background window connection, no credential read/import/export."""
import argparse,json,pathlib,shlex,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
checks=[];failure=None;result={}
def owner():
    r=subprocess.run(['osascript','-e','tell application "System Events" to return unix id of first application process whose frontmost is true'],capture_output=True,text=True,timeout=5)
    if r.returncode: raise RuntimeError('foreground_observation_failed')
    return int(r.stdout.strip())
def check(name,ok):
    checks.append({'name':name,'passed':bool(ok)});assert ok,name
try:
    before=owner()
    r=subprocess.run([a.bin,'item','connect'],capture_output=True,text=True,timeout=20)
    if r.returncode: raise RuntimeError('connect_command_failed')
    result=json.loads(r.stdout)
    check('trial actually observes Passwords in the background',result.get('passwords_frontmost') is False)
    check('actual CLI establishes an Apple-signed background window',result['ok'] and result['native_window_count']>0 and result['apple_process_verified'])
    check('foreground owner independently remains unchanged',owner()==before and result['foreground_preserved'] is True and result['app_activated'] is False)
    check('connection does not claim authentication or mutation acceptance',result['apple_live_verified'] is False and result['credentials_changed']==0 and result['exports']==0 and result['imports']==0)
except Exception as e: failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'observation':result,'background_window_reopen_verified':failure is None and result.get('opened_window') is True,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),*sys.argv[1:]]),'boundary':'actual CLI + Apple window, independent System Events foreground observation; no credential changes; existing windows do not prove reopening'}
pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure,'window_state':result.get('window_state')}));raise SystemExit(0 if report['passed'] else 1)
