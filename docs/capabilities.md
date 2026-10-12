# Apple Passwords capability and acceptance contract

`apw capabilities` reports implementation coverage without opening an app,
contacting the paired daemon, requesting authentication, exporting credentials,
or changing records. It is an audit of this build, not a test of the current
Apple Passwords library. A code path, successful JSON encoding, or a successful
mock test is not evidence that Apple saved a field.

## Failure specification (written before the capability implementation)

The feature fails if any of these happens:

1. The report requires a running browser, native helper, unlocked app, or daemon.
2. Reporting capabilities opens a window, asks for authentication, or writes data.
3. A field or setting is absent from the coverage matrix and is silently treated
   as supported.
4. `implemented` is treated as `live_verified`, or an offline/mock result is
   described as an Apple readback.
5. An operation claims live verification without a repeatable Apple evidence
   artifact for that operation and the current implementation.
6. Reading a username, generated OTP, count, or indicator is described as reading
   a password, TOTP seed, passkey, group membership, or complete record.
7. A null/unavailable password is normalized to an empty password.
8. A same-title/account match is accepted when more than one native item matches.
9. `MAYBE_ADD` or a receiver's import result is described as a precise update or
   delete of an identified existing item.
10. A CSV is described as a complete export, including passkeys, TOTP seeds,
    attachments, shared permissions, and unsupported source fields.
11. A credential-exchange codec check is described as successful receiving,
    merging, or preserving existing Apple records.
12. Personal collection names are implemented as shared groups without checking
    whether sharing is intended; moving a credential changes who can access it.
13. A recoverable item delete is confused with deleting a single field or with
    permanent deletion.
14. Customer deduplication is enabled before complete retained-state readback,
    target uniqueness, note persistence, and recoverable deletion are proved.
15. A count-only passkey/attachment/group comparison passes the migration gate.
16. A capability report leaks credentials or source library contents.
17. A reachable external-SSO placeholder path contradicts its operation row, or
    that placeholder is described as recreating native Sign in with Apple access.
18. Source password-history preservation is described as reading Apple's native
    View History or as permission to clear it.
19. An `app-settings` umbrella hides unobserved preferences or treats apw's browser
    configuration as Apple's AutoFill, iCloud sync, or extension settings.
20. Credential Exchange collections are described as shared-group participants,
    permissions, or proof of actual Apple group placement.
21. Group permissions imply arbitrary read-only/editor ACLs instead of Apple's
    owner/member model, or a group count is used to certify the participant set.
22. An approved-browser relying-party passkey query is described as whole-vault
    access, key export, exact item deletion, or a privilege of developer enrollment.

## Report schema

The command outputs one JSON object. All capability judgments are static in this
command; live evidence is reported only when a specific recorded acceptance run
exists. No setting is toggled while producing the report.

```json
{
  "format": "apw-capabilities-v1",
  "source": "static-implementation-audit",
  "full_library_api": false,
  "all_fields_and_settings_ready": false,
  "safe_for_customer_deduplication": false,
  "coverage": { "feature_count": 37, "operation_count": 148 },
  "features": [{
    "id": "notes",
    "apple_support": "native",
    "operations": {
      "read": {
        "implemented": true,
        "live_verified": false,
        "evidence": "code",
        "mechanism": "accessibility",
        "person_interaction": ["unlock"],
        "limitation": "Exact uniquely identified items only."
      },
      "create": {
        "implemented": true,
        "live_verified": false,
        "evidence": "offline-e2e",
        "mechanism": "credential-exchange",
        "person_interaction": ["receiver-selection"],
        "limitation": "Receiver acceptance and readback are separate gates."
      },
      "update": {
        "implemented": true,
        "live_verified": false,
        "evidence": "offline-e2e",
        "mechanism": "accessibility",
        "person_interaction": ["unlock"],
        "limitation": "The current native save path requires Apple acceptance."
      },
      "delete": {
        "implemented": false,
        "live_verified": false,
        "evidence": "none",
        "mechanism": "unavailable",
        "person_interaction": [],
        "limitation": "Dropping existing note content is deliberately refused."
      }
    }
  }]
}
```

