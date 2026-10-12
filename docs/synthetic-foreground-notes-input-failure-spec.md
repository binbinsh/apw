# Existing synthetic foreground notes input

Failure specification written before the E2E and implementation. This is a
single bounded experiment for two existing synthetic records, not a customer
mutation or background-input entry point. The CLI requires
`--foreground-synthetic`; it does not activate an application.

The experiment fails if:

1. Missing explicit foreground-synthetic authorization, non-private input,
   invalid UTF-8/JSON, invalid canonical snapshot SHA-256, incomplete state,
   or any snapshot other than the existing `apw API 测试 · SSO 与备注` /
   `apw API 测试 · 独立备注` can reach the native helper.
2. Native title differs from the exact key title, the original marker
   `APW_EXCHANGE_SYNTHETIC_V1` is absent, password is nonempty, account/domain
   is not empty or `.invalid`, sharing is not `unshared`, or extra fields
   exist. Rejection must occur without a journal or native call.
3. Replacement notes omit/reorder the complete original UTF-16 prefix, append
   nothing, contain NUL, or exceed 4,096 UTF-16 code units. The nonempty suffix
   must contain `APW_FOREGROUND_INPUT_SYNTHETIC_V1` and be at most 512 UTF-16 code
   units. Private notes input must be decoded without normalization or newline
   changes; supplementary Unicode characters count as two code units.
4. An existing journal of any state is overwritten, appended, interpreted
   as a new attempt, or causes a retry. New private journal reservation and
   fsynced intent must precede the one authorized native call.
5. The request dispatches any default read/probe/activation/import/export,
   sends anything except the original expected state/key and exact notes to
   `synthetic-foreground-notes-input`, or retries a failed/lost reply.
6. Native boolean acknowledgement alone counts as saved. Success also needs
   `synthetic_only:true`, `persisted:true`, `credentials_changed:1`, zero
   exports/imports, no activation, and a complete returned state exactly equal
   to the original state with only notes changed.
7. Partial state, changed password/sites/account/title/OTP/passkey/sharing/
   extra fields, original unsaved notes, wrong request ID, or unsafe diagnostic
   text produces done. Each post-intent failure must retain intent and a
   fsynced uncertain record; no automatic follow-up native request is allowed.
8. Stdout/stderr or journal includes the snapshot, original notes, appended
   notes, account, site or any free-form native secret. Success exposes only
   structural evidence and before/after hashes. Failure machine codes are
   bounded; arbitrary helper diagnostics are never forwarded.

Safe failure diagnostics may contain only the fixed `synthetic_input_stage`
enum (input_validation, foreground_owner, exact_read, preimage, notes_focus,
permission, selection, text_input, postimage, save, persisted_read,
final_cancel, complete), integer `synthetic_input_event_count` in 0..4, and
boolean permission/selection_verified/postimage_verified/persisted_verified/
editor_requires_review fields. Unknown keys, secret strings and wrong types
must be removed, including inside familiar diagnostic names.

All native before/uniqueness/foreground/Save/independent readback checks are the
native backend's responsibility. Mock E2E proves CLI protocol and safety only;
its report must explicitly say real Apple persistence was not verified.

Repeatable entry point:

    python3 tests/e2e_synthetic_foreground_notes.py --bin ./dist/apw --report ./reports/synthetic-foreground-notes.json
