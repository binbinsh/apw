import { Command, Input, Secret, Select } from "./deps.ts";
import { daemon } from "./daemon.ts";
import { ApplePasswordManager } from "./client.ts";
import { BROWSERS, installedBrowsers } from "./browser.ts";
import { readConfig, writeConfig } from "./config.ts";
import { APWError, Status, VERSION } from "./const.ts";
import type { PasswordEntry, Payload } from "./types.ts";
import { ensureStarted } from "./startup.ts";
import { exchangeStatus, launchExchangeDemo, launchOTPLoginDemo, prepareExchangeComponent } from "./exchange.ts";
import { launchNotesImport, prepareNotes } from "./notes.ts";
import { readItem, inspectItems, runBatch, maintenanceDoctor, maintenanceConnect, recoverEditor, probeNotesEditor, syntheticForegroundNotesInput } from "./maintenance.ts";
import { capabilities } from "./capabilities.ts";

const client = new ApplePasswordManager();

const printSuccess = () => console.log(JSON.stringify({ status: Status.SUCCESS }));

function printResult(payload: Payload, table: boolean): void {
  const entries = payload.Entries.map((entry) => {
    if ("USR" in entry) {
      return {
        username: entry.USR,
        domain: entry.sites[0],
        ...(entry.customTitle && { title: entry.customTitle }),
        ...(entry.PWD !== "Not Included" && { password: entry.PWD }),
        ...(entry.sites && { sites: entry.sites }),
        ...(entry.highLevelDomain && { highLevelDomain: entry.highLevelDomain }),
      };
    } else {
      return {
        username: entry.username,
        domain: entry.domain,
        ...(entry.source && { source: entry.source }),
        ...(entry.code && { code: entry.code }),
      };
    }
  });
  if (table) {
    console.table(entries);
  } else {
    console.log(JSON.stringify({ results: entries, status: Status.SUCCESS,
      ...(payload.RequiresUserAuthenticationToFill !== undefined
        ? { requires_user_authentication_to_fill: payload.RequiresUserAuthenticationToFill } : {}) }));
  }
}

const otp = new Command()
  .description("Interactively list accounts/OTPs.")
  .globalOption("-t, --table", "Output as a table.")
  .globalOption("-j, --json", "Output as JSON.")
  .action(async ({ json }: { json?: boolean }) => {
    await client.checkReady();
    const action: string = await Select.prompt({
      message: "Choose an action: ",
      options: ["list OTPs", "get OTPs"],
    });
    const url = await Input.prompt({ message: "Enter URL: ", minLength: 1 });
    if (action === "list OTPs") {
      printResult(await client.listOTPForURL(url), !json);
    } else if (action === "get OTPs") {
      printResult(await client.getOTPForURL(url), !json);
    }
  })
  .command("get", "Get an OTP for a website.")
  .arguments("<url:string> [username:string]")
  .option("--interactive", "Explicitly allow Apple's required user authentication for this selected OTP.")
  .action(async ({ table, json, interactive }: { table?: boolean; json?: boolean; interactive?: boolean }, url: string, username?: string) => {
    printResult(await client.getOTPForURL(url,username,interactive === true), !!table && !json);
  })
  .command("list", "List available OTPs for a website.")
  .arguments("<url:string>")
  .action(async ({ table, json }: { table?: boolean; json?: boolean }, url: string) => {
    printResult(await client.listOTPForURL(url), !!table && !json);
  })
  .reset();

