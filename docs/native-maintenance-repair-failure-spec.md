# Native maintenance repair failure specification

This specification precedes the repair. Live Apple execution belongs to the root agent.

1. A helper first used while Passwords is foreground must not permanently refuse later requests after the person returns to their work app. Bind a new lease only at the start of a request with no owned editor open; never renew a lease in the middle of an operation.
2. No owner PID, an inconsistent keyboard owner, an expired deadline, an activation, focused-field setter, or injected input must refuse. A foreground request must stop if the person switches away during that request; a new background request may then start.
3. A search field without complete SelectedText support must not make precise reads categorically impossible. First try AXValue only with a random query that demonstrably yields zero real rows, followed by the target query and two complete stable bounded row observations. An acknowledgement or visible value alone never proves the model changed. Empty target results after the sentinel cannot distinguish a stale sentinel model, so absence still requires the complete unfiltered index. If the search model cannot be proved, use one complete unfiltered list index per category, never a partial or silently truncated scan. This fallback must not change search text with AXValue or inject events.
4. Cached row labels are scoped to category and search query. A filtered label array must not overwrite the complete active index. After deletion invalidate indexes instead of adjusting an unverified generation.
5. A readonly editor may be cancelled only when all editable values still match the owned snapshot. A save or cancel acknowledgement is not completion: wait for the editor to disappear and the list to return under the same lease.
6. Native readiness must distinguish a locked window, user editor, missing window, missing trust, owner change, and incomplete discovery. Diagnostics must never include credential values.
7. Full-note, empty credential, no website, known absence of OTP/passkey, unknown-data, sharing, whole before/after, source and retainer safeguards remain mandatory; no real account is modified by policy verification.

Repeatable isolated entry point: compile the Swift helper and run `tests/e2e_native_policy.py --helper <helper> --report <result>`. The command must enter `--policy-test` before NSApplication initialization, so it does not inspect or operate Apple Passwords.

The focus ban above remains the default. The explicitly opted-in synthetic
foreground diagnostic has a separate failure specification in
`notes-editor-probe-failure-spec.md`; it grants no text-write or delete permission.

8. Delete confirmation requires an exact ordinary button plus an explicit recovery/deleted-location phrase. A bare number 30 is not recovery evidence. The bridge rechecks these conditions, candidate full native title/body and empty credentials immediately before its click. Native displayed title and editor title may differ; the editor title is bound to the verified preimage.

9. Initial preparation clears the addressed search field using its unique native Cancel/Clear child, not two sidebar category transitions. The candidate must be a known clear button owned by that exact search field and the verified process. No key events, focus setters, activation, or AXValue-only proof are permitted. Clearing completes only after the fresh search value is empty and a complete stable list observation confirms the model. A rejected or ambiguous action holds.
10. Safe diagnosis exposes bridge stage/error/exit codes and search child role/action names/known-clear-caption/identifier-presence flags. It never emits arbitrary captions, search values, usernames, passwords, or notes.

11. UI transition polling discards an incomplete stale frame in isolation. Only a fresh, complete frame may establish the current selected details, opened editor, or returned list; earlier transition errors must not permanently poison a later independent complete observation. Final identity/body and field snapshots still fail on any incomplete observation.
12. NotesField may be AXTextField or AXTextArea on this macOS version. Complete selected-text writes are allowed only for that exact identifier and those roles, or the exact AXSearchField. Password/UserName/unknown fields remain forbidden.
13. Recover-readonly-editor requires a supplied complete expected state, an independently complete unique current editor, two matching observations of every modeled value, and no sheets. Missing fields, changed password/notes/sites/extra data/sharing/OTP/passkey, ambiguity, and owner changes refuse. It cannot close an editor based merely on its title, and it cannot reset a journal.

14. Bounded selected-text/value search replaces the target directly; it must not first clear an old query. Only a complete unfiltered-index request clears. A category action is unique, and an independent complete selected-tile or toolbar category observation must confirm All/Deleted before any list is used as that category. Arbitrary account/title text containing All is not category evidence.
15. Search replacement can temporarily invalidate the toolbar/search field. Wait for independently complete fresh frames proving the requested value, under the unchanged lease, instead of one fixed 0.1-second observation. Final bounded rows still require a fresh complete stable generation and exact title, while empty/stale target models cannot imply absence.

16. The current snapshot schema does not include editable VerificationCodeField values. Recovery therefore refuses any VerificationCodeField with AXTextField, AXTextArea, or AXComboBox role; unknown/absent OTP status cannot prove an edited seed unchanged. Static generated-code/label roles do not imply editable seed data. This guard does not expand or reset the snapshot or journal schema.

17. Before any note mutation, obtain two independently complete fresh NotesField observations with exact unchanged editable fields. Record only role, IsAttributeSettable raw codes/booleans for range/text/value, and standard action names. A cannotComplete or stale-element return is transient/incomplete, never an unsupported-feature conclusion. Observe for at most three seconds and only attempt SelectedText once after two complete writable frames. A legitimate stable unsupported result holds; no AXValue write fallback or input injection is allowed.
