#!/usr/bin/env python3
"""Actual GPL apw command entry point against a synthetic Unix daemon."""
import argparse,contextlib,json,os,pathlib,shlex,socket,subprocess,tempfile,threading
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args();checks=[];failure=None
secret='  APW_SYNTHETIC_SECRET\n保留尾部空白  '
with tempfile.TemporaryDirectory(prefix='ap-apw-e2e-') as temp:
    base=pathlib.Path(temp);base.chmod(0o700);state={'mode':'ok','saves':0,'requests':0}
    server=socket.socket(socket.AF_UNIX);server.bind(str(base/'apw.sock'));(base/'apw.sock').chmod(0o600);server.listen();stop=threading.Event()
    def serve():
        while not stop.is_set():
            try:conn,_=server.accept()
            except OSError:break
            with conn:
                raw=b''
                while b'\n' not in raw:
                    chunk=conn.recv(65536)
                    if not chunk:break
                    raw+=chunk
                if not raw:continue
                request=json.loads(raw);state['requests']+=1
                if request.get('op')=='status':response={'data':{'STATUS':0,'running':True,'bridge':True,'paired':False,'browser':'Brave'}}
                elif state['mode']=='error':response={'status':100,'error':secret}
                elif request.get('cmd')==6:
                    state['saves']+=1;state['saved']=request['body']['NPWD']
                    state['save_host']=request['body']['NURL']
                    response={'data':{'STATUS':5}} if state['mode']=='save_failed' else ({'data':{}} if state['mode']=='missing_ack' else {'data':{'STATUS':0}})
                elif request.get('cmd') in (16,17):response={'data':{'STATUS':0,'Entries':[{'username':'alice@example.invalid','domain':'example.invalid','code':'931086'}]}}
                else:
                    state['query_host']=request['body']['URL']
                    entries=[] if state['mode']=='wrong_saved' else [{'USR':'alice@example.invalid','PWD':secret,'sites':['example.invalid']}]
                    response={'data':{'STATUS':0,'Entries':entries}}
                with contextlib.suppress(OSError):conn.sendall((json.dumps(response)+'\n').encode())
    thread=threading.Thread(target=serve,daemon=True);thread.start();env={**os.environ,'APW_DATA_DIR':temp}
    def call(*args,ok=True,input=None):
        r=subprocess.run([a.bin,*args],env=env,input=input,capture_output=True,text=True,timeout=40)
        assert (r.returncode==0)==ok,'unexpected_command_status'
        return r
    def check(name,condition):
        checks.append({'name':name,'passed':bool(condition)});assert condition,name
    try:
        check('native CLI help and version remain available','pw' in call('--help').stdout and '1.1.1' in call('--version').stdout)
        before=state['requests'];call('bridge',ok=False,input='{"operation":"status"}')
        check('removed ap-only JSON adapter is unavailable',state['requests']==before)
        listing=call('pw','list','example.invalid').stdout
        check('native list hides password material',secret not in listing and 'password' not in json.loads(listing)['results'][0])
        result=json.loads(call('pw','get','example.invalid','alice@example.invalid').stdout)
        check('explicit native password get preserves Unicode and whitespace',result['results'][0]['password']==secret)
        call('pw','get','https://example.invalid/path?x=1','alice@example.invalid')
        check('full password URL is normalized to Apple hostname scope',state['query_host']=='example.invalid')
        before=state['requests'];call('pw','get','file:///etc/passwd','alice@example.invalid',ok=False)
        check('native non-HTTP query is rejected before transport',state['requests']==before)
        check('native OTP get works',json.loads(call('otp','get','example.invalid').stdout)['results'][0]['code']=='931086')
        call('pw','save','--stdin','example.invalid','alice@example.invalid',input=secret)
        check('native stdin save preserves exact secret',state['saved']==secret)
        call('pw','save','--stdin','https://example.invalid/path','alice@example.invalid',input=secret)
        check('save URL is normalized to Apple hostname scope',state['save_host']=='example.invalid')
        state['mode']='wrong_saved';before=state['saves'];result=call('pw','save','--stdin','example.invalid','alice@example.invalid',input=secret,ok=False)
        check('native acknowledgement without matching readback fails without write retry',state['saves']==before+1 and 'apple_write_unverified' in result.stderr)
        state['mode']='missing_ack';call('pw','save','--stdin','example.invalid','alice@example.invalid',input=secret,ok=False)
        check('native missing explicit Apple status fails closed',True)
        state['mode']='save_failed';before=state['saves'];result=call('pw','save','--stdin','example.invalid','alice@example.invalid',input=secret,ok=False)
        check('Apple rejection is not reported as a successful save',state['saves']==before+1 and result.returncode!=0)
        state['mode']='error';result=call('pw','get','example.invalid','alice@example.invalid',ok=False)
        check('upstream error payload is not exposed',secret not in result.stdout+result.stderr and 'APW_SYNTHETIC_SECRET' not in result.stdout+result.stderr)
        state['mode']='ok';before=state['requests'];result=call('auth',ok=False,input='')
        check('noninteractive auth refuses before challenge',state['requests']==before and 'pair_requires_terminal' in result.stdout+result.stderr)
        result=call('auth','response','--pin','000000',ok=False,input='')
        check('PIN arguments are not accepted','000000' not in result.stdout+result.stderr and state['requests']==before)
        status=json.loads(call('status').stdout)
        check('native status reports live daemon state',status['running'] and not status['paired'])
        (base/'apw.sock').chmod(0o666);result=call('status',ok=False)
        check('unsafe socket permissions are refused','unsafe_apple_socket' in result.stdout+result.stderr)
    except Exception as exc:failure=type(exc).__name__+': '+str(exc)
    finally:
        stop.set()
        with contextlib.suppress(OSError):wake=socket.socket(socket.AF_UNIX);wake.connect(str(base/'apw.sock'));wake.close()
        server.close();thread.join(2)
report={'passed':failure is None,'checks':checks,'error':failure,'command':shlex.join(['python3','tests/e2e_apw.py','--bin',a.bin,'--report',a.report]),'real_apple_credentials_used':False,'boundary':'actual GPL apw CLI + synthetic Unix daemon'}
pathlib.Path(a.report).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'passed':report['passed'],'checks':len(checks),'error':failure}));raise SystemExit(0 if report['passed'] else 1)
