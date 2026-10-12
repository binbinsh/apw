# Exact native maintenance (experimental)

This GPL fork adds `item read`, `item notes set`, `item delete`, `batch inspect`,
`batch run`, `item connect`, `item recover-editor`, read-only `item probe-notes`,
and offline `capabilities`.
The existing browser backend and pairing remain separate and
are not restarted by these commands.

`batch run` validates only unless `--apply` is supplied. A batch contains at most
50 explicitly named operations. There is no whole-vault export, import, bulk
blind deletion, permanent deletion, or automatic mutation retry.

## Apple backend boundary

Passwords has no public developer API for arbitrary whole-library notes editing
or deletion. These new commands use a bundled Swift Accessibility backend,
verified against Apple's signed Passwords process. They do not bypass unlocking
or activate the application. Default commands do not generate keyboard/mouse
events or set focus. The explicitly requested synthetic foreground probe described
below has a separate, guarded internal field-focus operation. Commands may
change the internal category, clear a search, select a record, open its editor,
and dispatch its semantic Save/Delete actions in an already unlocked window.
Active lookup first replaces the search field's complete selected text and
verifies the query and at most 100 fresh result rows. If unsupported, AXValue is
accepted only after a random query demonstrably empties the actual list and the
target list is independently stable. The last fallback is one complete,
unfiltered category index per helper session; a partial index is refused and
not repeatedly rescanned. Filtered indexes are never reused as whole-library
evidence. Recently Deleted is indexed separately. Search clearing addresses only
the unique search-field Cancel button and verifies the actual list returned.

Touch ID and app unlocking require the person. Locked/unsupported windows stop
the command. `item doctor` reports actual local access/window availability;
`apple_live_verified:false` means the helper never claims live mutation support
from a successful compilation or an enum in Apple's extension protocol.

## Current verification status

The compiled CLI/helper boundary tests pass. A live synthetic trial has verified
exact reads and exposed an Apple editor behavior: AXValue updates the visible
NotesField but does not persist its model. The replacement implementation uses
complete AXSelectedText replacement with exact UTF-16 range and unchanged global
focus checks. This new live write path and recoverable deletion still need a
successful Apple synthetic trial; customer cleanup remains held. Exact bounded
search has succeeded live, but a subsequent read-only review found its text
submission unavailable and stopped before mutation. Search capability is not
reliably established. The advertised search Confirm action was also refused in a
background trial. In a separate self-owned SwiftUI fixture, successful AXValue
and AXConfirm returned without updating the real Binding model. That experiment
does not certify Apple operations.
Readiness reports distinguish editor, unavailable and incomplete views;
an unavailable context does not establish locking from text such as `unlock`.
static detail labels are not classified as editable fields. Each request obtains
a fresh owner lease; transient invalid UI frames are discarded rather than
poisoning a later complete observation. NotesField accepts the actually observed
AXTextField as well as AXTextArea role; other fields cannot use the notes setter.
Do not treat mock
E2E or read-only diagnostics as an Apple mutation acceptance result.

Notes capability checks require two fresh, complete, unchanged observations.
Their raw attribute-query error codes distinguish transient failures from a
stable unsupported field; no AXValue write fallback is used. The read-only
diagnostic below avoids changing the search altogether:

```sh
apw item probe-notes --snapshot /private/directory/original-synthetic-snapshot.json
```

This command accepts only a private, hash-verified existing `apw API 测试`
fixture with the synthetic marker, empty password and `.invalid` websites. It
binds one unique match in the current stable result cohort, captures NotesField
capabilities, descendants and target-app internal focus without secret values,
then cancels and independently rechecks the full original state. Both Cancel
operations must be verified. It does not change a query, field or journal. Its
current-cohort evidence does not prove whole-library uniqueness and never
authorizes a mutation. A failed or incomplete observation remains held.
See the [probe failure specification](notes-editor-probe-failure-spec.md).
An editor opened by a failed probe is recovered only when two complete
observations exactly match the supplied preimage under its original lease.
Otherwise the command reports `maintenance_editor_requires_review` and leaves
the editor protected.

One optional diagnostic checks whether NotesField capabilities change when the
person has already brought Passwords to the foreground:

```sh
apw item probe-notes --snapshot /private/directory/original-synthetic-snapshot.json \
  --foreground-focus
```

This mode requires Passwords to remain the existing foreground application; it
never activates or raises it. After verifying the full original synthetic state,
it may set `AXFocused` on the uniquely bound NotesField once. It verifies the
target application's focused element and every original value before probing.
It does not set search/note text, issue keyboard events, save, or delete. A known
external keyboard owner, ambiguous field, failed focus proof, app switch, or
incomplete state stops the diagnostic. Default background operations retain
their original focus ban. A successful diagnostic is still not note-write
acceptance.

## Build and repeatable tests

Requires macOS/Xcode CLI tools and the repository's Deno dependencies. No new
Node dependency or browser installation is introduced.

```sh
DENO_BIN=/path/to/deno ./script/build_macos.sh --verify
```

The stored reports contain their exact repeatable commands. The maintenance E2E
uses the actual compiled CLI with an isolated synthetic native-helper process;
it does **not** prove Apple accepts the live operations. The native contract test
runs the real Swift helper's read-only diagnostic entry point.

`tests/e2e_apple_synthetic.py --run` is a separate one-shot live test on the two
specific already imported synthetic fixtures named in that script. It never
creates/imports a record or activates/unlocks Passwords. Do not run again after
intent without reviewing its saved trial directory and journal. Customer data
must wait until the synthetic trial passes.

`tests/e2e_apple_resume.py` resumes that same saved trial and journal; it cannot
create a fresh plan or target customer identities. `--review-unchanged` first
performs the explicit read-only preimage review. A failed read/review stops before
any new write. Its report stores every exact CLI invocation.

