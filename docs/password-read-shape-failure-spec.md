# Password value verification failure specification

Written before implementation. Exercise the real CLI against an isolated local
synthetic daemon. Do not contact Apple or request a real password.

1. A matching account/site with missing, null, numeric, object, or array PWD must
   fail with `apple_password_value_unavailable`. It must not look like a verified
   empty password or a successful credential read.
2. The existing `Not Included` transport sentinel cannot certify a password.
3. An explicitly returned empty string is a valid empty password. Unicode,
   leading/trailing whitespace and newlines must remain exact.
4. A malformed password on a different account or site must not invalidate the
   requested matching credential. No results remains distinct from unavailable
   password data on a matching result.
5. An unavailable password must not be printed in stdout, leaked through an
   error payload, normalized, fetched again automatically, or trigger a write,
   startup, pairing or UI operation. One metadata and one fill request maximum.
6. Every run saves its exact repeatable command and result. Synthetic transport
   acceptance does not establish Apple password access or full field coverage.
