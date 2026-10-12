#!/usr/bin/env python3
"""Synthetic-only foreground notes protocol through the actual compiled CLI.

Specification: docs/synthetic-foreground-notes-input-failure-spec.md.
This does not access Apple or certify actual native persistence.
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

ORIGINAL = "APW_EXCHANGE_SYNTHETIC_V1 ORIGINAL_SYNTHETIC_NOTES\n"
SUFFIX = "\nAPW_FOREGROUND_INPUT_SYNTHETIC_V1 SYNTHETIC_APPENDED_NOTES"
SECRET = "SYNTHETIC_APPENDED_NOTES"


def sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    report_path = pathlib.Path(args.report).resolve()
    checks, invocations = [], []
    error = None
    expected = {"key": {"title": "apw API 测试 · SSO 与备注", "username": "synthetic-google@example.invalid"},
        "native_title": "apw API 测试 · SSO 与备注", "notes": ORIGINAL, "password": "",
        "sites": ["https://apw-exchange-demo.invalid"], "sharing": "unshared", "otp": "absent",
        "passkey": "unknown", "extra_fields": []}

    def check(name, condition):
        checks.append({"name": name, "passed": bool(condition)})

    with tempfile.TemporaryDirectory(prefix="apw-synthetic-notes-input-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        helper = root / "synthetic-notes-native.py"
        helper.write_text('''#!/usr/bin/env python3
import copy,json,os,sys
settings=json.load(open(os.environ['APW_TEST_SETTINGS']))
for line in sys.stdin:
 q=json.loads(line);before=settings['expected'];notes=settings['notes'];mode=settings['mode']
 try: journal=[json.loads(x) for x in open(settings['journal']) if x.strip()]
 except Exception: journal=[]
 with open(settings['calls'],'a') as f:
  f.write(json.dumps({'op':q.get('op'),'request_exact':set(q)=={'id','op','expected','key','notes','synthetic_only','foreground_focus'} and q.get('expected')==before and q.get('key')==before['key'] and q.get('notes')==notes and q.get('synthetic_only') is True and q.get('foreground_focus') is True,'intent_before_dispatch':len(journal)==1 and journal[0].get('event')=='intent' and journal[0].get('before_sha256')==settings['before_sha256'] and journal[0].get('after_sha256')==settings['after_sha256']})+'\\n')
 if mode=='lost-reply':sys.exit(1)
 r={'id':q['id'],'ok':True,'app_activated':False,'synthetic_only':True,'persisted':True,'credentials_changed':1,'exports':0,'imports':0,'state':{**before,'notes':notes}}
 if mode.startswith('native-error'):
  diag={'notes':notes,'password':'SYNTHETIC_SECRET_PASSWORD','unknown':notes}
  if mode=='native-error-safe-diagnostics':diag.update(synthetic_input_stage='text_input',synthetic_input_event_count=2,synthetic_input_permission=True,synthetic_input_selection_verified=True,synthetic_input_postimage_verified=False,synthetic_input_persisted_verified=False,synthetic_input_editor_requires_review=True)
  if mode=='native-error-bad-diagnostics':diag.update(synthetic_input_stage=notes,synthetic_input_event_count=5,synthetic_input_permission=1,synthetic_input_selection_verified='true',synthetic_input_postimage_verified=notes,synthetic_input_persisted_verified=None,synthetic_input_editor_requires_review=[])
  r.update(ok=False,error='maintenance_synthetic_native_refused',diagnostics=diag)
 elif mode=='wrong-id':r['id']+=1
 elif mode.startswith('ack-'):
  name=mode[4:];r[name]=not r[name] if type(r[name]) is bool else r[name]+1
 elif mode=='boolean-only':r.pop('state')
 elif mode=='partial-state':r['state'].pop('sites')
 elif mode=='unsaved-notes':r['state']['notes']=before['notes']
 elif mode.startswith('changed-'):
  name=mode[8:]
  if name=='title':r['state']['key']={**before['key'],'title':'other synthetic title'}
  elif name=='username':r['state']['key']={**before['key'],'username':'other@example.invalid'}
  elif name=='sites':r['state']['sites']=['https://other.invalid']
  elif name=='extra_fields':r['state']['extra_fields']=[{'unknown':'SYNTHETIC_SECRET_PASSWORD'}]
  elif name in ('otp','passkey','sharing'):r['state'][name]='unknown' if before[name]!='unknown' else 'present'
  else:r['state'][name]='SYNTHETIC_SECRET_PASSWORD'
 elif mode=='valid':
  with open(settings['model'],'w') as f:json.dump(r['state'],f)
 print(json.dumps(r),flush=True)
''')
        helper.chmod(0o700)

        def run(name, mode="valid", transform=None, notes=None, rejected=False, flag=True, file_mode=None, hash_bad=False, existing=False):
            directory = root / name
            directory.mkdir(mode=0o700)
            value = copy.deepcopy(expected)
            if transform:
                transform(value)
            content = notes if notes is not None else value["notes"] + SUFFIX
            snapshot, note_file, journal = directory / "snapshot.json", directory / "notes.txt", directory / "journal.jsonl"
            calls, model, settings_file = directory / "calls.jsonl", directory / "model.json", directory / "settings.json"
            raw = {"format": "apw-item-snapshot-v1", "sha256": "0" * 64 if hash_bad else sha(value), "state": value}
            snapshot.write_text(json.dumps(raw, ensure_ascii=False))
            snapshot.chmod(0o600)
            if isinstance(content, bytes):
                note_file.write_bytes(content)
            else:
                note_file.write_text(content)
            note_file.chmod(0o600)
            if file_mode == "snapshot-public":
                snapshot.chmod(0o644)
            elif file_mode == "notes-public":
                note_file.chmod(0o644)
            elif file_mode == "snapshot-symlink":
                source = directory / "real-snapshot.json"
                snapshot.rename(source)
                snapshot.symlink_to(source)
            sentinel = '{"event":"uncertain","synthetic_only":true}\n'
            if existing:
                journal.write_text(sentinel)
                journal.chmod(0o600)
            original_bytes = snapshot.read_bytes(), note_file.read_bytes()
            settings = {"mode": mode, "expected": value, "notes": content if isinstance(content, str) else "invalid UTF8",
                "journal": str(journal), "calls": str(calls), "model": str(model), "before_sha256": sha(value),
                "after_sha256": sha({**value, "notes": content if isinstance(content, str) else "invalid UTF8"})}
            settings_file.write_text(json.dumps(settings, ensure_ascii=False))
            settings_file.chmod(0o600)
            command = [binary, "item", "test-notes-input", "--snapshot", str(snapshot), "--notes-file", str(note_file), "--journal", str(journal)]
            if flag:
                command.append("--foreground-synthetic")
            env = {**os.environ, "APW_DATA_DIR": str(root), "APW_MAINTENANCE_HELPER": str(helper), "APW_TEST_SETTINGS": str(settings_file)}
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr})
            observed = [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else []
            history = [json.loads(line) for line in journal.read_text().splitlines()] if journal.exists() else []
            check(name + ": no secrets or state printed", all(secret not in result.stdout + result.stderr for secret in (SECRET, ORIGINAL, "SYNTHETIC_SECRET_PASSWORD", value["key"]["username"], value["sites"][0])))
            check(name + ": original private inputs unchanged", original_bytes == (snapshot.read_bytes(), note_file.read_bytes()))
            if rejected:
                code = "maintenance_synthetic_foreground_required" if not flag else "maintenance_synthetic_notes_journal_exists" if existing else "maintenance_synthetic_notes_input_invalid"
                check(name + ": rejected through implemented entry point", result.returncode != 0 and result.stdout == "" and code in result.stderr)
                check(name + ": no native interaction", observed == [])
                check(name + ": no new or changed journal", journal.read_text() == sentinel if existing else not journal.exists())
                return
            check(name + ": exactly one mutation request, no default read or retry", len(observed) == 1 and observed[0]["op"] == "synthetic-foreground-notes-input" and observed[0]["request_exact"])
            check(name + ": complete intent exists before native dispatch", len(observed) == 1 and observed[0]["intent_before_dispatch"])
            check(name + ": private journal contains no plaintext", journal.exists() and journal.stat().st_mode & 0o077 == 0 and all(secret not in journal.read_text() for secret in (SECRET, ORIGINAL, value["key"]["username"], value["sites"][0])))
            if mode == "valid":
                try:
                    public = json.loads(result.stdout)
                except ValueError:
                    public = {}
                check(name + ": after state proven and structural success reported", result.returncode == 0 and public == {"synthetic_only": True, "persisted": True, "credentials_changed": 1, "exports": 0, "imports": 0, "app_activated": False, "before_sha256": sha(value), "after_sha256": settings["after_sha256"]} and model.exists() and json.loads(model.read_text()) == {**value, "notes": content})
                check(name + ": only intent and verified done", [row.get("event") for row in history] == ["intent", "done"] and history[-1].get("after_sha256") == settings["after_sha256"])
            else:
                check(name + ": failed acknowledgement never reports persistence", result.returncode != 0 and result.stdout == "" and "maintenance_" in result.stderr)
                check(name + ": intent and uncertain, never done", [row.get("event") for row in history] == ["intent", "uncertain"] and history[-1].get("after_sha256") == settings["after_sha256"])
                if mode.startswith("native-error-"):
                    public_diagnostics = {}
                    for line in result.stderr.splitlines():
                        try:
                            public_diagnostics.update(json.loads(line).get("diagnostics", {}))
                        except (ValueError, TypeError, AttributeError):
                            pass
                    safe = {"synthetic_input_stage": "text_input", "synthetic_input_event_count": 2,
                        "synthetic_input_permission": True, "synthetic_input_selection_verified": True,
                        "synthetic_input_postimage_verified": False, "synthetic_input_persisted_verified": False,
                        "synthetic_input_editor_requires_review": True} if mode.endswith("safe-diagnostics") else {}
                    check(name + ": typed diagnostic allowlist and no unknown data", public_diagnostics == safe)
                second = subprocess.run(command, env=env, text=True, capture_output=True, timeout=8)
                invocations.append({"command": shlex.join(command), "exit_status": second.returncode, "stdout": second.stdout, "stderr": second.stderr})
                check(name + ": existing uncertain attempt holds without retry", second.returncode != 0 and "maintenance_synthetic_notes_journal_exists" in second.stderr and len(calls.read_text().splitlines()) == 1 and [json.loads(line).get("event") for line in journal.read_text().splitlines()] == ["intent", "uncertain"])

        try:
            run("valid")
            run("valid-unicode", notes=ORIGINAL + "\nAPW_FOREGROUND_INPUT_SYNTHETIC_V1 " + "😀" * 200)
            run("missing-foreground-flag", rejected=True, flag=False)
            run("bad-snapshot-hash", rejected=True, hash_bad=True)
            run("snapshot-public", rejected=True, file_mode="snapshot-public")
            run("notes-public", rejected=True, file_mode="notes-public")
            run("snapshot-symlink", rejected=True, file_mode="snapshot-symlink")
            run("invalid-utf8", rejected=True, notes=b"\xff")
            run("existing-journal", rejected=True, existing=True)
            for field, replacement in (("native_title", "another title"), ("password", "SYNTHETIC_SECRET_PASSWORD"), ("notes", "missing marker"), ("sites", ["https://customer.example"]), ("sharing", "unknown"), ("extra_fields", [{"field": "value"}])):
                run("invalid-" + field, rejected=True, transform=lambda value, field=field, replacement=replacement: value.update({field: replacement}))
            run("invalid-title", rejected=True, transform=lambda value: value.update(key={**value["key"], "title": "apw API 测试 · unauthorized new fixture"}, native_title="apw API 测试 · unauthorized new fixture"))
            run("invalid-account", rejected=True, transform=lambda value: value["key"].update(username="real@example.com"))
            run("prefix-omitted", rejected=True, notes=SUFFIX)
            run("no-append", rejected=True, notes=ORIGINAL)
            run("suffix-marker-omitted", rejected=True, notes=ORIGINAL + "\nplain additional text")
            run("suffix-utf16-over-limit", rejected=True, notes=ORIGINAL + "\nAPW_FOREGROUND_INPUT_SYNTHETIC_V1 " + "😀" * 250)
            run("total-over-limit", rejected=True, transform=lambda value: value.update(notes=ORIGINAL + "x" * 4000))
            run("nul-notes", rejected=True, notes=ORIGINAL + SUFFIX + "\0")
            for mode in ("native-error", "native-error-safe-diagnostics", "native-error-bad-diagnostics", "wrong-id", "lost-reply", "boolean-only", "partial-state", "unsaved-notes", "ack-synthetic_only", "ack-persisted", "ack-credentials_changed", "ack-exports", "ack-imports", "ack-app_activated", "changed-title", "changed-username", "changed-native_title", "changed-password", "changed-sites", "changed-otp", "changed-passkey", "changed-sharing", "changed-extra_fields"):
                run(mode, mode=mode)
        except Exception as exc:
            error = type(exc).__name__ + ": " + str(exc)
    report = {"passed": error is None and all(row["passed"] for row in checks), "checks": checks, "error": error,
        "command": shlex.join(["python3", str(pathlib.Path(__file__).resolve()), "--bin", binary, "--report", str(report_path)]),
        "invocations": invocations, "boundary": "actual compiled CLI + private synthetic foreground-operation helper",
        "real_apple_verified": False, "real_customer_records_modified": 0, "exports": 0, "imports": 0}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "error": error,
        "failed_checks": [row["name"] for row in checks if not row["passed"]]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
