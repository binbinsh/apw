# Deleted cache misses require current inventory proof

Both deletedNote and deletedLocationRead route through selectCategory's equal-count labels cache, then immediately throw item_not_found when the cached title is missing. Unlike readKey, neither path obtains currentCompleteCategoryLabels before declaring absence. A same-count replacement or newly visible post-delete record can therefore be absent from the routing cache while existing in the current list.

Failure list before implementation:

- A missing cached title must cause a fresh independently complete two-frame Deleted inventory scan, not item_not_found.
- The refreshed inventory must replace the routing labels and rebind current rows before selection. The original equal-count and exact fresh row-label proof must remain.
- A single current frame, changed membership/order/count, incomplete discovery, nonempty query, owner/window/category change or positive published count with zero rows cannot prove absence.
- Stable complete current inventory containing one target continues through the original exact-selection and full-body/location proof. It does not itself verify the note body or authorize deletion.
- Stable duplicate target titles still refuse as item_ambiguous. Cached hits retain the original routing and exact row verification gates.
- Refresh only these two miss paths, with no query mutation, recover/delete action, replay or broader authorization.

The isolated early native --policy-test replay exercises the same cache-miss decision and current category witness as the production paths. Root owns live acceptance; this agent performs no Apple operation.

Category transition observation must precede background empty-query clearing. The old navigate → single current context/clear → stable-model-wait order can stop on transient invalid references before reaching the stable-model wait. For a completely observed empty initial query in background and a pending navigation, require the existing two-frame structural category model proof first; then retain the existing clearQuery ready proof. Foreground and nonempty-query order remains unchanged. Unknown initial query cannot enable this route, and partial/changed model frames still fail closed.
