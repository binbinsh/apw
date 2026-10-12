// SPDX-License-Identifier: GPL-3.0-only
// Static coverage only. This command must never touch a credential backend.
import { VERSION } from "./const.ts";

type Mechanism = "extension" | "credential-exchange" | "accessibility" | "manual" | "local" | "unavailable";
type Operation = {
  implemented: boolean;
  live_verified: false;
  evidence: "none" | "code" | "offline-e2e";
  mechanism: Mechanism;
  person_interaction: string[];
  limitation: string;
};
type Operations = { read: Operation; create: Operation; update: Operation; delete: Operation };
const unavailable = (limitation: string): Operation => ({
  implemented: false, live_verified: false, evidence: "none", mechanism: "unavailable",
  person_interaction: [], limitation,
});
const path = (mechanism: Mechanism, limitation: string, person: string[] = [], tested = false): Operation => ({
  implemented: true, live_verified: false, evidence: tested ? "offline-e2e" : "code",
  mechanism, person_interaction: person, limitation,
});
const exchange = (limitation: string) => path("credential-exchange", limitation, ["unlock", "receiver-selection"], true);
const native = (limitation: string) => path("accessibility", limitation, ["unlock"], true);
const protocol = (limitation: string) => path("extension", limitation, ["pairing", "apple-authentication"]);
const absent = (limitation: string): Operations => ({
  read: unavailable(limitation), create: unavailable(limitation),
  update: unavailable(limitation), delete: unavailable(limitation),
});
const field = (id: string, apple_support: "native" | "workaround" | "unknown", operations: Partial<Operations>, reason: string) => ({
  id, apple_support, operations: { ...absent(reason), ...operations },
});
const availablePaths: Record<string, { command: string; operation: keyof Operations; mechanism: Mechanism; scope: string }[]> = {
  title: [{ command: "pw list", operation: "read", mechanism: "extension", scope: "Optional customTitle by website; neither whole-library inventory nor stable identity." }],
  account: [
    { command: "pw list", operation: "read", mechanism: "extension", scope: "Website-scoped USR account metadata." },
    { command: "pw save", operation: "create", mechanism: "extension", scope: "MAYBE_ADD login proposal; no exact duplicate-record update guarantee." },
  ],
  password: [
    { command: "item read", operation: "read", mechanism: "accessibility", scope: "Exact unique native complete-state read; explicitly empty is distinct from unavailable." },
    { command: "pw save", operation: "create", mechanism: "extension", scope: "MAYBE_ADD login proposal with password on stdin; independently validate resulting state." },
  ],
  websites: [{ command: "pw list", operation: "read", mechanism: "extension", scope: "All sites returned for a website-scoped login; no precise site-list replacement." }],
  sso: [{ command: "exchange credentials-prepare / credentials-import", operation: "create", mechanism: "credential-exchange", scope: "External-provider placeholder proposal: source provider account, explicitly empty password and provider notes. Receiver selection and independent readback required; no first-class SSO relationship." }],
};
const permissionModel = {
  roles: ["owner", "member"],
  owner_only: ["add-members", "remove-members", "rename-group", "delete-group"],
  all_members: ["add-items", "view-items", "edit-items", "delete-items"],
  members_can_leave: true,
  per_member_read_only_supported: false,
};
const featureDetails: Record<string, Record<string, unknown>> = {
  sso: { scope: "external-provider-placeholder", native_relationship_recreated: false },
  "sign-in-with-apple": { scope: "native-apple-account-relationship" },
  "password-history": { scope: "source-historical-passwords" },
  "native-password-history": { scope: "apple-native-history" },
  passkeys: {
    public_browser_api_scope: "Authorized relying-party metadata and real WebAuthn use, not whole-library inventory, key export, merging or deletion.",
    browser_eligibility_and_authorization_required: true,
    identity_store_scope: "Calling credential provider extension only; not Apple's Passwords library.",
  },
  groups: { exchange_collections_are_shared_acl: false, item_shared_group_limit: 1 },
  sharing: { permission_model: permissionModel },
  "preference-account-display": { scope: "apple-passwords-preference" },
  "preference-menu-bar": { scope: "apple-passwords-preference" },
  "preference-compromised-detection": { scope: "apple-passwords-preference" },
  "preference-strong-passwords": { scope: "apple-passwords-preference" },
  "preference-auto-passkeys": { scope: "apple-passwords-preference" },
  "autofill-provider-settings": { scope: "apple-system-integration" },
  "icloud-passwords-sync": { scope: "apple-system-integration" },
  "browser-extension-settings": { scope: "apple-system-integration" },
  export: { omitted_native_domains: ["passkeys", "otp-seeds", "wifi", "sign-in-with-apple", "shared-groups-owned-by-others", "sharing-permissions"] },
};

