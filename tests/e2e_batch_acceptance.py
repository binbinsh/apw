#!/usr/bin/env python3
"""Composed merge/delete and recovery through compiled CLI plus synthetic helper."""
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
    checks, commands = [], []
    error = None

    def sha(value):
        return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

    def check(name, passed):
        checks.append({"name": name, "passed": bool(passed)})
        assert passed, name

    source = "APW_COMPOSED_SYNTHETIC_SOURCE\nsource-id-composed-001\n保留空白  "
    keeper = {
        "key": {"title": "synthetic composed keeper", "username": "alice@example.invalid"},
        "native_title": "synthetic composed keeper", "notes": "original keeper body",
        "password": "SYNTHETIC_KEEPER_PASSWORD",
        "sites": ["one.example.invalid", "two.example.invalid"],
        "sharing": "unshared", "otp": "present", "passkey": "present",
        "extra_fields": [{"identifier": "synthetic-extra", "value": "retained synthetic value"}],
    }
    candidate = {
        "key": {"title": "synthetic composed candidate", "username": ""},
        "native_title": "synthetic composed candidate", "notes": source,
        "password": "", "sites": [], "sharing": "unshared", "otp": "absent",
        "passkey": "absent", "extra_fields": [],
    }

    with tempfile.TemporaryDirectory(prefix="apw-batch-acceptance-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        storefile = root / "store.json"
        helper = root / "synthetic-native.py"
        helper.write_text('''#!/usr/bin/env python3
import json,os,sys
p=os.environ['APW_TEST_STORE']
for line in sys.stdin:
 q=json.loads(line);s=json.load(open(p));op=q['op']
 rows=s['deleted'] if op=='deleted-read' else s['active']
 found=[x for x in rows if x['key']==q.get('key')]
 r={'id':q['id'],'app_activated':False,'backend':'synthetic'}
 if len(found)!=1: r.update(ok=False,error='maintenance_item_not_found' if not found else 'maintenance_item_ambiguous')
 elif op in ['read','deleted-read']: r.update(ok=True,state=found[0])
 elif op=='notes-set':
  s['writes'].append(op);found[0]['notes']=q['notes'];r.update(ok=True,persisted=True,background_only=True,original_foreground_preserved=True,input_keyboard_focus_preserved=True,input_focus_owner_kind='present',keyboard_focus_scope='focus_setter_through_save',credentials_changed=1,exports=0,imports=0,state=found[0])
 elif op=='delete-redundant-note':
  s['writes'].append(op);s['active'].remove(found[0]);s['deleted'].append(found[0]);r.update(ok=True,recoverable=True)
  if s['mode']=='keeper-drift': s['active'][0]['notes']+=' unexpected keeper drift'
 else: r.update(ok=False,error='maintenance_operation_unsupported')
 with open(p,'w') as f: json.dump(s,f,ensure_ascii=False)
 if op=='delete-redundant-note' and s['mode']=='lost-delete': sys.exit(0)
 print(json.dumps(r,ensure_ascii=False),flush=True)
''')
        helper.chmod(0o700)
        env = {**os.environ, "APW_DATA_DIR": str(root), "APW_MAINTENANCE_HELPER": str(helper), "APW_TEST_STORE": str(storefile)}

        def write(path, value):
            path.write_text(json.dumps(value, ensure_ascii=False))
            path.chmod(0o600)

        def prepare(name, mode="normal", alias=False):
            note = copy.deepcopy(candidate)
            if alias:
                note["native_title"] = "synthetic native title alias"
            after = {**keeper, "notes": keeper["notes"] + "\n\n" + source}
            operations = [
                {"id": "merge", "kind": "notes-set", "target": keeper["key"], "before_sha256": sha(keeper), "notes": after["notes"]},
                {"id": "delete", "kind": "delete-redundant-note", "target": note["key"], "before_sha256": sha(note), "keeper": {"target": keeper["key"], "before_sha256": sha(after)}, "preserve_text": source, "source_ids": ["source-id-composed-001"]},
            ]
            plan, journal = root / (name + "-plan.json"), root / (name + "-journal.jsonl")
            write(plan, {"format": "apw-maintenance-v1", "operations": operations})
            write(storefile, {"active": [copy.deepcopy(keeper), note], "deleted": [], "writes": [], "mode": mode})
            return plan, journal, after, note

        def run(plan, journal):
            command = [binary, "batch", "run", "--apply", "--plan", str(plan), "--journal", str(journal)]
            commands.append(shlex.join(command))
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=10)
            assert source not in result.stdout + result.stderr and keeper["password"] not in result.stdout + result.stderr, "secret printed"
            return result

        def current():
            return json.loads(storefile.read_text())

        def normal_mode():
            value = current()
            value["mode"] = "normal"
            write(storefile, value)

        def edit_delete_intent(journal, change):
            entries = [json.loads(line) for line in journal.read_text().splitlines()]
            for entry in entries:
                if entry["id"] == "delete" and entry["event"] == "intent":
                    change(entry)
            journal.write_text("".join(json.dumps(entry) + "\n" for entry in entries))
            journal.chmod(0o600)

        try:
            plan, journal, after, note = prepare("composed-success")
            result = run(plan, journal)
            check("append then delete completes using post-merge keeper hash", result.returncode == 0 and json.loads(result.stdout)["completed"] == 2)
            intent=json.loads(journal.read_text().splitlines()[0]); preimage=pathlib.Path(intent.get("before_snapshot_path","/nonexistent-synthetic-preimage"))
            check("composed notes intent retains complete private original keeper proof", preimage.exists() and preimage.stat().st_mode & 0o077 == 0 and json.loads(preimage.read_text()) == {"format":"apw-item-snapshot-v1","sha256":sha(keeper),"state":keeper})
            value = current()
            check("keeper complete state preserved and candidate recoverably deleted", value["active"] == [after] and value["deleted"] == [note] and value["writes"] == ["notes-set", "delete-redundant-note"])
            result = run(plan, journal)
            check("composed completed resume never repeats either mutation", result.returncode == 0 and json.loads(result.stdout)["mutations"] == 0 and current()["writes"] == value["writes"])

            plan, journal, after, note = prepare("lost-delete", "lost-delete")
            result = run(plan, journal)
            check("lost delete reply is recorded uncertain after completed merge", result.returncode != 0 and [json.loads(x)["event"] for x in journal.read_text().splitlines()] == ["intent", "done", "intent", "uncertain"])
            normal_mode()
            result = run(plan, journal)
            value = current()
            check("delete uncertainty resolves by placement/body and keeper readback", result.returncode == 0 and json.loads(result.stdout)["completed"] == 2 and json.loads(result.stdout)["mutations"] == 0 and value["active"] == [after] and value["deleted"] == [note])
            check("uncertain delete recovery never dispatches a second delete", value["writes"] == ["notes-set", "delete-redundant-note"])

            plan, journal, after, note = prepare("keeper-drift", "keeper-drift")
            result = run(plan, journal)
            check("keeper drift during delete blocks done and holds uncertain", result.returncode != 0 and json.loads(journal.read_text().splitlines()[-1])["event"] == "uncertain")
            before_writes = current()["writes"]
            result = run(plan, journal)
            check("keeper drift stops before uncertain delete can replay", result.returncode != 0 and current()["writes"] == before_writes and current()["deleted"] == [note])

            plan, journal, after, note = prepare("native-title-alias", "lost-delete", alias=True)
            result = run(plan, journal)
            check("native title alias deletion captures original state and uncertainty", result.returncode != 0 and current()["deleted"] == [note])
            normal_mode()
            result = run(plan, journal)
            check("native title alias resolves through captured preimage without a second write", result.returncode == 0 and json.loads(result.stdout)["completed"] == 2 and json.loads(result.stdout)["mutations"] == 0 and current()["active"] == [after] and current()["deleted"] == [note] and current()["writes"] == ["notes-set", "delete-redundant-note"])

            plan, journal, after, note = prepare("legacy-matching-title", "lost-delete")
            result = run(plan, journal)
            check("legacy matching-title fixture reaches uncertain delete", result.returncode != 0 and current()["deleted"] == [note])
            edit_delete_intent(journal, lambda entry: entry.pop("before_native_title", None))
            normal_mode()
            result = run(plan, journal)
            check("legacy journal falls back only to a hash-matching target title", result.returncode == 0 and json.loads(result.stdout)["mutations"] == 0 and current()["writes"] == ["notes-set", "delete-redundant-note"])

            plan, journal, after, note = prepare("legacy-missing-alias", "lost-delete", alias=True)
            result = run(plan, journal)
            check("legacy missing-alias fixture reaches uncertain delete", result.returncode != 0 and current()["deleted"] == [note])
            edit_delete_intent(journal, lambda entry: entry.pop("before_native_title", None))
            normal_mode()
            result = run(plan, journal)
            check("legacy missing alias remains held by the original hash", result.returncode != 0 and "maintenance_outcome_requires_review" in result.stderr and current()["writes"] == ["notes-set", "delete-redundant-note"])

            for name, invalid_title in [
                ("wrong-title", "synthetic forged different native title"),
                ("null-title", None),
                ("object-title", {"notes": "synthetic unknown content"}),
                ("nul-title", "synthetic\0native title"),
            ]:
                plan, journal, after, note = prepare(name, "lost-delete", alias=True)
                result = run(plan, journal)
                check(name + ": fixture reaches uncertain delete", result.returncode != 0 and current()["deleted"] == [note])
                edit_delete_intent(journal, lambda entry: entry.update(before_native_title=invalid_title))
                normal_mode()
                result = run(plan, journal)
                check(name + ": invalid metadata cannot weaken the preimage or replay delete", result.returncode != 0 and "maintenance_outcome_requires_review" in result.stderr and current()["writes"] == ["notes-set", "delete-redundant-note"])
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"

    passed = error is None and all(x["passed"] for x in checks)
    report = {
        "passed": passed, "checks": checks, "error": error,
        "command": shlex.join(["python3", str(pathlib.Path(__file__).resolve()), "--bin", binary, "--report", str(report_path)]),
        "entry_point_commands": commands,
        "boundary": "actual compiled CLI + isolated synthetic stateful helper; composed batch/recovery only",
        "real_apple_verified": False, "real_customer_records_modified": 0,
        "recovery_contract": "Captured native title is hash-bound; legacy missing or malformed alias never relaxes exact preimage verification.",
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": passed, "checks": len(checks), "error": error}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
