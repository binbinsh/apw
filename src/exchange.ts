// Optional official Apple credential-exchange trial. SPDX-License-Identifier: GPL-3.0-only
import { APWError, Status } from "./const.ts";

async function run(command: string, args: string[], input?: Uint8Array): Promise<Deno.CommandOutput> {
  const process = new Deno.Command(command, {
    args,
    stdin: input ? "piped" : "null",
    stdout: "piped",
    stderr: "piped",
  }).spawn();
  if (input) {
    const writer = process.stdin.getWriter();
    await writer.write(input);
    await writer.close();
  }
  return await process.output();
}

async function plist(input: Uint8Array, key?: string): Promise<Record<string, unknown>> {
  const args = key ? ["-extract", key, "json", "-o", "-", "-"] : ["-convert", "json", "-o", "-", "-"];
  const result = await run("/usr/bin/plutil", args, input);
  if (!result.success) throw new Error("plist_invalid");
  return JSON.parse(new TextDecoder().decode(result.stdout));
}

async function entitlements(path: string): Promise<Record<string, unknown>> {
  const result = await run("/usr/bin/codesign", ["--display", "--entitlements", ":-", path]);
  if (!result.success) throw new Error("signature_invalid");
  return await plist(result.stdout);
}

async function provisioned(path: string, ent: Record<string, unknown>, bundleID: string, team: string): Promise<boolean> {
  const profile = await run("/usr/bin/security", ["cms", "-D", "-i", `${path}/Contents/embedded.provisionprofile`]);
  if (!profile.success) return false;
  const allowed = await plist(profile.stdout, "Entitlements");
  const expiry = await run("/usr/bin/plutil", ["-extract", "ExpirationDate", "raw", "-o", "-", "-"], profile.stdout);
  const expiryTime = Date.parse(new TextDecoder().decode(expiry.stdout).trim());
  const privilege = "com.apple.developer.authentication-services.autofill-credential-provider";
  const teamKey = "com.apple.developer.team-identifier";
  const identityKey = "com.apple.application-identifier";
  return ent[privilege] === true && allowed[privilege] === true &&
    ent[teamKey] === team && allowed[teamKey] === team &&
    ent[identityKey] === `${team}.${bundleID}` && ent[identityKey] === allowed[identityKey] &&
    expiry.success && Number.isFinite(expiryTime) && expiryTime > Date.now();
}

async function runningComponents(app: string): Promise<Record<string, unknown>[]> {
  const found = await run("/usr/bin/pgrep", ["-x", "apw-exchange-probe"]);
  if (found.code === 1) return [];
  if (!found.success) throw new Error("runtime_lookup_failed");
  const pids = new TextDecoder().decode(found.stdout).trim().split(/\s+/).filter((s) => /^[0-9]+$/.test(s));
  const result: Record<string, unknown>[] = [];
  for (const pid of pids) {
    const inspect = await run(`${app}/Contents/MacOS/apw-exchange-probe`, ["--inspect-process", pid]);
    let details: Record<string, unknown>;
    try { details = JSON.parse(new TextDecoder().decode(inspect.stdout)); } catch { throw new Error("runtime_inspection_failed"); }
    if (details.matches_this_app === false) continue; // Never stop another bundle.
    if (details.inspection_succeeded !== true) {
      if (!(await run("/bin/kill", ["-0", pid])).success) continue;
      throw new Error("runtime_inspection_failed");
    }
    result.push({
      running_pid: Number(pid),
      inspection_succeeded: true,
      matches_this_app: details.matches_this_app === true,
      runtime_matches_disk: details.runtime_matches_disk === true,
      process_has_required_entitlement: details.process_has_required_entitlement === true,
    });
  }
  return result;
}