const pw = new Command()
  .description("Interactively manage accounts/passwords.")
  .globalOption("-t, --table", "Output as a table.")
  .globalOption("-j, --json", "Output as JSON.")
  .action(async ({ json }: { json?: boolean }) => {
    await client.checkReady();
    const action: string = await Select.prompt({
      message: "Choose an action: ",
      options: ["list accounts", "get password", "save account"],
    });
    const url = await Input.prompt({ message: "Enter URL: ", minLength: 1 });
    if (action === "save account") {
      const username = await Input.prompt({
        message: "Enter username: ",
        minLength: 1,
      });
      const password = await Secret.prompt({
        message: "Enter password: ",
        minLength: 1,
      });
      await client.saveAccountForURL(url, username, password);
      printSuccess();
      return;
    }
    if (action === "list accounts") {
      printResult(await client.getLoginNamesForURL(url), !json);
    } else if (action === "get password") {
      const accounts = await client.getLoginNamesForURL(url);
      if (!accounts.Entries.length) {
        console.log("No accounts found.");
        return;
      }
      const options = [
        { name: "All", value: "" },
        ...accounts.Entries
          .filter((e): e is PasswordEntry => "USR" in e)
          .map((e) => ({ name: `${e.USR} (${e.sites[0]})`, value: e.USR })),
      ];
      const username = options.length === 2
        ? options[1].value
        : await Select.prompt({ message: "Select account:", options });
      printResult(await client.getPasswordForURL(url, username), !json);
    }
  })
  .command("get", "Get a password for a website.")
  .arguments("<url:string> [username:string]")
  .option("--interactive", "Explicitly allow Apple's required user authentication for password retrieval.")
  .option("--wait-seconds <seconds:integer>", "Opt-in bounded wait (26..90 seconds), requires --interactive; never retries Apple.")
  .action(async ({ table, json, interactive, waitSeconds }: { table?: boolean; json?: boolean; interactive?: boolean; waitSeconds?: number }, url: string, username?: string) => {
    if (waitSeconds !== undefined && (!interactive || !Number.isInteger(waitSeconds) || waitSeconds < 26 || waitSeconds > 90)) {
      throw new APWError(Status.INVALID_PARAM, "apple_password_wait_invalid");
    }
    const metadata = await client.getLoginNamesForURL(url);
    if (!metadata.Entries.length) {
      printResult(metadata, !!table && !json);
      return;
    }
    if (metadata.RequiresUserAuthenticationToFill === true && !interactive) {
      throw new APWError(Status.INVALID_SESSION, "apple_password_user_authentication_required");
    }
    printResult(await client.getPasswordForURL(url, username, waitSeconds), !!table && !json);
  })
  .command("list", "List available accounts for a website.")
  .arguments("<url:string>")
  .action(async ({ table, json }: { table?: boolean; json?: boolean }, url: string) => {
    printResult(await client.getLoginNamesForURL(url), !!table && !json);
  })
  .command("save", "Create or update a password.")
  .option("--stdin", "Read password from stdin instead of prompting.")
  .arguments("<url:string> <username:string>")
  .action(async (options: { stdin?: boolean }, url: string, username: string) => {
    const pwd = options.stdin
      ? await new Response(Deno.stdin.readable).text()
      : await Secret.prompt({ message: "Enter password: ", minLength: 1 });
    await client.saveAccountForURL(url, username, pwd);
    printSuccess();
  })
  .reset();

const batchRun = () => new Command()
  .description("Validate or execute at most 50 exact, journaled native maintenance operations.")
  .option("--plan <path:string>", "Private hash-bound JSON plan.", { required: true })
  .option("--journal <path:string>", "Private fsynced checkpoint journal.", { required: true })
  .option("--apply", "Execute once; default only validates without native calls.")
  .action(async (o: { plan: string; journal: string; apply?: boolean }) => await runBatch(o.plan,o.journal,o.apply === true));
const batch = new Command().description("Recoverable, resumable maintenance batches.")
  .command("run", batchRun())
  .command("review",new Command().description("Read-only resolution of uncertain operations whose complete before-state is unchanged.")
    .option("--plan <path:string>","Original private plan.",{required:true})
    .option("--journal <path:string>","Original checkpoint journal.",{required:true})
    .option("--acknowledge-unchanged","Explicitly permit a later new dispatch only after exact unchanged readback.",{required:true})
    .action(async (o:{plan:string;journal:string;acknowledgeUnchanged?:boolean}) => {
      if (!o.acknowledgeUnchanged) throw new APWError(Status.INVALID_PARAM,"maintenance_review_requires_acknowledgement");
      await runBatch(o.plan,o.journal,true,undefined,true);
    }))
  .command("inspect", new Command().description("Read at most 50 named items using one native list index; no whole-vault export.")
    .option("--targets <path:string>", "Private explicit target list.", {required:true})
    .option("--output <path:string>", "New private snapshot file.", {required:true})
    .action(async (o:{targets:string;output:string}) => await inspectItems(o.targets,o.output)));
