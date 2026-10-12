# Collision-safe accessibility identity traversal

The actual readonly collision comparison `hash-collisions-result.json` found distinct AX elements with equal CFHash and CFEqual false. In particular, the toolbar collided with an earlier static node. The CFHash-only visited set silently omitted that toolbar and SearchField while reporting a complete traversal. This is an identity defect; it is not proof that Passwords locked.

Failure list before implementation:

- Different CFEqual identities sharing one CFHash must both be visited, including a child subtree containing the search/toolbar.
- Equal elements reached through repeated references or cycles must remain deduplicated. Ancestry/child cycle guards must retain their current rejection behavior.
- The visited count must count distinct elements, not hash buckets; existing node, row, child, depth and deadline bounds must remain in force.
- nodes, rowValues, notesProbeAncestorBound, notesProbeBoundInternalFocus and notesProbeChildren must all use collision-safe identity.
- CFHash is a routing hint only. Within each hash bucket, CFEqual determines whether an element was previously visited.
- This fix adds no actions, focus changes or error suppression. Current invalidUIElement remains incomplete and cannot authorize writes/deletion.

The isolated native early-entry replay must use the same identity registry as the real walkers. Graph identities and hashes are synthetic integers, not AX values. It runs through --policy-test before AppKit initialization; stored report includes command, helper SHA, no Apple access and no modified credentials. Root owns any actual Apple acceptance run.
