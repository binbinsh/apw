# Existing synthetic background notes input, version 2

Failure specification written before the new E2E and production implementation.
The actual compiled CLI entry point is `item test-notes-background-input` with
the explicit `--background-synthetic` flag. The mock native helper never accesses
Apple. This test does not certify actual Apple persistence.

The experiment fails if:

1. Missing explicit flag, invalid UTF-8/JSON/hash or incomplete canonical state,
   public input files/parents, symlink or hardlink inputs reaches the helper.
   Rejection must leave inputs unchanged and reserve no mutation journal.
2. The exact existing title is not `apw API 测试 · SSO 与备注` or
   `apw API 测试 · 独立备注`, native title differs, original notes lack
   `APW_EXCHANGE_SYNTHETIC_V1`, the password is nonempty, a nonempty account is
   not synthetic `.invalid`, any site is not a credential-free HTTP(S) `.invalid`
   URL, sharing is not unshared, or extra fields are present. OTP/passkey may be
   absent/unknown only; their before/after state must not change.
3. Notes fail to retain the complete original UTF-16 prefix, append nothing,
   omit `APW_BACKGROUND_INPUT_SYNTHETIC_V2`, include NUL, exceed 512 UTF-16 units
   in the suffix or 4,096 units overall. Supplementary characters count as two.
4. An existing journal of any format/state is overwritten or retried. A new
   private fsynced intent with `apw-synthetic-background-notes-input-v2`,
   synthetic_only/background_only true and full before/after hashes must
   precede the one helper request. Intent, uncertain and done contain no
   plaintext state, account, URL or notes.
5. Native dispatch differs from `synthetic-background-notes-input` and exact
   `{expected,key,notes,synthetic_only:true,background_only:true}`. There must be
   no foreground_focus key, default read/probe, automatic retry, export/import,
   activation or secondary request. A lost reply remains uncertain.
6. Success omits strict boolean `background_only:true`,
   `original_foreground_preserved:true`, or
   `input_keyboard_focus_preserved:true`, omits the exact string
   `keyboard_focus_scope:'focus_setter_through_save'`, or accepts false/null/
   missing/numeric/string lookalikes. The legacy
   `original_keyboard_focus_preserved` field cannot replace either new field.
   Other acknowledgements must be synthetic_only
   and persisted true, credentials_changed 1, app_activated false and zero
   exports/imports. Public CLI success includes all three preservation fields
   and the exact keyboard_focus_scope.
7. Boolean acknowledgement, partial state, unsaved notes, wrong request ID,
   or any change to title/account/password/sites/OTP/passkey/sharing/extra
   fields is marked done. Only a complete returned canonical state equal to
   before plus the exact notes append may finish intent→done. Every
   post-intent failure ends intent→uncertain and cannot be retried.
8. Helper free-form diagnostics or input secrets appear in stdout/stderr or
   journal. Failure emits only bounded machine errors and existing strictly
   typed diagnostics. The stored report explicitly records fake-helper scope,
   real_apple_verified:false and real_customer_records_modified:0.

Native ownership contract: original foreground PID must remain unchanged
throughout. The initial exact preimage is read using the ordinary readonly
lease. The native helper captures one exact keyboard-focused element before
the focus setter; focus setter, selection, input events and Save require every
owner frame to compare equal to that captured element, without reacquisition.
Only after Save has returned to the list may it end this strict phase and use
the ordinary readonly lease for a new independent full postimage. The public
result makes no whole-operation keyboard-element preservation claim.

Repeatable entry point:

    python3 tests/e2e_synthetic_background_input.py --bin ./dist/apw --report ./reports/synthetic-background-input.json

## Explicit external focus state

This SelectedText-only trial emits no keyboard events. The foreground app may
report an exact absent focused element (`AXError.noValue` with a null result).
Two complete observations with the same live process identity may capture that
state. The captured kind is immutable: absent must remain exactly absent, while
present must retain its AX element, PID and role. Any observed mismatch or
unknown failure is latched for the rest of the request, even if a later frame
looks valid. Never recapture during mutation.

A successful reply must report `input_focus_owner_kind` as `present` or `absent`
and `keyboard_focus_scope` as `focus_setter_through_save`. The absent case proves
continued absence during that scope, not CFEqual preservation of an element.
Missing, arbitrary or malformed kinds cannot mark the journal done.