const item = new Command().description("Exact native item/notes maintenance; never activates an app.")
  .command("test-notes-input", new Command().description("One journaled notes-input trial on two exact pre-existing synthetic fixtures; Passwords must already be foreground.")
    .option("--snapshot <path:string>", "Private hash-verified original synthetic snapshot.", {required:true})
    .option("--notes-file <path:string>", "Private UTF-8 notes preserving the complete original body.", {required:true})
    .option("--journal <path:string>", "New private one-shot journal; existing journals are never retried.", {required:true})
    .option("--foreground-synthetic", "Explicitly allow this narrow synthetic foreground trial; never activates an app.")
    .action(async (o:{snapshot:string;notesFile:string;journal:string;foregroundSynthetic?:boolean}) => {
      if (o.foregroundSynthetic !== true) throw new APWError(Status.INVALID_PARAM,"maintenance_synthetic_foreground_required");
      await syntheticForegroundNotesInput(o.snapshot,o.notesFile,o.journal);
    }))
  .command("probe-notes", new Command().description("Read-only NotesField diagnosis on a hash-verified pre-existing synthetic fixture; never changes search or authorizes a mutation.")
    .option("--snapshot <path:string>","Original private synthetic item snapshot.",{required:true})
    .option("--foreground-focus","Explicit synthetic-only field-focus diagnosis; Passwords must already be foreground. Never activates it.")
    .action(async (o:{snapshot:string;foregroundFocus?:boolean}) => await probeNotesEditor(o.snapshot,o.foregroundFocus === true)))
  .command("recover-editor", new Command().description("Cancel a readonly editor only after two complete observations equal the original private snapshot; never changes field values or journals.")
    .option("--snapshot <path:string>","Original private, hash-verified item snapshot.",{required:true})
    .action(async (o:{snapshot:string}) => await recoverEditor(o.snapshot)))
  .command("connect", new Command().description("Reopen Apple's signed Passwords window in the background; never unlock or activate it.")
    .action(async () => await maintenanceConnect()))
  .command("doctor", new Command().description("Report native access/capabilities without opening or unlocking an app.")
    .action(async () => await maintenanceDoctor()))
  .command("read", new Command().description("Read one exact native item into a new private snapshot file.")
    .option("--title <text:string>", "Exact displayed title.", { required: true })
    .option("--username <text:string>", "Exact account, including empty string.", { required: true })
    .option("--output <path:string>", "New private snapshot, never stdout.", { required: true })
    .action(async (o: { title:string; username:string; output:string }) => await readItem(o.title,o.username,o.output)))
  .command("delete", new Command().description("Recoverably delete proven redundant notes; logins/passkeys are protected.")
    .option("--plan <path:string>", "Private proof plan.", { required:true })
    .option("--journal <path:string>", "Private checkpoint journal.", { required:true })
    .option("--apply", "Execute; default validates only.")
    .action(async (o:{plan:string;journal:string;apply?:boolean}) => await runBatch(o.plan,o.journal,o.apply === true,"delete-redundant-note")))
  .command("notes", new Command().description("Edit existing notes without reimporting records.")
    .command("set", new Command().description("Preserve existing body and all other fields, then verify exact readback.")
      .option("--plan <path:string>", "Private before-hash and full after-body plan.", {required:true})
      .option("--journal <path:string>", "Private checkpoint journal.", {required:true})
      .option("--apply", "Execute; default validates only.")
      .action(async (o:{plan:string;journal:string;apply?:boolean}) => await runBatch(o.plan,o.journal,o.apply === true,"notes-set"))));

