#!/usr/bin/env python3
"""Hash-bound notes resume through compiled CLI and a read-only synthetic helper."""
import argparse
import copy
import hashlib
import json
import os
import pathlib
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    report_path = pathlib.Path(args.report).resolve()
    checks, invocations = [], []
    error = None

    def check(name, condition):
        checks.append({"name": name, "passed": bool(condition)})

    def sha(value):
        return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()

    before = {"key": {"title": "synthetic journal display title", "username": "alice@example.invalid"},
        "native_title": "synthetic native journal alias", "notes": "APW_SYNTHETIC_JOURNAL_ORIGINAL",
        "password": "APW_SYNTHETIC_JOURNAL_PASSWORD", "sites": ["https://journal.example.invalid"],
        "sharing": "unshared", "otp": "unknown", "passkey": "unknown", "extra_fields": []}
    planned = {**before, "notes": before["notes"] + "\nAPW_SYNTHETIC_JOURNAL_REQUIRED_ADDITION"}
    operation = {"id": "journal-security-001", "kind": "notes-set", "target": before["key"],
        "before_sha256": sha(before), "notes": planned["notes"]}
    plan = {"format": "apw-maintenance-v1", "operations": [operation]}

    with tempfile.TemporaryDirectory(prefix="apw-journal-security-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        helper = root / "synthetic-readonly.py"
        state_path, calls_path, plan_path = root / "state.json", root / "calls.jsonl", root / "plan.json"

        def write(path, value):
            path.write_text(json.dumps(value, ensure_ascii=False))
            path.chmod(0o600)

        write(plan_path, plan)
        helper.write_text('''#!/usr/bin/env python3
import hashlib,json,os,sys
def sha(value):return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
for line in sys.stdin:
 q=json.loads(line)
 proof=False
 if q['op']=='notes-set':
  try:
   entries=[json.loads(x) for x in open(os.environ['APW_TEST_JOURNAL']) if x.strip()];intent=entries[-1]
   preimage=json.load(open(intent['before_snapshot_path']));info=os.lstat(intent['before_snapshot_path'])
   proof=intent['event']=='intent' and preimage['state']==q['expected'] and preimage['sha256']==sha(q['expected']) and info.st_uid==os.getuid() and info.st_mode&0o077==0 and info.st_nlink==1
  except Exception:pass
 with open(os.environ['APW_TEST_CALLS'],'a') as f: f.write(json.dumps({'op':q['op'],'preimage_before_dispatch':proof})+'\\n')
 r={'id':q['id'],'app_activated':False,'backend':'synthetic'}
 if q['op']=='read': r.update(ok=True,state=json.load(open(os.environ['APW_TEST_STATE'])))
 elif q['op']=='notes-set' and os.environ.get('APW_TEST_MODE') in ('fresh','lost-reply'):
  value=json.load(open(os.environ['APW_TEST_STATE']));value['notes']=q['notes']
  with open(os.environ['APW_TEST_STATE'],'w') as f:json.dump(value,f)
  if os.environ['APW_TEST_MODE']=='lost-reply':sys.exit(0)
  r.update(ok=True)
 else: r.update(ok=False,error='maintenance_synthetic_mutation_forbidden')
 print(json.dumps(r),flush=True)
''')
        helper.chmod(0o700)
        env = {**os.environ, "APW_DATA_DIR": str(root), "APW_MAINTENANCE_HELPER": str(helper),
            "APW_TEST_STATE": str(state_path), "APW_TEST_CALLS": str(calls_path)}

        def run(name, current, stage="uncertain", intent_changes=None, should_pass=False, legacy=False, partial=False, no_reads=False, preimage=True, preimage_mode=None, preimage_value=None):
            write(state_path, current)
            calls_path.write_text("")
            calls_path.chmod(0o600)
            intent = {"plan": sha(plan), "id": operation["id"], "event": "intent",
                "before_sha256": sha(before), "after_sha256": sha(planned),
                "before_native_title": before["native_title"], "at": "2026-10-12T00:00:00.000Z"}
            if legacy:
                intent.pop("before_native_title")
            if intent_changes:
                for key, value in intent_changes.items():
                    if value == "__OMIT__":
                        intent.pop(key, None)
                    else:
                        intent[key] = value
            entries = [intent]
            if stage != "intent":
                entries.append({"plan": sha(plan), "id": operation["id"], "event": stage,
                    "before_sha256": sha(before), "at": "2026-10-12T00:00:01.000Z"})
            journal = root / (name + ".jsonl")
            before_path = pathlib.Path(str(journal) + "." + operation["id"] + ".before.json")
            if preimage:
                captured = preimage_value if preimage_value is not None else before
                write(before_path, {"format": "apw-item-snapshot-v1", "sha256": sha(captured), "state": captured})
                intent["before_snapshot_path"] = str(before_path)
                if preimage_mode == "public":
                    before_path.chmod(0o644)
                elif preimage_mode == "symlink":
                    source = root / (name + "-original-before.json")
                    before_path.rename(source)
                    before_path.symlink_to(source)
                elif preimage_mode == "corrupted":
                    write(before_path, {"format": "apw-item-snapshot-v1", "sha256": "0" * 64, "state": captured})
                elif preimage_mode == "missing":
                    before_path.unlink()
                elif preimage_mode == "hardlink":
                    os.link(before_path, root / (name + "-alias-before.json"))
                if intent_changes and "before_snapshot_path" in intent_changes:
                    intent["before_snapshot_path"] = intent_changes["before_snapshot_path"]
            original_journal = "".join(json.dumps(entry) + "\n" for entry in entries)
            if partial:
                original_journal = original_journal.rstrip("\n")
            journal.write_text(original_journal)
            journal.chmod(0o600)
            command = [binary, "batch", "run", "--apply", "--plan", str(plan_path), "--journal", str(journal)]
            result = subprocess.run(command, env={**env, "APW_TEST_JOURNAL": str(journal)}, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr})
            calls = [json.loads(line)["op"] for line in calls_path.read_text().splitlines()]
            check(name + ": no mutation dispatched and synthetic state unchanged",
                all(call == "read" for call in calls) and json.loads(state_path.read_text()) == current)
            check(name + ": no note or password printed", before["notes"] not in result.stdout + result.stderr and before["password"] not in result.stdout + result.stderr)
            if should_pass:
                value = json.loads(result.stdout) if result.stdout else {}
                check(name + ": valid intended complete state resumes read-only",
                    result.returncode == 0 and value.get("completed") == 1 and value.get("mutations") == 0 and calls == ["read"])
                check(name + ": recorded done only after correct readback",
                    json.loads(journal.read_text().splitlines()[-1])["event"] == "done")
            else:
                expected_error = "maintenance_journal_incomplete" if partial else "maintenance_outcome_requires_review"
                check(name + ": invalid or unsaved state is held", result.returncode != 0 and expected_error in result.stderr and result.stdout == "")
                check(name + ": held recovery appends no done or other journal record", journal.read_text() == original_journal)
            if no_reads:
                check(name + ": malformed journal rejected before native read", calls == [])

        def fresh(name, lost=False):
            write(state_path, before)
            calls_path.write_text("")
            calls_path.chmod(0o600)
            journal = root / (name + ".jsonl")
            command = [binary, "batch", "run", "--apply", "--plan", str(plan_path), "--journal", str(journal)]
            local = {**env, "APW_TEST_JOURNAL": str(journal), "APW_TEST_MODE": "lost-reply" if lost else "fresh"}
            result = subprocess.run(command, env=local, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            check(name + ": private full before snapshot precedes the one mutation", len([x for x in calls if x["op"] == "notes-set"]) == 1 and all(x["preimage_before_dispatch"] for x in calls if x["op"] == "notes-set"))
            check(name + ": fresh operation preserves the complete original fields", json.loads(state_path.read_text()) == planned and (result.returncode != 0 if lost else result.returncode == 0))
            check(name + ": no snapshot secret printed", before["password"] not in result.stdout + result.stderr and before["notes"] not in result.stdout + result.stderr)
            local["APW_TEST_MODE"] = "fresh"
            resumed = subprocess.run(command, env=local, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": resumed.returncode, "stdout": resumed.stdout, "stderr": resumed.stderr})
            calls = [json.loads(line) for line in calls_path.read_text().splitlines()]
            check(name + ": valid full-preimage resume is readonly", resumed.returncode == 0 and json.loads(resumed.stdout).get("mutations") == 0 and len([x for x in calls if x["op"] == "notes-set"]) == 1)
            check(name + ": done appended only after complete original-state proof", json.loads(journal.read_text().splitlines()[-1])["event"] == "done")

        try:
            for stage in ["intent", "uncertain", "done"]:
                run("unsaved-note-" + stage, before, stage=stage, intent_changes={"after_sha256": sha(before)})
            run("wrong-before-hash", planned, intent_changes={"before_sha256": "0" * 64}, no_reads=True)
            run("missing-before-hash", planned, intent_changes={"before_sha256": "__OMIT__"}, no_reads=True)
            run("malformed-native-title", planned, intent_changes={"before_native_title": None}, no_reads=True)
            run("changed-native-title", planned, intent_changes={"before_native_title": "different synthetic native title"})
            run("valid-alias", planned, should_pass=True)
            run("legacy-without-preimage", planned, legacy=True, preimage=False, no_reads=True)
            run("legacy-done-without-preimage", planned, stage="done", preimage=False, no_reads=True)
            run("partial-journal", planned, partial=True, no_reads=True)
            for field, value in (("password", "APW_SYNTHETIC_WRONG_PASSWORD"), ("sites", ["https://changed.example.invalid"]), ("otp", "present"), ("passkey", "present"), ("sharing", "unknown"), ("extra_fields", [{"identifier": "changed", "value": "wrong"}])):
                current = {**planned, field: value}
                run("rewritten-after-hash-" + field, current, intent_changes={"after_sha256": sha(current)}, no_reads=True)
            for mode in ("public", "symlink", "corrupted", "missing", "hardlink"):
                run("invalid-before-file-" + mode, planned, preimage_mode=mode, no_reads=True)
            run("changed-before-file", planned, preimage_value={**before, "password": "APW_SYNTHETIC_WRONG_PASSWORD"}, no_reads=True)
            run("unexpected-before-path", planned, intent_changes={"before_snapshot_path": "/private/tmp/unrelated-preimage.json"}, no_reads=True)
            fresh("new-done")
            fresh("new-uncertain", lost=True)
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"

    report = {
        "passed": error is None and all(check["passed"] for check in checks), "checks": checks, "error": error,
        "command": shlex.join(["python3", str(pathlib.Path(__file__).resolve()), "--bin", binary, "--report", str(report_path)]),
        "invocations": invocations, "boundary": "actual compiled CLI recovery + isolated synthetic readonly helper",
        "real_apple_verified": False, "real_customer_records_modified": 0,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "error": error,
        "failed_checks": [check["name"] for check in checks if not check["passed"]]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
