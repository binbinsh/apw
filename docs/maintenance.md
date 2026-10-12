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
Background lookup uses the complete unfiltered category index directly. It does
not probe or rewrite the search field. If the visible search is nonempty or its
list model is incomplete, the command stops without altering the query. This
avoids leaving a visible empty field bound to an old empty result model.

The foreground-only lookup strategies remain guarded by live model witnesses.
Filtered indexes are never reused as whole-library evidence. Recently Deleted
is indexed separately. Cached labels may route a positive lookup, whose selected
record is re-read completely. A missing target requires two fresh, complete,
stable unfiltered observations; equal row counts do not prove absence.

Touch ID and app unlocking require the person. Locked/unsupported windows stop
the command. `item doctor` reports actual local access/window availability;
`apple_live_verified:false` means the helper never claims live mutation support
from a successful compilation or an enum in Apple's extension protocol.

## Current verification status

The compiled CLI/helper boundary tests pass. A live synthetic trial has verified
exact reads and exposed an Apple editor behavior: AXValue updates the visible
NotesField but does not persist its model. The replacement implementation uses
complete AXSelectedText replacement with exact UTF-16 range and unchanged global
focus checks. The new live notes write path still needs a successful Apple synthetic trial.
Targeted live batch reads and individual recoverable deletion have been observed;
content-preservation reconciliation has also succeeded for a historical pending
operation. Uninterrupted batch cleanup remains under live verification. Exact bounded
search has succeeded live, but a subsequent read-only review found its text
submission unavailable and stopped before mutation. Search capability is not
reliably established. The advertised search Confirm action was also refused in a
background trial. In a separate self-owned SwiftUI fixture, successful AXValue
and AXConfirm returned without updating the real Binding model. That experiment
does not certify Apple operations.
Readiness reports distinguish editor, unavailable and incomplete views;
an unavailable context does not establish locking from text such as `unlock`.
static detail labels are not classified as editable fields. Each request obtains
a fresh owner lease. AX elements are deduplicated by CFEqual within CFHash
buckets, because distinct live elements can share a hash; their subtrees must
not disappear from a complete observation. Transient invalid UI frames are discarded rather than
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

For a targeted batch, explicitly preserve completed reads if a later target fails:

```sh
apw batch inspect --targets /private/directory/targets.json \
  --output /private/directory/new-snapshots.json --save-partial
```

The command stops at the first error and exits nonzero. It never reads the next
target or automatically retries, including after a timeout, malformed helper
reply, ambiguous/missing item, or unclosed editor. When the reserved output is
still private and safely bound, it fsyncs only the completed, validated prefix
as `apw-item-snapshots-v1`, with `complete:false`, `requested_count`, one-based
`failed_index`, and `failures:[{"index":N,"error":"maintenance_..."}]`.
Every saved `items` entry contains its full state and canonical SHA-256; the
failed target is excluded. An error on the first target produces an empty prefix.
Public error diagnostics expose only safe structural evidence, positions,
`completed_reads` and `partial_saved:true`; no snapshot values are printed.
An unsafe/replaced/linked output is refused rather than receiving cleartext.

The default remains all-or-nothing: without `--save-partial`, a failed batch
does not write the buffered prefix. Full success retains the existing
`{"format":"apw-item-snapshots-v1","items":[...]}` schema in either mode.
Startup/input/output failures before a target read do not invent a partial
manifest. This is first-error salvage, not a per-read crash checkpoint.

A partial manifest is evidence only for its saved items. It does not prove full
target coverage, whole-library inventory, or absence of an omitted identity.
After resolving the failed helper/editor state, use a new private targets file
starting at the failed target and a new output pathname to inspect the remainder.
Do not repeat the successful prefix or overwrite its existing artifact. Plans
may reference only explicitly selected saved items with verified hashes; a
candidate/keeper deletion pair requires both complete states. `batch run` still
performs fresh native reads and full before-hash checks for every planned item.
Saving a prefix grants no extra deletion or continuation authority.

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

Deletion is deliberately limited to unshared, credential-free notes with no
sites, OTP, passkey, or additional editable data. The keeper's full live state
is checked before and after. Only ordinary recoverable deletion is dispatched.
New deletions first save a private, fsynced full preimage and check for a
same-title collision in Recently Deleted.

The default outcome proof reads the full immutable Deleted body. When a complete
Deleted view explicitly fails only because it does not expose that body, a
separate conservation proof is available for this narrow empty-credential note
shape: exact Deleted location in two complete frames, fresh Active absence,
and two independent complete keeper reads equal to the original keeper hash,
including the entire candidate body and every source identifier. The journal
records `content_preservation_verified:true` and `deleted_body_verified:false`.
It does not claim to have read or verified the hidden Deleted body. Existing
uncertain operations are reconciled read-only and never automatically re-deleted.

Normal login deduplication and passkey/group inventory are not yet implemented.
A count alone is not proof of identity coverage.

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

For a long batch, explicitly reuse qualified historical completions:

```sh
apw batch run --apply --skip-completed --plan /private/directory/plan.json \
  --journal /private/directory/journal.jsonl
```

The default still rechecks every completed outcome read-only. This option skips
current Apple reads only for a final `done` backed by the original plan/id,
consistent ordered checkpoint history, a private single-link journal and the
private complete original snapshot at its fixed journal-derived path. Notes
completions must bind the unique planned after-state hash. Deletion completions
must carry a consistent content-preservation/deleted-body proof. Legacy or
damaged completion metadata is not trusted for skipping and instead follows the
existing read-only audit; invalid plan/preimage evidence still stops execution.

`intent` and `uncertain` always follow read-only outcome reconciliation and
never dispatch the old mutation again. `reviewed-no-change` is not skipped: its
existing explicit unchanged-review authorization and checks remain unchanged.
New operations still require fresh full preimages and their normal verification.
No extra writes, retry authority, imports or exports are introduced by this flag.

The result adds `skipped_completed` only when requested. `completed` counts this
run's verified outcomes/new operations and excludes those historical skips;
their sum may cover `total`, but skipped entries are **not** current Apple-state
verification. Proof counters likewise count only this run's checks. Use the
default mode whenever a current audit of already completed outcomes is needed.

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

## maintenance.6: incomplete-model and outcome protection

Search polling now scopes completeness to each independent frame while preserving
an outer incomplete observation. Two adjacent complete frames must agree on the
query, category, owner, and actual list model. Clearing a query cannot reuse a
zero-row model contradicted by the sidebar. A failed text submission cannot
fall back to a second submission. Structural diagnostics contain bounded counts
and Booleans, never queries, account labels or note contents.

Recently Deleted verification independently binds one selected exact row, the
full original body, its category and ordinary recovery control in two adjacent
complete frames. A title match alone does not complete a deletion journal.

In the latest live background run, exact candidate and keeper reads passed. One
recoverable-delete attempt then returned an uncertain outcome. Read-only review
found the exact candidate in Recently Deleted but could not verify its full body;
the active list also remained a stale empty model. The journal remains uncertain,
and no second delete was dispatched. The original snapshots and source manager
remain preserved. This is an unfinished acceptance result, not successful bulk
cleanup. Default background notes persistence also remains unverified.

The initial build passed 19 suites / 1,126 checks. After the clear-query and deleted
frame changes, the seven affected suites passed 406 checks through the compiled
CLI/helper boundaries. Each saved report records its command. Pure frame replay
and isolated transport tests prove refusal/recovery contracts; they do not prove
Apple accepts the corresponding live action. See the
[search failure specification](native-search-preparation-failure-spec.md).
