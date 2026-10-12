# Notes journal recovery security specification

Written before the security E2E and fix on 2026-10-12. The real CLI and an
isolated synthetic helper are used; no Apple or customer data is accessed.

The reproducible defect is in notes-set resume: the current state is compared
only with the intent's after_sha256. A damaged intent can put the unchanged
before-state hash into that field. Resume then marks the operation done although
the note required by the original unchanged plan was never saved. The journal
is private but still requires semantic validation; a copied or damaged record
must not become migration acceptance.

Recovery fails if:

1. An intent, uncertain or done record can mark an operation completed while
   the actual complete notes differ from that original plan's notes.
2. A notes intent's before_sha256 is missing or differs from the original
   operation's before_sha256, or its after_sha256 is not a lowercase SHA-256.
3. Captured before_native_title is malformed, contains NUL, or differs from the
   actual current native title, yet the operation is marked done.
4. Invalid metadata triggers a native read or any mutation instead of holding.
5. A recovery failure appends done, retries notes-set, changes the backing
   synthetic state, or emits note/password text on stdout or stderr.
6. A valid complete original intended state with its private, hash-bound full
   before snapshot cannot resume read-only. An older notes journal without
   full before evidence must instead hold, even if its after hash matches.
7. An incomplete journal line is interpreted as a fresh operation or invokes
   the helper instead of failing before native interaction.

The fix must keep full after-state hashing and the original plan hash; note
equality is an additional binding to the plan, not a replacement for the hash.
It does not authenticate arbitrary same-user edits to every local file and does
not claim Apple persistence, passkey identity or complete-library acceptance.

The repeatable entry point is:

    python3 tests/e2e_journal_security.py --bin ./dist/apw --report ./reports/journal-security.json

## Complete before-state binding

Peer review found a second false-acceptance path: an after hash rewritten to
match a current state with the required notes but a wrong password, sites, OTP,
passkey, sharing or extra fields. The changed after hash must not authorize
those changes. Written before the extended E2E and implementation:

1. A new notes operation first saves its complete native before state as a
   createNew 0600 private snapshot at `${journal}.${operation.id}.before.json`.
   File/path owner, type, mode, single link and inode/device are rechecked;
   snapshot fsync precedes the intent and native mutation.
2. The intent contains only that exact path and hashes. Recovery validates
   private snapshot schema/key and full canonical hash against the original
   plan's before_sha256, then reconstructs the only permitted intended state
   by replacing notes in that before state with the original plan's notes.
3. A forged after hash, missing/public/symlink/corrupted before file, wrong
   before content or unexpected path must hold before a native read. A legacy
   uncertain/done notes operation without complete before proof also holds.
   Recovery never reconstructs a before password/site from the current state.
4. Valid new run, done resume and lost-reply resume preserve every other field
   and never dispatch the same mutation twice. No sidecar/journal secret is
   printed; existing sidecars are never overwritten. Delete recovery retains
   its separate existing exact empty-credential before proof.

## Snapshot after-reservation privacy specification

Written before the snapshot E2E/fix. item read and batch inspect reserve an
output file before starting their helper, which correctly blocks pre-existing
files. They do not currently revalidate that descriptor/path before writing
the returned cleartext passwords. A chmod to 0644 during the helper read makes
the successful snapshot publicly readable; path replacement can also make the
success output identify an unrelated object.

The snapshot change fails if:

1. A file whose owner/type/private mode has changed receives any password bytes.
2. The reserved pathname is replaced with a different file or symlink, yet the
   command reports a successful snapshot or modifies that replacement/target.
3. A hard-linked reserved file receives secrets through an unverified alias.
4. A now-insecure parent directory is accepted as the required private output
   directory.
5. A failed privacy recheck prints secret data or leaves a success-shaped record.
6. The valid private single-file snapshot no longer works, or the batch inspect
   path omits the same protection.

Check the opened descriptor and the current path, including owner, private
mode, regular-file type, device/inode and link count, immediately before and
after persistence. Retain createNew and fsync. These checks address observed
drift/replacement; they cannot defend against a same-user attacker changing
permissions continuously after the command ends or authenticate every program
running as that user. Do not describe them as an absolute sandbox.

    python3 tests/e2e_snapshot_security.py --bin ./dist/apw --report ./reports/snapshot-security.json
