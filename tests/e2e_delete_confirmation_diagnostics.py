#!/usr/bin/env python3
"""Delete-kind failure diagnostics through real CLI, synthetic helper only."""
import argparse
import hashlib
import json
import os
import pathlib
import shlex
import subprocess
import tempfile

FAILURES = [
    "editor_address_unavailable", "owner_changed", "process_changed",
    "window_changed", "sheet_changed", "fields_ambiguous", "identity_changed",
    "credential_changed", "editor_address_changed", "ordinary_confirmation_unavailable",
    "none", "unclassified_system_events_error",
]
SAFE = {
    "confirmation_bridge_failure": "editor_address_changed",
    "confirmation_native_editor_role": "AXGroup",
    "confirmation_bridge_timed_out": False,
    "confirmation_account_list_enumerated": False,
    "confirmation_bridge_exit_code": 1,
    "confirmation_bridge_system_error_code": -1728,
    "confirmation_editor_path_depth": 4,
}
SECRET = "APW_SYNTHETIC_CONFIRMATION_SECRET"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    report_path = pathlib.Path(args.report).resolve()
    checks, invocations = [], []
    error = None

    def check(name, passed):
        checks.append({"name": name, "passed": bool(passed)})

    def sha(value):
        return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

    body = "APW_SYNTHETIC_CONFIRMATION_BODY\nsource-id-delete-diag-001"
    candidate = {"key": {"title": "synthetic confirmation candidate", "username": ""},
        "native_title": "synthetic confirmation candidate", "notes": body,
        "password": "", "sites": [], "sharing": "unshared", "otp": "absent",
        "passkey": "absent", "extra_fields": []}
    keeper = {**candidate, "key": {"title": "synthetic confirmation keeper", "username": ""},
        "native_title": "synthetic confirmation keeper", "notes": "keeper original\n" + body}
    with tempfile.TemporaryDirectory(prefix="apw-delete-diagnostics-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        helper, reply_path, calls_path = root / "synthetic-delete.py", root / "reply.json", root / "calls.jsonl"
        data_path, plan_path = root / "data.json", root / "plan.json"

        def write(path, value):
            path.write_text(json.dumps(value, ensure_ascii=False))
            path.chmod(0o600)

        write(data_path, [candidate, keeper])
        write(plan_path, {"format": "apw-maintenance-v1", "operations": [{
            "id": "delete-diag-001", "kind": "delete-redundant-note", "target": candidate["key"],
            "before_sha256": sha(candidate), "keeper": {"target": keeper["key"], "before_sha256": sha(keeper)},
            "preserve_text": body, "source_ids": ["source-id-delete-diag-001"],
        }]})
        helper.write_text('''#!/usr/bin/env python3
import json,os,sys
for line in sys.stdin:
 q=json.loads(line)
 with open(os.environ['APW_TEST_CALLS'],'a') as f: f.write(json.dumps({'op':q['op']})+'\\n')
 r={'id':q['id'],'app_activated':False,'backend':'synthetic'}
 if q['op']=='read':
  found=[x for x in json.load(open(os.environ['APW_TEST_DATA'])) if x['key']==q['key']]
  r.update(ok=True,state=found[0]) if len(found)==1 else r.update(ok=False,error='maintenance_item_not_found')
 elif q['op']=='delete-redundant-note':
  r.update(ok=False,error='maintenance_delete_outcome_requires_review',diagnostics=json.load(open(os.environ['APW_TEST_REPLY'])))
 else: r.update(ok=False,error='maintenance_operation_unsupported')
 print(json.dumps(r),flush=True)
''')
        helper.chmod(0o700)
        env = {**os.environ, "APW_DATA_DIR": str(root), "APW_MAINTENANCE_HELPER": str(helper),
            "APW_TEST_DATA": str(data_path), "APW_TEST_CALLS": str(calls_path), "APW_TEST_REPLY": str(reply_path)}

        def run(name, diagnostics, expected):
            write(reply_path, diagnostics)
            journal = root / (name + ".jsonl")
            command = [binary, "batch", "run", "--apply", "--plan", str(plan_path), "--journal", str(journal)]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr})
            check(name + ": delete failure remains a failure without success output", result.returncode != 0 and result.stdout == "")
            value = json.loads(result.stderr)
            check(name + ": exact machine failure retained", value.get("error") == "maintenance_delete_outcome_requires_review")
            check(name + ": exact safe confirmation diagnostics survive", value.get("diagnostics", {}) == expected)
            check(name + ": no secret or field values emitted", SECRET not in result.stdout + result.stderr and body not in result.stdout + result.stderr)
            check(name + ": original intent followed by uncertain, never done", [json.loads(line)["event"] for line in journal.read_text().splitlines()] == ["intent", "uncertain"])

        try:
            unsafe = {"title": SECRET, "username": SECRET, "notes": SECRET, "password": SECRET,
                "raw_script_error": SECRET, "confirmation_editor_address": SECRET, "unknown": {"value": SECRET}}
            run("all-safe-plus-secrets", {**SAFE, **unsafe}, SAFE)
            for failure in FAILURES:
                expected = {**SAFE, "confirmation_bridge_failure": failure}
                run("failure-" + failure.replace("_", "-"), expected, expected)
            for role in ["AXScrollArea", "AXSplitGroup"]:
                expected = {**SAFE, "confirmation_native_editor_role": role}
                run("role-" + role, expected, expected)
            malformed = {
                "confirmation_bridge_failure": SECRET, "confirmation_native_editor_role": "AXTextField:" + SECRET,
                "confirmation_bridge_timed_out": "false", "confirmation_account_list_enumerated": 1,
                "confirmation_bridge_exit_code": True, "confirmation_bridge_system_error_code": {"notes": SECRET},
                "confirmation_editor_path_depth": [4, SECRET], **unsafe,
            }
            run("wrong-types-and-free-text", malformed, {})
            run("out-of-range-scalars", {
                "confirmation_bridge_exit_code": -1, "confirmation_bridge_system_error_code": 100000001,
                "confirmation_editor_path_depth": 17,
            }, {})
            calls = [json.loads(line)["op"] for line in calls_path.read_text().splitlines()]
            # The existing collision preflight is readonly and precedes the one
            # mutation. Keep an exact sequence so extra reads/retries still fail.
            check("one delete dispatch per failing invocation, without retry", calls == ["read", "read", "deleted-location-read", "delete-redundant-note"] * len(invocations))
            check("synthetic backing records never changed", json.loads(data_path.read_text()) == [candidate, keeper])
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"
    report = {
        "passed": error is None and all(x["passed"] for x in checks), "checks": checks, "error": error,
        "command": shlex.join(["python3", str(pathlib.Path(__file__).resolve()), "--bin", binary, "--report", str(report_path)]),
        "invocations": invocations,
        "boundary": "real compiled CLI delete kind + isolated synthetic failing helper; no native Apple producer or UI acceptance",
        "real_apple_verified": False, "real_customer_records_modified": 0,
        "native_confirmation_producer_verified": False, "native_per_request_reset_verified": False,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks),
        "failed_checks": [x["name"] for x in checks if not x["passed"]], "error": error}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
