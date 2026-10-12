# Post-delete expected-arrival proof

The real stage log observed a successful recoverable delete followed by the old, internally complete Deleted inventory: raw13, published11, eleven account-shaped rows and zero exact target matches. Both published count and rows still represented the prior inventory, with no invalidUIElement. Current negative frames therefore cannot prove that an acknowledged deletion failed; Apple has not yet published the expected postimage.

Failure list before repair:

- Only deletedNote post-delete verification may wait for expected arrival on a cached miss. deletedLocationRead preflight must keep its present bounded absent semantics.
- Two complete identical old negative inventories continue waiting; they must never return item_not_found or prove absence for this post-delete operation.
- Exact title must appear uniquely in two adjacent independent complete full Deleted frames before selection and the existing body proof. One positive frame, changed membership, interrupted completeness, changed owner/window/category/query or partial inventory cannot authorize continuation.
- Two matching duplicate titles refuse as item_ambiguous. Title prefixes/substrings do not count as an exact label match.
- Wait at most eight seconds, constrained by the remaining request deadline. Every inner row/attribute traversal must use that same earlier deadline. Timeout means deleted_arrival_unverified, not absence, and grants no retry/delete.
- No navigation retry, search write, restoration, repeated deletion or keeper proof bypass is added. The original fresh selected-row binding, full-note/location and keeper protection remains.

Isolated early --policy-test entry uses the same positive-arrival witness as the actual deletedNote wait. Stored report includes exact command/helper SHA and no Apple access. Root performs one bounded real acceptance run; this agent performs no Apple operation.