const start = new Command()
  .description("Start APW and choose a managed browser.")
  .option("-b, --browser <browser:string>", "Browser to use (auto, chromium, chrome, brave, or edge).")
  .action(async (options: { browser?: string }) => {
    const browsers = installedBrowsers();
    if (!browsers.length) {
      const hints = BROWSERS.map(({ name, brewCask }) => `  brew install --cask ${brewCask}  # ${name}`).join("\n");
      throw new APWError(Status.GENERIC_ERROR, `No supported browser found. Install one:\n${hints}`);
    }
    const saved = readConfig().browser ?? "auto";
    let selected: string;
    if (options.browser) {
      selected = options.browser.toLowerCase();
    } else if (Deno.stdin.isTerminal()) {
      selected = (await Select.prompt({
        message: "Browser:",
        default: saved,
        options: ["auto", ...browsers.map(({ id }) => id)],
      })).toLowerCase();
    } else {
      selected = saved;
    }
    if (selected !== saved) writeConfig({ browser: selected });
    const browser = selected === "auto"
      ? browsers[0]
      : browsers.find(({ id, name }) => id === selected || name.toLowerCase() === selected);
    if (!browser) {
      throw new APWError(Status.INVALID_PARAM, `Unsupported browser: ${selected}`);
    }
    await daemon(browser);
  });

const auth = new Command()
  .description("Authenticate CLI with daemon.")
  .action(async () => {
    if (!Deno.stdin.isTerminal()) throw new APWError(Status.INVALID_PARAM, "pair_requires_terminal");
    await ensureStarted(client);
    await client.requestChallenge();
    const pin = await Secret.prompt({
      message: "Enter PIN: ",
      minLength: 6,
      maxLength: 6,
    });
    await client.verifyChallenge(pin);
    printSuccess();
  })
  .command("request", "Request a challenge from the daemon.")
  .action(async () => {
    await client.requestChallenge();
    printSuccess();
  })
  .command("response", "Respond to a challenge from the daemon.")
  .option("--stdin", "Read the PIN from stdin, never process arguments.", { required: true })
  .action(async () => {
    const pin = (await new Response(Deno.stdin.readable).text()).trim();
    if (!/^[0-9]{6}$/.test(pin)) throw new APWError(Status.INVALID_PARAM, "invalid_pairing_code");
    await client.verifyChallenge(pin);
    printSuccess();
  });

const exchange = new Command()
  .description("Optional official Apple API trial using three synthetic records.")
  .action(async () => console.log(JSON.stringify(await exchangeStatus())))
  .command("status", new Command().description("Verify the signed component without opening a window.")
    .action(async () => console.log(JSON.stringify(await exchangeStatus()))))
  .command("prepare", new Command().description("Stop only this verified component; never open a window.")
    .action(async () => console.log(JSON.stringify(await prepareExchangeComponent()))))
  .command("demo", new Command().description("Open the user-operated synthetic handoff component.")
    .option("--interactive", "Explicitly allow opening the component and Apple's system UI.")
    .action(async (options: { interactive?: boolean }) => await launchExchangeDemo(options.interactive === true)))
  .command("otp-login-demo", new Command().description("Test one fixed synthetic login containing a bound TOTP; no real migration data.")
    .option("--interactive", "Open the person-operated synthetic control window.")
    .option("--check", "Check signed encoding and the one-shot journal; never open UI.")
    .action(async (options: { interactive?: boolean; check?: boolean }) => await launchOTPLoginDemo(options.interactive === true,options.check === true)))
  .command("notes-prepare", new Command().description("Prepare private source-linked native notes; no UI or credential writes.")
    .option("--plan <path:string>", "Private fresh workaround plan.", { required: true })
    .option("--output <path:string>", "Optional private transport path for validation.")
    .option("--batch <name:string>", "Separate private migration correction batch.")
    .action(async (options: { plan: string; output?: string; batch?: string }) => await prepareNotes(options.plan, options.output, options.batch)))
  .command("notes-import", new Command().description("Open the user-operated official notes-only import.")
    .option("--interactive", "Explicitly allow opening the component and Apple's system UI.")
    .option("--check", "Validate with the signed component; no window, API call, or writes.")
    .option("--batch <name:string>", "Explicit correction batch; default transport remains unchanged.")
    .action(async (options: { interactive?: boolean; check?: boolean; batch?: string }) => await launchNotesImport(options.interactive === true, options.check === true, options.batch)))
  .command("credentials-prepare", new Command().description("Stage reviewed missing native identities, preserving own credentials; no UI.")
    .option("--plan <path:string>", "Private reviewed new-identity migration plan.", { required: true })
    .option("--output <path:string>", "Explicit private transport for codec validation.")
    .option("--batch <name:string>", "Isolated named native credential batch.")
    .action(async (options: { plan: string; output?: string; batch?: string }) => await prepareNotes(options.plan,options.output,options.batch,true)))
  .command("credentials-import", new Command().description("Open official exchange for a reviewed new-identity batch.")
    .option("--interactive", "Explicitly open the user-operated exchange window.")
    .option("--check", "Validate the private native batch without UI.")
    .option("--batch <name:string>", "Named native credential batch.")
    .action(async (options: { interactive?: boolean; check?: boolean; batch?: string }) => await launchNotesImport(options.interactive === true,options.check === true,options.batch,true)))
  .command("otp-prepare", new Command().description("Stage reviewed TOTP-only data without native password credentials or UI.")
    .option("--plan <path:string>", "Private reviewed OTP-only migration plan.", { required: true })
    .option("--output <path:string>", "Explicit private transport for codec validation.")
    .option("--batch <name:string>", "Isolated named OTP batch.")
    .action(async (options: { plan: string; output?: string; batch?: string }) => await prepareNotes(options.plan,options.output,options.batch,false,true)))
  .command("otp-import", new Command().description("Open official exchange for a reviewed OTP-only batch.")
    .option("--interactive", "Explicitly open the user-operated exchange window.")
    .option("--check", "Validate the private OTP batch without UI.")
    .option("--batch <name:string>", "Named OTP batch.")
    .action(async (options: { interactive?: boolean; check?: boolean; batch?: string }) => await launchNotesImport(options.interactive === true,options.check === true,options.batch,false,true)));

