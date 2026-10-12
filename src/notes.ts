// Official notes-only migration transport. SPDX-License-Identifier: GPL-3.0-only
import { APWError, Status } from "./const.ts";
import { exchangeStatus, prepareExchangeComponent } from "./exchange.ts";

function fail(): never { throw new APWError(Status.INVALID_PARAM, "exchange_notes_plan_invalid"); }
export async function privateBytes(path: string, exclusive = false): Promise<Uint8Array> {
  const before = await Deno.lstat(path);
  if (!before.isFile || before.isSymlink || before.uid !== Deno.uid() || !before.mode || (before.mode & 0o077) !== 0 || before.size > 32 * 1024 * 1024) fail();
  const file = await Deno.open(path, { read: true });
  try {
    const opened = await file.stat();
    if (exclusive && (before.nlink !== 1 || opened.nlink !== 1)) fail();
    if (!opened.isFile || opened.uid !== Deno.uid() || !opened.mode || (opened.mode & 0o077) !== 0 || opened.ino !== before.ino || opened.dev !== before.dev || opened.size !== before.size) fail();
    const bytes = new Uint8Array(opened.size);
    let offset = 0;
    while (offset < bytes.length) { const n = await file.read(bytes.subarray(offset)); if (n === null || n === 0) fail(); offset += n; }
    const after = await file.stat();
    const pathAfter = await Deno.lstat(path);
    if (exclusive && (after.nlink !== 1 || pathAfter.nlink !== 1)) fail();
    if (after.size !== opened.size || after.mtime?.getTime() !== opened.mtime?.getTime() || pathAfter.isSymlink || pathAfter.ino !== opened.ino || pathAfter.dev !== opened.dev) fail();
    return bytes;
  } finally { file.close(); }
}
function decode(bytes: Uint8Array): Record<string, unknown> { return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
async function digest(bytes: Uint8Array): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)))].map((v) => v.toString(16).padStart(2, "0")).join("");
}
function validateBatch(batch?: string): void {
  if (batch !== undefined && !/^[a-z0-9][a-z0-9-]{0,63}$/.test(batch)) throw new APWError(Status.INVALID_PARAM, "exchange_notes_batch_invalid");
}
function otpConfiguration(raw: unknown, username: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) fail();
  const c = raw as Record<string, unknown>;
  if (Object.keys(c).some((k) => !["secret_base64", "algorithm", "digits", "period", "username", "issuer"].includes(k)) ||
    typeof c.secret_base64 !== "string" || c.secret_base64.length > 2048 ||
    !["SHA1", "SHA256", "SHA512"].includes(String(c.algorithm)) ||
    !Number.isInteger(c.digits) || Number(c.digits) < 1 || Number(c.digits) > 10 ||
    !Number.isInteger(c.period) || Number(c.period) < 1 || Number(c.period) > 65535 ||
    typeof c.username !== "string" || !c.username || c.username !== username || c.username.length > 4096 || c.username.includes("\0") ||
    (c.issuer !== undefined && c.issuer !== null && (typeof c.issuer !== "string" || c.issuer.length > 4096 || c.issuer.includes("\0")))) fail();
  try {
    const bytes = atob(c.secret_base64);
    if (!bytes.length || bytes.length > 1024 || btoa(bytes) !== c.secret_base64) fail();
  } catch { fail(); }
  return { secret_base64: c.secret_base64, algorithm: c.algorithm, digits: c.digits, period: c.period,
    username: c.username, ...(c.issuer !== undefined ? { issuer: c.issuer } : {}) };
}
async function transportPath(batch?: string, native = false, otpOnly = false): Promise<string> {
  validateBatch(batch);
  const status = await exchangeStatus();
  if (status.ready_for_synthetic_trial !== true || typeof status.notes_transport_path !== "string") throw new APWError(Status.GENERIC_ERROR, "exchange_signed_provider_not_ready");
  const name = otpOnly ? "otp-preservation.json" : native ? "credentials-preservation.json" : "notes-preservation.json";
  return batch ? status.notes_transport_path.replace(/notes-preservation\.json$/, `batches/${batch}/${name}`) : status.notes_transport_path;
}
export async function prepareNotes(planPath: string, destination?: string, batch?: string, native = false, otpOnly = false): Promise<void> {
  validateBatch(batch);
  if (native && otpOnly) fail();
  const scoped = native || otpOnly;
  if (destination && batch) throw new APWError(Status.INVALID_PARAM, "exchange_notes_batch_invalid");
  try {
    const raw = await privateBytes(planPath), plan = decode(raw);
    if (plan.historical !== false || !Array.isArray(plan.apple_items) || plan.apple_items.length < 1 || plan.apple_items.length > 3000 || typeof plan.source_destinations !== "object" || plan.source_destinations === null || Array.isArray(plan.source_destinations)) fail();
    if (scoped && (plan.native_creation_reviewed !== true || typeof plan.native_reviewed_snapshot_sha256 !== "string" || !/^[a-f0-9]{64}$/.test(plan.native_reviewed_snapshot_sha256) || !Number.isInteger(plan.native_reviewed_timestamp) || Number(plan.native_reviewed_timestamp) > Date.now()/1000 + 60 || Date.now()/1000 - Number(plan.native_reviewed_timestamp) > 3600 || plan.apple_items.length > 100 || (!destination && !batch))) fail();
    const mapping = plan.source_destinations as Record<string, unknown>;
    const sources = new Set<string>(), ids = new Set<string>();
    const items = plan.apple_items.map((entry: Record<string, unknown>) => {
      if (typeof entry.id !== "string" || !/^apple-[A-Za-z0-9-]{1,80}$/.test(entry.id) || ids.has(entry.id) || typeof entry.title !== "string" || typeof entry.notes !== "string" || entry.notes.length > 4096 || entry.notes.length === 0 || entry.notes.includes("\0") || !Array.isArray(entry.source_ids) || entry.source_ids.length < 1 || typeof entry.source_payload_sha256 !== "string" || !/^[a-f0-9]{64}$/.test(entry.source_payload_sha256) || !Number.isInteger(entry.part_index) || !Number.isInteger(entry.part_count) || Number(entry.part_index) < 1 || Number(entry.part_index) > Number(entry.part_count)) fail();
      ids.add(entry.id);
      for (const sid of entry.source_ids) {
        if (typeof sid !== "string" || sid.length < 1 || sid.length > 200 || !entry.notes.includes(sid) || !Array.isArray(mapping[sid]) || !(mapping[sid] as Record<string, unknown>[]).some((x) => x.destination === "apple_passwords" && x.id === entry.id)) fail();
        sources.add(sid);
      }
      const display = entry.title.replace(/[\r\n\t\0]/g, " ");
      const title = [...display].slice(0, 200).join("") + (otpOnly ? " · 验证码 [" : native ? " · 登录 [" : " · 资料 [") + entry.id.slice(-12) + "]";
      let totp: Record<string, unknown> | undefined;
      if (scoped) {
        if (entry.write_blocked !== false || entry.part_index !== 1 || typeof entry.username !== 'string' || !entry.username || entry.username.includes('\0') || entry.username.length > 4096 || typeof entry.password !== 'string' || entry.password.includes('\0') || entry.password.length > 4096 || entry.otp !== '' || !Array.isArray(entry.urls) || !entry.urls.length || entry.urls.length > 100 || !entry.urls.every((v) => {
          if (typeof v !== 'string' || v.length > 8192) return false;
          try { const u = new URL(v.includes('://') ? v : 'https://' + v); return ['http:','https:'].includes(u.protocol) && !!u.hostname && !u.username && !u.password; } catch { return false; }
        })) fail();
        if (otpOnly) {
          if (entry.kind !== "verification_code" || entry.password !== "") fail();
          totp = otpConfiguration(entry.totp, entry.username);
        } else if (entry.kind === 'bound_otp_login') {
          if (plan.native_totp_addition_reviewed !== true) fail();
          totp = otpConfiguration(entry.totp, entry.username);
        } else if (!['login','sso'].includes(String(entry.kind)) || (entry.kind === 'sso' && entry.password !== '') || entry.totp !== undefined) fail();
      }
      return { id: (otpOnly ? "apw-otp-" : native ? "apw-native-" : "apw-notes-") + entry.id, title, notes: entry.notes, source_ids: entry.source_ids,
        ...(native ? { username: entry.username, password: entry.password, urls: (entry.urls as string[]).map((v) => v.includes('://') ? v : 'https://' + v), kind: entry.kind, ...(totp ? {totp} : {}) } : {}),
        ...(otpOnly ? { totp, urls: (entry.urls as string[]).map((v) => v.includes('://') ? v : 'https://' + v), kind: entry.kind } : {}),
        part_index: entry.part_index, part_count: entry.part_count, source_payload_sha256: entry.source_payload_sha256 };
    });
    if (scoped) {
      const identities = new Set<string>();
      for (const item of items) {
        for (const host of new Set((item.urls as string[]).map((v) => new URL(v).hostname.toLowerCase().replace(/^www\./,'')))) {
          const config = item.totp;
          const key = otpOnly ? [config!.username, host, config!.secret_base64, config!.algorithm, config!.digits, config!.period].join('\0') : String(item.username).toLowerCase() + '\0' + host;
          if (identities.has(key)) fail();
          identities.add(key);
        }
      }
    }
    if (sources.size !== Object.keys(mapping).length || Object.keys(mapping).some((key) => !sources.has(key))) fail();
    const planSHA = await digest(raw), output = destination ?? await transportPath(batch,native,otpOnly);
    const directory = output.replace(/\/[^/]+$/, "");
    await Deno.mkdir(directory, { recursive: true, mode: 0o700 });
    const dirInfo = await Deno.lstat(directory);
    if (!dirInfo.isDirectory || dirInfo.isSymlink || dirInfo.uid !== Deno.uid() || !dirInfo.mode || (dirInfo.mode & 0o077) !== 0) fail();
    let already = false;
    let transport: Record<string, unknown> = { format: otpOnly ? "apw-passwords-totp-v1" : native ? "apw-passwords-native-v1" : "apw-passwords-notes-v1", plan_sha256: planSHA, created_timestamp: Math.floor(Date.now() / 1000), source_count: sources.size, items,
      ...(scoped ? { reviewed_snapshot_sha256: plan.native_reviewed_snapshot_sha256, reviewed_timestamp: plan.native_reviewed_timestamp } : {}) };
    try {
      const existing = decode(await privateBytes(output));
      if (existing.plan_sha256 !== planSHA || existing.format !== transport.format || existing.source_count !== sources.size || JSON.stringify(existing.items) !== JSON.stringify(items)) throw new APWError(Status.INVALID_PARAM, "exchange_notes_pending_transport_exists");
      transport = existing; already = true;
    } catch (error) { if (!(error instanceof Deno.errors.NotFound)) throw error; }
    if (!already) {
      const file = await Deno.open(output, { createNew: true, write: true, mode: 0o600 });
      try { const bytes = new TextEncoder().encode(JSON.stringify(transport)); let offset = 0; while (offset < bytes.length) offset += await file.write(bytes.subarray(offset)); await file.sync(); } finally { file.close(); }
    }
    const boundCount = native ? items.filter((item) => item.totp !== undefined).length : 0;
    console.log(JSON.stringify({ prepared: true, already_prepared: already, note_count: items.length, ...(native ? {credential_count:items.length,new_identities_only:boundCount === 0,bound_otp_count:boundCount,...(boundCount ? {receiver_merge_behavior_verified:false} : {})}:{}), ...(otpOnly ? {otp_count:items.length,native_password_credentials_sent:0,receiver_merge_behavior_verified:false}:{}), source_count: sources.size,
      plan_sha256: planSHA, transport_path: output, credential_overwrites: 0, launched: false, exchange_api_invoked: false,
      native_apple_import_verified: false, whole_vault_verified: false, text_preservation_only: !scoped }));
  } catch (error) {
    if (error instanceof APWError) throw error;
    throw new APWError(Status.INVALID_PARAM, "exchange_notes_plan_invalid");
  }
}
async function notesPreflight(batch?: string, native = false, otpOnly = false): Promise<Record<string, unknown>> {
  validateBatch(batch);
  const status = await exchangeStatus();
  if (status.ready_for_synthetic_trial !== true || typeof status.app_path !== "string") throw new APWError(Status.GENERIC_ERROR, "exchange_signed_provider_not_ready");
  let result: Deno.CommandOutput;
  try {
    // The signed sandboxed component reads its own container. The unsigned CLI
    // never needs broad privacy access merely to launch this migration.
    result = await new Deno.Command(`${status.app_path}/Contents/MacOS/apw-exchange-probe`, {
      args: batch ? [otpOnly ? "--otp-check" : native ? "--credentials-check" : "--notes-check", "--batch", batch] : [native ? "--credentials-check" : "--notes-check"], stdin: "null", stdout: "piped", stderr: "piped",
    }).output();
  } catch { throw new APWError(Status.GENERIC_ERROR, "exchange_notes_component_check_failed"); }
  let report: Record<string, unknown>;
  try { report = decode(result.stdout); } catch { throw new APWError(Status.GENERIC_ERROR, "exchange_notes_component_check_failed"); }
  if (!result.success) {
    const known = new Set(["exchange_notes_plan_invalid", "exchange_notes_transport_missing", "exchange_notes_transport_access_denied", "exchange_notes_attempt_requires_review", "exchange_notes_attempt_lookup_failed", "exchange_native_review_expired"]);
    const code = typeof report.error === "string" && known.has(report.error) ? report.error : "exchange_notes_component_check_failed";
    throw new APWError(code === "exchange_notes_transport_access_denied" || code === "exchange_notes_attempt_lookup_failed" || code === "exchange_notes_component_check_failed" ? Status.GENERIC_ERROR : Status.INVALID_PARAM, code);
  }
  const boundCount = Number(report.bound_otp_count ?? 0);
  if (!Number.isInteger(boundCount) || boundCount < 0 || boundCount > Number(report.note_count) || (!native && boundCount !== 0) ||
      (boundCount > 0 && report.same_item_binding_exact !== true) || report.checked !== true || report.ready_to_import !== true || report.codec_exact !== true || report.gui_launched !== false || report.exchange_api_invoked !== false || !Number.isInteger(report.note_count) || Number(report.note_count) < 1 || Number(report.note_count) > 3000 || !Number.isInteger(report.source_count) || Number(report.source_count) < 1 || report.basic_authentication_count !== (native ? report.note_count : 0) || report.totp_count !== (otpOnly ? report.note_count : boundCount) || report.scope_count !== (native || otpOnly ? report.note_count : 0)) throw new APWError(Status.GENERIC_ERROR, "exchange_notes_component_check_failed");
  return { note_count: report.note_count, source_count: report.source_count,...(native ? {credential_count:report.note_count,new_identities_only:boundCount === 0,bound_otp_count:boundCount,same_item_binding_exact:report.same_item_binding_exact,...(boundCount ? {receiver_merge_behavior_verified:false} : {})}: {}), ...(otpOnly ? {otp_count:report.note_count,native_password_credentials_sent:0,receiver_merge_behavior_verified:false}: {}) };
}
export async function launchNotesImport(interactive: boolean, checkOnly = false, batch?: string, native = false, otpOnly = false): Promise<void> {
  validateBatch(batch);
  if (!interactive && !checkOnly) throw new APWError(Status.INVALID_PARAM, "exchange_requires_interactive");
  if ((native || otpOnly) && !batch) throw new APWError(Status.INVALID_PARAM, "exchange_notes_batch_invalid");
  const report = await notesPreflight(batch,native,otpOnly);
  if (checkOnly) {
    console.log(JSON.stringify({ checked: true, ready_to_import: true, ...report, credential_overwrites: 0,
      launched: false, exchange_api_invoked: false, native_apple_import_verified: false, text_preservation_only: !(native || otpOnly) }));
    return;
  }
  let prepared: Record<string, unknown>;
  try { prepared = await prepareExchangeComponent(); }
  catch (error) {
    if (error instanceof APWError) throw error;
    throw new APWError(Status.GENERIC_ERROR, "exchange_component_prepare_failed");
  }
  let result: Deno.CommandOutput;
  try {
    const args = [String(prepared.app_path), "--args", otpOnly ? "--otp-import" : native ? "--credentials-import" : "--notes-import"];
    if (batch) args.push("--batch", batch);
    result = await new Deno.Command("/usr/bin/open", { args, stdin: "null", stdout: "piped", stderr: "piped" }).output();
  } catch { throw new APWError(Status.GENERIC_ERROR, "exchange_launch_failed"); }
  if (!result.success) throw new APWError(Status.GENERIC_ERROR, "exchange_launch_failed");
  console.log(JSON.stringify({ launched: true, ...report,
    credential_overwrites: 0, exchange_api_invoked: false, native_apple_import_verified: false, text_preservation_only: !(native || otpOnly) }));
}