export function capabilities(): Record<string, unknown> {
  const exact = "Exact unique native title/account only; ambiguous matches stop. Background accessibility needs Apple acceptance on this OS.";
  const create = "Reviewed official exchange only. Receiver acknowledgment does not prove acceptance or merge; independent readback is required.";
  const features = [
      field("title", "native", { read: native(exact), create: exchange(create) }, "Precise title replacement or removal is not implemented."),
      field("account", "native", { read: native(exact), create: exchange(create) }, "MAYBE_ADD cannot precisely replace an identified duplicate account."),
      field("password", "native", {
        read: protocol("Selected account read; Apple may require personal authentication. Null/unavailable is never an empty password."),
        create: exchange(create),
      }, "pw save uses MAYBE_ADD, not exact record replacement or field deletion."),
      field("websites", "native", { read: native(exact), create: exchange(create + " Multisite receiver behavior requires per-site validation.") }, "Exact site-list replacement/removal is not implemented."),
      field("notes", "native", {
        read: native(exact + " Complete body is required; metadata is insufficient."), create: exchange(create),
        update: native("Preserves the entire previous body and all other fields. Save, close, reopen and full-state readback are required."),
      }, "Dropping existing note content is deliberately refused."),
      field("otp", "native", {
        read: protocol("Generated code and account association only; seed, algorithm, digits and period are not read back."),
        create: exchange(create + " Existing-login TOTP additions require password, sites and actual time-window code validation."),
      }, "Precise seed replacement/removal and complete OTP settings read are not implemented."),
      field("passkeys", "native", {}, "An AX presence indicator is not a passkey inventory. apw has no complete passkey identity, transfer or deletion command."),
      field("groups", "native", {}, "Group inventory, create, rename, item movement and member-set readback are not implemented. Exchange collections are not shared groups or ACLs."),
      field("sharing", "native", {}, "AX unshared/unknown is not a complete participant set. Apple uses owner/member roles; no arbitrary read-only ACL or apw participant-management command."),
      field("wifi", "native", {}, "Exchange format support alone is insufficient; apw has no SSID/security/password management command."),
      field("sso", "workaround", {
        create: exchange("Propose an external-provider placeholder with the reviewed provider account, explicitly empty password and complete provider notes. Verify the exact empty password, site/account and notes independently; this does not recreate a native federation relationship."),
      }, "Provider relationships are not read or precisely edited. Placeholder creation is separate from native Sign in with Apple."),
      field("sign-in-with-apple", "native", {}, "Native Apple Account/service relationships and sharing can be inspected in Apple's UI, but apw has no inventory, creation, update or deletion command. A blank-password placeholder does not recreate this access."),
      field("custom-fields", "workaround", {}, "Preserve source labels, types and values in complete retained notes; no structured field CRUD or source-linked parser."),
      field("tags", "workaround", {}, "Preserve exact source tags in retained notes; Apple Passwords has no general source-tag schema here."),
      field("attachments", "workaround", {}, "Keep the existing encrypted archive; independently restore and verify every attachment's bytes, path and source ID."),
      field("password-history", "workaround", {}, "Preserve required historical values in existing encrypted backup or notes. Never replace the selected primary password."),
      field("native-password-history", "native", {}, "Apple's View History shows prior versions, dates and sharing events. apw has no native history reader or clear-history command; source history in notes is a separate domain."),
      field("source-vaults", "workaround", {}, "Preserve source vault identity in notes; sharing permissions must be audited separately."),
      field("security", "native", {}, "Apple-generated security recommendations have no full apw inspection or management command."),
      field("autofill", "native", {}, "No system provider-settings reader/writer; website metadata is not an autofill acceptance test."),
      field("app-settings", "native", {}, "Installed OS settings inventory and preferences CRUD are not implemented. apw browser configuration is a different domain."),
      field("preference-account-display", "native", {}, "Company-title versus URL display preference has no apw reader/writer. This preference can affect displayed-title identity; never change it during bound maintenance."),
      field("preference-menu-bar", "native", {}, "Show Passwords in Menu Bar has no apw settings reader/writer or current-OS live acceptance."),
      field("preference-compromised-detection", "native", {}, "Detect Compromised Passwords has no apw settings reader/writer. Reading an alert is not reading or toggling this preference."),
      field("preference-strong-passwords", "native", {}, "Suggest Strong Passwords has no apw settings reader/writer. Website password metadata does not prove the Safari preference."),
      field("preference-auto-passkeys", "native", {}, "Automatically Create Passkeys has no apw settings reader/writer. Exchange or browser registration support is not this preference."),
      field("autofill-provider-settings", "native", {}, "System AutoFill provider selection has no apw reader/writer. apw configuration and successful URL lookup are not system provider settings or autofill acceptance."),
      field("icloud-passwords-sync", "native", {}, "iCloud Passwords/Keychain sync settings have no apw reader/writer. Local item presence is not proof of sync enablement or propagation."),
      field("browser-extension-settings", "native", {}, "Apple browser-extension enablement/permissions have no complete apw reader/writer. A paired apw browser session is not an inventory of user browser integrations."),
      field("recoverable-delete", "native", {
        read: native("Exact active/deleted placement and full redundant-note body only; login/password read from Deleted is not implied."),
        delete: native("Only unshared credential-free notes whose complete body and source IDs are present in the verified keeper. Verify Deleted placement and keeper readback."),
      }, "No restore command; ordinary login/passkey deletion is protected."),
      field("permanent-delete", "native", {}, "Irrecoverable deletion is deliberately unsupported and is not required for migration cleanup."),
      field("library-inventory", "native", {}, "Bounded title/account or website queries do not enumerate all item types with stable Apple IDs."),
      field("import", "native", { create: exchange(create) }, "No silent whole-library import or implicit replacement; partial receiver errors must be reviewed."),
      field("export", "unknown", {}, "Targeted snapshots are not a whole-library export. CSV omits passkeys, OTP seeds, Wi-Fi, native Sign in with Apple access, groups owned by others and sharing permissions."),
      field("comparison", "unknown", {
        read: path("local", "Targeted native complete-state snapshots and SHA-256 preimages only; no complete source-to-Apple mapping command.", ["unlock"], true),
      }, "Whole-library field-aware comparison is not implemented by this CLI."),
      field("deduplication", "unknown", {}, "Ordinary duplicate-login union/merge/delete is not implemented. Blank redundant-note cleanup is a separate guarded operation."),
      field("batch-maintenance", "native", {
        read: native("At most 50 explicit named targets per process; not a whole-vault inventory."),
        update: native("Bounded hash-bound notes plans with fsynced intent, uncertain-state hold and independent readback; Apple mutation acceptance remains pending."),
        delete: native("Bounded proven redundant-note deletion only. Completed checkpoints never dispatch again; uncertainties require read-only review."),
      }, "Batch orchestration cannot grant missing Apple capabilities or bypass personal authentication."),
    ].map(feature => ({ ...feature, ...(featureDetails[feature.id] ?? {}), ...(availablePaths[feature.id] ? { available_paths: availablePaths[feature.id] } : {}) }));
  return {
    format: "apw-capabilities-v1", source: "static-implementation-audit", version: VERSION,
    full_library_api: false, all_fields_and_settings_ready: false,
    safe_for_customer_deduplication: false,
    coverage: { feature_count: features.length, operation_count: features.length * 4 },
    readiness_reasons: [
      "Native notes persistence and recoverable deletion need current-build Apple readback.",
      "Ordinary duplicate logins lack a stable-identity merge/delete implementation.",
      "Passkeys, native Sign in with Apple, native history, memberships and settings are not fully managed by this build.",
      "Apple Developer membership does not grant Apple's private keychain groups or approved browser eligibility.",
    ],
    features,
  };
}
