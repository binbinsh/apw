# Deleted location evidence, with body verification explicitly unknown

The live deleted detail exposed an exact selected row, TitleField and ordinary Recover control. A complete read-only attribute and parameterized text probe found no NotesField, no long value and text lengths of 2, 10 and 4, although the pending note has 706 characters. This is evidence that the available Deleted view does not expose that body; it is not permission to invent a snapshot or relax deleted-read's full-body proof.

Failure list before implementation:

- Missing, malformed or non-note expected preimage, account/password/sites/OTP/passkey/shared/custom data: refuse before selection. This constrains the supplied preimage; it does not claim those fields are visible in Deleted.
- Incomplete index, multiple exact title rows, stale current row labels, wrong selected-row identity or changed process/window: hold.
- A matching title in the table/sidebar or a loose text match cannot represent the current detail. Require one static TitleField with its actual whole value matching the input title, bound through same-process, unique current child/parent ancestry to the verified window without crossing a table, toolbar, account outline or sheet.
- Require a unique ordinary Recover control in the same independently observed detail subtree as TitleField. Do not invoke it.
- Query/category/owner changes or incomplete/transient native reads invalidate the current frame and break the adjacent-frame pair. Two complete adjacent frames must retain exact row identity and native title.
- `deleted-location-read` reports location only with `body_verified:false`. It never returns `state`, body text, account-empty or note-kind claims, and cannot authorize deletion or recovery.
- Preserve `deleted-read`'s full-body path. Only the maintenance coordinator may combine location with a preserved complete candidate preimage, independently verified Active absence, and unchanged keeper AFTER state containing the whole candidate body and provenance.
- Read row/direct-child action structure only. Do not perform AXPress, arbitrary child actions, keyboard/mouse input, focus changes, activation, recovery or deletion.

The separate `--deleted-location-replay-test` executable entry runs before AppKit/Apple inspection. It exercises the same preimage and consecutive-frame contract used by the native operation, with synthetic data. Its output cannot certify live Apple selection or detail loading; the parent owns one real read-only acceptance. The exact command and stored JSON result are produced by tests/e2e_native_deleted_location.py.
