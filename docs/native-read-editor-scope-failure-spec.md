# Complete editor scope versus prior transition errors

Static finding in read(): completeDiscovery's independentComplete restores the preexisting nativeObservationIncomplete flag. The editor poll can therefore observe a complete editable TitleField and Cancel frame (`opened=true`) and immediately fail `guard opened,!nativeObservationIncomplete` because an earlier discovery or UI transition marked the outer flag. The same flag is read later by snapshot(). SDK AXError -25202 is invalidUIElement; it must never be recategorized as optional noValue (-25212).

The live aggregate failure stage and four -25202 counts do not distinguish `opened=false` from `opened=true` with a stale prior flag. Do not claim that this code defect explains that live failure until those structural observations are available. No Apple or fixture runtime was invoked for this finding.

Failure list before a repair:

- Prior invalidUIElement plus a fully independent complete current editor must not be rejected solely by the restored outer flag. Preserve the old error counts for diagnostics.
- invalidUIElement/cannotComplete/illegalArgument during the current editor scope must reject that frame and break consecutive-frame stability; do not ignore it or reset it halfway through a frame.
- TitleField/Cancel presence alone is not a complete credential observation. Require current unique editable Title/User/Password/Notes, owner/window identity, sites/sharing/verification/passkey/extra-field observation and canonical snapshot completeness in the same fresh scope.
- Snapshot work must remain inside that complete scope, or it will read the restored stale outer flag and repeat the failure. Removing only the guard is not a complete repair.
- Changed editor fields, title/account mismatch, changed selected identity/index, owner/window change, unknown or incomplete field discovery refuse before any cancellation/write/delete authorization.
- Require two adjacent independent complete canonical editor observations where later maintenance relies on a stable whole state; partial or different frames reset the pair. No failure fallback may substitute old NativeRead metadata.
- Keep exact row/query/index selection gates intact; this repair does not grant a current-cohort shortcut.
- An opened but incomplete editor requires the existing complete expected-state recovery protocol; do not blindly Cancel it or clear ownership bookkeeping.

Suggested first safe diagnostics: opened Boolean, prior_incomplete Boolean at editor observation entry, complete_editor_frames count, current_editor_frame_complete Boolean. No values or actual identifiers. Suggested native replay RED case: prior=true, current complete=true must return a verified current observation and preserve prior diagnostics, while current invalidUIElement must hold even if Title/Cancel are present. Exercise through an early native entry shared with the actual frame scope, before AppKit/Apple initialization. Then integrate a fresh whole-editor/canonical-snapshot scope, not a global flag reset.

A successful terminal read retires the old incomplete phase flag only after the complete current canonical snapshot and exact native title/account checks. Diagnostic error counts remain. Every later Cancel/dialog/delete error is a new phase and must set incomplete again; a failed current observation cannot retire history. Cancel must not query an obsolete list row solely for diagnostics inside its current editor scope.
