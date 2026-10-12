# Apple Passwords browser protocol and REA: static evidence

Date: 2026-10-12. This audit reads only public source and signed system code. It does not read a credential database, send native messages, start a browser, attach a debugger, inject code, re-sign an Apple binary, or alter the Passwords UI.

## Conclusion

The actual upstream apw and installed Apple browser extension do not implement passkey management, shared-group management, ACL management, notes editing, or precise deletion. This conclusion is based on their executable command paths and on the installed native helper's parsed keys and action dispatch, rather than on a README alone.

REA is useful for further static call-graph and Objective-C/Swift analysis. It does not grant Apple private entitlements or make unsupported protocol actions work. Its native UI bridge uses the same Accessibility operations as the current helper; its text action is AXValue, which by itself does not resolve the observed SwiftUI save failure.

## Inputs and reproducibility

- Upstream apw commit: `9f90f011071f68cdb9415ba72ed6f77c67e756a8`.
- REA audited commit: `538f8cc7224dba44b728cf6c000920f911957fc4`.
- Installed helper: `/System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app/Contents/MacOS/PasswordManagerBrowserExtensionHelper`.
- Helper whole-file SHA-256: `adad3611bbb8456715849c8cc05bb8e3ac30bfa5150bf3937db596eb089ebb3a`.
- Binary is universal: x86_64, arm64e, arm64e.x1. Addresses below are the arm64e slice.
- Installed extension examined: `/Users/binbinsh/.apw/extension/background.js`, bounded static string/command extraction only; SHA-256 `8123953b217f8b03cae386dacb59bf082c604437b2735627193fb7e7a724de16`.

The exact disassembly command used was:

```sh
xcrun llvm-objdump --macho --arch=arm64e --disassemble --section=__objc_stubs /System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app/Contents/MacOS/PasswordManagerBrowserExtensionHelper
```

This includes text and Objective-C selector stubs on the installed Xcode toolchain. The method-to-implementation mapping was independently read with:

```sh
otool -arch arm64e -ov /System/Cryptexes/App/System/Library/CoreServices/PasswordManagerBrowserExtensionHelper.app/Contents/MacOS/PasswordManagerBrowserExtensionHelper
```

Relative method metadata names reference `__objc_selrefs`; the selector section starts at `0x100025990` and contains 413 eight-byte references. Objective-C call annotations below are resolved against the actual selector stub loads.

## Actual apw and extension code