Every feature has all four operation keys, including operations that are not
applicable. `implemented` describes a reachable command with that meaning, not
the presence of a matching protocol enum. `live_verified` may be true only with
`evidence: "apple-readback"` and an `evidence_artifact` naming the stored command
and exact independent result. A historical test of a different implementation
does not certify this build. An empty `person_interaction` array means no personal
interaction for that particular operation; it does not mean Apple authentication
can be bypassed.

The original feature IDs and operation fields remain compatible. The existing
`sso` ID is specifically the external-provider placeholder workaround, and
`password-history` is source historical-password preservation. Native
`sign-in-with-apple` and `native-password-history` are separate rows. Each
`available_paths` entry names an `operation` that is implemented in that feature;
its scope remains narrower than a generic Apple item mutation. All current live
verification fields and readiness flags remain false.

Allowed evidence levels are `none`, `code`, `offline-e2e`, and `apple-readback`.
Mechanisms are `extension`, `credential-exchange`, `accessibility`, `manual`,
`local`, and `unavailable`. Apple support is `native`, `workaround`, or `unknown`.
The report must not describe any of those mechanisms as an unrestricted public
Apple Passwords developer API.

## Coverage matrix

The matrix describes current scope from the checked-in CLI and native transport.
“Read” below must be interpreted literally; an indicator is not a credential
export. Exact update/delete requires a uniquely identified record and a verified
preimage. An import acknowledgment is insufficient.