export async function exchangeStatus(): Promise<Record<string, unknown>> {
  const dir = Deno.execPath().replace(/\/[^/]+$/, "");
  const app = `${dir}/apw-exchange-probe.app`;
  const provider = `${app}/Contents/PlugIns/APWExchangeProvider.appex`;
  const result: Record<string, unknown> = {
    ready_for_synthetic_trial: false,
    signed_bundle_valid: false,
    host_entitlement_provisioned: false,
    provider_entitlement_provisioned: false,
    launched: false,
    synthetic_only: false,
    default_demo_synthetic_only: true,
    notes_preservation_supported: true,
    totp_preservation_supported: true,
    native_totp_import_verified: false,
    native_apple_import_verified: false,
    foreground_automation_paused: true,
  };
  if (Deno.build.os !== "darwin") return { ...result, unavailable_reason: "requires_macos" };
  try {
    const info = await plist(await Deno.readFile(`${app}/Contents/Info.plist`));
    const providerInfo = await plist(await Deno.readFile(`${provider}/Contents/Info.plist`));
    const hostID = info.CFBundleIdentifier;
    if (typeof hostID !== "string" || !/^dev\.apw\.exchangeprobe\.[0-9a-f]{8}$/.test(hostID)) {
      throw new Error("bundle_invalid");
    }
    if (providerInfo.CFBundleIdentifier !== `${hostID}.provider`) throw new Error("provider_invalid");
    const signature = await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app]);
    const hostSigning = await run("/usr/bin/codesign", ["--display", "--verbose=4", app]);
    const hostTeam = new TextDecoder().decode(hostSigning.stderr).match(/^TeamIdentifier=([A-Z0-9]+)$/m)?.[1];
    const hostEnt = await entitlements(app);
    const providerEnt = await entitlements(provider);
    result.signed_bundle_valid = signature.success && hostEnt["com.apple.security.app-sandbox"] === true &&
      providerEnt["com.apple.security.app-sandbox"] === true && hostSigning.success && typeof hostTeam === "string";
    result.host_entitlement_provisioned = typeof hostTeam === "string" && await provisioned(app, hostEnt, hostID, hostTeam);
    result.provider_entitlement_provisioned = typeof hostTeam === "string" && await provisioned(provider, providerEnt, `${hostID}.provider`, hostTeam);
    result.ready_for_synthetic_trial = result.signed_bundle_valid === true && result.host_entitlement_provisioned === true &&
      result.provider_entitlement_provisioned === true;
    result.app_path = app;
    if (result.ready_for_synthetic_trial !== true) result.unavailable_reason = "signed_provider_not_ready";
    result.running_components = await runningComponents(app);
    const home = Deno.env.get("HOME");
    result.notes_transport_path = `${home}/Library/Containers/${hostID}/Data/Library/Application Support/apw-exchange-probe/notes-preservation.json`;
    const report = `${home}/Library/Containers/${hostID}/Data/Library/Application Support/apw-exchange-probe/latest-result.json`;
    try {
      const receipt = JSON.parse(await Deno.readTextFile(report));
      // Do not print arbitrary receipt contents or credential values.
      result.latest_trial = {
        export_api_completed: receipt.export_api_completed === true,
        data_roundtrip_matches: receipt.data_roundtrip_matches === true,
        source_review_required: receipt.source_review_required !== false,
        native_apple_import_verified: false,
      };
      result.report_path = report;
    } catch { /* No trial receipt yet. */ }
    return result;
  } catch {
    return { ...result, ready_for_synthetic_trial: false, unavailable_reason: "signed_provider_not_ready" };
  }
}

