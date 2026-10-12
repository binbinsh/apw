#!/usr/bin/env python3
"""Ordinary notes-set contract through the compiled CLI; fake native only.

Specification: docs/batch-notes-background-contract-failure-spec.md.
"""
import argparse
import copy
import hashlib
import json
import os
import pathlib
import shlex
import subprocess
import tempfile


def sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                    separators=(",", ":")).encode()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bin", required=True)
    p.add_argument("--report", required=True)
    a = p.parse_args()
    binary = str(pathlib.Path(a.bin).resolve())
    report_path = pathlib.Path(a.report).resolve()
    checks, invocations, error = [], [], None
    before = {"key": {"title": "synthetic normal notes login", "username": "ordinary@example.invalid"},
              "native_title": "synthetic normal native title", "notes": "原始正文🙂 e\u0301\nAPW_ORDINARY_NOTE_ORIGINAL",
              "password": "APW_ORDINARY_SECRET_PASSWORD", "sites": ["https://ordinary.example.invalid"],
              "sharing": "unshared", "otp": "present", "passkey": "present",
              "extra_fields": [{"identifier": "synthetic_metadata", "value": "APW_ORDINARY_EXTRA"}]}
    append = "\n\nAPW_ORDINARY_ADDITION 多行\n中文🙂 e\u0301"
    required = {"persisted": True, "background_only": True, "original_foreground_preserved": True,
                "input_keyboard_focus_preserved": True, "app_activated": False,
                "credentials_changed": 1, "exports": 0, "imports": 0,
                "input_focus_owner_kind": "present", "keyboard_focus_scope": "focus_setter_through_save"}

    def check(name, passed):
        checks.append({"name": name, "passed": bool(passed)})

    with tempfile.TemporaryDirectory(prefix="apw-batch-notes-background-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        helper = root / "fake-native.py"
        helper.write_text('''#!/usr/bin/env python3
import copy,hashlib,json,os,sys
s=json.load(open(os.environ['APW_TEST_SETTINGS']))
def sha(v):return hashlib.sha256(json.dumps(v,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
for line in sys.stdin:
 q=json.loads(line);op=q['op'];proof=False
 if op=='notes-set':
  try:
   intent=json.loads(open(s['journal']).read().splitlines()[-1]);path=intent['before_snapshot_path'];pre=json.load(open(path));info=os.lstat(path)
   proof=intent['event']=='intent' and intent['before_sha256']==sha(s['before']) and pre['state']==s['before'] and pre['sha256']==sha(s['before']) and info.st_uid==os.getuid() and info.st_nlink==1 and info.st_mode&0o077==0
  except Exception:pass
 with open(s['calls'],'a') as f:f.write(json.dumps({'op':op,'intent_before_dispatch':proof,'request_exact':q.get('expected')==s['before'] and q.get('key')==s['before']['key'] and q.get('notes')==s['notes']})+'\\n')
 r={'id':q['id'],'ok':True,'app_activated':False}
 if op=='read':r['state']=json.load(open(s['state']))
 elif op=='notes-set':
  expected={**s['before'],'notes':s['notes']};after=copy.deepcopy(expected)
  r={'id':q['id'],'ok':True,**s['ack'],'state':copy.deepcopy(expected)}
  mode=s['mode']
  if mode=='native-error':r.update(ok=False,error='maintenance_native_refused')
  elif mode=='missing-state':r.pop('state')
  elif mode=='partial-state':r['state'].pop('sites')
  elif mode=='wrong-state':r['state']=s['bad_state']
  elif mode=='readback-mismatch':after={**expected,'password':'APW_CHANGED_SECRET_PASSWORD'}
  if mode!='native-error':
   with open(s['state'],'w') as f:json.dump(after,f,ensure_ascii=False)
  if mode=='lost-reply':sys.exit(0)
 else:r.update(ok=False,error='maintenance_operation_unsupported')
 print(json.dumps(r,ensure_ascii=False),flush=True)
''')
        helper.chmod(0o700)

        def write(path, value):
            path.write_text(json.dumps(value, ensure_ascii=False))
            path.chmod(0o600)

        def run(name, mode="valid", ack=None, notes=None, bad_state=None, rejection=False, legacy=None):
            directory = root / name
            directory.mkdir(mode=0o700)
            notes = before["notes"] + append if notes is None else notes
            after = {**before, "notes": notes}
            operation = {"id": "ordinary-notes-001", "kind": "notes-set", "target": before["key"],
                         "before_sha256": sha(before), "notes": notes}
            plan = {"format": "apw-maintenance-v1", "operations": [operation]}
            plan_path, journal, state_path = directory / "plan.json", directory / "journal.jsonl", directory / "state.json"
            calls, settings = directory / "calls.jsonl", directory / "settings.json"
            write(plan_path, plan)
            write(state_path, after if legacy else before)
            if legacy:
                preimage = pathlib.Path(str(journal) + ".ordinary-notes-001.before.json")
                write(preimage, {"format": "apw-item-snapshot-v1", "sha256": sha(before), "state": before})
                intent = {"plan": sha(plan), "id": operation["id"], "event": "intent", "before_sha256": sha(before),
                          "after_sha256": sha(after), "before_native_title": before["native_title"],
                          "before_snapshot_path": str(preimage), "at": "2026-10-12T00:00:00.000Z"}
                history = [intent, {"plan": sha(plan), "id": operation["id"], "event": legacy,
                                   "before_sha256": sha(before), "after_sha256": sha(after), "at": "2026-10-12T00:00:01.000Z"}]
                journal.write_text("".join(json.dumps(x) + "\n" for x in history))
                journal.chmod(0o600)
            write(settings, {"before": before, "notes": notes, "ack": required if ack is None else ack,
                             "mode": mode, "bad_state": bad_state, "journal": str(journal),
                             "state": str(state_path), "calls": str(calls)})
            command = [binary, "batch", "run", "--apply", "--plan", str(plan_path), "--journal", str(journal)]
            env = {**os.environ, "APW_DATA_DIR": str(root), "APW_MAINTENANCE_HELPER": str(helper),
                   "APW_TEST_SETTINGS": str(settings)}
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": result.returncode,
                                "stdout": result.stdout, "stderr": result.stderr})
            observed = [json.loads(x) for x in calls.read_text().splitlines()] if calls.exists() else []
            history = [json.loads(x) for x in journal.read_text().splitlines()] if journal.exists() else []
            public = result.stdout + result.stderr
            check(name + ": no note/password/account/site disclosure", all(secret not in public for secret in
                  [before["notes"], before["password"], before["key"]["username"], *before["sites"], append, "APW_CHANGED_SECRET_PASSWORD"]))
            check(name + ": structural journal has no secret content", all(secret not in journal.read_text() for secret in
                  [before["notes"], before["password"], before["key"]["username"], *before["sites"], append]) if journal.exists() else True)
            if legacy:
                check(name + ": historical proof succeeds without a fresh acknowledgement", result.returncode == 0 and json.loads(result.stdout).get("completed") == 1)
                check(name + ": old intent is never replayed", [x["op"] for x in observed] == ["read"] and json.loads(state_path.read_text()) == after)
                return
            if rejection:
                check(name + ": append-only refusal before intent or mutation", result.returncode != 0 and "maintenance_note_preservation_refused" in result.stderr and [x["op"] for x in observed] == ["read"] and not history)
                check(name + ": full original unchanged", json.loads(state_path.read_text()) == before)
                return
            check(name + ": one exact dispatch preceded by private full preimage and intent", len([x for x in observed if x["op"] == "notes-set"]) == 1 and all(x["request_exact"] and x["intent_before_dispatch"] for x in observed if x["op"] == "notes-set"))
            if mode == "valid":
                check(name + ": acknowledgement plus subsequent independent complete read produces done", result.returncode == 0 and [x["op"] for x in observed] == ["read", "notes-set", "read"] and [x["event"] for x in history] == ["intent", "done"] and history[-1].get("after_sha256") == sha(after) and json.loads(state_path.read_text()) == after)
                return
            check(name + ": invalid acknowledgement/readback yields uncertain and never done", result.returncode != 0 and result.stdout == "" and [x["event"] for x in history] == ["intent", "uncertain"])
            # Explicit recovery may prove persisted full state, but may not resend
            # the old write even if the first acknowledgement was malformed.
            mutation_count = sum(x["op"] == "notes-set" for x in observed)
            resumed = subprocess.run(command, env=env, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": resumed.returncode,
                                "stdout": resumed.stdout, "stderr": resumed.stderr})
            final_calls = [json.loads(x) for x in calls.read_text().splitlines()]
            check(name + ": explicit recovery never retries uncertain mutation", sum(x["op"] == "notes-set" for x in final_calls) == mutation_count and all(x["op"] == "read" for x in final_calls[len(observed):]))

        try:
            run("valid-present")
            run("valid-absent", ack={**required, "input_focus_owner_kind": "absent"})
            run("no-append", notes=before["notes"], rejection=True)
            prefix_units = len(before["notes"].encode("utf-16-le")) // 2
            boundary = before["notes"] + "🙂" * ((4096 - prefix_units) // 2) + "x" * ((4096 - prefix_units) % 2)
            run("utf16-boundary", notes=boundary)
            run("utf16-over-limit", notes=boundary + "x", rejection=True)
            run("moved-original", notes=append + "\n" + before["notes"], rejection=True)
            run("prepend-original", notes="PREFIX\n" + before["notes"] + append, rejection=True)
            for name, value in required.items():
                missing = {k: v for k, v in required.items() if k != name}
                run("missing-" + name, mode="ack-bad", ack=missing)
                wrong = not value if type(value) is bool else value + 1 if type(value) is int else "unknown"
                run("wrong-" + name, mode="ack-bad", ack={**required, name: wrong})
                typed = "true" if type(value) is bool else True if type(value) is int else {}
                run("type-" + name, mode="ack-bad", ack={**required, name: typed})
            for field, value in (("key", {"title": "other synthetic title", "username": before["key"]["username"]}),
                                 ("native_title", "different alias"), ("notes", before["notes"]),
                                 ("password", "APW_CHANGED_SECRET_PASSWORD"), ("sites", ["https://changed.invalid"]),
                                 ("sharing", "unknown"), ("otp", "unknown"), ("passkey", "unknown"), ("extra_fields", [])):
                changed = copy.deepcopy({**before, "notes": before["notes"] + append})
                changed[field] = value
                run("changed-state-" + field, mode="wrong-state", bad_state=changed)
            for mode in ("native-error", "missing-state", "partial-state", "lost-reply", "readback-mismatch"):
                run(mode, mode=mode)
            run("legacy-uncertain-includes", notes="OLD_PREFIX\n" + before["notes"] + append, legacy="uncertain")
            run("legacy-done-includes", notes="OLD_PREFIX\n" + before["notes"] + append, legacy="done")
        except Exception as exc:
            error = type(exc).__name__ + ": " + str(exc)
    report = {"passed": error is None and all(x["passed"] for x in checks), "checks": checks, "error": error,
              "command": shlex.join(["python3", str(pathlib.Path(__file__).resolve()), "--bin", binary, "--report", str(report_path)]),
              "invocations": invocations, "boundary": "actual compiled ordinary batch CLI + private fake native",
              "real_apple_verified": False, "real_customer_records_modified": 0, "exports": 0, "imports": 0}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "error": error,
                      "failed_checks": [x["name"] for x in checks if not x["passed"]]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