| ID | Apple field or function | apw read | apw create / update / delete | Required Apple acceptance |
| --- | --- | --- | --- | --- |
| `title` | Native item title | URL metadata or exact AX detail | Exchange creates titles; no precise title update/delete | Exact Unicode title and account; duplicate-title ambiguity must stop |
| `account` | Username / account | Extension and exact AX detail | Extension/exchange create; `MAYBE_ADD` is not precise account replacement | Explicit empty account distinguished from unavailable; case and Unicode preserved |
| `password` | Login password, including empty password | Selected extension retrieval or complete AX edit state | Extension/exchange create; exact existing replacement/delete not provided by maintenance | Exact bytes including empty string; unavailable/null must stop; Apple personal authentication may be required |
| `websites` | All associated websites | Extension list and exact AX state | Exchange stages all sites; no precise existing site-list update/delete | Every website retained, no accidental URL loss; receiver's multisite behavior verified independently |
| `notes` | Complete item notes | Exact AX state; extension metadata is insufficient | Exchange creates; in-place AX update experimental; removal of existing body refused | Save, close, reopen and read the complete body; all other fields unchanged |
| `otp` | TOTP verification codes | Extension lists/fills generated codes; no seed export | Exchange stages reviewed TOTP additions; no precise seed replacement/delete | Account/site association and actual time-window code match; original password/sites unchanged |
| `passkeys` | Passkeys | Maintenance may observe an indicator; no full passkey inventory | No apw passkey transfer, update, or deletion command | Match relying party, user identity and credential identity using a suitable Apple/source path; counts alone fail |
| `groups` | Group inventory and item membership | No full command | No create/rename/move/remove command | Read complete member sets and item placement; distinguish personal organization from actual sharing |
| `sharing` | Shared-group participants and permissions | AX may report unshared/unknown; not full ACLs | No sharing-management command | Exact participants, ownership/permissions and affected item scope; never infer from group count |
| `wifi` | Saved Wi-Fi passwords | No apw Wi-Fi command | No command | SSID/security/password and sharing policy need an independently supported path |
| `sso` | Source “Sign in with…” association | No first-class provider relationship in maintenance | Account + empty password + explanatory notes is a workaround | Preserve actual provider and provider account; blank password must be read back explicitly |
| `sign-in-with-apple` | Native Apple Account/service relationship | No apw inventory command | No native relationship CRUD command; a placeholder cannot recreate native access | Match actual app/service and Apple Account relationship, any forwarding metadata and sharing placement; verify continued sign-in |
| `custom-fields` | Source labeled or concealed fields | Apple has no matching general source-field schema here | Preserve field label, type and complete value in the retained item's notes | Full source-linked body equality; do not create one duplicate login per field |
| `tags` | Source tags | No native tag command | Retain source tags in notes; no tag CRUD | Exact tags and source references retained without affecting autofill or sharing |
| `attachments` | Source file attachments | No Apple Passwords attachment command | No attachment CRUD; use the existing encrypted archive | Restore every file and verify bytes, paths and source ID; a note containing a filename is insufficient |
| `password-history` | Source historical passwords | No history export command | Preserve source history in notes or the existing encrypted archive when required | Distinguish current primary password from historical values; do not overwrite a newer Apple password |
| `native-password-history` | Apple's own prior-password and sharing history | No apw View History reader | No clear-history command | Independently inspect native versions/dates and sharing events; source history in notes does not replace this history |
| `source-vaults` | Source vault ownership / classification | No Apple vault mapping command | Retain source vault ID/name in notes; sharing is a separate decision | Source item identity and provenance retained; personal vaults must not become unintended shared access |
| `security` | Compromised / reused / weak password state | No full security-report command | Apple-generated state is not a source field; no alert CRUD | Apple own result can be inspected; importing source alert text does not set Apple's security state |
| `autofill` | Autofill provider and item applicability | No Apple system-settings reader | No provider or autofill-setting writer | Correct site/account availability and chosen provider; passkeys must remain usable |
| `app-settings` | Passwords preferences and system integration | No complete settings inventory | No preferences CRUD | Inventory settings on the installed OS; distinguish apw browser settings from Apple settings |
| `preference-account-display` | Company titles versus URLs | No reader | No writer | Read exact setting; displayed-title identity may change, so do not toggle during bound maintenance |
| `preference-menu-bar` | Show Passwords in Menu Bar | No reader | No writer | Independently read the installed OS preference and resulting menu-bar state |
| `preference-compromised-detection` | Detect Compromised Passwords | No reader | No writer | A security alert is not proof of the preference value |
| `preference-strong-passwords` | Suggest Strong Passwords | No reader | No writer | Website lookup does not prove Safari's suggestion setting |
| `preference-auto-passkeys` | Automatically Create Passkeys | No reader | No writer | Passkey schema/browser registration support does not prove the preference value |
| `autofill-provider-settings` | System Password AutoFill provider selection | No reader | No writer | Exact selected providers and real site/account availability; apw configuration is separate |
| `icloud-passwords-sync` | iCloud Passwords/Keychain sync | No reader | No writer | Actual sync enablement and propagation; local presence alone is insufficient |
| `browser-extension-settings` | Apple browser-extension enablement and permissions | No complete reader | No complete writer | Distinguish user browser integrations from an isolated paired apw browser session |
| `recoverable-delete` | Move an item to Recently Deleted | Exact retained/deleted placement is experimental | Only proven redundant unshared credential-free notes; ordinary login deletion unsupported | Confirm full candidate body in Recently Deleted and full keeper state after deletion |
| `permanent-delete` | Irrecoverable deletion | No command | Deliberately unsupported | Never used to complete migration deduplication |
| `library-inventory` | Enumerate the whole library with stable identities | No complete stable-ID API | No full-library CRUD | Include every item kind and group; a bounded URL search is not whole-library enumeration |
| `import` | Data import | No generic importer readback | Reviewed official exchange batches; receiver selection required | Per-field independent Apple readback; partial receiver errors are failures, not success |
| `export` | Data export | Targeted maintenance snapshots, not a complete export | No complete apw exporter | Apple CSV has a limited schema; unavailable passkeys/OTP seeds/group data cannot be inferred |
| `comparison` | Field-aware migration comparison | Targeted snapshots and preimage hashes | No complete library-wide comparison command | Complete source-to-retained mapping; exact secrets and extra-field equality; provenance supports split/merge |
| `deduplication` | Merge normal duplicate logins | No normal duplicate-login operation | Not implemented; maintenance only handles proven redundant blank-credential notes | Stable target distinction plus union of sites/notes/OTP/passkeys/sharing; retain differing primary versions |
| `batch-maintenance` | Bounded read / verified notes / recoverable cleanup | Up to 50 explicit targets per invocation | Plans, locks, fsynced intent and readback checkpoints; current Apple mutation gate remains unverified | One existing synthetic acceptance run must prove save/delete/resume without frontend activation or lost data |

## Public API and settings boundaries

