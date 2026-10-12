#!/usr/bin/env python3
"""Resume the saved two-fixture live trial; no new plan, exports or imports."""
import argparse,json,pathlib,shlex,subprocess
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--trial',required=True);p.add_argument('--report',required=True);p.add_argument('--review-unchanged',action='store_true');a=p.parse_args()
trial=pathlib.Path(a.trial);checks=[];commands=[];failure=None
def check(name,ok):
    checks.append({'name':name,'passed':bool(ok)});assert ok,name
def call(*args):
    cmd=[a.bin,*args];commands.append(shlex.join(cmd))
    r=subprocess.run(cmd,capture_output=True,text=True,timeout=110)
    if r.returncode: raise RuntimeError(json.loads(r.stderr.strip().splitlines()[-1]).get('error','command_failed'))
    return json.loads(r.stdout)
try:
    plan=json.loads((trial/'plan.json').read_text());snap=json.loads((trial/'snapshots.json').read_text())['items']
    check('saved plan contains only the two pre-existing synthetic fixtures',
          [o['target'] for o in plan['operations']]==[
          {'title':'apw API 测试 · SSO 与备注','username':'synthetic-google@example.invalid'},
          {'title':'apw API 测试 · 独立备注','username':''}] and
          all('APW_EXCHANGE_SYNTHETIC_V1' in x['state']['notes'] and x['state']['password']=='' and
              all('.invalid' in site for site in x['state']['sites']) for x in snap))
    args=['--plan',str(trial/'plan.json'),'--journal',str(trial/'journal.jsonl')]
    if a.review_unchanged:
        reviewed=call('batch','review',*args,'--acknowledge-unchanged')
        check('uncertain save reviewed read-only before a new dispatch',reviewed['mutations']==0 and reviewed['reviewed_no_change']==1)
    result=call('batch','run',*args,'--apply')
    check('live full merge and recoverable deletion read back',result['completed']==2 and result['exports']==0 and result['imports']==0 and result['app_activated'] is False)
    result=call('batch','run',*args,'--apply')
    check('completed live batch resumes without another write',result['completed']==2 and result['mutations']==0)
except Exception as e: failure=type(e).__name__+': '+str(e)
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),*__import__('sys').argv[1:]]),'entry_point_commands':commands,'boundary':'compiled CLI and actual Apple Passwords; saved synthetic trial only','exports':0,'imports':0,'app_activated':False,'real_customer_records_modified':0}
pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
