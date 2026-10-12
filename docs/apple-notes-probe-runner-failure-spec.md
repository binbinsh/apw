# Apple Notes probe runner failure specification

The agreed test boundary is the runner's command-line entry point, the existing
compiled apw CLI, and explicit isolated replacements for the OS foreground-owner
query and native helper. Isolated runs never certify Apple behavior.

The runner can fail because:

1. The CLI, selected native helper, or private synthetic snapshot is missing,
   unsafe, or not usable. Report preflight failure before asking for foreground.
2. The helper cannot respond to the read-only `item doctor` preflight, returns an
   invalid reply, or reports unavailable Accessibility access. Never print ready.
3. The owner observer cannot launch, times out, exits with an error, returns bad
   JSON/types, or cannot identify an owner. Record a fixed error classification
   and safe numeric/boolean metadata, without raw stdout/stderr or app names.
4. A healthy observer sees other apps until the bounded watch ends. Say only that
   the target was not observed; do not infer that the person did not switch.
5. Owner querying fails after readiness. Preserve the ready artifact and report
   the observer error separately from target absence. Do not invoke the probe.
6. The person has already opened Passwords when the observer becomes ready. Use
   that first positive observation immediately, without another preflight wait.
7. The observer detects Passwords only briefly. Prepare and emit a flushed ready
   event before watching, then dispatch exactly one probe immediately on detection.
   The native backend remains responsible for subsequent owner/window validation.
8. Preflight, querying, waiting, or the probe exceeds its per-call or total budget.
   Bound all subprocess waits and sleeps by one monotonic total deadline.
9. The probe fails or returns incomplete preservation/focus evidence. Never retry
   it or declare notes writes, deletion, or complete migration verified.
10. A process emits secret-bearing text. Store only allowlisted structural reply
    fields; observer process text and exception descriptions are never artifacts.
11. An isolated test seam is active. Mark the report and ready event as isolated,
    with `real_apple_verified: false`, even when the compiled CLI checks pass.
12. Artifact collection fails. Still produce a bounded failure report where
    possible; never lose the original error to an unconditional file hash read.
13. `APW_MAINTENANCE_HELPER` is set without the explicit isolated seam. Refuse
    before any helper or owner query, so mock provenance cannot certify Apple.
14. Report/ready paths contain `..`, parent symlink aliases, final symlinks or
    existing hard links to a snapshot, helper, CLI or seam input. Compare canonical
    paths and existing inode identities before writing. On conflict, preserve all
    input/alias bytes and write a fresh sibling refusal report; print its actual
    artifact path. Error reporting must not bypass this protection.
15. An artifact aliases the foreground owner's executable, script or existing
    file argument. These are inputs too: preserve their contents before and after
    owner preflight, including aliases using parent symlinks or `..`.
16. A generic caller selects an unverified executable/helper pair. Process
    completion and recorded hashes do not prove Apple backend provenance. Always
    report `real_apple_verified: false`; report `backend_probe_completed` and
    `provenance_unverified` separately. A real Apple acceptance requires externally
    matching the recorded executable hashes to an independently verified build.

Acceptance artifacts contain the exact runner/CLI commands, executable hashes,
readiness, invocation counts, owner observations, bounds and outcome. No export,
import, text/query mutation, activation, or real customer change is authorized.

The generic runner is a repeatable diagnostic, not a provenance verifier. Its
`passed` and `backend_probe_completed` fields describe only the selected backend's
completed protocol and preservation evidence. Both ready and result artifacts
always retain `real_apple_verified: false` and `provenance_unverified: true`, even
without an isolated test seam. The recorded CLI/helper SHA-256 values must be
matched to a separately verified local build before a person or another tool can
classify the run as actual Apple acceptance. A matching hash is a prerequisite;
the probe's limited synthetic, read-only boundary still does not certify notes
writes, deletion, passkeys, settings, or complete migration.