[Upstream client.ts](https://github.com/bendews/apw/blob/9f90f011071f68cdb9415ba72ed6f77c67e756a8/src/client.ts) exposes login lookup, password lookup/save, OTP lookup/list, and authentication. Its client/types/browser/daemon sources contain no passkey, sharing, group, ACL, or notes operation.

[Upstream const.ts](https://github.com/bendews/apw/blob/9f90f011071f68cdb9415ba72ed6f77c67e756a8/src/const.ts) declares DELETE and UPDATE enum values. A declaration is not an implemented command; the installed helper's dispatch below establishes the important distinction.

The installed official background.js declares commands 0–19 and 1984. The actual extension command functions use:

- cmd 4: login names for a URL.
- cmd 5: password for login name and URL.
- cmd 6: `ACT:actMaybeAdd` with `URL/USR/PWD` plus `NURL/NUSR/NPWD`.
- cmd 16/17: one-time-code listing/fill.
- cmd 13: open the Passwords UI, optionally using `searchQueryURL`, `newPasswordWithSuggestedURL`, or `setUpTOTPPageURL` plus `setUpTOTPURI`.

Static extraction found no passkey/publicKey/credentialID/relyingParty/sharing/accessControl path. The occurrences of `group` are JavaScript regexp.groups and SRP knownGroup, not password-sharing groups. cmd 18 is declared as SetUpTOTPGenerator, but the extension's implemented setup path sends cmd 13 and opens the system interface.

## Native helper's actual accepted password keys

`AccountStorePasswordsQuery._initWithDictionaryRepresentation:` starts at `0x100002184` and reads exactly these keys:

| Address | Key | Accessor |
|---|---|---|
| `0x1000021b0` | ACT | numberForKey: |
| `0x100002218` | URL | stringForKey: |
| `0x10000224c` | USR | stringForKey: |
| `0x100002280` | PWD | stringForKey: |
| `0x1000022b4` | NURL | stringForKey: |
| `0x1000022e8` | NUSR | stringForKey: |
| `0x10000231c` | NPWD | stringForKey: |

No groupID, ACL, notes, passkey, title, or arbitrary website-array payload is consumed by this password-query parser.

`CommandHandler._handleSetPasswordForLoginNameAndURL:completionHandler:` starts at `0x100006f7c`. Its observed call chain is:

1. `0x100006fd8`: `_validateSMSGUsernameInInputObject:`.
2. `0x100006fe8`: `_decryptedSMSGPayloadInInputObject:`.
3. `0x100007004`: `queryWithDictionaryRepresentation:`.
4. `0x100007018`: `runQuery:`.
5. `0x100007034`: `_responseObjectWithQueryResult:shouldPopulateSensitiveData:shouldAddEnumeratedEntryItems:`.

This is not a generic setter for all fields.

## DELETE and UPDATE are not dispatched as those operations

`AccountStoreQuery._actionFromInteger:` is at `0x100001e40`:

```asm
cmp   x2, #0x6
csinv x0, x2, xzr, lo
ret
```

It accepts integers 0–5 and maps other unsigned values to -1. Acceptance of the integer does not imply implementation.

`AccountStoreQueryRunner._runPasswordsQuery:` at `0x1000029d8` initializes the result to nil, then dispatches:

| ACT | Observed control flow |
|---|---|
| -1 | `_runUnknownQuery:` at call `0x100002a50` |
| 2, 5 | `_runSearchQuery:checkPasswords:` at call `0x100002a3c` |
| 4 | `_runAddOrUpdateQuery:` at call `0x100002a64` |
| 0, 1, 3 | Fall through to `0x100002a70`, return the initialized nil result |

There is no delete route or direct ACT=UPDATE route in this dispatch. Do not send those actions as an experiment against the paired production session.

## groupID is a fixed unshared sentinel

The only groupID selector in the native helper is `saveUser:password:forProtectionSpace:highLevelDomain:groupID:`. Its call inside `_runAddOrUpdateQuery:` at `0x10000361c` has this setup:

```asm
1000035fc: adrp x8, 31
100003600: ldr  x8, [x8, #0x4b0] ; _WBSOngoingSharingGroupIDNone
100003604: ldr  x6, [x8]
100003608: mov  x0, x25
10000360c: mov  x2, x27
100003610: mov  x3, x28
100003614: mov  x4, x24
100003618: mov  x5, x26
10000361c: bl   0x1000159c0 ; saveUser:password:forProtectionSpace:highLevelDomain:groupID:
```

In the Objective-C ARM64 calling convention, x0/x1 are receiver/selector and x2–x6 are this method's five arguments. Thus the groupID argument is loaded from `_WBSOngoingSharingGroupIDNone`, not from the message payload. This browser save path does not select a sharing group or change its membership/ACL.

The update branch constructs `WBSSavedAccountChangeRequest` and calls `setSavedAccount:`, `setUser:`, `setPassword:`, then `changeSavedAccountWithRequest:` at `0x1000033b8`. It does not call a notes/title/group setter. The path includes Apple's add/update confirmation alert methods; it should not be assumed to provide unattended background saving.

## Public APIs and native UI are separate capability domains

The missing extension commands do not imply that Apple's native UI lacks these
features. They do mean that the browser transport cannot claim their operation.
See [the operation-by-operation contract](capabilities.md); all current live
verification and full-readiness flags remain false.

- **Passkeys:** The public
  `ASAuthorizationWebBrowserPublicKeyCredentialManager.platformCredentials(forRelyingParty:)`
  returns authorized relying-party metadata. The installed SDK's
  `ASAuthorizationWebBrowserPlatformPublicKeyCredential` has `name`, `customTitle`,
  `relyingParty`, `credentialID`, `userHandle`, and `providerName`, no key data or
  deletion method. Providers may be third-party. Browser authorization, a real
  WebAuthn challenge and independent identity/readback are different gates; this
  is not all-library access. [Apple's browser passkey guide](https://developer.apple.com/documentation/authenticationservices/authenticating-people-by-using-passkeys-in-browser-apps)
  describes that scope. The [browser entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
  requires genuine browser eligibility and Apple approval; its documented
  application requires an organization Account Holder. Developer enrollment is
  not a grant of unrestricted passkey management.
- **Identity store:** `ASCredentialIdentityStore` is the caller's credential
  provider extension suggestion store, contains no passwords, and cannot inspect
  or delete Apple's vault. [Apple's identity-store documentation](https://developer.apple.com/documentation/authenticationservices/ascredentialidentitystore)
  explicitly limits retrieval to identities saved for that extension.
- **Credential Exchange:** `ASCredentialExportManager` and
  `ASCredentialImportManager` transfer supplied records following user-selected
  app handoff; they do not perform silent background vault CRUD. The SDK's
  `ASImportableCollection` contains linked items/subcollections and no owner,
  participants or permissions. Current apw bundles use `collections: []`.
  Successful decoding or receiver receipt proves neither shared membership nor
  exact merge. Passkey schema support alone is not an implemented apw passkey
  transfer. [Apple export manager](https://developer.apple.com/documentation/authenticationservices/ascredentialexportmanager)
  and [import manager](https://developer.apple.com/documentation/authenticationservices/ascredentialimportmanager).
- **Groups and participants:** Apple's native UI supplies File → New Shared
  Group and group → Manage for owners and member management. The owner controls
  membership/group metadata; members can add/view/edit/delete shared credentials.
  An item can belong to only one shared group. No arbitrary per-member read-only
  ACL is documented. No current apw command implements this UI flow or complete
  participant readback. [macOS 26 group guide](https://support.apple.com/guide/passwords/share-with-a-group-mchlc00a3602/2.0/mac/26)
  and [owner/member roles](https://support.apple.com/guide/personal-safety/manage-shared-password-and-passkeys-ips3ce9f6e15/1.0/web/1.0).
- **SSO and history:** Passwords natively manages Sign in with Apple accounts;
  external Google/etc. provider usernames plus blank passwords/notes are a
  separate source-preservation workaround. Apple's native View History is also
  separate from source historical passwords saved in notes or the existing
  archive. [Apple's native history](https://support.apple.com/guide/passwords/mchl4da98004/2.0/mac/26)
  records versions/dates and sharing events. Neither source representation grants
  native relationship/history CRUD.
- **Settings and export:** The [macOS 26 settings UI](https://support.apple.com/guide/passwords/sfri40599/2.0/mac/26)
  has five documented preferences, distinct from system AutoFill, iCloud sync,
  extensions and apw configuration. A display-title preference can alter a
  title-based identity and must not change during maintenance. [Apple CSV export](https://support.apple.com/guide/passwords/mchl35b12625/2.0/mac/26)
  omits native Sign in with Apple access, Wi-Fi and shared passwords in groups the
  exporter did not create; it cannot prove those migration dispositions. No
  generic file-attachment case is present in `ASImportableCredential`; attachment
  preservation remains a byte-verified restore of the existing encrypted archive.

These are concrete API/UI acceptance targets for future commands, not a claim
that background AX currently implements them. Counts, metadata indicators,
successful action dispatch and offline schema tests must not certify full state.

## REA capabilities and practical limits

[REA Apple analysis documentation](https://github.com/morluto/rea/blob/538f8cc7224dba44b728cf6c000920f911957fc4/docs/apple-application-analysis.md) describes execution-free bundle inventory, plist/signature inspection, and dylib resolution. It explicitly distinguishes inventory hypotheses from actual runtime calls. Deep native pseudocode/call references need Hopper, Ghidra, or IDA. No such engine was found in /Applications or the command PATH during this audit; none was installed or started.

[ReaNativeUI.swift](https://github.com/morluto/rea/blob/538f8cc7224dba44b728cf6c000920f911957fc4/bridge/native/ReaNativeUI.swift) lines 105–107 implement AXPress, AXIncrement/Decrement, and AXValue text entry. It records bounded Accessibility children and validates process/window identity. This can improve selector/path evidence, but AXValue entry alone is the same operation that previously failed to persist a SwiftUI note.

[NativeUiObservation.ts](https://github.com/morluto/rea/blob/538f8cc7224dba44b728cf6c000920f911957fc4/src/native/NativeUiObservation.ts) states it admits only an explicitly selected, already-running window, does not change foreground applications, and has no global input fallback. Stale/ambiguous paths fail.

[LldbCallTracer.ts](https://github.com/morluto/rea/blob/538f8cc7224dba44b728cf6c000920f911957fc4/src/native/LldbCallTracer.ts) states hardened-runtime targets need `com.apple.security.get-task-allow` for debugging. REA is not an entitlement or SIP bypass. Both Apple Passwords and this Apple helper have private keychain expansion/sharing entitlements and Apple access groups; ordinary developer signing does not provide those groups.

## Shortest useful next step

1. Keep the paired browser backend for its proven website-login and OTP reads. Preserve unknown metadata rather than dropping it, but do not infer unsupported mutations from metadata.
2. Fix AX note persistence and recoverable exact deletion, with one saved original state and one synthetic entry per trial. REA's bounded child snapshots can inform stable role/identifier lookup; no dependency installation is required to reuse the existing native helper approach.
3. Use official Credential Exchange for credential migration, with explicit Apple receiver choice and independent readback. The public export/import managers do not provide silent whole-vault edits.
4. Further static REA work is warranted only for a concrete unresolved selector/call graph, not an open-ended search for an assumed whole-vault API. No new protocol mutation was identified by this audit.

If another real protocol handler is discovered later, first document its exact consumed keys and action dispatch; create a `.invalid` synthetic fixture; take a full before snapshot; issue the operation once; read back every original field; verify session health and reversible behavior. Do not probe cmd 14, action DELETE, or any unproven command against the production paired session.
