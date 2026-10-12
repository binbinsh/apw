// SPDX-License-Identifier: GPL-3.0-only
// No additional vault. Plans/snapshots are private maintenance input/output.
import { APWError, Status } from "./const.ts";
import { privateBytes } from "./notes.ts";

type Key = { title: string; username: string };
type State = { key: Key; native_title: string; notes: string; password: string; sites: string[];
  sharing: string; otp: string; passkey: string; extra_fields: unknown[] };
type Operation = { id: string; kind: "notes-set" | "delete-redundant-note"; target: Key; before_sha256: string;
  notes?: string; keeper?: { target: Key; before_sha256: string }; preserve_text?: string; source_ids?: string[] };
type Entry = { plan: string; id: string; event: string; after_sha256?: string; before_sha256?: string; at: string };
const encoder = new TextEncoder();
const fail = (code: string): never => { throw new APWError(Status.INVALID_PARAM, "maintenance_" + code); };
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
      if (!r!.ok) fail(typeof r!.error === "string" && /^maintenance_[a-z_]+$/.test(r!.error) ? r!.error.slice(12) : "native_operation_failed");
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
export async function readItem(title: string, username: string, output: string): Promise<void> {
  const target = { title, username }; if (!key(target)) fail("identity_invalid");
  output = await absolute(output); await privateParent(output);
  // Reserve first: an unsafe/existing output must not trigger native interaction.
  const file = await Deno.open(output, { createNew: true, write: true, mode: 0o600 });
  let native: Native | undefined;
  try {
    native = new Native(); const value = await native.read(target);
    await writeAll(file, encoder.encode(JSON.stringify({ format: "apw-item-snapshot-v1", sha256: await hash(value), state: value }) + "\n"));
    console.log(JSON.stringify({ read: true, private_output: output, sha256: await hash(value), app_activated: false }));
  } finally { await native?.close(); file.close(); }
}
export async function inspectItems(targetsPath: string, output: string): Promise<void> {
  let plan: { format:string; targets:Key[] };
  try { plan=JSON.parse(new TextDecoder("utf-8", {fatal:true}).decode(await privateBytes(targetsPath))); } catch { fail("targets_invalid"); }
  if (plan!.format !== "apw-maintenance-targets-v1" || !Array.isArray(plan!.targets) || !plan!.targets.length ||
    plan!.targets.length>50 || !plan!.targets.every(key) || new Set(plan!.targets.map(canonical)).size !== plan!.targets.length) fail("targets_invalid");
  output=await absolute(output); await privateParent(output);
  const file=await Deno.open(output, {createNew:true,write:true,mode:0o600});
  let native:Native | undefined;
  try {
    native=new Native(); const items=[];
    for (const target of plan!.targets) { const value=await native.read(target); items.push({state:value,sha256:await hash(value)}); }
    await writeAll(file,encoder.encode(JSON.stringify({format:"apw-item-snapshots-v1",items})+"\n"));
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
export async function runBatch(planPath: string, journalPath: string, apply: boolean, onlyKind?: Operation["kind"], review=false): Promise<void> {
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
  let completed = 0, mutations = 0, reviewed=0;
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
    if (!opened.isFile || opened.uid !== Deno.uid() || (opened.mode! & 0o077) || pathNow.isSymlink || pathNow.ino !== opened.ino) fail("journal_unsafe");
    const append = async (o: Operation, event: string, after?: string) => {
      const entry: Entry = { plan: planHash, id: o.id, event, before_sha256: o.before_sha256,
        ...(after ? { after_sha256: after } : {}), at: new Date().toISOString() };
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
      // Every completed/uncertain operation is verified read-only. Never replay intent.
      if (last && last.event!=="reviewed-no-change") {
        if (o.kind === "notes-set") {
          const now = await native.read(o.target), h = await hash(now);
          const intended = prior.findLast(x => x.event === "intent")?.after_sha256;
          if (!intended || h !== intended) fail("outcome_requires_review");
          if (last.event !== "done") await append(o, "done", h);
        } else {
          // Deleted notes cannot be edited. Bind placement/body verification to
          // the original empty-credential note snapshot, never infer empty data.
          const deletedBefore: State = { key: o.target, native_title: o.target.title, notes: o.preserve_text!, password: "",
            sites: [], sharing: "unshared", otp: "absent", passkey: "absent", extra_fields: [] };
          if (await hash(deletedBefore) !== o.before_sha256) fail("outcome_requires_review");
          let active = false;
          try { await native.read(o.target); active = true; } catch (e) { if (!(e instanceof APWError) || e.message !== "maintenance_item_not_found") throw e; }
          if (active || await hash(await native.read(o.target, true, deletedBefore)) !== o.before_sha256 ||
            await hash(await native.read(o.keeper!.target)) !== o.keeper!.before_sha256) fail("outcome_requires_review");
          if (last.event !== "done") await append(o, "done");
        }
        completed++; continue;
      }
      const before = await native.read(o.target);
      if (await hash(before) !== o.before_sha256) fail("preimage_changed");
      let intended: State | undefined;
      if (o.kind === "notes-set") {
        if (before.sharing !== "unshared" || !o.notes!.includes(before.notes)) fail("note_preservation_refused");
        intended = { ...before, notes: o.notes! };
      } else {
        if (before.password !== "" || before.key.username !== "" || before.sites.length || before.otp !== "absent" ||
          before.passkey !== "absent" || before.sharing !== "unshared" || before.extra_fields.length || before.notes !== o.preserve_text) fail("redundant_note_proof_refused");
        const keeper = await native.read(o.keeper!.target);
        if (await hash(keeper) !== o.keeper!.before_sha256 || keeper.sharing !== "unshared" || !keeper.notes.includes(before.notes) ||
          o.source_ids!.some(x => !keeper.notes.includes(x))) fail("keeper_proof_refused");
      }
      const afterHash = intended ? await hash(intended) : undefined;
      await append(o, "intent", afterHash); // fsync precedes any mutation
      try {
        const result = await native.call(o.kind, { key: o.target, expected: before, ...(intended ? { notes: intended.notes } : {}) });
        mutations++;
        if (intended) {
          if (await hash(await native.read(o.target)) !== afterHash) fail("readback_changed");
        } else {
          if (result.recoverable !== true || await hash(await native.read(o.target, true, before)) !== o.before_sha256) fail("deletion_unverified");
          let found = false;
          try { await native.read(o.target); found = true; } catch (e) { if (!(e instanceof APWError) || e.message !== "maintenance_item_not_found") throw e; }
          if (found || await hash(await native.read(o.keeper!.target)) !== o.keeper!.before_sha256) fail("deletion_unverified");
        }
        await append(o, "done", afterHash); completed++;
        console.error(JSON.stringify({ event: "maintenance_checkpoint", id: o.id, completed, total: operations.length }));
      } catch (e) { await append(o, "uncertain", afterHash); throw e; }
    }
    console.log(JSON.stringify({ completed, total: operations.length, mutations, ...(review ? {reviewed_no_change:reviewed}:{}), app_activated: false, imports: 0, exports: 0, permanent_deletions: 0 }));
  } finally {
    await native?.close(); file?.close();
    await Deno.remove(lock, { recursive: true });
  }
}
