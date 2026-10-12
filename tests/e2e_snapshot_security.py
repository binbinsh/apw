#!/usr/bin/env python3
"""Output-reservation privacy through actual CLI and a synthetic state helper."""
import argparse
import json
import os
import pathlib
import shlex
import subprocess
import tempfile

SECRET = "APW_SYNTHETIC_SNAPSHOT_PASSWORD"
SENTINEL = "APW_SYNTHETIC_UNRELATED_FILE"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    report_path = pathlib.Path(args.report).resolve()
    checks, invocations = [], []
    error = None
    value = {"key": {"title": "synthetic snapshot guard", "username": ""},
        "native_title": "synthetic snapshot guard", "notes": "APW_SYNTHETIC_SNAPSHOT_NOTE",
        "password": SECRET, "sites": ["https://snapshot.example.invalid"],
        "sharing": "unshared", "otp": "unknown", "passkey": "unknown", "extra_fields": []}

    def check(name, condition):
        checks.append({"name": name, "passed": bool(condition)})

    with tempfile.TemporaryDirectory(prefix="apw-snapshot-security-e2e-") as tmp:
        outer = pathlib.Path(tmp)
        outer.chmod(0o700)
        helper = outer / "synthetic-output-drift.py"
        data = outer / "data.json"
        data.write_text(json.dumps(value))
        data.chmod(0o600)
        helper.write_text('''#!/usr/bin/env python3
import json,os,sys
for line in sys.stdin:
 q=json.loads(line)
 with open(os.environ['APW_TEST_CALLS'],'a') as f: f.write(json.dumps({'op':q['op']})+'\\n')
 p=os.environ['APW_TEST_OUTPUT'];mode=os.environ['APW_TEST_MODE']
 if mode=='public-mode': os.chmod(p,0o644)
 elif mode=='replacement':
  os.unlink(p)
  with open(p,'w') as f: f.write('APW_SYNTHETIC_UNRELATED_FILE')
  os.chmod(p,0o600)
 elif mode=='symlink':
  os.unlink(p);os.symlink(os.environ['APW_TEST_TARGET'],p)
 elif mode=='hardlink': os.link(p,os.environ['APW_TEST_ALIAS'])
 elif mode=='public-parent': os.chmod(os.path.dirname(p),0o755)
 r={'id':q['id'],'app_activated':False,'backend':'synthetic','ok':True,'state':json.load(open(os.environ['APW_TEST_DATA']))}
 print(json.dumps(r),flush=True)
''')
        helper.chmod(0o700)

        def run(name, mode, batch=False):
            root = outer / name
            root.mkdir(mode=0o700)
            output, target, alias, calls = root / "snapshot.json", root / "unrelated.json", root / "alias.json", root / "calls.jsonl"
            target.write_text(SENTINEL)
            target.chmod(0o600)
            env = {**os.environ, "APW_DATA_DIR": str(outer), "APW_MAINTENANCE_HELPER": str(helper),
                "APW_TEST_DATA": str(data), "APW_TEST_OUTPUT": str(output), "APW_TEST_MODE": mode,
                "APW_TEST_TARGET": str(target), "APW_TEST_ALIAS": str(alias), "APW_TEST_CALLS": str(calls)}
            if batch:
                targets = root / "targets.json"
                targets.write_text(json.dumps({"format": "apw-maintenance-targets-v1", "targets": [value["key"]]}))
                targets.chmod(0o600)
                command = [binary, "batch", "inspect", "--targets", str(targets), "--output", str(output)]
            else:
                command = [binary, "item", "read", "--title", value["key"]["title"], "--username", "", "--output", str(output)]
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=8)
            invocations.append({"command": shlex.join(command), "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr})
            check(name + ": one synthetic read only", [json.loads(line)["op"] for line in calls.read_text().splitlines()] == ["read"])
            check(name + ": secrets never printed", SECRET not in result.stdout + result.stderr)
            if mode == "valid":
                snapshot = json.loads(output.read_text())
                captured = snapshot["items"][0]["state"] if batch else snapshot["state"]
                check(name + ": valid private output still persists the exact snapshot", result.returncode == 0 and captured == value and output.stat().st_mode & 0o077 == 0)
            else:
                check(name + ": unsafe output fails instead of reporting success", result.returncode != 0 and result.stdout == "" and ("maintenance_snapshot_unsafe" in result.stderr or "maintenance_private_directory_required" in result.stderr))
                check(name + ": no secret written into reserved path or aliases", SECRET not in output.read_text() and (not alias.exists() or SECRET not in alias.read_text()))
                check(name + ": unrelated target untouched", target.read_text() == SENTINEL)
                if mode == "replacement":
                    check(name + ": replacement file untouched", output.read_text() == SENTINEL)
            root.chmod(0o700)

        try:
            run("item-valid", "valid")
            run("item-public-mode", "public-mode")
            run("batch-public-mode", "public-mode", batch=True)
            run("item-replacement", "replacement")
            run("item-symlink", "symlink")
            run("item-hardlink", "hardlink")
            run("item-public-parent", "public-parent")
            run("batch-valid", "valid", batch=True)
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"
    report = {
        "passed": error is None and all(check["passed"] for check in checks), "checks": checks, "error": error,
        "command": shlex.join(["python3", str(pathlib.Path(__file__).resolve()), "--bin", binary, "--report", str(report_path)]),
        "invocations": invocations, "boundary": "actual CLI item/batch snapshot + private synthetic output-drift helper",
        "real_apple_verified": False, "real_customer_records_modified": 0,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "error": error,
        "failed_checks": [check["name"] for check in checks if not check["passed"]]}))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
