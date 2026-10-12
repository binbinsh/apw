# Direct location proof for a preflighted redundant note

This is a request-order optimization, not a weaker deletion proof. It uses the
actual compiled `batch run --apply` entry point with a temporary synthetic helper;
it does not access Apple Passwords or customer data.

Failures that must remain refused:

- A new or resumed intent whose verified private preimage and successful Deleted
  absence preflight are recorded as `deleted_preflight_absent: true` must never
  request `deleted-read`; requesting the hidden body wastes time and is a failure.
- Deleted location missing, incomplete, ambiguous or inconsistent with the exact
  preimage cannot complete the operation.
- Either independent full keeper state must match the original keeper hash and
  retain the entire candidate body and all source identifiers. A missing first
  read, changed second read or partial state cannot complete the operation.
- The final Active lookup must independently report exact `item_not_found`.
  Presence, timeout or any other error cannot complete the operation.
- A failed post-delete proof remains uncertain and a second CLI invocation may
  only reconcile evidence; it must never replay deletion.
- `false` preflight records and historical records without that field retain the
  existing Deleted-body request. Only the exact `deleted_body_unverified` result
  may take the historical location fallback, and `false` must refuse that fallback.
- No notes, passwords or raw states may appear in CLI stdout/stderr or the public
  report. Location preservation must not claim that the hidden Deleted body was
  verified or that its full content is recoverable.

The repeatable command and stored result are emitted by
`tests/e2e_delete_direct_location.py --bin <compiled-cli> --report <report>`.
