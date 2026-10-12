# Read-only synthetic note backing diagnosis

Specification written before implementation. Extend the existing hash-bound,
synthetic-only `item probe-notes` entry point. Do not add a write capability.

The diagnostic fails closed if the original complete state, process, window,
owner lease or unique NotesField changes. It must cancel its own unchanged
editor and independently reread the original state, using the existing probe.
Attribute acknowledgements never establish an input receiver or persisted text.

Report only integer AX return codes, strict booleans, bounded relationship
counts, and a fixed whitelist of parameterized attribute names. Never print
text, arbitrary attribute names, identifiers, titles, users or child values.
Missing or unsupported text backing is distinct from a successful empty value.
Compare the field's exact UTF-16 value with AXNumberOfCharacters and
AXStringForRange. Shared text/focus arrays are optional read-only observations,
not permission to send input or a claim that any element is first responder.

The compiled CLI boundary test must reject malformed nested schemas, unknown
keys/names, strings posing as booleans and unbounded counts. Real acceptance
requires one complete synthetic probe with original-state preservation. No
foreground activation, focus setter, keyboard event, export or import is used.