try {
  await new Command()
    .throwErrors()
    .name("apw")
    .version(`v${VERSION}`)
    .description("🔑 a CLI for Apple Passwords 🔒")
    .command("capabilities", new Command().description("Report field/settings coverage and acceptance gaps offline; never opens an app or reads credentials.")
      .action(() => console.log(JSON.stringify(capabilities()))))
    .command("auth", auth)
    .command("pw", pw)
    .command("item", item)
    .command("batch", batch)
    .command("otp", otp)
    .command("exchange", exchange)
    .command("start", start)
    .command(
      "status",
      new Command().description("Report daemon and pairing state.").action(async () =>
        console.log(JSON.stringify(await client.status()))
      ),
    )
    .command(
      "stop",
      new Command().description("Stop only this managed daemon/browser.").action(async () => {
        if ((await client.status()).running) await client.stop();
        printSuccess();
      }),
    )
    .parse(Deno.args);
} catch (error: unknown) {
  let status = Status.GENERIC_ERROR;
  let msg = "Unknown Error";
  if (error instanceof APWError || error instanceof Error) {
    status = error instanceof APWError ? error.status : status;
    msg =
      ["apple_otp_account_selection_required", "apple_otp_user_authentication_required", "apple_password_user_authentication_required",
        "apple_native_timeout", "apple_native_reply_invalid", "apple_native_request_failed", "apple_native_channel_busy",
        "apple_native_frame_exhausted", "apple_native_operation_failed", "apple_native_response_invalid", "apple_browser_mode_invalid",
        "apple_native_wait_invalid", "apple_native_wait_expired", "apple_password_wait_invalid", "apple_password_value_unavailable"].includes(error.message) ||
      /^(maintenance_|unsafe_apple_|pair_requires_terminal|apple_pairing_failed|invalid_pairing_code|extension_verification_failed|apple_daemon_already_running|apple_write_unverified|exchange_)/
          .test(error.message)
        ? error.message
        : "operation_failed";
  }
  console.error(JSON.stringify({ error: msg, status, results: [],
    ...(error instanceof APWError && error.diagnostics && Object.keys(error.diagnostics).length ? {diagnostics:error.diagnostics} : {}) }));
  Deno.exit(status);
}
