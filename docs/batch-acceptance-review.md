# Batch acceptance review

## Safe native diagnostics failure specification

This specification and entry-point E2E precede the diagnostic forwarding change.
The current helper can identify the structural stage of a failure, but the CLI
drops that evidence. Reproducing the same operation directly against the helper
just to recover an error stage creates unnecessary native work.

The change fails if:

1. A helper failure loses its safe structural failure stage, status, AX attribute
   name, integer error code, or All-category bridge stage/reason.
2. Native diagnostics are forwarded as an unfiltered object.
3. Notes, passwords, usernames, target keys, search text, or arbitrary nested data
   become stdout/stderr diagnostics.
4. A nominally permitted diagnostic key accepts a secret-bearing free-text value,
   an object/array in place of a scalar, or a boolean in place of an integer code.
5. A failed read prints a snapshot or writes any secret to its reserved output.
6. Requesting a diagnostic retries the native operation or switches to a different
   target/backend.

The helper's safe failure remains the top-level `error`. Optional `diagnostics`
contains a whitelist of structural names and typed values. A machine error code
is preserved; a native localized message is not a license to print arbitrary
text. The CLI can diagnose a safe failure in one invocation without a second
direct helper read.

The offline test invokes `apw item read` through the real compiled CLI, using a
private synthetic helper process that returns a fixed failing reply. It does
not contact Apple Passwords, any paired daemon, or a real credential. Its report
stores the exact command and repeatable results. Passing this test proves safe
diagnostic transport only; it cannot prove native read/save/delete acceptance.

```sh
python3 tests/e2e_native_diagnostics.py --bin ./dist/apw --report ./reports/native-diagnostics-e2e.json
```

## Current batch flow review

The executor supports a two-step append-then-delete plan: the delete operation's
keeper hash must be the complete *post-merge* keeper state, not its initial hash.
Once the merge is `done`, resuming the batch rechecks that exact complete state
and never dispatches the merge again. Each write has an fsynced `intent`; a
missing response or unexpected readback becomes `uncertain` and cannot trigger
an automatic retry. Explicit unchanged-preimage review is read-only.

Deletion currently proves an unshared note with empty account/password, no
websites/OTP/passkey/additional editable data. The full candidate body and source
IDs must already be in a uniquely identified keeper. It verifies Recently Deleted
placement/body and the unchanged keeper after deletion. This does not implement
ordinary duplicate-login merging; a title/account pair that names two normal
logins must remain held until an unambiguous identity mechanism exists.

## Composed-batch failure specification

The composed entry-point E2E adds cases absent from the existing single-operation
checks. It fails if:

1. Append followed by delete requires the keeper's stale initial hash instead of
   the complete intended post-append state.
2. A completed combined batch changes the keeper's password, websites, OTP/passkey
   indicators or extra editable fields, or repeats either write when resumed.
3. Losing the delete acknowledgment dispatches delete again instead of verifying
   active absence, Deleted body placement and keeper state.
4. A keeper changes during deletion but the batch still records deletion `done`
   or continues to a subsequent operation.
5. A captured native title is lost from an uncertain delete's intent, so exact
   deleted-state evidence cannot resolve the operation without a replay.
6. A legacy journal's missing native title or malformed/changed title metadata
   relaxes the original complete preimage hash check.

`tests/e2e_batch_acceptance.py` checks those cases against the actual compiled
CLI and a private synthetic stateful helper. The native-title-alias case requires
read-only recovery. Legacy journals may fall back to the displayed target title
only when that reconstruction matches the original complete preimage hash.

```sh
python3 tests/e2e_batch_acceptance.py --bin ./dist/apw --report ./reports/batch-acceptance-e2e.json
```

### Smallest recovery improvement

The initial deletion can legitimately capture `native_title` different from the
displayed target title. The failing behavior reconstructs it as the target title,
preventing resolution of an already-deleted record with that alias. The minimal
fix stores the captured `before_native_title` in the fsynced intent, then uses it
to reconstruct the exact original blank-note state. The reconstructed hash must
still equal the plan's before-hash, and Deleted placement/body plus keeper state
must still match. Malformed metadata or a missing alias in a legacy journal stops
without a guessed hash or a repeated deletion. Journals with no title metadata
remain compatible only when the target title really matches the original state.

The current `available_paths` capability additions correctly distinguish the
existing extension metadata/password-save paths from precise updates, and the
SSO empty-password/provider-notes workaround from a native provider relationship.
`MAYBE_ADD` has not become a stable record-identity API.
