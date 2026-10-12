# Complete current recoverable-dialog observation

The live deletion reached `recoverable_confirmation_refused` twice, with invalidUIElement/cannotComplete observations, after a single DeleteButton dispatch. The old path sleeps 0.1 seconds, reads the sheet, then checks current fields and the request-wide sticky incomplete flag. A transition error can therefore reject a later complete dialog. These reports do not prove that a valid current dialog existed or that Apple was locked.

Failure list before implementation:

- Observe only after the existing single DeleteButton dispatch. Never retry that dispatch, navigate, modify a field/query/focus, cancel or confirm from the wait loop.
- An invalid/incomplete transition frame must not poison a later independent complete frame, but must remain in the historical error counters. Current invalidUIElement/cannotComplete is never ignored.
- Require one standard window and one current sheet, same signed Apple process, bound window/sheet/ordinary-confirm ancestors, unchanged request owner, exact full current editor field dictionary and title/account identity from the complete preimage.
- Require the existing recoverable wording, one ordinary confirmation button, no permanent-delete button, and no additional editable value in the sheet. Unknown/ambiguous/malformed observations hold.
- Any matching permanent-delete button rejects, including two or more: a unique-button lookup returning nil must never masquerade as absence.
- Two adjacent independently complete frames must meet every guard and refer to the same window, sheet and confirmation button. Changed references or an incomplete frame reset adjacency.
- Observe for at most three seconds and no longer than the original request deadline; inner AX queries use that deadline and a late completed frame cannot pass.
- After the exact current pair succeeds, retire only the earlier transition Boolean; preserve all error counters and direct-action diagnostics. Any new error at or after the final guard still rejects.
- The existing confirmation routine is called once only after the proof. A failed/lost reply remains uncertain; no action replay is introduced.

The isolated actual early `--policy-test` entry shares the dialog witness and independentComplete scope. The report records command and helper SHA, without initializing AppKit, accessing Apple or changing a record. Root alone performs actual acceptance.