export async function prepareExchangeComponent(): Promise<Record<string, unknown>> {
  const status = await exchangeStatus();
  if (status.ready_for_synthetic_trial !== true || !Array.isArray(status.running_components)) {
    throw new APWError(Status.GENERIC_ERROR, "exchange_signed_provider_not_ready");
  }
  let stopped = 0;
  for (const process of status.running_components) {
    if (process.matches_this_app !== true || !Number.isInteger(process.running_pid)) {
      throw new APWError(Status.GENERIC_ERROR, "exchange_runtime_ownership_unverified");
    }
    const pid = String(process.running_pid);
    // Recheck ownership immediately before signaling; a listed PID may exit
    // while status is being read. Never signal a reused PID for another app.
    const probe = await run(`${status.app_path}/Contents/MacOS/apw-exchange-probe`, ["--inspect-process", pid]);
    let ownership: Record<string, unknown>;
    try { ownership = JSON.parse(new TextDecoder().decode(probe.stdout)); } catch {
      throw new APWError(Status.GENERIC_ERROR, "exchange_runtime_ownership_unverified");
    }
    if (ownership.matches_this_app !== true) {
      if (!(await run("/bin/kill", ["-0", pid])).success) continue;
      throw new APWError(Status.GENERIC_ERROR, "exchange_runtime_ownership_unverified");
    }
    const signaled = await run("/bin/kill", ["-TERM", pid]);
    if (!signaled.success && (await run("/bin/kill", ["-0", pid])).success) {
      throw new APWError(Status.GENERIC_ERROR, "exchange_restart_failed");
    }
    let alive = true;
    for (let attempt = 0; attempt < 20; attempt++) {
      alive = (await run("/bin/kill", ["-0", pid])).success;
      if (!alive) break;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    if (alive) throw new APWError(Status.GENERIC_ERROR, "exchange_restart_failed");
    stopped++;
  }
  return { stopped_count: stopped, launched: false, exchange_api_invoked: false, app_path: status.app_path };
}

export async function launchExchangeDemo(interactive: boolean): Promise<void> {
  if (!interactive) throw new APWError(Status.INVALID_PARAM, "exchange_requires_interactive");
  const result = await prepareExchangeComponent();
  const opened = await run("/usr/bin/open", [String(result.app_path)]);
  if (!opened.success) throw new APWError(Status.GENERIC_ERROR, "exchange_launch_failed");
  console.log(JSON.stringify({ launched: true, synthetic_only: true, test_record_count: 3, native_apple_import_verified: false }));
}

export async function launchOTPLoginDemo(interactive: boolean, checkOnly: boolean): Promise<void> {
  if (!interactive && !checkOnly) throw new APWError(Status.INVALID_PARAM, "exchange_requires_interactive");
  const status = await exchangeStatus();
  if (status.ready_for_synthetic_trial !== true || typeof status.app_path !== "string") {
    throw new APWError(Status.GENERIC_ERROR, "exchange_signed_provider_not_ready");
  }
  const checked = await run(`${status.app_path}/Contents/MacOS/apw-exchange-probe`, ["--otp-login-demo-check"]);
  let report: Record<string, unknown>;
  try { report = JSON.parse(new TextDecoder().decode(checked.stdout)); }
  catch { throw new APWError(Status.GENERIC_ERROR, "exchange_component_check_failed"); }
  if (!checked.success) {
    if (report.error === "exchange_notes_attempt_requires_review") throw new APWError(Status.INVALID_PARAM, report.error);
    throw new APWError(Status.GENERIC_ERROR, "exchange_component_check_failed");
  }
  if (report.codec_exact !== true || report.same_item_binding_exact !== true || report.test_record_count !== 1 ||
    report.basic_authentication_count !== 1 || report.totp_count !== 1 || report.scope_count !== 1 ||
    report.synthetic_only !== true || report.real_user_secret_used !== false || report.native_reads !== 0 ||
    report.gui_launched !== false || report.exchange_api_invoked !== false ||
    typeof report.fixture_sha256 !== "string" || !/^[0-9a-f]{64}$/.test(report.fixture_sha256)) {
    throw new APWError(Status.GENERIC_ERROR, "exchange_component_check_failed");
  }
  const safe = { codec_exact: true, same_item_binding_exact: true, test_record_count: 1,
    basic_authentication_count: 1, totp_count: 1, scope_count: 1, synthetic_only: true,
    fixture_sha256: report.fixture_sha256,
    real_user_secret_used: false, native_reads: 0, exchange_api_invoked: false,
    native_apple_import_verified: false, native_totp_import_verified: false };
  if (checkOnly) { console.log(JSON.stringify({ ...safe, launched: false })); return; }
  const prepared = await prepareExchangeComponent();
  const opened = await run("/usr/bin/open", [String(prepared.app_path), "--args", "--otp-login-demo"]);
  if (!opened.success) throw new APWError(Status.GENERIC_ERROR, "exchange_launch_failed");
  console.log(JSON.stringify({ ...safe, launched: true }));
}
