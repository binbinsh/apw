#!/usr/bin/env python3
"""Replay the location-only contract through the actual native entry point."""
import argparse, copy, hashlib, json, subprocess, sys
from pathlib import Path

p=argparse.ArgumentParser()
p.add_argument('--helper', required=True)
p.add_argument('--report', required=True)
a=p.parse_args()
helper=Path(a.helper).resolve()
expected={'key':{'title':'Synthetic Deleted Note','username':''},'native_title':'Synthetic Deleted Note','notes':'APW_DELETED_LOCATION_SYNTHETIC_V1\nDo not echo this body.', 'password':'','sites':[],'sharing':'unshared','otp':'absent','passkey':'absent','extra_fields':[]}
frame={'selected_exact':True,'title_matches':True,'recovery_unique':True,'query_empty':True,'category_deleted':True,'owner_unchanged':True,'process_window_bound':True,'detail_bound':True,'complete':True,'row_binding':17,'native_title':expected['native_title']}
cases=[]
def add(name,frames,ok,exp=None,key=None):
    cases.append((name,{'expected':exp or expected,'key':key or expected['key'],'frames':frames},ok))
add('complete location pair is body-unknown', [frame,frame], True)
add('one frame cannot establish stability', [frame], False)
for name in ['selected_exact','title_matches','recovery_unique','query_empty','category_deleted','owner_unchanged','process_window_bound','detail_bound','complete']:
    bad=copy.deepcopy(frame);bad[name]=False
    add(name+' interrupts the pair',[frame,bad,frame],False)
add('fresh pair after incomplete frame',[dict(frame,complete=False),frame,frame],True)
add('different current row cannot join pair',[frame,dict(frame,row_binding=18)],False)
add('native title must match exact request',[dict(frame,native_title='Another record')]*2,False)
for key,value in [('password','secret'),('sites',['https://synthetic.invalid']),('otp','unknown'),('passkey','unknown'),('sharing','shared'),('extra_fields',[{'key':'custom','value':'secret'}]),('notes','')]:
    exp=copy.deepcopy(expected);exp[key]=value
    add('non-note preimage '+key,[frame,frame],False,exp)
exp=copy.deepcopy(expected);exp['key']['username']='synthetic@example.invalid'
add('account preimage cannot become empty observation',[frame,frame],False,exp,exp['key'])
exp=copy.deepcopy(expected);exp['unknown']='untrusted'
add('unknown preimage schema refuses',[frame,frame],False,exp)
exp=copy.deepcopy(expected);exp['native_title']='Another record'
add('input native title mismatch refuses',[frame,frame],False,exp)
results=[]
for name,request,ok in cases:
    run=subprocess.run([str(helper),'--deleted-location-replay-test'],input=json.dumps(request)+'\n',text=True,capture_output=True,timeout=5)
    try: result=json.loads(run.stdout)
    except Exception: result=None
    passed=run.returncode==0 and isinstance(result,dict) and result.get('ok') is ok and result.get('apple_accessed') is False and 'state' not in result and expected['notes'] not in run.stdout
    if ok and passed:
        loc=result.get('location',{})
        passed=result.get('verification')=='deleted_note_location_only' and result.get('body_verified') is False and result.get('app_activated') is False and loc.get('key')==request['key'] and loc.get('native_title')==expected['native_title'] and loc.get('stable_complete_frames')==2 and all(loc.get(k) is True for k in ['selected_exact','title_matches','recovery_unique','frame_complete','query_empty','owner_unchanged']) and loc.get('category')=='deleted' and 'notes' not in loc and 'account_empty' not in loc and 'note_kind' not in loc
    results.append({'name':name,'passed':passed,'returncode':run.returncode,'result':result,'stderr':run.stderr[:256]})
report={'command':sys.argv,'helper':str(helper),'helper_sha256':hashlib.sha256(helper.read_bytes()).hexdigest(),'checks':len(results),'passed':all(r['passed'] for r in results),'apple_accessed':False,'results':results}
out=Path(a.report);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'report':str(out),'checks':len(results),'passed':report['passed']}))
sys.exit(0 if report['passed'] else 1)
