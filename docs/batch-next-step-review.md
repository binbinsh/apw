# Next batch acceptance review

Static review on 2026-10-12. No Apple process, customer record, export, browser,
pairing or UI was accessed. The handoff reports 2 of 24 candidates cleaned;
this review does not independently recount the live library.

## Smallest useful next acceptance

The remaining blank-credential notes do not intrinsically require a notes
write: runBatch already requires the candidate's complete body and source IDs
to exist in its keeper before deleting it (maintenance.ts:361–365).
Consequently the narrowest useful deletion test is two consecutive synthetic
deletes whose keeper already contains both complete bodies, followed by a
read-only resume using the same plan/journal. That tests the actual next-row
selection after Active → Deleted → Active, not just an isolated delete.

**This is an acceptance design, not the current execution plan.** Only two
existing synthetic records are authorized, and the candidate's full body is
not yet in the keeper. The delete precondition is currently false. Do not
create/import a third fixture or delete the current candidate to bypass the
unverified notes-save step. A two-candidate/one-keeper design would require
already authorized records satisfying containment.

Necessary evidence, acquired through the real compiled CLI with the actual
maintenance helper rather than a test-helper override:

1. Unique complete candidate/keeper snapshots: exact title/account, native title,
   password, every website, full notes and the current snapshot schema's
   sharing/OTP/passkey/extra-field observations. Each deletable candidate must
   have an explicitly empty account/password, no websites, proven absent
   OTP/passkey, unshared state and no extra editable fields. Unknown is a hold.
2. Complete candidate body and every required source ID in the hash-bound keeper.
   The plan/journal must be private, original and unchanged; existing uncertain
   operations are resolved read-only before any new dispatch.
3. Exact editor and ordinary recoverable-delete confirmation, with original
   frontend ownership preserved and no activation or global injected input.
4. Each candidate absent from a complete Active observation and present exactly
   once in Recently Deleted with its complete original body. Keeper's complete
   observable-state hash remains unchanged after each delete. Counts alone fail.
5. The next candidate succeeds in the same helper session. Re-running the same
   plan/journal reports zero mutations and re-proves both deleted bodies and
   keeper state. A missing reply never causes a second delete.

The planned entry point is batch run --apply --plan <private-synthetic-plan>
--journal <private-synthetic-journal>, then the identical command for read-only
resume. No such live command was run by this review. The record must include
the exact executable/helper paths and signatures, plan/journal hashes,
per-operation readback evidence and zero-activation evidence.

This scoped acceptance would prove only blank-note deletion. It would not
prove notes persistence or normal-login merging. The existing broader gate in
capabilities.md:233–237 requires a combined append/save/reopen/delete trial;
a narrower gate must be adopted explicitly and must not be reported as passing
that combined trial.

## Current implementation and definite diagnostic defect

The batch is sequential and reuses one native helper; it is not an Apple bulk
delete API. Native delete still opens the AX editor, finds DeleteButton and
uses a System Events UI confirmation (native/maintenance.swift:1818–1869,
355–454). There is no extension-protocol or Credential Exchange delete path.

The review identified and the integration subsequently repaired the following
confirmation-diagnostic transport defect. The dedicated delete-kind E2E now
checks safe transport, journaled uncertainty and no retry; it does not certify
Apple deletion.

Originally:
confirmRecoverable records its refusal/exit/timeout information, but the native
failure reply whitelist at line 1889 and maintenance.ts safeDiagnostics omit
all seven fields below. The request reset at native line 1877 omits them too,
so adding only transport would risk reporting a previous request's diagnostic.
The generic delete_outcome_requires_review previously could not distinguish an
unavailable editor address, owner change, ordinary-button refusal or script
error through the actual CLI.

| Field | Exact allowed value/type |
| --- | --- |
| confirmation_bridge_failure | editor_address_unavailable, owner_changed, process_changed, window_changed, sheet_changed, fields_ambiguous, identity_changed, credential_changed, editor_address_changed, ordinary_confirmation_unavailable, none, unclassified_system_events_error |
| confirmation_native_editor_role | AXGroup, AXScrollArea, AXSplitGroup |
| confirmation_bridge_timed_out | boolean |
| confirmation_account_list_enumerated | boolean; current producer reports false |
| confirmation_bridge_exit_code | integer, 0–255 |
| confirmation_bridge_system_error_code | integer, absolute value ≤100000000 |
| confirmation_editor_path_depth | integer, 0–16 |

No title, account, notes, password, script source, UI address/expression or raw
localized error text should cross this diagnostic boundary.

### Confirmation-diagnostic failure specification

This specification precedes the dedicated delete-kind CLI E2E.
The change fails if:

1. An actual delete-kind failure loses any permitted field, enum or integer
   error code, changes its top-level error, or prints a successful completion.
2. An unknown field, free-text enum, role, raw script error, title/account,
   notes/password or arbitrary nested object is forwarded.
3. A boolean is accepted as an integer; fractions, out-of-range numbers, arrays,
   objects or strings survive scalar validation.
4. A failed confirmation automatically retries the delete, logs done, or loses
   the fsynced intent/uncertain outcome.
5. A later native request inherits an earlier confirmation field. All seven
   producer fields must be reset before each request, not only filtered later.
6. A synthetic failing-helper transport test is described as an actual Apple
   delete, native producer/reset acceptance, or permission to clean customers.

tests/e2e_delete_confirmation_diagnostics.py invokes the real CLI batch/delete
entry point with a private failing synthetic helper. It proves transport,
typing, no-retry and journal behavior only; producer/reset acceptance needs
the native-side implementation/checks. It performs no customer operation.

## Why current offline passes cannot authorize customer mutations

The composed test directly edits Python JSON for notes-set and deletion
(e2e_batch_acceptance.py:62–69), chooses that helper through
APW_MAINTENANCE_HELPER (line 73), and asserts the synthetic store (119–146).
Its report correctly states real_apple_verified=false (185–186). These passes
prove CLI composition/recovery, not SwiftUI persistence, delete confirmation,
fresh AX row discovery, foreground preservation, or Recently Deleted behavior.

Native policy cases execute --policy-test, which exits before AppKit/Apple
inspection (native:157–185; e2e_native_policy.py:163). The doctor contract
declares apple_live_verified=false and tests no writes
(e2e_native_contract.py:7–17). Neither closes the mutation gate.

Native.call currently validates request ID, ok and app_activated but does not
distinguish a synthetic helper from Apple (maintenance.ts:138–146). The public
batch mutations counter increments after an ok response (line 371); it counts
acknowledged mutation dispatches, not independently observed Apple saves.
A live acceptance runner must bind the helper identity and readback evidence;
the same stdout completed/mutations values can otherwise come from a mock.

deletedNote intentionally verifies the unique title, full body and recovery
button, then returns the expected pre-deletion state (native:1657–1679). It is
not an independent reread of every deleted credential field. Its safe scope
depends on the already-proved immutable blank-note preimage. Do not generalize
it to ordinary login deletion or treat an expected-state echo as a native
whole-field reader.

The snapshot's OTP/passkey values are absence/unknown observations
(native:1242–1251), not seeds or credential IDs. Exact normal-login identity,
field union, passkey verification, attachments and group permissions remain
unimplemented/unverified. Cleaning these 24 notes therefore cannot by itself
justify removing 1Password or claim that the roughly 2000-item library is fixed.
