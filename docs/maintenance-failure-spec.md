# Maintenance failure specification (written before implementation)

The real CLI is tested with an isolated synthetic native-helper process. That
boundary test does not prove Apple's live UI supports an operation. A signed
macOS helper performs live reads and mutations without activation or key events.

Fail closed when:
- The plan is malformed, has duplicate operation IDs, has unsafe file permissions,
  or the journal belongs to another plan. No mutation happens in validation mode.
- Title/account selects zero or multiple native records. Titles are not native IDs.
- A required field is unreadable (null is never an empty password).
- A before-state hash changes, or notes content to preserve is missing.
- A deletion candidate has credentials, sites, an OTP, a passkey, unknown fields,
  unknown sharing, or content absent from the separately verified keeper.
- Notes editing changes any field other than NotesField, including sites/password.
- A save/deletion acknowledgement is missing, late, or followed by bad readback.
  Do not retry a mutation automatically. Persist intent before dispatch.
- A process dies after intent but before done. Resume must verify only and stop
  when the outcome cannot be established; no second write.
- Two runs compete for the same journal. Only one process may execute.
- A completed checkpoint is resumed. Readback verifies it; no repeat mutation.
- Apple is locked, Accessibility access is unavailable, a user editor or sheet is
  already open, the list is filtered, or a native observation is incomplete.
- The UI owner changes during an operation. Do not activate, focus, send keyboard
  or mouse events, or retain an editor indefinitely. Background execution stops
  if the user starts interacting with Passwords.
- A destructive confirmation is ambiguous or permanent. Only ordinary recoverable
  deletion followed by exact matching in Recently Deleted is permitted.
- App/version/schema is unsupported. Report the limitation rather than guessing
  protocol commands or treating a DELETE enum as a supported Apple API.

No native read/write may print secrets to stdout or copy them to the clipboard.
Snapshots/plans are temporary private files, not an additional credential vault.

Readiness diagnostics must distinguish a locked window, an already open editor,
an unsupported window and incomplete Accessibility observations. They may expose
only structure, standard action names and attribute writability, never field
values. An open user editor must not be cancelled to make a diagnostic succeed.
