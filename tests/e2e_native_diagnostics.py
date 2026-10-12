#!/usr/bin/env python3
"""Real compiled CLI native-failure diagnostics, with an isolated synthetic helper.

Delete-dialog failure specification: six named observations accept strict bool
only; frames accepts only an integer 0..3000. True/False and frame boundaries
must survive, while strings, containers, null, integer-as-bool, bool-as-count,
fractional/out-of-range counts and arbitrary unknown secret data must be dropped.
The diagnostic cannot turn a refused native operation into successful readback.

Background-input proof diagnostics failure specification: the exact four keys
focus_verified, selection_verified, postimage_verified, owner_verified accept
both boolean values only. Strings, numbers, null and containers must be dropped;
their presence never converts a failing native read into a completed snapshot.

Owner-diagnostic failure specification: only the fourteen fixed owner failure
reasons below survive; copy/pid/role error codes are strict integers bounded by
100,000,000 in either direction, and the five owner comparisons are strict
booleans. Unknown/free-form reasons, strings, numeric booleans, fractional/
out-of-range codes and containers must be dropped without reporting success.
"""
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
    "notes_text_backing": {
        "number_code":0,"count_known":True,"count_matches":True,
        "string_code":0,"string_known":True,"string_matches":True,
        "focus_code":0,"focus_known":True,"focus_value":False,
        "focus_settable_code":0,"focus_settable":True,
        "shared_text_code":-25205,"shared_text_count":-1,
        "shared_focus_code":0,"shared_focus_count":0,
        "parameterized_code":0,"parameterized":["AXStringForRange","AXAttributedStringForRange"],
    },
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
    "search_model_frames": [
        {"phase":"empty_witness","complete":False,"query_matches":True,"category_matches":True,"owner_unchanged":True,
         "raw_count":2024,"published_count":2019,"cached_raw_count":-1,"native_errors":[{"code":-25202,"count":181}]},
        {"phase":"clear_model","complete":True,"query_matches":True,"category_matches":True,"owner_unchanged":True,
         "raw_count":2024,"published_count":2019,"cached_raw_count":2024,"native_errors":[]},
    ],
    "search_model_frame_counts": {"empty_witness":2,"target_model":0,"clear_model":2},
    "deleted_selected_exact": True,
    "deleted_title_matches": True,
    "deleted_note_matches": False,
    "deleted_recovery_unique": True,
    "deleted_frame_complete": True,
    "deleted_frames_observed": 2,
    "search_clear_method": "addressed_selected_text",
    "search_clear_failure": "clear_text_submission_failed",
    "delete_dialog_previous_incomplete": True,
    "delete_dialog_observation_complete": False,
    "delete_dialog_verified": True,
    "delete_dialog_fields_exact": False,
    "delete_dialog_recoverable": True,
    "delete_dialog_binding_verified": False,
    "delete_dialog_frames_observed": 2,
    "background_input_focus_verified": True,
    "background_input_selection_verified": False,
    "background_input_postimage_verified": True,
    "background_input_owner_verified": False,
    "background_input_post_gate": "initial",
    "background_input_permission_phase": "unicode",
    "background_input_post_access": True,
    "background_input_modifiers_clear": False,
    "background_input_permission_verified": False,
    "background_input_focus_scope_verified": True,
    "background_input_selected_text_attempted": True,
    "background_input_selected_text_settable": False,
    "background_input_selected_text_code": -25205,
    "background_input_modifier_flags": {"shift":False,"command":True,"unknown":False},
    "background_input_permission_scope": {"owner_exact":True,"selection_exact":False,"modifiers_clear":True},
    "background_input_owner_failure": "focused_element_changed",
    "background_input_owner_copy_code": 0,
    "background_input_owner_pid_code": -25204,
    "background_input_owner_role_code": 0,
    "background_input_owner_foreground_same": True,
    "background_input_owner_pid_same": False,
    "background_input_owner_role_same": True,
    "background_input_owner_element_same": False,
    "background_input_owner_frame_complete": True,
}
SECRET = "APW_SYNTHETIC_DIAGNOSTIC_SECRET_20261012"
OWNER_REASONS = ("none", "no_lease", "deadline", "foreground_unavailable",
    "passwords_foreground", "foreground_changed", "focused_copy_failed",
    "focused_type_invalid", "focused_pid_failed", "focused_pid_changed",
    "focused_role_failed", "focused_role_changed", "focused_element_changed",
    "observation_incomplete")


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
                "notes_text_backing": {**SAFE["notes_text_backing"],"text":SECRET},
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
                "search_model_frames": [{**SAFE["search_model_frames"][0],"notes":SECRET}],
                "search_model_frame_counts": {"empty_witness":2,"target_model":0,"clear_model":2,"notes":SECRET},
                "deleted_selected_exact": 1,
                "deleted_title_matches": SECRET,
                "deleted_note_matches": {"notes":SECRET},
                "deleted_recovery_unique": "true",
                "deleted_frame_complete": None,
                "deleted_frames_observed": 3001,
                "search_clear_method": SECRET,
                "search_clear_failure": SECRET,
                "delete_dialog_previous_incomplete": SECRET,
                "delete_dialog_observation_complete": 1,
                "delete_dialog_verified": {"notes": SECRET},
                "delete_dialog_fields_exact": "true",
                "delete_dialog_recoverable": None,
                "delete_dialog_binding_verified": [],
                "delete_dialog_frames_observed": 3001,
                "background_input_focus_verified": SECRET,
                "background_input_selection_verified": 1,
                "background_input_postimage_verified": {"notes": SECRET},
                "background_input_owner_verified": None,
                "background_input_owner_failure": SECRET,
                "background_input_owner_copy_code": True,
                "background_input_owner_pid_code": 100000001,
                "background_input_owner_role_code": {"notes": SECRET},
                "background_input_owner_foreground_same": "true",
                "background_input_owner_pid_same": 1,
                "background_input_owner_role_same": SECRET,
                "background_input_owner_element_same": [],
                "background_input_owner_frame_complete": None,
                "background_input_post_gate": SECRET,
                "background_input_permission_phase": SECRET,
                "background_input_post_access": 1,
                "background_input_modifiers_clear": "true",
                "background_input_permission_verified": None,
                "background_input_focus_scope_verified": [],
                "background_input_selected_text_attempted": 1,
                "background_input_selected_text_settable": "true",
                "background_input_selected_text_code": True,
                "background_input_modifier_flags": {"shift":False,"secret":SECRET},
                "background_input_permission_scope": {"owner_exact":True,"selection_exact":SECRET},
            }
            reply = run("malformed-allowed-keys", malformed)
            check("allowed diagnostic keys reject free text, containers and wrong scalar types", reply.get("diagnostics", {}) == {})
            reply = run("unavailable-status", {"status": "unavailable", "notes": SECRET})
            check("known unavailable context classification survives without free text", reply.get("diagnostics") == {"status": "unavailable"})

            backing=SAFE["notes_text_backing"]
            for index, patch in enumerate((
                {"count_known":1}, {"string_matches":"true"}, {"focus_value":None},
                {"number_code":True}, {"focus_code":100000001},
                {"shared_text_count":17}, {"shared_focus_count":-2},
                {"shared_text_count":False}, {"parameterized":[SECRET]},
                {"parameterized":["AXStringForRange"]*17},
            )):
                reply=run("text-backing-malformed-"+str(index),{"notes_text_backing":{**backing,**patch}})
                check("malformed backing observation is entirely dropped "+str(index),reply.get("diagnostics",{})=={})

            for index, value in enumerate((0, 3000)):
                reply = run("delete-dialog-count-boundary-" + str(index), {"delete_dialog_frames_observed": value, "unknown": SECRET})
                check("delete-dialog exact integer boundary " + str(index), reply.get("diagnostics") == {"delete_dialog_frames_observed": value})
            for index, value in enumerate((-1, 3001, True, False, 1.5, SECRET, {}, [], None)):
                reply = run("delete-dialog-count-malicious-" + str(index), {"delete_dialog_frames_observed": value})
                check("delete-dialog malformed count dropped " + str(index), reply.get("diagnostics", {}) == {})
            bool_keys = [key for key in SAFE if key.startswith("delete_dialog_") and key != "delete_dialog_frames_observed"]
            reply = run("delete-dialog-reversed-booleans", {key:not SAFE[key] for key in bool_keys})
            check("delete-dialog both exact bool values survive", reply.get("diagnostics") == {key:not SAFE[key] for key in bool_keys})

            background_keys = [key for key in SAFE if key.startswith("background_input_") and type(SAFE[key]) is bool]
            reply = run("background-input-reversed-booleans", {key:not SAFE[key] for key in background_keys})
            check("background-input all four exact bool values survive", reply.get("diagnostics") == {key:not SAFE[key] for key in background_keys})
            for index, bad_value in enumerate((SECRET, 1, "true", {}, [], None)):
                reply = run("background-input-malicious-" + str(index), {key:bad_value for key in background_keys})
                check("background-input all four reject malformed value " + str(index), reply.get("diagnostics", {}) == {})

            for value in ("present", "absent"):
                reply = run("owner-kind-" + value, {"background_input_owner_kind": value})
                check("owner kind " + value + " survives", reply.get("diagnostics") == {"background_input_owner_kind": value})
            for index, value in enumerate((SECRET, "unknown", 1, True, None, {}, [])):
                reply = run("owner-kind-bad-" + str(index), {"background_input_owner_kind": value})
                check("invalid owner kind dropped " + str(index), reply.get("diagnostics", {}) == {})

            # Capture failure enum must expose no app identities or arbitrary text.
            capture_reasons = ("none", "foreground_unavailable", "passwords_foreground", "foreground_changed", "wrong_phase", "lease_already_present", "input_already_attempted")
            for index, reason in enumerate(capture_reasons):
                reply = run("background-capture-reason-" + str(index), {"background_input_capture_failure": reason, "unknown": SECRET})
                check("background capture fixed reason survives " + str(index), reply.get("diagnostics") == {"background_input_capture_failure": reason})
            for index, bad_reason in enumerate((SECRET, "foreground_changed:" + SECRET, 1, {}, [], None)):
                reply = run("background-capture-reason-malicious-" + str(index), {"background_input_capture_failure": bad_reason})
                check("background capture unknown reason dropped " + str(index), reply.get("diagnostics", {}) == {})

            for index, reason in enumerate(OWNER_REASONS):
                reply = run("background-owner-reason-" + str(index), {"background_input_owner_failure": reason, "unknown": SECRET})
                check("background owner fixed reason survives " + str(index), reply.get("diagnostics") == {"background_input_owner_failure": reason})
            for index, bad_reason in enumerate((SECRET, "focused_role_failed:" + SECRET, 1, {}, [], None)):
                reply = run("background-owner-reason-malicious-" + str(index), {"background_input_owner_failure": bad_reason})
                check("background owner unknown reason dropped " + str(index), reply.get("diagnostics", {}) == {})
            owner_codes = ("background_input_owner_copy_code", "background_input_owner_pid_code", "background_input_owner_role_code")
            for index, code in enumerate((-100000000, 0, 100000000)):
                reply = run("background-owner-code-boundary-" + str(index), {key:code for key in owner_codes})
                check("background owner three exact code bounds survive " + str(index), reply.get("diagnostics") == {key:code for key in owner_codes})
            for index, bad_code in enumerate((-100000001, 100000001, True, False, 0.5, SECRET, {}, [], None)):
                reply = run("background-owner-code-malicious-" + str(index), {key:bad_code for key in owner_codes})
                check("background owner three malformed codes dropped " + str(index), reply.get("diagnostics", {}) == {})

            recovery_variants = [("search_clear_method", value) for value in ["addressed_semantic_clear", "addressed_value_then_semantic_clear", "addressed_value_cycle"]] + [("search_clear_failure", value) for value in ["clear_binding_unverified", "clear_value_submission_failed"]]
            for field, value in recovery_variants:
                reply = run("bounded-clear-recovery-" + value, {field:value})
                check("known bounded recovery diagnostic " + value + " survives", reply.get("diagnostics") == {field:value})

            valid_frame = SAFE["search_model_frames"][0]
            invalid_frames = [
                SECRET, {"notes":SECRET}, [valid_frame]*17,
                [{**valid_frame,"phase":SECRET}],
                [{**valid_frame,"complete":1}],
                [{**valid_frame,"raw_count":True}],
                [{**valid_frame,"raw_count":3001}],
                [{**valid_frame,"published_count":-2}],
                [{**valid_frame,"cached_raw_count":0.5}],
                [{**valid_frame,"native_errors":[{"code":-25202,"count":True}]}],
                [{**valid_frame,"native_errors":[{"code":-25202,"count":6001}]}],
                [{**valid_frame,"native_errors":[{"code":-25202,"count":1,"attribute":SECRET}]}],
                [{**valid_frame,"native_errors":[{"code":SECRET,"count":1}]}],
                [{**valid_frame,"native_errors":[{"code":-25202,"count":1}]*9}],
            ]
            for index, bad_frames in enumerate(invalid_frames):
                reply=run("malformed-search-frames-"+str(index),{"search_model_frames":bad_frames})
                check("malformed structural search frame "+str(index)+" is fully refused",reply.get("diagnostics",{})=={})
            invalid_counts = [
                {"empty_witness":True,"target_model":0,"clear_model":2},
                {"empty_witness":1025,"target_model":0,"clear_model":2},
                {"empty_witness":2,"target_model":-1,"clear_model":2},
                {"empty_witness":2,"clear_model":2},
                {"empty_witness":2,"target_model":0,"clear_model":SECRET},
            ]
            for index,bad_counts in enumerate(invalid_counts):
                reply=run("malformed-search-frame-counts-"+str(index),{"search_model_frame_counts":bad_counts})
                check("malformed search frame counts "+str(index)+" are refused",reply.get("diagnostics",{})=={})
            records = [json.loads(line) for line in calls.read_text().splitlines()]
            check("one failing native read per invocation, without retry", records == [{"op":"read"}]*len(invocations))
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
