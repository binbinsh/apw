# New ordinary batch notes writes: background persistence contract

Specification before implementation. The seam is the compiled `apw batch run
--apply` command with a private fake native process. No Apple requests occur.

Failure conditions:

1. A fresh notes write permits moving/prepending the existing note rather than
   exact UTF16 `startsWith(before.notes)`. Shared or changed preimages retain
   their existing refusal rules. New writes initially require a nonempty append
   and at most 4096 UTF16 units, checked before intent. This is the current
   validated feature limit, not a claimed Apple storage limit. Old journal recovery keeps the prior `includes`
   interpretation; it cannot resend the historical mutation.
2. Fresh native success lacks exact booleans `persisted`, `background_only`,
   `original_foreground_preserved`, `input_keyboard_focus_preserved` equal true;
   `app_activated` equal false; integer `credentials_changed` equal 1 and
   `exports`/`imports` equal 0; exact owner kind `present` or `absent`; or exact
   `keyboard_focus_scope:focus_setter_through_save`. Missing, false/wrong values
   and types cannot be coerced into acceptance.
3. Native acknowledgement has no complete state, or any complete state field
   differs from the unique full preimage with only the planned notes append.
4. The subsequent independent complete native read differs from the planned
   full state/hash. A native acknowledgement is not a substitute for this read.
5. A dispatched write lacks its fsynced private intent and full before snapshot,
   an uncertain reply is marked done, or recovery automatically resends it.
6. Historical intent/uncertain/done requires a new persistence acknowledgement.
   Valid full before evidence plus exact current intended state is sufficient
   for the existing read-only recovery path, including legacy `includes` notes.
7. Private note/password/account/site content leaks to CLI stdout/stderr or
   structural journals, or the report lacks exact replay command and artifacts.

The tests use only synthetic `.invalid` records. They first run against the old
compiled CLI to demonstrate RED. Production code is owned by the parent agent.