## Private targeted snapshots

Use a 0700 directory and 0600 files. Snapshots include plaintext secret fields;
they are temporary local maintenance artifacts, not another credential vault.
Do not commit or upload them.

```sh
apw item read --title 'exact displayed title' --username 'exact account' \
  --output /private/directory/snapshot.json
apw batch inspect --targets /private/directory/targets.json \
  --output /private/directory/snapshots.json
```

Targets format:

```json
{"format":"apw-maintenance-targets-v1","targets":[{"title":"synthetic note","username":""}]}
```

Read captures a complete state and a canonical SHA-256. Title/account identifies
a record only when exactly one native row matches; it is not a permanent Apple
record ID. Ambiguous same-title/account duplicates are refused.

An unchanged readonly editor left by an interrupted helper can be safely closed:

```sh
apw item recover-editor --snapshot /private/directory/original-snapshot.json
```

The original snapshot must be private and hash-verified. The native helper reads
the complete editor state twice; both must exactly match the original. It only
dispatches Cancel, never edits values or resets a mutation journal. An incomplete,
changed or ambiguous editor remains protected. Live recovery of the existing
synthetic SSO editor passed on 2026-10-12; this does not certify notes persistence
or deletion.

## Plans and execution

```json
{
  "format": "apw-maintenance-v1",
  "operations": [{
    "id": "merge-001",
    "kind": "notes-set",
    "target": {"title":"synthetic login","username":"alice@example.invalid"},
    "before_sha256":"<snapshot sha256>",
    "notes":"<complete original body, followed by merged content>"
  }]
}
```

`notes-set` preserves the original complete body and changes only NotesField.
Readback must match the expected complete state, including the unchanged
password, sites, sharing and credential indicators. Shared/unknown-sharing
records are held.

`delete-redundant-note` additionally requires:

```json
{
  "keeper":{"target":{"title":"synthetic login","username":"alice@example.invalid"},"before_sha256":"<keeper snapshot sha256>"},
  "preserve_text":"<entire candidate note body>",
  "source_ids":["<source identifier present in both note bodies>"]
}
```

Deletion is currently deliberately limited to unshared, credential-free notes
with no sites, OTP, passkey, or additional editable data. The keeper's full live
state is checked before and after. Ordinary recoverable deletion is confirmed,
then the exact title and full note body must appear in the immutable Recently
Deleted detail view. Deleted verification binds this placement/body evidence to
the captured pre-deletion empty-credential snapshot; it does not read passwords
from Deleted. Normal login deduplication and passkey/group inventory are not yet
implemented. A count alone is not proof of identity coverage.

```sh
apw batch run --plan /private/directory/plan.json \
  --journal /private/directory/journal.jsonl          # no native calls
apw batch run --apply --plan /private/directory/plan.json \
  --journal /private/directory/journal.jsonl
```

An exclusive journal lock prevents two writers. Intent is fsynced before every
mutation, completion only after exact readback. Before a notes mutation, the
complete original state is also saved and fsynced in a new 0600 snapshot named
`<journal>.<operation-id>.before.json` inside the same private directory. This
snapshot contains plaintext secret fields; keep it local alongside the journal.
Interrupted/unknown operations resume read-only: the command binds that full
snapshot to the original plan's before hash, reconstructs the sole permitted
after-state with the planned notes, and verifies every field or stops for
review. It never resends a write because a response was lost. Completed entries
are reverified, not repeated. A dead executor's lock can be reclaimed only for
the same plan. New intents retain the native title, so readonly deletion recovery
can handle a native/list title difference. Legacy intents without that metadata
still require reconstruction to match the original complete hash exactly.
Legacy notes intents without complete before-snapshot evidence are held for
review; a matching after hash in an editable journal is insufficient.

An operator can explicitly resolve a failed, unchanged operation with a read-only
review. It checks the entire original state before permitting a later dispatch:

```sh
apw batch review --plan /private/directory/plan.json \
  --journal /private/directory/journal.jsonl --acknowledge-unchanged
```

Review never mutates Apple records. A changed or unreadable state remains held.

## Narrow synthetic notes-input experiment

`item test-notes-input` is separate from `notes set` and batch execution. It
cannot edit customer records or authorize event input for ordinary maintenance.
It accepts only the exact existing fixture titles `apw API 测试 · SSO 与备注`
and `apw API 测试 · 独立备注`, their complete hash-verified private original
state, empty credentials, `.invalid` identities/sites, and unshared placement.
The replacement text must preserve the entire original UTF-16 prefix and append
a bounded `APW_FOREGROUND_INPUT_SYNTHETIC_V1` test marker.

```sh
apw item test-notes-input --foreground-synthetic \
  --snapshot /private/directory/original-synthetic-snapshot.json \
  --notes-file /private/directory/complete-synthetic-notes.txt \
  --journal /private/directory/new-synthetic-attempt.jsonl
```

Passwords must already be in front. The helper never activates it, changes the
clipboard, requests permissions, or posts global input. It proves exact item,
window, field focus and selection before at most four PID-addressed events.
After an attempted input, any failure leaves the editor for review. A single
semantic Save must be followed by independent complete persisted readback and
safe closure before the command acknowledges success. The new private journal
records fsynced intent first; any existing journal is refused, including a
failed or completed attempt. No automatic retry or resume exists for this test.

The actual self-owned SwiftUI fixture passed Unicode Binding and persisted
readback; this does not certify Apple. Apple notes persistence and recoverable
deletion remain separate unfinished acceptance gates. See the
[failure specification](native-synthetic-notes-input-failure-spec.md).

Do not retire the source manager until field coverage, passkey identity,
attachments and sharing/group checks all pass independently.
