#!/usr/bin/env python3
"""One bounded, ready-signaled existing-synthetic probe; never retry or activate.

Failure specification: docs/apple-notes-probe-runner-failure-spec.md.
This runner does not certify notes writes, deletion, or complete migration.
"""
import argparse, hashlib, json, os, pathlib, re, shlex, stat, subprocess, sys, time, uuid

p=argparse.ArgumentParser()
for name in ('bin','snapshot','report'):p.add_argument('--'+name,required=True)
p.add_argument('--foreground-focus',action='store_true')
p.add_argument('--wait-foreground-seconds',type=int,default=0)
p.add_argument('--total-deadline-seconds',type=float)
p.add_argument('--ready-file')
p.add_argument('--isolated-test-seam',help='Explicit private OS-owner/native-helper adapter configuration; never certifies Apple.')
a=p.parse_args()
if not 0<=a.wait_foreground_seconds<=180 or (a.wait_foreground_seconds and not a.foreground_focus):p.error('bounded foreground wait requires --foreground-focus')
total=a.total_deadline_seconds if a.total_deadline_seconds is not None else min(300,a.wait_foreground_seconds+120)
if not 0.1<=total<=300:p.error('total deadline must be between 0.1 and 300 seconds')
started=time.monotonic();deadline=started+total;run_id=str(uuid.uuid4())
binary=pathlib.Path(a.bin).absolute();snapshot=pathlib.Path(a.snapshot).absolute();report_path=pathlib.Path(a.report).absolute()
ready_path=pathlib.Path(a.ready_file).absolute() if a.ready_file else report_path.with_suffix('.ready.json')
cmd=[str(binary),'item','probe-notes','--snapshot',str(snapshot)]
if a.foreground_focus:cmd.append('--foreground-focus')
doctor_cmd=[str(binary),'item','doctor']
owner_script='ObjC.import("AppKit"); var a=$.NSWorkspace.sharedWorkspace.frontmostApplication; var b=a.bundleIdentifier.js; var p=Number(a.processIdentifier); JSON.stringify({ok:true,owner_known:typeof b==="string" && b.length>0 && p>0,is_passwords:b==="com.apple.Passwords",pid_positive:p>0});'
owner_cmd=['/usr/bin/osascript','-l','JavaScript','-e',owner_script]
env=dict(os.environ);helper=pathlib.Path(env.get('APW_MAINTENANCE_HELPER',str(binary.with_name('apw-maintenance')))).absolute()
isolated=bool(a.isolated_test_seam);owner_timeout=3.0
seam_path=pathlib.Path(a.isolated_test_seam).absolute() if isolated else None
checks=[];failure=None;observations=[];owner_observations=[];exit_status=None;probe_invocations=0;doctor_invocations=0;artifacts={}
preflight={'tool_ready':False,'owner_observer_ready':False,'doctor_completed':False}

class Failed(Exception):
    def __init__(self,code):self.code=code
def fail(code):raise Failed(code)
def remaining():
    value=deadline-time.monotonic()
    if value<=0:fail('total_deadline_exceeded')
    return value
def check(name,value):
    checks.append({'name':name,'passed':bool(value)})
    if not value:fail('probe_evidence_incomplete')
def write_json(path,value):
    # Observer file arguments may have been created during preflight. Recheck
    # inputs at the actual write boundary as well as before process dispatch.
    if artifact_conflict(path):fail('artifact_path_conflict')
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_name(path.name+'.'+run_id+'.tmp')
    fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as stream:json.dump(value,stream,ensure_ascii=False,indent=2);stream.write('\n')
    os.replace(temporary,path)
def safe_file(path,private=False):
    try:
        info=path.lstat();parent=path.parent.lstat()
        return stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and not info.st_mode & (0o077 if private else 0o022) and (not private or (stat.S_ISDIR(parent.st_mode) and parent.st_uid==os.getuid() and not parent.st_mode&0o077))
    except OSError:return False
def same_identity(left,right):
    # resolve follows parent symlinks before processing '..'. samefile also
    # catches existing hard links, which canonical pathname equality cannot.
    if left.resolve(strict=False)==right.resolve(strict=False):return True
    try:return os.path.samefile(left,right)
    except FileNotFoundError:return False
def input_paths():
    # The observer executable and existing script/config arguments are inputs,
    # even when they are reachable through '..', symlinks or hard links.
    observer_files=[pathlib.Path(part).absolute() for part in owner_cmd if pathlib.Path(part).is_file()]
    return [binary,helper,snapshot]+([seam_path] if seam_path else [])+observer_files
def artifact_conflict(path):
    return any(same_identity(path,source) for source in input_paths())
def verify_artifact_paths():
    if same_identity(ready_path,report_path) or artifact_conflict(ready_path) or artifact_conflict(report_path):fail('artifact_path_conflict')
def report_destination():
    # Even an early validation failure must not overwrite its own input while
    # attempting to record the failure. Refuse that destination and use a fresh
    # sibling; stdout identifies the actual report artifact.
    if artifact_conflict(report_path) or same_identity(report_path,ready_path):
        candidate=report_path.parent.resolve(strict=False)/(report_path.name+'.refused-'+run_id+'.json')
        if artifact_conflict(candidate):fail('artifact_path_conflict')
        return candidate
    return report_path
