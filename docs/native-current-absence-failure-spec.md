# Current full-index absence and background routing

Isolation is necessary because reproducing a cloud inventory exchange against
Apple Passwords would alter real data. The agreed seam is the native helper's
early `--policy-test`, before AppKit/process access. Fixture labels are synthetic.
The same strategy and complete-index reducer must guard production `readKey`.
These checks verify the local lifecycle contract, not Apple acceptance.

The source's legacy counterexample is a cached two-row inventory without the
requested title and a current two-row inventory containing it. `selectCategory`
reuses the cached labels because counts match; the old `readKey` then throws
`item_not_found`. Equal counts do not establish equal membership.

Failures to guard before implementation:

1. A cached miss, even with identical current raw row count, proves absence.
2. A single fresh frame, partial scan, stale/invalid AX row, incomplete required
   attribute, missing label array, or fewer labels than rows proves absence.
3. A filtered query, wrong category, unknown/changed owner, foreign process,
   ambiguous window, or list/search not bound to the same window is accepted.
4. Two full scans with the same count but different labels/order are considered
   the same generation. Any incomplete or mismatched intermediate frame must
   reset the consecutive pair.
5. A zero-row list with positive or unknown published inventory is called an
   empty library. Only a complete empty current model with published count zero
   can prove an empty inventory; cached count zero is not evidence.
6. A target found in the current stable full inventory is still reported absent
   because it was missing from the cache. Refresh routing and use the existing
   exact row/full editor checks; this proof grants no extra write permission.
7. A cached positive match skips fresh row/field identity checks. Existing
   identity and preimage checks must remain unchanged.
8. A prior incomplete frame poisons a later independent full pair, or independent
   scanning erases the outer request's earlier incomplete status.
9. A background read chooses SelectedText or AXValue search when supported,
   writes a random sentinel, or mutates a user search to recover an empty model.
   Background always routes through the complete unfiltered index.
10. A background initial model that is filtered, dirty without positive full
    model proof, zero with positive inventory, incomplete, or unbound attempts
    a search setter/action instead of holding. A normal complete readable All
    initial state must use the index without any search mutation.
11. A failure is converted to `item_not_found` without a complete stable current
    inventory. It must remain a distinct failure requiring review.
12. New permission to delete/replace records, activate/focus/raise windows,
    inject input, re-export, or inspect real journals appears in this repair.
13. A new helper's empty local `currentCategory` causes an unnecessary press of
    All even though an independent complete actual category observation already
    proves All. Cached category is routing state, not navigation authority.
14. Unknown or incomplete category evidence triggers navigation. Only complete
    explicitly false actual evidence can select the requested category; true
    evidence binds the local category without a press.
15. After actual navigation, a single header match starts scanning old rows
    while the list reloads. Require two independent complete structural frames
    with unchanged category, empty query, permitted owner, exact same bound
    window/search/list/row references and row order before building the index.
16. A full label scan accepts a retained row array after the current model has
    changed. Reacquire the full context, query, window and rows after scanning;
    replacement, reordering, category changes or incomplete AX access refuse.
    A same-count replacement must fail even when all retained labels are read.
17. A positive raw count in the wrong or unbound model passes a structural pair.
    Zero with positive/unknown published inventory still fails; incomplete
    intermediate observations reset the consecutive structural pair.
18. An arbitrary local 20-second limit prevents a second complete current scan
    even though the existing 90-second request deadline has not expired. Fresh
    absence scans use that existing request deadline, with no new timeout or
    incomplete-index permission. Isolation checks the proof policies; actual
    large-library latency remains a separate live observation.

Reports store the exact rerunnable command, helper hash, deterministic literal
expectations and `apple_accessed=false`. No actual row labels or secrets are
printed by the production verifier.
