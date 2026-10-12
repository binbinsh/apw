#!/usr/bin/env python3
"""Real compiled CLI native-failure diagnostics, with an isolated synthetic helper."""
import argparse
import json
import os
import pathlib
import shlex
import subprocess
import tempfile


SAFE = {
    "failure_stage": "initial_list_preparation",
    "status": "incomplete_window_observation",
    "ui_set_attribute": "AXSelected",
    "ui_set_error_code": -25205,
    "ui_press_error_code": -25205,
    "all_list_bridge_failure": "category_changed",
    "all_list_bridge_stage": 3,
    "all_list_bridge_error_code": -1728,
    "all_list_bridge_exit_code": 1,
    "all_list_bridge_timed_out": False,
    "notes_role": "AXTextField",
    "notes_range_code": 0,
    "notes_text_code": -25205,
    "notes_value_code": 0,
    "notes_range_settable": True,
    "notes_text_settable": False,
    "notes_value_settable": True,
    "notes_actions_code": 0,
    "notes_action_names": ["AXConfirm", "AXShowMenu", "AXScrollToVisible"],
    "notes_observation_frames": 2,
    "notes_observation_end": "stable_unsupported",
    "notes_probe_stage": "notes_structure",
    "notes_probe_row_count": 1,
    "notes_children": {"count":1,"complete":True,"nodes":[{"role":"AXTextField","depth":1,"identifier_present":False,"same_pid":True,"parent_bound":True,"editable_role":True}]},
    "notes_internal_focus": {"code":0,"same_pid":True,"matches_notes":False,"known_role":"AXTextField"},
    "notes_probe_read_opened": True,
    "notes_probe_recovery_attempted": False,
    "notes_probe_editor_recovered": False,
    "notes_probe_editor_requires_review": False,
    "focus_requested": True,
    "focus_settable": True,
    "focus_set_code": 0,
    "focus_verified": True,
    "confirmation_bridge_failure": "editor_address_changed",
    "confirmation_bridge_exit_code": 1,
    "confirmation_bridge_system_error_code": -1728,
    "confirmation_bridge_timed_out": False,
    "confirmation_native_editor_role": "AXGroup",
    "confirmation_account_list_enumerated": False,
    "confirmation_editor_path_depth": 3,
}
SECRET = "APW_SYNTHETIC_DIAGNOSTIC_SECRET_20261012"


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

    with tempfile.TemporaryDirectory(prefix="apw-native-diagnostics-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)

        def write(path, value):
            path.write_text(json.dumps(value, ensure_ascii=False))
            path.chmod(0o600)

        fixture = root / "reply.json"
        calls = root / "calls.jsonl"
        helper = root / "native-synthetic.py"
        helper.write_text(
            "#!/usr/bin/env python3\n"
            "import json,os,sys\n"
            "for line in sys.stdin:\n"
            " q=json.loads(line)\n"
            " with open(os.environ['APW_TEST_CALLS'],'a') as f: f.write(json.dumps({'op':q['op']})+'\\n')\n"
            " r=json.load(open(os.environ['APW_TEST_REPLY']))\n"
            " r['id']=q['id']\n"
            " print(json.dumps(r),flush=True)\n"
        )
        helper.chmod(0o700)
        env = {
            **os.environ,
            "APW_DATA_DIR": str(root),
            "APW_MAINTENANCE_HELPER": str(helper),
            "APW_TEST_REPLY": str(fixture),
            "APW_TEST_CALLS": str(calls),
        }

        def run(name, diagnostics):
            output = root / (name + "-snapshot.json")
            write(fixture, {
                "ok": False, "backend": "synthetic", "app_activated": False,
                "error": "maintenance_initial_list_preparation_failed",
                "diagnostics": diagnostics,
            })
            command = [
                binary, "item", "read", "--title", "synthetic diagnostics fixture",
                "--username", "", "--output", str(output),
            ]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=8)
            invocations.append({
                "argv": command, "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr,
            })
            check(name + ": CLI fails without pretending a snapshot succeeded", result.returncode != 0 and result.stdout == "")
            try:
                value = json.loads(result.stderr)
            except json.JSONDecodeError:
                value = {}
            check(name + ": machine failure preserved", value.get("error") == "maintenance_initial_list_preparation_failed")
            check(name + ": no secret-bearing diagnostic emitted", SECRET not in result.stdout + result.stderr)
            check(name + ": reserved snapshot contains no secret data", output.exists() and output.stat().st_size == 0)
            return value

        try:
            diagnostics = {
                **SAFE,
                "notes": SECRET,
                "password": SECRET,
                "key": {"title": SECRET, "username": SECRET},
                "search_query": SECRET,
                "unknown_field": {"notes": SECRET},
                "unexpected_count": 100,
            }
            reply = run("safe-structural-plus-secret", diagnostics)
            check("all safe native structural diagnostics survive CLI boundary", reply.get("diagnostics") == SAFE)
            check("unknown diagnostic keys are dropped", isinstance(reply.get("diagnostics"), dict) and set(reply["diagnostics"]) <= set(SAFE))

            malformed = {
                "failure_stage": SECRET + " leaked notes",
                "status": {"notes": SECRET},
                "ui_set_attribute": "AXValue:" + SECRET,
                "ui_set_error_code": SECRET,
                "ui_press_error_code": True,
                "all_list_bridge_failure": SECRET + " leaked notes",
                "all_list_bridge_stage": [1, SECRET],
                "all_list_bridge_error_code": {"password": SECRET},
                "all_list_bridge_exit_code": SECRET,
                "all_list_bridge_timed_out": "false " + SECRET,
                "search_query": SECRET,
                "notes_role": SECRET,
                "notes_range_code": True,
                "notes_text_code": [SECRET],
                "notes_value_code": 100000001,
                "notes_range_settable": "true " + SECRET,
                "notes_text_settable": {"password": SECRET},
                "notes_value_settable": 1,
                "notes_actions_code": SECRET,
                "notes_action_names": ["AXConfirm", SECRET],
                "notes_observation_frames": -1,
                "notes_observation_end": SECRET,
                "notes_probe_stage": SECRET,
                "notes_probe_row_count": 101,
                "notes_children": {"count":1,"complete":True,"nodes":[{"role":SECRET,"depth":1,"identifier_present":True,"same_pid":True,"parent_bound":True,"editable_role":True}]},
                "notes_internal_focus": {"code":0,"same_pid":True,"matches_notes":True,"known_role":SECRET},
                "notes_probe_read_opened": SECRET,
                "notes_probe_recovery_attempted": 1,
                "notes_probe_editor_recovered": {"notes":SECRET},
                "notes_probe_editor_requires_review": "false",
                "focus_requested": SECRET,
                "focus_settable": 1,
                "focus_set_code": True,
                "focus_verified": "true",
                "confirmation_bridge_failure": SECRET,
                "confirmation_bridge_exit_code": True,
                "confirmation_bridge_system_error_code": {"notes": SECRET},
                "confirmation_bridge_timed_out": "true",
                "confirmation_native_editor_role": SECRET,
                "confirmation_account_list_enumerated": 0,
                "confirmation_editor_path_depth": 17,
            }
            reply = run("malformed-allowed-keys", malformed)
            check("allowed diagnostic keys reject free text, containers and wrong scalar types", reply.get("diagnostics", {}) == {})
            records = [json.loads(line) for line in calls.read_text().splitlines()]
            check("one failing native read per invocation, without retry", records == [{"op": "read"}, {"op": "read"}])
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"

    passed = error is None and all(x["passed"] for x in checks)
    report = {
        "passed": passed, "checks": checks, "error": error,
        "command": shlex.join([
            "python3", str(pathlib.Path(__file__).resolve()), "--bin", binary,
            "--report", str(report_path),
        ]),
        "invocations": invocations,
        "boundary": "actual compiled CLI + isolated synthetic failing native helper; no Apple Passwords access",
        "real_apple_verified": False, "real_customer_records_modified": 0,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": passed, "checks": len(checks), "failed_checks": [x["name"] for x in checks if not x["passed"]], "error": error}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