def file_hash(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        while True:
            remaining();chunk=stream.read(1024*1024)
            if not chunk:break
            digest.update(chunk)
    return digest.hexdigest()
def run(command,limit):
    return subprocess.run(command,text=True,capture_output=True,timeout=min(limit,remaining()),env=env)
def safe_probe_observation(value):
    if not isinstance(value,dict):return {}
    out={k:value[k] for k in ('probed','synthetic_only','mutation_authorized','current_cohort_only','journal_modified','app_activated','foreground_focus') if type(value.get(k)) is bool}
    if type(value.get('credentials_changed')) is int and 0<=value['credentials_changed']<=100:out['credentials_changed']=value['credentials_changed']
    error=value.get('error')
    if isinstance(error,str) and re.fullmatch(r'maintenance_[a-z_]{1,100}',error):out['error']=error
    raw=value.get('diagnostics');diag={}
    if isinstance(raw,dict):
        for key in ('focus_requested','focus_settable','focus_verified','notes_range_settable','notes_text_settable','notes_value_settable','notes_probe_read_opened','notes_probe_recovery_attempted','notes_probe_editor_recovered','notes_probe_editor_requires_review'):
            if type(raw.get(key)) is bool:diag[key]=raw[key]
        for key in ('focus_set_code','notes_range_code','notes_text_code','notes_value_code','notes_actions_code','notes_observation_frames','notes_probe_row_count'):
            if type(raw.get(key)) is int and abs(raw[key])<=100000000:diag[key]=raw[key]
        allowed={'notes_role':('AXTextField','AXTextArea'),'notes_observation_end':('two_complete_writable_frames','stable_unsupported','transient_or_incomplete_timeout','editable_fields_changed'),'notes_probe_stage':('input_validation','initial_cohort','initial_read','initial_state','notes_capabilities','notes_structure','first_cancel','preservation_cohort','preservation_read','preservation_state','final_cancel','complete','foreground_owner','notes_focus')}
        for key,values in allowed.items():
            if raw.get(key) in values:diag[key]=raw[key]
    if diag:out['diagnostics']=diag
    return out
def observe_owner(stage):
    observation={'sequence':len(owner_observations)+1,'stage':stage,'query_ok':False,'metadata_known':False,'is_passwords':False,'timed_out':False}
    code=None;classification=None
    try:
        result=run(owner_cmd,owner_timeout);observation['exit_code']=result.returncode
        if result.returncode:
            codes=re.findall(r'\((-?\d{1,8})\)',result.stderr)
            if codes:code=int(codes[-1]);observation['system_error_code']=code
            classification='owner_query_permission_denied' if code==-1743 else 'owner_query_exit_error'
        else:
            try:value=json.loads(result.stdout)
            except (ValueError,TypeError):value=None
            if not isinstance(value,dict) or any(type(value.get(k)) is not bool for k in ('ok','owner_known','is_passwords','pid_positive')) or value.get('ok') is not True or (value.get('is_passwords') and not (value.get('owner_known') and value.get('pid_positive'))):classification='owner_query_invalid_response'
            else:
                observation.update(query_ok=True,metadata_known=value['owner_known'],is_passwords=value['is_passwords'])
                if not value['owner_known'] or not value['pid_positive']:classification='owner_metadata_unavailable'
    except subprocess.TimeoutExpired:
        observation['timed_out']=True;classification='total_deadline_exceeded' if time.monotonic()>=deadline else 'owner_query_timeout'
    except OSError:classification='owner_query_launch_error'
    observation['classification']=classification or 'observed';owner_observations.append(observation)
    if classification:fail(classification)
    return observation['is_passwords']

try:
    verify_artifact_paths()
    if not isolated and 'APW_MAINTENANCE_HELPER' in os.environ:fail('helper_override_requires_isolated')
    if isolated:
        seam=seam_path
        if not safe_file(seam,private=True):fail('isolated_seam_unsafe')
        try:settings=json.loads(seam.read_text())
        except (OSError,ValueError):fail('isolated_seam_invalid')
        if not isinstance(settings,dict) or set(settings)!={'format','owner_command','helper_path','owner_query_timeout_seconds'} or settings['format']!='apw-notes-probe-isolated-v1' or not isinstance(settings['owner_command'],list) or not settings['owner_command'] or any(not isinstance(x,str) or not x or '\0' in x for x in settings['owner_command']) or not isinstance(settings['helper_path'],str) or type(settings['owner_query_timeout_seconds']) not in (int,float) or not 0.05<=settings['owner_query_timeout_seconds']<=3:fail('isolated_seam_invalid')
        owner_cmd=settings['owner_command'];helper=pathlib.Path(settings['helper_path']).absolute();owner_timeout=float(settings['owner_query_timeout_seconds']);env['APW_MAINTENANCE_HELPER']=str(helper)
        verify_artifact_paths()
    if not safe_file(binary) or not os.access(binary,os.X_OK):fail('preflight_cli_unavailable')
    if not safe_file(helper) or not os.access(helper,os.X_OK):fail('preflight_helper_unavailable')
    if not safe_file(snapshot,private=True):fail('preflight_snapshot_unsafe')
    artifacts={'cli_sha256':file_hash(binary),'helper_sha256':file_hash(helper)}
    doctor_invocations+=1
    try:doctor=run(doctor_cmd,10)
    except subprocess.TimeoutExpired:fail('total_deadline_exceeded' if time.monotonic()>=deadline else 'preflight_helper_timeout')
    if doctor.returncode:fail('preflight_helper_failed')
    try:doctor_value=json.loads(doctor.stdout)
    except ValueError:fail('preflight_helper_invalid_response')
    if not isinstance(doctor_value,dict) or doctor_value.get('ok') is not True or doctor_value.get('app_activated') is not False:fail('preflight_helper_invalid_response')
    preflight['doctor_completed']=True
    preflight['accessibility_trusted']=doctor_value.get('accessibility_trusted') is True
    if not preflight['accessibility_trusted']:fail('preflight_accessibility_unavailable')
    target=observe_owner('preflight');preflight.update(tool_ready=True,owner_observer_ready=True)
    ready={'event':'ready','run_id':run_id,'tool_ready':True,'owner_observer_ready':True,'awaiting_foreground':a.foreground_focus and not target,'isolated_test_seam':isolated,'backend_probe_completed':False,'provenance_unverified':True,'real_apple_verified':False}
    write_json(ready_path,ready);print(json.dumps(ready),flush=True)
    if a.foreground_focus and not target:
        watch_deadline=min(deadline,time.monotonic()+a.wait_foreground_seconds)
        while time.monotonic()<watch_deadline:
            time.sleep(min(0.2,remaining(),max(0,watch_deadline-time.monotonic())))
            remaining()
            if time.monotonic()>=watch_deadline:break
            if observe_owner('foreground_watch'):target=True;break
        remaining()
        if not target:fail('target_owner_not_observed')
    remaining();probe_invocations+=1
    try:result=run(cmd,110)
    except subprocess.TimeoutExpired:fail('total_deadline_exceeded' if time.monotonic()>=deadline else 'probe_timeout')
    exit_status=result.returncode
    for line in (result.stdout+'\n'+result.stderr).splitlines():
        try:
            value=safe_probe_observation(json.loads(line))
            if value:observations.append(value)
        except ValueError:pass
    if exit_status:fail('probe_failed')
    try:v=json.loads(result.stdout)
    except ValueError:fail('probe_reply_invalid')
    check('actual compiled entry point completed',exit_status==0)
    check('whole original state preserved and both editors canceled',v.get('probed') is True and v.get('credentials_changed')==0)
    check('cohort observation never authorizes a mutation',v.get('synthetic_only') is True and v.get('current_cohort_only') is True and v.get('mutation_authorized') is False)
    check('no journal modification or application activation',v.get('journal_modified') is False and v.get('app_activated') is False)
    check('internal field-focus mode matches explicit request',v.get('foreground_focus',False) is a.foreground_focus)
    check('complete diagnostic stage reached',v.get('diagnostics',{}).get('notes_probe_stage')=='complete')
    if a.foreground_focus:check('requested field focus was actually verified',v.get('diagnostics',{}).get('focus_requested') is True and v.get('diagnostics',{}).get('focus_verified') is True)
except Failed as exc:failure=exc.code
except OSError:failure='runner_filesystem_or_launch_error'
except Exception:failure='runner_unexpected_failure'

actual_report=report_destination()
report={'passed':failure is None,'checks':checks,'error':failure,'run_id':run_id,'command':shlex.join([sys.executable,str(pathlib.Path(__file__).resolve()),*sys.argv[1:]]),'entry_point_command':shlex.join(cmd),'preflight_command':shlex.join(doctor_cmd),'exit_status':exit_status,'artifacts':artifacts,'preflight':preflight,'ready_artifact':str(ready_path),'report_artifact':str(actual_report),'owner_observations':owner_observations,'observations':observations,'doctor_invocations':doctor_invocations,'probe_invocations':probe_invocations,'bounds':{'total_seconds':total,'preflight_max_seconds':10,'owner_query_max_seconds':owner_timeout,'probe_max_seconds':110,'owner_poll_seconds':0.2,'probe_retries':0},'elapsed_seconds':round(time.monotonic()-started,3),'person_action_inferred':False,'isolated_test_seam':isolated,'backend_probe_completed':failure is None,'provenance_unverified':True,'real_apple_verified':False,'boundary':'isolated owner/native helper adapters through existing compiled apw' if isolated else 'compiled apw diagnostic with unverified backend provenance; existing synthetic preimage only, no query/text writes or activation','apple_notes_write_verified':False,'apple_delete_verified':False,'exports':0,'imports':0,'real_customer_records_modified':0}
write_json(actual_report,report);print(json.dumps({'event':'result','passed':report['passed'],'checks':len(checks),'error':failure,'report':str(actual_report)}),flush=True);raise SystemExit(0 if report['passed'] else 1)
