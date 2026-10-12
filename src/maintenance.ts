// SPDX-License-Identifier: GPL-3.0-only
// No additional vault. Plans/snapshots are private maintenance input/output.
import { APWError, Status } from "./const.ts";
import { privateBytes } from "./notes.ts";

type Key = { title: string; username: string };
type State = { key: Key; native_title: string; notes: string; password: string; sites: string[];
  sharing: string; otp: string; passkey: string; extra_fields: unknown[] };
type Operation = { id: string; kind: "notes-set" | "delete-redundant-note"; target: Key; before_sha256: string;
  notes?: string; keeper?: { target: Key; before_sha256: string }; preserve_text?: string; source_ids?: string[] };
type DeletionProof = { deletion_verification: "full_deleted_body" | "content_preservation_deleted_location" | "legacy_pending_content_preservation_deleted_location";
  content_preservation_verified: true; deleted_body_verified: boolean };
type Entry = { plan: string; id: string; event: string; after_sha256?: string; before_sha256?: string; before_native_title?: string;
  before_snapshot_path?: string; deleted_preflight_absent?: boolean; deletion_verification?: DeletionProof["deletion_verification"];
  content_preservation_verified?: boolean; deleted_body_verified?: boolean; at: string };
const encoder = new TextEncoder();
const fail = (code: string): never => { throw new APWError(Status.INVALID_PARAM, "maintenance_" + code); };
// Backend diagnostics cross the public stderr boundary. Never forward arbitrary
// native objects or free text, even when a field has a familiar name.
function safeDiagnostics(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const raw = value as Record<string, unknown>, out: Record<string, unknown> = {};
  const strings: Record<string, string[]> = {
    failure_stage: ["initial_list_preparation", "search_context", "single_query_edit", "bounded_search", "unique_native_row",
      "current_selection_list", "index_generation_changed", "index_identity_changed", "current_selection_identity",
      "select_unique_row", "open_readonly_editor", "editor_open_unverified", "cancel_readonly_editor", "unknown"],
    status: ["native_timeout_setup_failed", "native_access_unavailable", "passwords_foreground_required", "incomplete_window_observation",
      "user_editor_open", "locked", "unsupported_window", "no_standard_window", "locked_or_access_unavailable", "unavailable"],
    ui_set_attribute: ["AXValue", "AXSelected", "AXSelectedRows", "AXSelectedText", "AXSelectedTextRange"],
    all_list_bridge_failure: ["owner_changed", "process_changed", "window_changed", "sheet_changed", "sidebar_changed", "category_changed",
      "search_changed", "query_changed", "clear_changed", "none", "unclassified_system_events_error"],
    request_owner_mode: ["foreground", "background", "refuse", "preserve"],
    search_strategy: ["selected-text", "witnessed-value", "unfiltered-index"],
    search_witness_failure: ["maintenance_search_baseline_unverified", "maintenance_search_value_unsupported", "maintenance_search_value_refused",
      "maintenance_search_empty_witness_unverified", "maintenance_search_context_changed", "maintenance_search_target_model_unverified",
      "maintenance_search_observation_incomplete"],
    search_clear_failure: ["clear_button_ambiguous", "clear_action_refused", "clear_model_unverified", "clear_capability_incomplete", "clear_text_submission_failed", "clear_binding_unverified", "clear_value_submission_failed"],
    search_clear_method: ["addressed_cancel_button", "addressed_selected_text", "addressed_semantic_clear", "addressed_value_then_semantic_clear", "addressed_value_cycle"],
    bounded_click_bridge_failure: ["owner_changed", "process_changed", "window_changed", "sheet_changed", "role_changed", "identity_changed",
      "caption_changed", "none", "unclassified_system_events_error"],
    confirmation_bridge_failure: ["editor_address_unavailable", "owner_changed", "process_changed", "window_changed", "sheet_changed",
      "fields_ambiguous", "identity_changed", "credential_changed", "editor_address_changed", "ordinary_confirmation_unavailable", "none", "unclassified_system_events_error"],
    confirmation_native_editor_role: ["AXGroup", "AXScrollArea", "AXSplitGroup"],
    search_phase: ["selected_text_value_wait", "category_confirmation", "bounded_model_wait"],
    search_wait_end: ["fresh_target_value_verified", "fresh_target_value_timeout", "category_verified", "category_unverified",
      "bounded_exact_model_verified", "bounded_target_missing_using_complete_index"],
    notes_role: ["AXTextField", "AXTextArea"],
    notes_observation_end: ["two_complete_writable_frames", "stable_unsupported", "transient_or_incomplete_timeout", "editable_fields_changed"],
    notes_probe_stage: ["input_validation", "initial_cohort", "initial_read", "initial_state", "notes_capabilities", "notes_structure",
      "first_cancel", "preservation_cohort", "preservation_read", "preservation_state", "final_cancel", "complete", "foreground_owner", "notes_focus"],
    synthetic_input_stage: ["input_validation", "foreground_owner", "exact_read", "preimage", "notes_focus", "permission", "selection",
      "text_input", "postimage", "save", "persisted_read", "final_cancel", "complete"],
  };
  for (const [name, allowed] of Object.entries(strings)) if (typeof raw[name] === "string" && allowed.includes(raw[name] as string)) out[name] = raw[name];
  for (const name of ["ui_set_error_code", "ui_press_error_code", "all_list_bridge_stage", "all_list_bridge_error_code", "all_list_bridge_exit_code",
    "bounded_click_bridge_error_code", "bounded_click_bridge_exit_code", "confirmation_bridge_system_error_code"]) {
    const v = raw[name]; if (typeof v === "number" && Number.isInteger(v) && Math.abs(v) <= 100000000) out[name] = v;
  }
  for (const name of ["notes_range_code", "notes_text_code", "notes_value_code", "notes_actions_code", "focus_set_code"]) {
    const v=raw[name]; if (typeof v === "number" && Number.isInteger(v) && Math.abs(v)<=100000000) out[name]=v;
  }
  for (const name of ["notes_range_settable", "notes_text_settable", "notes_value_settable", "notes_probe_read_opened", "notes_probe_recovery_attempted",
    "notes_probe_editor_recovered", "notes_probe_editor_requires_review", "focus_requested", "focus_settable", "focus_verified"]) {
    if (typeof raw[name] === "boolean") out[name]=raw[name];
  }
  for (const name of ["confirmation_bridge_timed_out", "confirmation_account_list_enumerated"]) {
    if (typeof raw[name] === "boolean") out[name]=raw[name];
  }
  for (const name of ["deleted_selected_exact","deleted_title_matches","deleted_note_matches","deleted_recovery_unique","deleted_frame_complete"]) {
    if (typeof raw[name] === "boolean") out[name]=raw[name];
  }
  const deletedFrames=raw.deleted_frames_observed;
  if (typeof deletedFrames === "number" && Number.isInteger(deletedFrames) && deletedFrames>=0 && deletedFrames<=3000) out.deleted_frames_observed=deletedFrames;
  for (const name of ["synthetic_input_permission", "synthetic_input_selection_verified", "synthetic_input_postimage_verified",
    "synthetic_input_persisted_verified", "synthetic_input_editor_requires_review"]) {
    if (typeof raw[name] === "boolean") out[name]=raw[name];
  }
  const inputEvents=raw.synthetic_input_event_count;
  if (typeof inputEvents === "number" && Number.isInteger(inputEvents) && inputEvents>=0 && inputEvents<=4) out.synthetic_input_event_count=inputEvents;
  for (const [name,max] of [["confirmation_bridge_exit_code",255],["confirmation_editor_path_depth",16]] as const) {
    const v=raw[name]; if (typeof v === "number" && Number.isInteger(v) && v>=0 && v<=max) out[name]=v;
  }
  const noteActions = raw.notes_action_names;
  const allowedActions = ["AXPress", "AXIncrement", "AXDecrement", "AXConfirm", "AXCancel", "AXShowMenu", "AXPick", "AXRaise",
    "AXScrollToVisible", "AXShowAlternateUI", "AXShowDefaultUI"];
  if (Array.isArray(noteActions) && noteActions.length <= allowedActions.length &&
      noteActions.every(x => typeof x === "string" && allowedActions.includes(x))) out.notes_action_names = noteActions;
  const noteFrames = raw.notes_observation_frames;
  if (typeof noteFrames === "number" && Number.isInteger(noteFrames) && noteFrames >= 0 && noteFrames <= 3000) out.notes_observation_frames = noteFrames;
  const probeRows = raw.notes_probe_row_count;
  if (typeof probeRows === "number" && Number.isInteger(probeRows) && probeRows >= 1 && probeRows <= 100) out.notes_probe_row_count = probeRows;
  const roles = ["other", "AXTextField", "AXTextArea", "AXComboBox", "AXStaticText", "AXGroup", "AXScrollArea", "AXButton", "AXImage",
    "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXOutline", "AXTable", "AXRow", "AXToolbar", "AXWindow", "AXApplication"];
  const children = raw.notes_children as Record<string, unknown> | undefined;
  if (children && typeof children === "object" && !Array.isArray(children) && Number.isInteger(children.count) &&
      typeof children.count === "number" && children.count >= 0 && children.count <= 16 && typeof children.complete === "boolean" &&
      Array.isArray(children.nodes) && children.nodes.length === children.count && children.nodes.every(node => {
        if (!node || typeof node !== "object" || Array.isArray(node)) return false;
        const n = node as Record<string, unknown>;
        return Object.keys(n).sort().join() === "depth,editable_role,identifier_present,parent_bound,role,same_pid" &&
          typeof n.role === "string" && roles.includes(n.role) && typeof n.depth === "number" && Number.isInteger(n.depth) && n.depth >= 1 && n.depth <= 4 &&
          [n.identifier_present,n.same_pid,n.parent_bound,n.editable_role].every(x => typeof x === "boolean");
      })) out.notes_children = {count:children.count,complete:children.complete,nodes:children.nodes};
  const focus = raw.notes_internal_focus as Record<string,unknown> | undefined;
  if (focus && typeof focus === "object" && !Array.isArray(focus) &&
      Object.keys(focus).sort().join() === "code,known_role,matches_notes,same_pid" &&
      typeof focus.code === "number" && Number.isInteger(focus.code) && Math.abs(focus.code) <= 100000000 &&
      typeof focus.same_pid === "boolean" && typeof focus.matches_notes === "boolean" &&
      typeof focus.known_role === "string" && [...roles,"none"].includes(focus.known_role)) out.notes_internal_focus = focus;
  if (typeof raw.all_list_bridge_timed_out === "boolean") out.all_list_bridge_timed_out = raw.all_list_bridge_timed_out;
  for (const name of ["search_clear_before_count", "search_clear_after_count", "search_result_count"]) {
    const v=raw[name]; if (typeof v === "number" && Number.isInteger(v) && v>=0 && v<=3000) out[name]=v;
  }
  const counts = raw.native_incomplete_error_counts;
  if (counts && typeof counts === "object" && !Array.isArray(counts)) {
    const safe: Record<string, number> = {};
    for (const [code, count] of Object.entries(counts)) {
      if (/^-252\d{2}$/.test(code) && typeof count === "number" && Number.isInteger(count) && count > 0 && count <= 1000000) safe[code] = count;
    }
    if (Object.keys(safe).length) out.native_incomplete_error_counts = safe;
  }
  // Search model evidence contains only bounded, fixed structural fields.
  // Reject the whole value when any nested key/type is outside that schema.
  const integerBetween=(v:unknown,min:number,max:number):boolean =>
    typeof v==="number" && Number.isInteger(v) && v>=min && v<=max;
  const phases=["empty_witness","target_model","clear_model"];
  const modelFrames=raw.search_model_frames;
  if (Array.isArray(modelFrames) && modelFrames.length<=16 && modelFrames.every(frame=> {
    if (!frame || typeof frame!=="object" || Array.isArray(frame)) return false;
    const f=frame as Record<string,unknown>;
    if (Object.keys(f).sort().join()!=="cached_raw_count,category_matches,complete,native_errors,owner_unchanged,phase,published_count,query_matches,raw_count" ||
      typeof f.phase!=="string" || !phases.includes(f.phase) ||
      ![f.complete,f.query_matches,f.category_matches,f.owner_unchanged].every(v=>typeof v==="boolean") ||
      ![f.raw_count,f.published_count,f.cached_raw_count].every(v=>integerBetween(v,-1,3000)) ||
      !Array.isArray(f.native_errors) || f.native_errors.length>8) return false;
    return f.native_errors.every(error=> {
      if (!error || typeof error!=="object" || Array.isArray(error)) return false;
      const e=error as Record<string,unknown>;
      return Object.keys(e).sort().join()==="code,count" && integerBetween(e.code,-100000000,100000000) && integerBetween(e.count,1,6000);
    });
  })) out.search_model_frames=modelFrames;
  const frameCounts=raw.search_model_frame_counts;
  if (frameCounts && typeof frameCounts==="object" && !Array.isArray(frameCounts) &&
    Object.keys(frameCounts).sort().join()==="clear_model,empty_witness,target_model" &&
    Object.values(frameCounts).every(v=>integerBetween(v,0,1024))) out.search_model_frame_counts=frameCounts;
  return out;
}
function canonical(v: unknown): string {
  if (Array.isArray(v)) return "[" + v.map(canonical).join(",") + "]";
  if (v && typeof v === "object") return "{" + Object.entries(v).sort(([a], [b]) => a.localeCompare(b, "en")).map(([k, x]) => JSON.stringify(k) + ":" + canonical(x)).join(",") + "}";
  return JSON.stringify(v);
}
async function hash(v: unknown): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(canonical(v))))].map(x => x.toString(16).padStart(2,"0")).join("");
}
function key(v: unknown): v is Key {
  if (!v || typeof v !== "object" || Array.isArray(v)) return false;
  const k = v as Key;
  return Object.keys(k).sort().join() === "title,username" && typeof k.title === "string" && !!k.title && k.title.length <= 4096 &&
    typeof k.username === "string" && k.username.length <= 4096 && !k.title.includes("\0") && !k.username.includes("\0");
}
function state(v: unknown, target: Key): State {
  if (!v || typeof v !== "object" || Array.isArray(v)) fail("snapshot_incomplete");
  const s = v as State;
  if (!key(s.key) || canonical(s.key) !== canonical(target) ||
    [s.native_title, s.notes, s.password].some(x => typeof x !== "string" || x.includes("\0")) ||
    !Array.isArray(s.sites) || s.sites.some(x => typeof x !== "string" || !x || x.includes("\0")) ||
    !["unshared", "unknown"].includes(s.sharing) || !["absent", "present", "unknown"].includes(s.otp) ||
    !["absent", "present", "unknown"].includes(s.passkey) || !Array.isArray(s.extra_fields)) fail("snapshot_incomplete");
  return s;
}
function validate(raw: unknown): Operation[] {
  const p = raw as { format: string; operations: Operation[] };
  if (!p || p.format !== "apw-maintenance-v1" || !Array.isArray(p.operations) || !p.operations.length || p.operations.length > 50) fail("plan_invalid");
  const ids = new Set<string>();
  for (const o of p.operations) {
    if (!o || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(o.id) || ids.has(o.id) || !key(o.target) || !/^[a-f0-9]{64}$/.test(o.before_sha256)) fail("plan_invalid");
    ids.add(o.id);
    if (o.kind === "notes-set") {
      if (typeof o.notes !== "string" || !o.notes || o.notes.length > 65536 || o.notes.includes("\0")) fail("plan_invalid");
    } else if (o.kind === "delete-redundant-note") {
      if (!o.keeper || !key(o.keeper.target) || canonical(o.target) === canonical(o.keeper.target) || !/^[a-f0-9]{64}$/.test(o.keeper.before_sha256) ||
        typeof o.preserve_text !== "string" || !o.preserve_text || !Array.isArray(o.source_ids) || !o.source_ids.length ||
        o.source_ids.some(x => typeof x !== "string" || !x || !o.preserve_text!.includes(x))) fail("plan_invalid");
    } else fail("plan_invalid");
  }
  return p.operations;
}
class Native {
  child!: Deno.ChildProcess;
  writer: WritableStreamDefaultWriter<Uint8Array>;
  reader: ReadableStreamDefaultReader<Uint8Array>;
  buffer = ""; counter = 0; decoder = new TextDecoder();
  constructor() {
    const path = Deno.env.get("APW_MAINTENANCE_HELPER") ?? Deno.execPath().replace(/\/[^/]*$/, "/apw-maintenance");
    try {
      const f = Deno.lstatSync(path);
      if (!f.isFile || f.isSymlink || (f.mode! & 0o022)) fail("helper_unsafe");
      this.child = new Deno.Command(path, { args: ["--serve"], stdin: "piped", stdout: "piped", stderr: "null" }).spawn();
    } catch (e) { if (e instanceof APWError) throw e; fail("helper_unavailable"); }
    this.writer = this.child!.stdin.getWriter(); this.reader = this.child!.stdout.getReader();
  }
  async call(op: string, body: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    const id = ++this.counter;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const response = async () => {
      await this.writer.write(encoder.encode(JSON.stringify({ id, op, ...body }) + "\n"));
      while (!this.buffer.includes("\n")) {
        const v = await this.reader.read(); if (v.done) fail("helper_reply_missing");
        this.buffer += this.decoder.decode(v.value, { stream: true });
        if (this.buffer.length > 4 * 1024 * 1024) fail("helper_reply_invalid");
      }
      const n = this.buffer.indexOf("\n"), line = this.buffer.slice(0, n); this.buffer = this.buffer.slice(n + 1);
      let r: Record<string, unknown>; try { r = JSON.parse(line); } catch { fail("helper_reply_invalid"); }
      if (r!.id !== id || r!.app_activated !== false || typeof r!.ok !== "boolean") fail("helper_reply_invalid");
      if (!r!.ok) {
        const code = typeof r!.error === "string" && /^maintenance_[a-z_]+$/.test(r!.error) ? r!.error : "maintenance_native_operation_failed";
        throw new APWError(Status.INVALID_PARAM, code, safeDiagnostics(r!.diagnostics));
      }
      return r!;
    };
    try {
      return await Promise.race([response(), new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new APWError(Status.GENERIC_ERROR, "maintenance_helper_timeout")), 90000); })]);
    } finally { clearTimeout(timer); }
  }
  async read(k: Key, deleted = false, expected?: State): Promise<State> {
    return state((await this.call(deleted ? "deleted-read" : "read", { key: k, ...(expected ? { expected } : {}) })).state, k);
  }
  async close(): Promise<void> {
    // Give the helper EOF first so it can close its own unchanged editor.
    // The bounded kill is a final fallback, not a mutation retry.
    try { await this.writer.close(); } catch { /* child already exited */ }
    let timer:ReturnType<typeof setTimeout> | undefined;
    try {
      await Promise.race([this.child.status,new Promise<void>(resolve => {timer=setTimeout(() => {
        try {this.child.kill("SIGTERM");}catch {/* already exited */} resolve();
      },1000);})]);
    } finally {clearTimeout(timer);this.writer.releaseLock();this.reader.releaseLock();}
  }
}
async function privateParent(path: string): Promise<void> {
  const dir = path.replace(/\/[^/]+$/, "");
  const f = await Deno.lstat(dir);
  if (!f.isDirectory || f.isSymlink || f.uid !== Deno.uid() || (f.mode! & 0o077)) fail("private_directory_required");
}
async function writeAll(file: Deno.FsFile, data: Uint8Array): Promise<void> {
  let n = 0; while (n < data.length) { const wrote = await file.write(data.subarray(n)); if (!wrote) fail("journal_write_failed"); n += wrote; }
  await file.sync();
}
async function verifySnapshotOutput(file: Deno.FsFile, path: string, reserved: Deno.FileInfo): Promise<void> {
  await privateParent(path);
  let opened: Deno.FileInfo, named: Deno.FileInfo;
  try { opened = await file.stat(); named = await Deno.lstat(path); }
  catch { fail("snapshot_unsafe"); }
  // The helper may take time. Recheck both the reserved descriptor and its
  // pathname before any cleartext write, rather than trusting initial mode.
  if (reserved.ino === null || reserved.dev === null ||
      [opened!, named!].some(f => !f.isFile || f.isSymlink || f.uid !== Deno.uid() ||
        (f.mode! & 0o077) || f.nlink !== 1 || f.ino !== reserved.ino || f.dev !== reserved.dev)) fail("snapshot_unsafe");
}
async function writeSnapshot(file: Deno.FsFile, path: string, reserved: Deno.FileInfo, data: Uint8Array): Promise<void> {
  await verifySnapshotOutput(file, path, reserved);
  await writeAll(file, data);
  await verifySnapshotOutput(file, path, reserved);
}
async function notesPreimage(path: string, target: Key, beforeHash: string): Promise<State> {
  let file: Deno.FsFile | undefined;
  try {
    file=await Deno.open(path,{read:true});
    const reserved=await file.stat(); await verifySnapshotOutput(file,path,reserved);
    const raw=JSON.parse(new TextDecoder("utf-8",{fatal:true}).decode(await privateBytes(path)));
    await verifySnapshotOutput(file,path,reserved);
    if (!raw || raw.format!=="apw-item-snapshot-v1" || raw.sha256!==beforeHash) fail("outcome_requires_review");
    const before=state(raw.state,target);
    if (await hash(before)!==beforeHash) fail("outcome_requires_review");
    return before;
  } catch {return fail("outcome_requires_review");}
  finally {file?.close();}
}
export async function readItem(title: string, username: string, output: string): Promise<void> {
  const target = { title, username }; if (!key(target)) fail("identity_invalid");
  output = await absolute(output); await privateParent(output);
  // Reserve first: an unsafe/existing output must not trigger native interaction.
  const file = await Deno.open(output, { createNew: true, write: true, mode: 0o600 });
  let native: Native | undefined;
  try {
    const reserved = await file.stat(); await verifySnapshotOutput(file, output, reserved);
    native = new Native(); const value = await native.read(target);
    await writeSnapshot(file, output, reserved, encoder.encode(JSON.stringify({ format: "apw-item-snapshot-v1", sha256: await hash(value), state: value }) + "\n"));
    console.log(JSON.stringify({ read: true, private_output: output, sha256: await hash(value), app_activated: false }));
  } finally { await native?.close(); file.close(); }
}
export async function inspectItems(targetsPath: string, output: string, savePartial = false): Promise<void> {
  let plan: { format:string; targets:Key[] };
  try { plan=JSON.parse(new TextDecoder("utf-8", {fatal:true}).decode(await privateBytes(targetsPath))); } catch { fail("targets_invalid"); }
  if (plan!.format !== "apw-maintenance-targets-v1" || !Array.isArray(plan!.targets) || !plan!.targets.length ||
    plan!.targets.length>50 || !plan!.targets.every(key) || new Set(plan!.targets.map(canonical)).size !== plan!.targets.length) fail("targets_invalid");
  output=await absolute(output); await privateParent(output);
  const file=await Deno.open(output, {createNew:true,write:true,mode:0o600});
  let native:Native | undefined;
  try {
    const reserved=await file.stat(); await verifySnapshotOutput(file,output,reserved);
    native=new Native(); const items=[];
    for (let index=0; index<plan!.targets.length; index++) {
      try {
        const value=await native.read(plan!.targets[index]);items.push({state:value,sha256:await hash(value)});
      } catch (e) {
        const error=e instanceof APWError ? e : undefined;
        const code=error && /^maintenance_[a-z_]+$/.test(error.message) ? error.message : "maintenance_inspection_failed";
        // Opt-in salvage stops at the first failure, including a helper timeout
        // or an unclosed editor. It grants no continuation/recovery authority.
        // Only complete state()-validated, hash-bound prefix items are saved.
        if (savePartial) {
          await writeSnapshot(file,output,reserved,encoder.encode(JSON.stringify({format:"apw-item-snapshots-v1",complete:false,
            requested_count:plan!.targets.length,failed_index:index+1,items,failures:[{index:index+1,error:code}]})+"\n"));
        }
        // The cleartext prefix stays private; public diagnostics contain only
        // filtered structural evidence, local positions and the fsynced status.
        throw new APWError(error?.status ?? Status.GENERIC_ERROR,
          code,{...safeDiagnostics(error?.diagnostics),target_index:index+1,completed_reads:items.length,...(savePartial ? {partial_saved:true}:{})});
      }
    }
    await writeSnapshot(file,output,reserved,encoder.encode(JSON.stringify({format:"apw-item-snapshots-v1",items})+"\n"));
    console.log(JSON.stringify({read:true,count:items.length,private_output:output,app_activated:false}));
  } finally {await native?.close();file.close();}
}
async function absolute(path: string): Promise<string> {
  if (!path || path.includes("\0")) fail("path_invalid");
  const url = new URL(path.startsWith("/") ? "file://" + path : path, "file://" + Deno.cwd() + "/");
  if (url.protocol !== "file:") fail("path_invalid");
  return decodeURIComponent(url.pathname);
}
export async function maintenanceDoctor(): Promise<void> {
  const native = new Native(); try { console.log(JSON.stringify(await native.call("doctor"))); } finally { await native.close(); }
}
export async function maintenanceConnect(): Promise<void> {
  const native = new Native(); try { console.log(JSON.stringify(await native.call("connect"))); } finally { await native.close(); }
}
export async function recoverEditor(snapshotPath: string): Promise<void> {
  let raw: {format?: string; sha256?: string; state?: State};
  try { raw = JSON.parse(new TextDecoder("utf-8", {fatal:true}).decode(await privateBytes(snapshotPath))); }
  catch { fail("recovery_snapshot_invalid"); }
  if (raw!.format !== "apw-item-snapshot-v1" || !raw!.state || !key(raw!.state.key)) fail("recovery_snapshot_invalid");
  const expected = state(raw!.state,raw!.state!.key);
  if (raw!.sha256 !== await hash(expected)) fail("recovery_snapshot_invalid");
  const native = new Native();
  try {
    const result = await native.call("recover-readonly-editor", {expected});
    if (result.recovered !== true || result.credentials_changed !== 0 || result.journal_modified !== false) fail("editor_recovery_unverified");
    console.log(JSON.stringify({recovered:true,credentials_changed:0,journal_modified:false,app_activated:false}));
  } finally {await native.close();}
}
export async function probeNotesEditor(snapshotPath: string, foregroundFocus = false): Promise<void> {
  let raw: {format?: string; sha256?: string; state?: State} | null;
  try {raw = JSON.parse(new TextDecoder("utf-8",{fatal:true}).decode(await privateBytes(snapshotPath)));}
  catch {fail("probe_snapshot_invalid");}
  if (!raw! || raw!.format !== "apw-item-snapshot-v1" || !raw!.state || !key(raw!.state.key)) fail("probe_snapshot_invalid");
  const expected = state(raw!.state,raw!.state!.key);
  if (raw!.sha256 !== await hash(expected)) fail("probe_snapshot_invalid");
  const syntheticSite = (site:string):boolean => {
    try {return new URL(site.includes("://") ? site : "https://"+site).hostname.endsWith(".invalid");} catch {return false;}
  };
  if (!expected.key.title.startsWith("apw API 测试") || expected.native_title !== expected.key.title ||
      !expected.notes.includes("APW_EXCHANGE_SYNTHETIC_V1") || expected.password !== "" ||
      (expected.key.username !== "" && !expected.key.username.endsWith(".invalid")) ||
      !expected.sites.every(syntheticSite) || expected.sharing !== "unshared" || expected.extra_fields.length !== 0) fail("probe_synthetic_required");
  const native = new Native();
  try {
    const result = await native.call("notes-editor-probe",{expected,key:expected.key,synthetic_only:true,foreground_focus:foregroundFocus});
    if (result.probed !== true || result.synthetic_only !== true || result.mutation_authorized !== false ||
        result.current_cohort_only !== true || result.credentials_changed !== 0 || result.journal_modified !== false ||
        result.foreground_focus !== foregroundFocus) fail("probe_completion_unverified");
    console.log(JSON.stringify({probed:true,synthetic_only:true,mutation_authorized:false,current_cohort_only:true,
      credentials_changed:0,journal_modified:false,app_activated:false,foreground_focus:foregroundFocus,diagnostics:safeDiagnostics(result.diagnostics)}));
  } finally {await native.close();}
}
export async function syntheticForegroundNotesInput(snapshotPath: string, notesFilePath: string, journalPath: string): Promise<void> {
  let expected: State, notes: string, beforeHash: string;
  try {
    snapshotPath = await absolute(snapshotPath); notesFilePath = await absolute(notesFilePath);
    await privateParent(snapshotPath); await privateParent(notesFilePath);
    const raw = JSON.parse(new TextDecoder("utf-8", {fatal:true}).decode(await privateBytes(snapshotPath)));
    if (!raw || raw.format !== "apw-item-snapshot-v1" || !raw.state || !key(raw.state.key)) fail("synthetic_notes_input_invalid");
    expected = state(raw.state, raw.state.key);
    if (Object.keys(expected).sort().join() !== "extra_fields,key,native_title,notes,otp,passkey,password,sharing,sites" ||
        typeof raw.sha256 !== "string" || !/^[a-f0-9]{64}$/.test(raw.sha256)) fail("synthetic_notes_input_invalid");
    beforeHash = await hash(expected);
    const existingTitles = ["apw API 测试 · SSO 与备注", "apw API 测试 · 独立备注"];
    const syntheticSite = (site: string): boolean => {
      try {
        const url = new URL(site.includes("://") ? site : "https://" + site);
        return ["http:", "https:"].includes(url.protocol) && url.hostname.endsWith(".invalid") && !url.username && !url.password;
      } catch {return false;}
    };
    if (raw.sha256 !== beforeHash || !existingTitles.includes(expected.key.title) || expected.native_title !== expected.key.title ||
        !expected.notes.includes("APW_EXCHANGE_SYNTHETIC_V1") || expected.password !== "" ||
        (expected.key.username !== "" && !expected.key.username.endsWith(".invalid")) || !expected.sites.every(syntheticSite) ||
        expected.sharing !== "unshared" || expected.extra_fields.length !== 0) fail("synthetic_notes_input_invalid");
    notes = new TextDecoder("utf-8", {fatal:true}).decode(await privateBytes(notesFilePath));
    const suffix = notes.slice(expected.notes.length);
    // JS string length/slice use the exact UTF-16 units bound by the native API.
    if (!notes.startsWith(expected.notes) || !suffix || suffix.length > 512 ||
        !suffix.includes("APW_FOREGROUND_INPUT_SYNTHETIC_V1") || notes.length > 4096 || notes.includes("\0")) fail("synthetic_notes_input_invalid");
  } catch {fail("synthetic_notes_input_invalid");}
  const intended: State = {...expected!, notes:notes!}, afterHash = await hash(intended);
  journalPath = await absolute(journalPath); await privateParent(journalPath);
  let file: Deno.FsFile;
  try {file = await Deno.open(journalPath, {createNew:true,write:true,mode:0o600});}
  catch (e) {
    if (e instanceof Deno.errors.AlreadyExists) fail("synthetic_notes_journal_exists");
    fail("synthetic_notes_journal_unsafe");
  }
  let native: Native | undefined;
  try {
    const reserved = await file!.stat(); await verifySnapshotOutput(file!,journalPath,reserved);
    const append = async (event: "intent" | "done" | "uncertain") => {
      await writeSnapshot(file!,journalPath,reserved,encoder.encode(JSON.stringify({format:"apw-synthetic-notes-input-v1",event,
        synthetic_only:true,before_sha256:beforeHash!,after_sha256:afterHash,at:new Date().toISOString()}) + "\n"));
    };
    await append("intent"); // private, fsynced intent always precedes the one call
    try {
      native = new Native();
      const result = await native.call("synthetic-foreground-notes-input",{expected:expected!,key:expected!.key,notes:notes!,
        synthetic_only:true,foreground_focus:true});
      if (result.synthetic_only !== true || result.persisted !== true || result.credentials_changed !== 1 ||
          result.exports !== 0 || result.imports !== 0 || result.app_activated !== false) fail("synthetic_notes_input_unverified");
      let after: State;
      try {after = state(result.state,expected!.key);} catch {fail("synthetic_notes_input_unverified");}
      if (canonical(after!) !== canonical(intended) || await hash(after!) !== afterHash) fail("synthetic_notes_input_unverified");
      await append("done");
      console.log(JSON.stringify({synthetic_only:true,persisted:true,credentials_changed:1,exports:0,imports:0,app_activated:false,
        before_sha256:beforeHash!,after_sha256:afterHash}));
    } catch (e) {await append("uncertain");throw e;}
  } finally {await native?.close();file!.close();}
}
async function exactActiveAbsence(native: Native, target: Key): Promise<void> {
  try { await native.read(target); }
  catch (e) { if (e instanceof APWError && e.message === "maintenance_item_not_found") return; throw e; }
  fail("deletion_unverified");
}
async function completePreservedKeeper(native: Native, o: Operation, before: State): Promise<State> {
  const keeper = await native.read(o.keeper!.target);
  if (await hash(keeper) !== o.keeper!.before_sha256 || keeper.sharing !== "unshared" ||
      !keeper.notes.includes(before.notes) || o.source_ids!.some(id => !keeper.notes.includes(id))) fail("keeper_proof_refused");
  return keeper;
}
async function verifyRedundantDeletion(native: Native, o: Operation, before: State, preflightAbsent: boolean | undefined): Promise<DeletionProof> {
  // This branch is limited to a complete, hash-bound empty-credential note.
  // It cannot be a general fallback for an ordinary login or a partial read.
  if (await hash(before) !== o.before_sha256 || before.password !== "" || before.key.username !== "" || before.sites.length ||
      before.otp !== "absent" || before.passkey !== "absent" || before.sharing !== "unshared" || before.extra_fields.length ||
      !before.notes || before.notes !== o.preserve_text || o.source_ids!.some(id => !before.notes.includes(id))) fail("redundant_note_proof_refused");
  try {
    if (await hash(await native.read(o.target, true, before)) !== o.before_sha256) fail("deletion_unverified");
  } catch (e) {
    // A timeout/invalid/ambiguous/refused reply must never become evidence that
    // Apple merely hides the body. Only this precise successful-frame failure
    // may request the separate, location-only native observation.
    if (!(e instanceof APWError) || e.message !== "maintenance_deleted_body_unverified") throw e;
    // An unsupported preflight on a new delete preserves legacy full-body
    // compatibility, but never permits the weaker historical identity scope.
    if (preflightAbsent === false) fail("outcome_requires_review");
    await exactActiveAbsence(native, o.target);
    const result = await native.call("deleted-location-read", {key:o.target, expected:before});
    const location = result.location as Record<string,unknown> | undefined;
    if (result.verification !== "deleted_note_location_only" || result.body_verified !== false || Object.hasOwn(result,"state") ||
        !location || typeof location !== "object" || Array.isArray(location) ||
        Object.keys(location).sort().join() !== "category,frame_complete,key,native_title,owner_unchanged,query_empty,recovery_unique,selected_exact,stable_complete_frames,title_matches" ||
        location.category !== "deleted" || canonical(location.key) !== canonical(o.target) || location.native_title !== before.native_title ||
        [location.selected_exact,location.title_matches,location.recovery_unique,location.frame_complete,location.query_empty,location.owner_unchanged].some(x => x !== true) ||
        typeof location.stable_complete_frames !== "number" || !Number.isInteger(location.stable_complete_frames) ||
        location.stable_complete_frames < 2 || location.stable_complete_frames > 3000) fail("deleted_location_unverified");
    const first = await completePreservedKeeper(native, o, before);
    await exactActiveAbsence(native, o.target);
    const second = await completePreservedKeeper(native, o, before);
    if (canonical(first) !== canonical(second)) fail("keeper_proof_refused");
    return {deletion_verification:preflightAbsent === true ? "content_preservation_deleted_location" : "legacy_pending_content_preservation_deleted_location",
      content_preservation_verified:true, deleted_body_verified:false};
  }
  await exactActiveAbsence(native, o.target);
  await completePreservedKeeper(native, o, before);
  return {deletion_verification:"full_deleted_body",content_preservation_verified:true,deleted_body_verified:true};
}
export async function runBatch(planPath: string, journalPath: string, apply: boolean, onlyKind?: Operation["kind"], review=false, skipCompleted=false): Promise<void> {
  const bytes = await privateBytes(planPath);
  let raw: unknown; try { raw = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); } catch { fail("plan_invalid"); }
  const operations = validate(raw), planHash = await hash(raw);
  if (onlyKind && operations.some(o => o.kind !== onlyKind)) fail("plan_kind_invalid");
  if (!apply) { console.log(JSON.stringify({ dry_run: true, operations: operations.length, plan_sha256: planHash, native_calls: 0, writes: 0 })); return; }
  journalPath = await absolute(journalPath); await privateParent(journalPath);
  const lock = journalPath + ".lock";
  try { await Deno.mkdir(lock, { mode: 0o700 }); }
  catch (e) {
    if (!(e instanceof Deno.errors.AlreadyExists)) throw e;
    const f = await Deno.lstat(lock);
    if (!f.isDirectory || f.isSymlink || f.uid !== Deno.uid() || (f.mode! & 0o077)) fail("journal_locked");
    const owner = JSON.parse(new TextDecoder().decode(await privateBytes(lock + "/owner.json")));
    if (!Number.isInteger(owner.pid) || owner.pid < 1 || owner.plan !== planHash) fail("journal_locked");
    try { Deno.kill(owner.pid, 0); fail("journal_locked"); }
    catch (x) { if (!(x instanceof Deno.errors.NotFound)) throw x; }
    const names: string[] = []; for await (const entry of Deno.readDir(lock)) names.push(entry.name);
    if (names.join() !== "owner.json") fail("journal_locked");
    await Deno.remove(lock + "/owner.json"); await Deno.remove(lock);
    await Deno.mkdir(lock, { mode: 0o700 });
  }
  let file: Deno.FsFile | undefined, native: Native | undefined;
  let completed = 0, mutations = 0, reviewed=0, skippedCompleted=0, contentPreservationVerifications=0, deletedBodyVerifications=0;
  try {
    const owner = await Deno.open(lock + "/owner.json", { createNew: true, write: true, mode: 0o600 });
    try { await writeAll(owner, encoder.encode(JSON.stringify({ pid: Deno.pid, plan: planHash }))); } finally { owner.close(); }
    let history: Entry[] = [];
    try {
      const text = new TextDecoder("utf-8", { fatal: true }).decode(await privateBytes(journalPath));
      if (text && !text.endsWith("\n")) fail("journal_incomplete");
      history = text.trim() ? text.trim().split("\n").map(x => JSON.parse(x)) : [];
      if (history.some(x => x.plan !== planHash || !operations.some(o => o.id === x.id) || !["intent", "done", "uncertain", "reviewed-no-change"].includes(x.event))) fail("journal_plan_mismatch");
      file = await Deno.open(journalPath, { append: true, write: true });
    } catch (e) {
      if (!(e instanceof Deno.errors.NotFound)) throw e;
      file = await Deno.open(journalPath, { createNew: true, write: true, mode: 0o600 });
    }
    const opened = await file!.stat(), pathNow = await Deno.lstat(journalPath);
    if (!opened.isFile || opened.uid !== Deno.uid() || (opened.mode! & 0o077) || pathNow.isSymlink || pathNow.ino !== opened.ino ||
        (skipCompleted && (opened.nlink!==1 || pathNow.nlink!==1 || pathNow.dev!==opened.dev))) fail("journal_unsafe");
    const append = async (o: Operation, event: string, after?: string, beforeNativeTitle?: string, beforeSnapshotPath?: string,
        deletionProof?: DeletionProof, deletedPreflightAbsent?: boolean) => {
      const entry: Entry = { plan: planHash, id: o.id, event, before_sha256: o.before_sha256,
        ...(after ? { after_sha256: after } : {}),
        ...(event === "intent" && beforeNativeTitle !== undefined ? { before_native_title: beforeNativeTitle } : {}), at: new Date().toISOString() };
      if (event==="intent" && beforeSnapshotPath!==undefined) entry.before_snapshot_path=beforeSnapshotPath;
      if (event==="intent" && deletedPreflightAbsent!==undefined) entry.deleted_preflight_absent=deletedPreflightAbsent;
      if (event==="done" && deletionProof) Object.assign(entry,deletionProof);
      await writeAll(file!, encoder.encode(JSON.stringify(entry) + "\n")); history.push(entry);
    };
    native = new Native();
    for (const o of operations) {
      const prior = history.filter(x => x.id === o.id), last = prior.at(-1);
      if (review) {
        if (!last || last.event==="done" || last.event==="reviewed-no-change") continue;
        if (await hash(await native.read(o.target))!==o.before_sha256 ||
          (o.keeper && await hash(await native.read(o.keeper.target))!==o.keeper.before_sha256)) fail("review_preimage_changed");
        await append(o,"reviewed-no-change");reviewed++;continue;
      }
      // Only modern, internally consistent checkpoint chains may avoid current
      // reads. Damaged/legacy evidence falls back to the existing readonly audit.
      // This is historical authority, never a claim about Apple's current state.
      let checkpointHistory=skipCompleted && last?.event==="done", phase="", previousTime=-Infinity;
      if (checkpointHistory) for (const entry of prior) {
        const time=typeof entry.at==="string" ? Date.parse(entry.at) : NaN;
        if (entry.before_sha256!==o.before_sha256 || !Number.isFinite(time) || time<previousTime ||
            (entry.event==="intent" ? !["","reviewed-no-change"].includes(phase) :
             entry.event==="uncertain" ? phase!=="intent" :
             entry.event==="reviewed-no-change" ? !["intent","uncertain"].includes(phase) :
             !["intent","uncertain"].includes(phase))) {checkpointHistory=false;break;}
        phase=entry.event;previousTime=time;
      }
      // Completed/uncertain operations never replay intent. The explicit skip
      // may reuse a qualified done only after all metadata/preimage checks below.
      if (last && last.event!=="reviewed-no-change") {
        if (o.kind === "notes-set") {
          const intent = prior.findLast(x => x.event === "intent"), intended = intent?.after_sha256;
          const capturedTitle = intent?.before_native_title;
          if (!intent || intent.before_sha256 !== o.before_sha256 || typeof intended !== "string" ||
            !/^[a-f0-9]{64}$/.test(intended) ||
            (capturedTitle !== undefined && (typeof capturedTitle !== "string" || capturedTitle.includes("\0")))) fail("outcome_requires_review");
          // An after hash alone cannot authorize changes to passwords/sites or
          // other fields. Reconstruct the unique intended state from the full
          // private preimage bound to the unchanged original plan.
          const preimagePath=journalPath+"."+o.id+".before.json";
          if (intent?.before_snapshot_path!==preimagePath) fail("outcome_requires_review");
          const before=await notesPreimage(preimagePath,o.target,o.before_sha256);
          if (before.sharing!=="unshared" || !o.notes!.includes(before.notes) ||
              (capturedTitle!==undefined && capturedTitle!==before.native_title)) fail("outcome_requires_review");
          const expected={...before,notes:o.notes!}, expectedHash=await hash(expected);
          if (intended!==expectedHash) fail("outcome_requires_review");
          if (checkpointHistory && capturedTitle===before.native_title && last.after_sha256===expectedHash) {
            await verifySnapshotOutput(file!,journalPath,opened);
            skippedCompleted++;continue;
          }
          const now = await native.read(o.target), h = await hash(now);
          // A private journal can still be damaged or copied incorrectly.
          // Its after-hash never substitutes for the original plan's note body.
          if (canonical(now)!==canonical(expected) || h!==expectedHash) fail("outcome_requires_review");
          if (last.event !== "done") await append(o, "done", h);
        } else {
          // Deleted notes cannot be edited. Bind placement/body verification to
          // the original empty-credential note snapshot, never infer empty data.
          const intent=prior.findLast(x => x.event === "intent");
          if (!intent) return fail("outcome_requires_review");
          if (intent.before_sha256!==o.before_sha256 ||
              (intent.deleted_preflight_absent!==undefined && typeof intent.deleted_preflight_absent!=="boolean")) fail("outcome_requires_review");
          const capturedTitle = intent.before_native_title;
          if (capturedTitle !== undefined && (typeof capturedTitle !== "string" || capturedTitle.includes("\0"))) fail("outcome_requires_review");
          const deletedBefore: State = { key: o.target, native_title: capturedTitle === undefined ? o.target.title : capturedTitle, notes: o.preserve_text!, password: "",
            sites: [], sharing: "unshared", otp: "absent", passkey: "absent", extra_fields: [] };
          if (await hash(deletedBefore) !== o.before_sha256) fail("outcome_requires_review");
          if (intent.before_snapshot_path!==undefined) {
            const path=journalPath+"."+o.id+".before.json";
            if (intent.before_snapshot_path!==path || canonical(await notesPreimage(path,o.target,o.before_sha256))!==canonical(deletedBefore)) fail("outcome_requires_review");
          } else if (intent.deleted_preflight_absent!==undefined) fail("outcome_requires_review");
          const completedDeletionProof=last.content_preservation_verified===true &&
            (last.deletion_verification==="full_deleted_body" ? last.deleted_body_verified===true :
             last.deletion_verification==="content_preservation_deleted_location" ? last.deleted_body_verified===false && intent.deleted_preflight_absent===true :
             last.deletion_verification==="legacy_pending_content_preservation_deleted_location" && last.deleted_body_verified===false && intent.deleted_preflight_absent===undefined);
          if (checkpointHistory && completedDeletionProof && last.after_sha256===undefined &&
              typeof capturedTitle==="string" && intent.before_snapshot_path===journalPath+"."+o.id+".before.json" &&
              deletedBefore.key.username==="" && o.source_ids!.every(id=>deletedBefore.notes.includes(id))) {
            await verifySnapshotOutput(file!,journalPath,opened);
            skippedCompleted++;continue;
          }
          await exactActiveAbsence(native,o.target);
          const proof=await verifyRedundantDeletion(native,o,deletedBefore,intent.deleted_preflight_absent);
          contentPreservationVerifications++;if(proof.deleted_body_verified)deletedBodyVerifications++;
          if (last.event !== "done") await append(o, "done",undefined,undefined,undefined,proof);
        }
        completed++; continue;
      }
      const before = await native.read(o.target);
      if (await hash(before) !== o.before_sha256) fail("preimage_changed");
      let intended: State | undefined, deletedPreflightAbsent: boolean | undefined;
      if (o.kind === "notes-set") {
        if (before.sharing !== "unshared" || !o.notes!.includes(before.notes)) fail("note_preservation_refused");
        intended = { ...before, notes: o.notes! };
      } else {
        if (before.password !== "" || before.key.username !== "" || before.sites.length || before.otp !== "absent" ||
          before.passkey !== "absent" || before.sharing !== "unshared" || before.extra_fields.length || before.notes !== o.preserve_text) fail("redundant_note_proof_refused");
        const keeper = await native.read(o.keeper!.target);
        if (await hash(keeper) !== o.keeper!.before_sha256 || keeper.sharing !== "unshared" || !keeper.notes.includes(before.notes) ||
          o.source_ids!.some(x => !keeper.notes.includes(x))) fail("keeper_proof_refused");
        try {
          await native.call("deleted-location-read",{key:o.target,expected:before});
          fail("deleted_identity_preexisting");
        } catch (e) {
          if (e instanceof APWError && e.message==="maintenance_item_not_found") deletedPreflightAbsent=true;
          else if (e instanceof APWError && e.message==="maintenance_operation_unsupported") deletedPreflightAbsent=false;
          else throw e;
        }
      }
      const afterHash = intended ? await hash(intended) : undefined;
      let beforeSnapshotPath: string | undefined;
      if (intended || o.kind==="delete-redundant-note") {
        beforeSnapshotPath=journalPath+"."+o.id+".before.json";
        let snapshot: Deno.FsFile | undefined;
        try {snapshot=await Deno.open(beforeSnapshotPath,{createNew:true,write:true,mode:0o600});}
        catch (e) {
          // Only an explicitly reviewed unchanged operation can reuse its
          // original exact preimage. Never overwrite or infer orphan evidence.
          if (!(e instanceof Deno.errors.AlreadyExists) || last?.event!=="reviewed-no-change") fail("outcome_requires_review");
          if (canonical(await notesPreimage(beforeSnapshotPath,o.target,o.before_sha256))!==canonical(before)) fail("outcome_requires_review");
        }
        if (snapshot) {
          try {
            const reserved=await snapshot.stat();
            await writeSnapshot(snapshot,beforeSnapshotPath,reserved,encoder.encode(JSON.stringify({format:"apw-item-snapshot-v1",
              sha256:o.before_sha256,state:before})+"\n"));
          } finally {snapshot.close();}
        }
      }
      await append(o, "intent", afterHash, before.native_title,beforeSnapshotPath,undefined,deletedPreflightAbsent); // both fsyncs precede any mutation
      try {
        const result = await native.call(o.kind, { key: o.target, expected: before, ...(intended ? { notes: intended.notes } : {}) });
        mutations++;
        let deletionProof:DeletionProof | undefined;
        if (intended) {
          if (await hash(await native.read(o.target)) !== afterHash) fail("readback_changed");
        } else {
          if (result.recoverable !== true) fail("deletion_unverified");
          deletionProof=await verifyRedundantDeletion(native,o,before,deletedPreflightAbsent);
          contentPreservationVerifications++;if(deletionProof.deleted_body_verified)deletedBodyVerifications++;
        }
        await append(o, "done", afterHash,undefined,undefined,deletionProof); completed++;
        console.error(JSON.stringify({ event: "maintenance_checkpoint", id: o.id, completed, total: operations.length }));
      } catch (e) { await append(o, "uncertain", afterHash); throw e; }
    }
    console.log(JSON.stringify({ completed, total: operations.length, mutations, ...(review ? {reviewed_no_change:reviewed}:{}), ...(skipCompleted ? {skipped_completed:skippedCompleted}:{}),
      content_preservation_verifications:contentPreservationVerifications,deleted_body_verifications:deletedBodyVerifications,
      app_activated: false, imports: 0, exports: 0, permanent_deletions: 0 }));
  } finally {
    await native?.close(); file?.close();
    await Deno.remove(lock, { recursive: true });
  }
}
