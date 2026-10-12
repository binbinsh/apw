# Exact native maintenance (experimental)

This GPL fork adds `item read`, `item notes set`, `item delete`, `batch inspect`,
and `batch run`. The existing browser backend and pairing remain separate and
are not restarted by these commands.

`batch run` validates only unless `--apply` is supplied. A batch contains at most
50 explicitly named operations. There is no whole-vault export, import, bulk
blind deletion, permanent deletion, or automatic mutation retry.

## Apple backend boundary

Passwords has no public developer API for arbitrary whole-library notes editing
or deletion. These new commands use a bundled Swift Accessibility backend,
verified against Apple's signed Passwords process. They do not bypass unlocking,
activate the application, set focus, or generate keyboard/mouse events. They may
change the internal category, clear a search, select a record, open its editor,
and dispatch its semantic Save/Delete actions in an already unlocked window.
Active lookup replaces the search field's complete selected text and verifies
the new query and at most 100 fresh result rows. No complete active-library scan
is used. A fresh result model and selected row must match the bounded index; a
mismatch fails closed. Recently Deleted is indexed separately.

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
successful Apple synthetic trial; customer cleanup remains held. A later complete
native index read was incomplete and stopped before a mutation. Bounded search
now avoids that scan. The advertised search Confirm action was refused in a
background trial; complete selected-text replacement still needs live acceptance.
Readiness reports distinguish lock, editor, unsupported and incomplete views;
static detail labels are not classified as editable fields. Do not treat mock
E2E or read-only diagnostics as an Apple mutation acceptance result.

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
mutation, completion only after exact readback. Interrupted/unknown operations
resume read-only: the command verifies the expected after-state or stops for
review. It never resends a write because a response was lost. Completed entries
are reverified, not repeated. A dead executor's lock can be reclaimed only for
the same plan. Notes-only deletion resume requires the captured native title to
equal the displayed title; otherwise it stops for explicit review.

An operator can explicitly resolve a failed, unchanged operation with a read-only
review. It checks the entire original state before permitting a later dispatch:

```sh
apw batch review --plan /private/directory/plan.json \
  --journal /private/directory/journal.jsonl --acknowledge-unchanged
```

Review never mutates Apple records. A changed or unreadable state remains held.

Do not retire the source manager until field coverage, passkey identity,
attachments and sharing/group checks all pass independently.