Apple's native Sign in with Apple accounts already appear in Passwords and can
be shared with a group. The external-provider `sso` workaround proposes a
reviewed provider username, explicitly empty password and provider notes through
the existing exchange command; it does not create an Apple or Google federation
relationship. Import receiver choice and full independent readback are required.
See [Apple's macOS 26 sharing guide](https://support.apple.com/guide/passwords/share-with-a-group-mchlc00a3602/2.0/mac/26).

Shared groups have an owner/member permission model. The owner alone can add or
remove people, rename or delete the group. Members can add, view, edit and delete
shared credentials, and can leave. No per-member read-only setting is documented.
An item belongs to at most one shared group. Before moving an item, read the
complete accepted/pending participant set, role and actual item placement; for
personal organization, verify there are no other participants. A collection name
or AX `unshared/unknown` is not that proof. Current exchange bundles use
`collections: []`; even populated `ASImportableCollection` objects contain no
owner/member ACL and do not prove receiver group placement. See [group management](https://support.apple.com/guide/passwords/mchl6a796d86/mac)
and [Apple's permission roles](https://support.apple.com/guide/personal-safety/manage-shared-password-and-passkeys-ips3ce9f6e15/1.0/web/1.0).

An eligible browser can request passkey authorization and call
`ASAuthorizationWebBrowserPublicKeyCredentialManager.platformCredentials(forRelyingParty:)`
for metadata such as credential ID, user handle, relying party, account name and
provider. This may include third-party providers; it returns no key data and is
not all-library inventory, transfer, merge or deletion. Genuine registration and
assertion require the site's WebAuthn flow and Apple authentication. The
[browser entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
requires Apple's approval and browser eligibility; its documented application
requires an organization Account Holder. Xcode login alone is insufficient.
[ASCredentialIdentityStore](https://developer.apple.com/documentation/authenticationservices/ascredentialidentitystore)
holds the calling provider extension's suggestion metadata, not Apple's vault.

Apple's [macOS 26 settings guide](https://support.apple.com/guide/passwords/sfri40599/2.0/mac/26)
lists the five preferences represented above. Actual settings coverage must be
versioned to the installed OS and include observed values, implemented readers
and writers, and saved live results. Unknown and OS-inapplicable remain explicit.
System AutoFill, iCloud sync and browser-extension settings are separate domains;
they are not established by apw pairing or browser configuration.

[Apple's native View History](https://support.apple.com/guide/passwords/mchl4da98004/2.0/mac/26)
includes prior versions/dates and sharing events. Preserved source history is a
different domain; migration cleanup does not clear native history.
[Apple CSV export](https://support.apple.com/guide/passwords/mchl35b12625/2.0/mac/26)
also omits Wi-Fi, native Sign in with Apple access and passwords in groups the
exporter did not create. CSV comparison cannot certify those classes, passkeys,
TOTP seeds or sharing permissions. Restore and compare every attachment from the
existing encrypted archive; a filename or an archive's existence is insufficient.

## Migration and cleanup gates

The command must report the current incomplete state, not mark the migration
ready merely because the matrix exists. Ordinary duplicate logins and the
source-linked “资料” records are different cleanup categories. The latter can be
removed only after their full extra-field body is proved present in a retained
record. A note-bearing login cannot be removed by the blank-note-only operation.

Before customer writes, the native path must pass one saved synthetic trial:
exact read → append complete existing note → save → reopen and read exact state
→ recoverably delete the now-redundant synthetic note → prove its deleted
placement/body and keeper's unchanged credentials. A missed response is resolved
through the existing read-only journal review/resume path, never a fresh import.

Before retiring 1Password, every source item must have a retained identity and a
full field mapping, including any split/merged target records; passkey identities,
all attachment restore results, personal/shared memberships, and ordinary
duplicate-login dispositions must be proved. Existing exports are reused. A
settings capability audit is necessary for honest tool coverage, but cannot
replace item-by-item data acceptance.

## Repeatable offline acceptance

The capability E2E invokes the actual compiled CLI in an isolated private data
directory, with a native-helper sentinel and a synthetic local socket sentinel.
It contacts no real library. It validates the JSON truthfulness contract and
captures the exact command plus a stored report. It cannot certify Apple field
read/write behavior.

```sh
python3 tests/e2e_capabilities.py --bin ./dist/apw --report ./reports/capabilities-e2e.json
```
