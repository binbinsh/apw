# Batch inspect failure position, without partial secret output

This change is observability only. It adds no recovery, replay, checkpoint storage, native operations or partial snapshot format.

Failure list before code:

- A failed first read must expose `diagnostics.target_index=1`, `completed_reads=0`. A failed third read after two complete states must expose `3` and `2`. Native-reported indices, strings or attacker-provided fields cannot replace these locally computed numbers.
- Metadata/body/credential failures and invalid protocol replies must preserve a safe fixed maintenance error plus the position. Known filtered structural native diagnostics remain available; title, username, key, notes, password, sites, query and unknown error text must never enter public output.
- A completed read means the full native State and its hash were accepted; a partial, null or invalid state does not increase `completed_reads`.
- Stop at the first failure. No following target is read, and no target is retried. Native cleanup is the existing bounded close only.
- Failure must leave the reserved private snapshot empty: buffered successful items are not written as a partial snapshot or printed. Success keeps the existing `apw-item-snapshots-v1` complete-item schema and private file permissions.
- Input/output validation errors before target dispatch must not invent a target index. All fields are derived from the validated, bounded local array (at most 50).

E2E invokes the compiled CLI `batch inspect` through an isolated synthetic helper, with first/third/protocol/state failures and normal success. Exact entry commands and a stored result report make the result repeatable. No Apple, window, browser, export/import or customer journal is accessed.
