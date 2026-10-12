#!/usr/bin/env python3
"""Offline capability reporting through the real compiled CLI; no Apple requests."""
import argparse
import json
import os
import pathlib
import shlex
import socket
import subprocess
import tempfile


LEGACY_FEATURE_IDS = {
    "title", "account", "password", "websites", "notes", "otp", "passkeys",
    "groups", "sharing", "wifi", "sso", "custom-fields", "tags", "attachments",
    "password-history", "source-vaults", "security", "autofill", "app-settings",
    "recoverable-delete", "permanent-delete", "library-inventory", "import",
    "export", "comparison", "deduplication", "batch-maintenance",
}
PREFERENCE_IDS = {
    "preference-account-display", "preference-menu-bar",
    "preference-compromised-detection", "preference-strong-passwords",
    "preference-auto-passkeys",
}
FEATURE_IDS = LEGACY_FEATURE_IDS | PREFERENCE_IDS | {
    "sign-in-with-apple", "native-password-history",
    "autofill-provider-settings", "icloud-passwords-sync",
    "browser-extension-settings",
}
OPERATIONS = {"read", "create", "update", "delete"}
EVIDENCE = {"none", "code", "offline-e2e", "apple-readback"}
MECHANISMS = {
    "extension", "credential-exchange", "accessibility", "manual", "local",
    "unavailable",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bin", required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    binary = str(pathlib.Path(args.bin).resolve())
    report_path = pathlib.Path(args.report).resolve()
    checks = []
    invocations = []
    error = None

    def check(name, passed):
        checks.append({"name": name, "passed": bool(passed)})

    with tempfile.TemporaryDirectory(prefix="apw-capabilities-e2e-") as tmp:
        root = pathlib.Path(tmp)
        root.chmod(0o700)
        marker = root / "native-invoked"
        helper = root / "native-sentinel.py"
        helper.write_text(
            "#!/usr/bin/env python3\n"
            "import os,pathlib\n"
            "pathlib.Path(os.environ['APW_TEST_SENTINEL']).write_text('invoked')\n"
            "raise SystemExit(91)\n"
        )
        helper.chmod(0o700)
        # Only this isolated synthetic socket is reachable through APW_DATA_DIR.
        sentinel = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sentinel.bind(str(root / "apw.sock"))
        sentinel.listen(1)
        sentinel.settimeout(0.01)
        env = {
            **os.environ,
            "APW_DATA_DIR": str(root),
            "APW_MAINTENANCE_HELPER": str(helper),
            "APW_TEST_SENTINEL": str(marker),
        }

        def call(*command):
            argv = [binary, *command]
            result = subprocess.run(
                argv, env=env, capture_output=True, text=True, timeout=8,
            )
            invocations.append({
                "argv": argv, "exit_status": result.returncode,
                "stdout": result.stdout, "stderr": result.stderr,
            })
            return result

        try:
            initial_names = set(x.name for x in root.iterdir())
            help_result = call("--help")
            check("root help advertises offline capabilities", help_result.returncode == 0 and "capabilities" in help_result.stdout)
            result = call("capabilities")
            check("capabilities succeeds without paired daemon or native helper", result.returncode == 0)
            try:
                value = json.loads(result.stdout)
            except (json.JSONDecodeError, TypeError):
                value = None
            check("capabilities emits exactly one JSON object", isinstance(value, dict))

            if isinstance(value, dict):
                check("report is static implementation evidence", value.get("format") == "apw-capabilities-v1" and value.get("source") == "static-implementation-audit")
                check("no unrestricted whole-library API claim", value.get("full_library_api") is False)
                check("all-fields/settings readiness is held", value.get("all_fields_and_settings_ready") is False)
                check("customer deduplication remains held", value.get("safe_for_customer_deduplication") is False)
                features = value.get("features")
                valid_features = isinstance(features, list) and all(isinstance(x, dict) for x in features)
                check("features are structured rows", valid_features)
                if valid_features:
                    index = {x.get("id"): x for x in features if isinstance(x.get("id"), str)}
                    check("all native/source/settings/batch domains covered exactly once", FEATURE_IDS == set(index) and len(index) == len(features))
                    coverage = value.get("coverage")
                    check("coverage width is 37 features and 148 operation rows", isinstance(coverage, dict) and coverage.get("feature_count") == 37 and coverage.get("operation_count") == 148 and len(features) == 37)
                    rows = []
                    valid_operations = True
                    for feature in features:
                        operations = feature.get("operations")
                        valid_operations = valid_operations and isinstance(operations, dict) and set(operations) == OPERATIONS
                        if isinstance(operations, dict):
                            rows.extend(x for x in operations.values())
                    check("every domain declares read/create/update/delete", valid_operations)
                    valid_rows = all(
                        isinstance(x, dict)
                        and type(x.get("implemented")) is bool
                        and type(x.get("live_verified")) is bool
                        and x.get("evidence") in EVIDENCE
                        and x.get("mechanism") in MECHANISMS
                        and isinstance(x.get("person_interaction"), list)
                        and all(isinstance(y, str) and y for y in x.get("person_interaction", []))
                        and isinstance(x.get("limitation"), str)
                        and bool(x.get("limitation"))
                        for x in rows
                    )
                    check("all operation rows distinguish implementation/evidence/mechanism/person interaction", valid_rows)
                    check("native versus workaround support is explicit", all(x.get("apple_support") in {"native", "workaround", "unknown"} for x in features))
                    if valid_rows:
                        check("live evidence is operation-specific and artifact-backed", all(
                            not x["live_verified"] or (
                                x["implemented"] and x["evidence"] == "apple-readback"
                                and isinstance(x.get("evidence_artifact"), str)
                                and bool(x["evidence_artifact"])
                            ) for x in rows
                        ))
                        check("offline tests never mean live Apple verification", all(not x["live_verified"] for x in rows if x["evidence"] != "apple-readback"))
                        check("unimplemented paths cannot claim live proof", all(not x["live_verified"] for x in rows if not x["implemented"]))
                    if LEGACY_FEATURE_IDS <= set(index) and valid_operations and valid_rows:
                        op = lambda domain, operation: index[domain]["operations"][operation]
                        check("experimental notes/save/delete gates remain unverified", not op("notes", "update")["live_verified"] and not op("recoverable-delete", "delete")["live_verified"])
                        check("ordinary duplicate logins are not claimed implemented", all(not x["implemented"] for x in index["deduplication"]["operations"].values()))
                        check("no fake passkey CRUD or permanent-deletion path", all(not x["implemented"] for x in index["passkeys"]["operations"].values()) and not op("permanent-delete", "delete")["implemented"])
                        check("complete inventory/export are not inferred from targeted reads", not op("library-inventory", "read")["implemented"] and not op("export", "read")["implemented"])
                        check("unsupported source attachments and SSO are marked as workaround", index["attachments"]["apple_support"] == "workaround" and index["sso"]["apple_support"] == "workaround")
                        exchange_rows = [x for x in rows if x["implemented"] and x["mechanism"] == "credential-exchange"]
                        check("credential exchange explicitly requires receiver selection", bool(exchange_rows) and all("receiver-selection" in x["person_interaction"] for x in exchange_rows))
                        check("external SSO has its reachable narrow exchange creation path", op("sso", "create")["implemented"] and op("sso", "create")["mechanism"] == "credential-exchange" and not op("sso", "create")["live_verified"] and index["sso"].get("scope") == "external-provider-placeholder")
                        check("SSO creation is not first-class federation mutation", not op("sso", "read")["implemented"] and not op("sso", "update")["implemented"] and not op("sso", "delete")["implemented"] and index["sso"].get("native_relationship_recreated") is False)
                        paths_consistent = True
                        for feature in features:
                            for available in feature.get("available_paths", []):
                                operation = available.get("operation") if isinstance(available, dict) else None
                                paths_consistent = paths_consistent and operation in OPERATIONS and feature["operations"][operation]["implemented"]
                        check("every available command path names an implemented scoped operation", paths_consistent)
                        model = index["sharing"].get("permission_model")
                        check("sharing states Apple's owner/member model without invented read-only ACLs", isinstance(model, dict) and model.get("roles") == ["owner", "member"] and model.get("owner_only") == ["add-members", "remove-members", "rename-group", "delete-group"] and model.get("all_members") == ["add-items", "view-items", "edit-items", "delete-items"] and model.get("per_member_read_only_supported") is False)
                        check("groups do not equate exchange collections with shared ACLs", index["groups"].get("exchange_collections_are_shared_acl") is False and index["groups"].get("item_shared_group_limit") == 1 and all(not x["implemented"] for x in index["groups"]["operations"].values()))
                        check("CSV limitations include omitted native Apple/sharing/Wi-Fi classes", set(index["export"].get("omitted_native_domains", [])) >= {"passkeys", "otp-seeds", "wifi", "sign-in-with-apple", "shared-groups-owned-by-others", "sharing-permissions"})
                    if FEATURE_IDS <= set(index) and valid_operations and valid_rows:
                        check("native Sign in with Apple is separate and has no invented command", index["sign-in-with-apple"]["apple_support"] == "native" and index["sign-in-with-apple"].get("scope") == "native-apple-account-relationship" and all(not x["implemented"] and not x["live_verified"] for x in index["sign-in-with-apple"]["operations"].values()))
                        check("source history preservation and native Apple history are separate", index["password-history"]["apple_support"] == "workaround" and index["password-history"].get("scope") == "source-historical-passwords" and index["native-password-history"]["apple_support"] == "native" and all(not x["implemented"] for x in index["native-password-history"]["operations"].values()))
                        check("five documented preferences have explicit unverified operation coverage", all(index[k]["apple_support"] == "native" and index[k].get("scope") == "apple-passwords-preference" and all(not x["implemented"] and not x["live_verified"] for x in index[k]["operations"].values()) for k in PREFERENCE_IDS))
                        check("AutoFill, iCloud sync and extension settings are distinct from apw configuration", all(index[k].get("scope") == "apple-system-integration" and all(not x["implemented"] for x in index[k]["operations"].values()) for k in {"autofill-provider-settings", "icloud-passwords-sync", "browser-extension-settings"}))

            check("native helper was never invoked", not marker.exists())
            contacted_socket = False
            try:
                connection, _ = sentinel.accept()
                contacted_socket = True
                connection.close()
            except socket.timeout:
                pass
            check("paired daemon was never contacted", not contacted_socket)
            check("capability report creates no files in APW_DATA_DIR", initial_names == set(x.name for x in root.iterdir()))
            check("report does not print test environment paths or sentinel values", str(root) not in result.stdout + result.stderr and "APW_TEST_SENTINEL" not in result.stdout + result.stderr)
        except Exception as exc:
            error = f"{type(exc).__name__}: {exc}"
        finally:
            sentinel.close()

    passed = error is None and all(x["passed"] for x in checks)
    report = {
        "passed": passed,
        "checks": checks,
        "error": error,
        "command": shlex.join([
            "python3", str(pathlib.Path(__file__).resolve()), "--bin", binary,
            "--report", str(report_path),
        ]),
        "invocations": invocations,
        "boundary": "actual compiled CLI offline static capability contract; isolated synthetic native/socket sentinels",
        "real_apple_verified": False,
        "real_library_contacted": False,
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"passed": passed, "checks": len(checks), "failed_checks": [x["name"] for x in checks if not x["passed"]], "error": error}))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
