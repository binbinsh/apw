#!/usr/bin/env python3
"""Actual CLI password-read shape contract, isolated synthetic Unix daemon."""
import argparse,contextlib,json,os,pathlib,shlex,socket,subprocess,tempfile,threading
p=argparse.ArgumentParser();p.add_argument('--bin',required=True);p.add_argument('--report',required=True);a=p.parse_args()
checks=[];error=None;secret='  APW_PASSWORD_SHAPE_SYNTHETIC\n密碼 🔑  '
def check(name,value):checks.append({'name':name,'passed':bool(value)})
with tempfile.TemporaryDirectory(prefix='apw-password-shape-e2e-') as tmp:
 root=pathlib.Path(tmp);root.chmod(0o700);state={'entries':[],'calls':[]}
 server=socket.socket(socket.AF_UNIX);server.bind(str(root/'apw.sock'));(root/'apw.sock').chmod(0o600);server.listen();stop=threading.Event()
 def serve():
  while not stop.is_set():
   try:conn,_=server.accept()
   except OSError:break
   with conn:
    data=b''
    while b'\n' not in data:
     chunk=conn.recv(65536)
     if not chunk:break
     data+=chunk
    if not data:continue
    request=json.loads(data);state['calls'].append(request.get('cmd'))
    if request.get('cmd')==4:entries=[{'USR':'alice@example.invalid','PWD':'Not Included','sites':['example.invalid']}]
    elif request.get('cmd')==5:entries=state['entries']
    else:entries=[]
    with contextlib.suppress(OSError):conn.sendall((json.dumps({'data':{'STATUS':0,'Entries':entries,'RequiresUserAuthenticationToFill':False}})+'\n').encode())
 thread=threading.Thread(target=serve,daemon=True);thread.start()
 def run(entries):
  state['entries']=entries;state['calls']=[]
  r=subprocess.run([str(pathlib.Path(a.bin).resolve()),'pw','get','example.invalid','alice@example.invalid'],env={**os.environ,'APW_DATA_DIR':tmp},capture_output=True,text=True,timeout=10)
  return r,list(state['calls'])
 base={'USR':'alice@example.invalid','sites':['example.invalid']}
 try:
  for name,value in [('missing',... ),('null',None),('number',42),('object',{'secret':secret}),('array',[secret]),('sentinel','Not Included')]:
   r,calls=run([{**base,**({} if value is ... else {'PWD':value})}])
   try:failure=json.loads(r.stderr)
   except json.JSONDecodeError:failure={}
   check(name+': unavailable matching password refuses without successful output',r.returncode!=0 and r.stdout=='' and failure.get('error')=='apple_password_value_unavailable')
   check(name+': no leaked secret, retry, startup or mutation',secret not in r.stdout+r.stderr and calls==[4,5])
  for name,value in [('empty',''),('exact Unicode whitespace',secret)]:
   r,calls=run([{**base,'PWD':value}]);v=json.loads(r.stdout or '{}')
   check(name+': explicitly returned password preserved',r.returncode==0 and v.get('results',[{}])[0].get('password')==value and calls==[4,5])
  r,calls=run([{**base,'USR':'other@example.invalid','PWD':None},{**base,'sites':['other.invalid'],'PWD':None},{**base,'PWD':secret}]);v=json.loads(r.stdout or '{}')
  check('unrelated malformed results do not replace or block requested credential',r.returncode==0 and len(v.get('results',[]))==1 and v['results'][0].get('password')==secret and calls==[4,5])
  r,calls=run([]);v=json.loads(r.stdout or '{}')
  check('actual no results is distinct from matching unavailable data',r.returncode==0 and v.get('results')==[] and calls==[4,5])
 except Exception as exc:error=type(exc).__name__+': '+str(exc)
 finally:
  stop.set()
  with contextlib.suppress(OSError):wake=socket.socket(socket.AF_UNIX);wake.connect(str(root/'apw.sock'));wake.close()
  server.close();thread.join(2)
report={'passed':error is None and all(x['passed'] for x in checks),'checks':checks,'error':error,'command':shlex.join(['python3',str(pathlib.Path(__file__).resolve()),'--bin',str(pathlib.Path(a.bin).resolve()),'--report',str(pathlib.Path(a.report).resolve())]),'boundary':'actual compiled CLI and isolated synthetic daemon; no Apple access','real_apple_verified':False,'real_customer_records_modified':0}
pathlib.Path(a.report).parent.mkdir(parents=True,exist_ok=True);pathlib.Path(a.report).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'passed':report['passed'],'checks':len(checks),'failed_checks':[x['name'] for x in checks if not x['passed']],'error':error}));raise SystemExit(0 if report['passed'] else 1)
