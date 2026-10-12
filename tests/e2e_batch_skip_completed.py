#!/usr/bin/env python3
"""Failure specification, written before the skip-completed implementation.

An explicit skip must not: reread a qualified done; replay any intent/uncertain;
skip a new op or explicit reviewed-no-change; turn legacy/malformed done evidence
into authority; bypass plan/id/private-journal/preimage checks; count historical
skips as current verified work; leak state. Default behavior must still audit.
The actual compiled CLI is used with an isolated synthetic native process only.
"""
import argparse, copy, hashlib, json, os, pathlib, shlex, subprocess, tempfile


def sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--bin", required=True); p.add_argument("--report", required=True)
    a = p.parse_args(); checks, commands = [], []
    before = {"key": {"title": "synthetic completed note", "username": ""}, "native_title": "synthetic completed note",
              "notes": "APW_SYNTHETIC_SKIP_ORIGINAL source-id-skip", "password": "", "sites": [], "sharing": "unshared",
              "otp": "absent", "passkey": "absent", "extra_fields": []}
    keeper = {**before, "key": {"title": "synthetic keeper", "username": "synthetic@example.invalid"},
              "native_title": "synthetic keeper", "sites": ["https://skip.invalid"], "password": "SYNTHETIC_SKIP_PASSWORD"}
    after = {**before, "notes": before["notes"] + "\nAPW_SYNTHETIC_SKIP_APPEND"}
    note = {"id": "skip-note-001", "kind": "notes-set", "target": before["key"], "before_sha256": sha(before), "notes": after["notes"]}
    deletion = {"id": "skip-delete-001", "kind": "delete-redundant-note", "target": before["key"], "before_sha256": sha(before),
                "keeper": {"target": keeper["key"], "before_sha256": sha(keeper)}, "preserve_text": before["notes"], "source_ids": ["source-id-skip"]}
    with tempfile.TemporaryDirectory(prefix="apw-skip-completed-e2e-") as tmp:
        root = pathlib.Path(tmp); root.chmod(0o700)
        helper = root / "helper.py"
        helper.write_text('''#!/usr/bin/env python3
import json, os, sys
for line in sys.stdin:
 q=json.loads(line); p=os.environ['APW_TEST_STATE']; s=json.load(open(p))
 with open(os.environ['APW_TEST_CALLS'],'a') as f: f.write(json.dumps({'op':q['op'],'key':q.get('key')})+'\\n')
 records=s['deleted'] if q['op']=='deleted-read' else s['active']
 found=[x for x in records if x['key']==q.get('key')]
 r={'id':q['id'],'app_activated':False,'backend':'synthetic'}
 if q['op']=='deleted-location-read': r.update(ok=False,error='maintenance_operation_unsupported')
 elif len(found)!=1: r.update(ok=False,error='maintenance_item_not_found' if not found else 'maintenance_item_ambiguous')
 elif q['op'] in ('read','deleted-read'): r.update(ok=True,state=found[0])
 elif q['op']=='notes-set': found[0]['notes']=q['notes']; s['writes']+=1; r.update(ok=True)
 elif q['op']=='delete-redundant-note': s['active'].remove(found[0]); s['deleted'].append(found[0]); s['writes']+=1; r.update(ok=True,recoverable=True)
 else: r.update(ok=False,error='maintenance_operation_unsupported')
 with open(p,'w') as f: json.dump(s,f)
 print(json.dumps(r),flush=True)
'''); helper.chmod(0o700)
        def write(path, v):
            path.write_text(json.dumps(v, ensure_ascii=False) + "\n"); path.chmod(0o600)
        def check(name, ok): checks.append({"name": name, "passed": bool(ok)})
        def run(name, *, kind="notes", event="done", skip=True, tamper=None, legacy=False, unsafe=None, new=False, reviewed=False):
            d = root / name; d.mkdir(mode=0o700)
            operation = copy.deepcopy(note if kind == "notes" else deletion)
            plan = {"format": "apw-maintenance-v1", "operations": [operation]}
            if new:
                fresh = {**before, "key": {"title": "synthetic new note", "username": ""}, "native_title": "synthetic new note"}
                fresh_op = {**note, "id": "skip-new-002", "target": fresh["key"], "before_sha256": sha(fresh), "notes": fresh["notes"] + "\nNEW_SYNTHETIC_APPEND"}
                plan["operations"].append(fresh_op)
            planpath, journal, statepath, callpath = d / "plan.json", d / "journal.jsonl", d / "state.json", d / "calls.jsonl"
            preimage = pathlib.Path(str(journal) + "." + operation["id"] + ".before.json")
            write(planpath, plan); write(preimage, {"format": "apw-item-snapshot-v1", "state": before, "sha256": sha(before)})
            intent = {"plan": sha(plan), "id": operation["id"], "event": "intent", "before_sha256": sha(before),
                      "before_native_title": before["native_title"], "before_snapshot_path": str(preimage), "at": "2026-10-12T00:00:00.000Z"}
            last = {"plan": sha(plan), "id": operation["id"], "event": event, "before_sha256": sha(before), "at": "2026-10-12T00:00:01.000Z"}
            if kind == "notes": intent["after_sha256"] = sha(after); last["after_sha256"] = sha(after)
            else:
                intent["deleted_preflight_absent"] = True
                if event == "done": last.update(deletion_verification="full_deleted_body", content_preservation_verified=True, deleted_body_verified=True)
            if legacy:
                last.pop("before_sha256", None)
                if kind == "delete": last.pop("content_preservation_verified", None)
            if tamper == "done-hash": last["after_sha256"] = "0" * 64
            if tamper == "before-hash": last["before_sha256"] = "0" * 64
            if tamper == "plan": last["plan"] = "0" * 64
            if tamper == "id": last["id"] = "not-in-this-plan"
            if tamper == "proof": last["deleted_body_verified"] = False
            if tamper == "preimage": write(preimage, {"format": "apw-item-snapshot-v1", "state": {**before, "password": "TAMPERED_SYNTHETIC"}, "sha256": sha(before)})
            if tamper == "order": last["at"] = "2026-10-11T00:00:00.000Z"
            rows = [intent] if event == "intent" else [intent, last]
            if reviewed:
                rows.append({"plan": sha(plan), "id": operation["id"], "event": "reviewed-no-change", "before_sha256": sha(before), "at": "2026-10-12T00:00:02.000Z"})
            journal.write_text("".join(json.dumps(x) + "\n" for x in rows)); journal.chmod(0o600)
            if unsafe == "public": journal.chmod(0o644)
            if unsafe == "symlink": journal.rename(d / "journal-target.jsonl"); journal.symlink_to("journal-target.jsonl")
            if unsafe == "hardlink": os.link(journal, d / "journal-alias.jsonl")
            active = [keeper] + ([copy.deepcopy(before if reviewed else after)] if kind == "notes" else [])
            if new: active.append(fresh)
            write(statepath, {"active": active, "deleted": [before] if kind == "delete" else [], "writes": 0})
            env = {**os.environ, "APW_MAINTENANCE_HELPER": str(helper), "APW_TEST_STATE": str(statepath), "APW_TEST_CALLS": str(callpath), "APW_DATA_DIR": str(d)}
            cmd = [a.bin, "batch", "run", "--apply", "--plan", str(planpath), "--journal", str(journal)] + (["--skip-completed"] if skip else [])
            commands.append(shlex.join(cmd)); r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=25)
            calls = [json.loads(x) for x in callpath.read_text().splitlines()] if callpath.exists() else []
            try: result = json.loads(r.stdout)
            except Exception: result = {}
            rejected = tamper in ("plan", "id", "preimage") or unsafe is not None
            eligible = event == "done" and not reviewed and not legacy and not tamper and not unsafe
            expected_skips = 1 if eligible and skip else 0
            check(name + ": exit matches contract", (r.returncode == 0) == (not rejected))
            check(name + ": historical skip distinct", rejected or ((result.get("skipped_completed") == expected_skips) if skip else ("skipped_completed" not in result)))
            expected_verified = (0 if expected_skips else 1) + (1 if new else 0)
            check(name + ": verified count excludes skip", rejected or result.get("completed") == expected_verified)
            check(name + ": qualified skip has no calls for old identity", not expected_skips or all(x.get("key") != operation["target"] for x in calls))
            check(name + ": only explicitly new/reviewed mutations", json.loads(statepath.read_text())["writes"] == (1 if not rejected and (new or reviewed) else 0))
            if not rejected and not expected_skips:
                check(name + ": otherwise uses readonly audit/current path", any(x["op"] in ("read", "deleted-read") for x in calls))
            check(name + ": secret-safe public result", before["notes"] not in r.stdout + r.stderr and "SYNTHETIC_SKIP_PASSWORD" not in r.stdout + r.stderr)
        run("notes-done")
        run("delete-done", kind="delete")
        run("default-notes", skip=False)
        run("default-delete", kind="delete", skip=False)
        run("uncertain", event="uncertain")
        run("intent", event="intent")
        run("done-and-new", new=True)
        run("explicit-reviewed", event="uncertain", reviewed=True)
        run("legacy-done", legacy=True)
        run("legacy-delete", kind="delete", legacy=True)
        run("changed-done-hash", tamper="done-hash")
        run("changed-before-hash", tamper="before-hash")
        run("changed-order", tamper="order")
        run("changed-proof", kind="delete", tamper="proof")
        run("changed-plan", tamper="plan")
        run("changed-id", tamper="id")
        run("changed-preimage", tamper="preimage")
        run("public-journal", unsafe="public")
        run("symlink-journal", unsafe="symlink")
        run("hardlink-journal", unsafe="hardlink")
    report = {"passed": all(x["passed"] for x in checks), "checks": checks, "invocations": commands,
              "command": shlex.join(["python3", __file__, "--bin", a.bin, "--report", a.report]),
              "real_apple_verified": False, "real_customer_records_modified": 0}
    pathlib.Path(a.report).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "failed": sum(not x["passed"] for x in checks), "report": a.report}))
    return 0 if report["passed"] else 1


if __name__ == "__main__": raise SystemExit(main())
