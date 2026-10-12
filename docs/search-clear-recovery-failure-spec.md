# Bounded search-model recovery failure specification

The isolated seam is the native helper's existing early `--policy-test` entry.
It runs before AppKit/process inspection and shares the recovery decision and
clear-caption policy with the live clear path. It does not prove Apple accepts
an AX operation. Live verification remains one query-only recovery attempt and
two independently complete restored model frames, followed by the existing full
index and exact record proof. It never authorizes a credential edit or deletion.

Fail closed for each of these cases:

1. Incomplete search/context, unknown/changed owner, category mismatch, duplicate
   search fields, or an unbound search field/window.
2. Attribute/capability observation returns an error rather than a complete
   positive result. Unknown `AXClearButton` availability cannot become absence.
3. A semantic `AXClearButton` is disabled, foreign, outside the exact SearchField,
   lacks AXPress, or fails to retain the same element across two complete frames.
4. A generic Search button, magnifier, empty caption, or unrecognized localized
   caption is mistaken for a Clear/Cancel action.
5. Addressed SelectedText is supported: retain the existing preferred path,
   rather than additionally changing AXValue.
6. Without a usable clear action, AXValue is not positively writable, or selected
   text capability codes are incomplete.
7. A single synthetic sentinel setter fails, its fresh value differs, or fresh
   observations fail to settle to the same complete SearchField/button identity.
8. After the sentinel, the positively bound semantic `AXClearButton` is preferred.
   Only its explicit `noValue` result allows one AXValue-empty submission;
   unsupported/unknown errors, invalid elements or a refused Clear never allow
   that fallback. Captions alone never authorize a new recovery button press.
9. The action acknowledgement or visible empty value is treated as successful
   model recovery. Only the existing two-frame `clear_model` witness can finish.
10. Raw AXRows remain zero while the published category count is positive; an
    unknown cache, a stale reference, a partial list, or AXVisibleRows substitutes
    for a complete unfiltered index.
11. A failed recovery clears the dirty flag, retains filtered index authority,
    retries/falls back after an attempted action, or triggers another delete.
12. Recovery activates/focuses/raises the app, injects keys, restarts the app,
    changes preferences/auto-lock, uses an unbounded wait, or logs query/record
    contents. At most one sentinel and one clear action/empty setter are allowed.

Safe diagnostics contain only fixed method/failure enums, booleans, AX error
codes, and bounded counts. Every isolated run stores its exact command and
helper SHA with `apple_accessed=false` and zero customer-record modifications.
