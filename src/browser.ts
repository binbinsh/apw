import bridgeSource from "../ext/bridge.js" with { type: "text" };
import { writeConfig } from "./config.ts";
import { APWError, BROWSER_PROFILE_PATH, EXTENSION_PATH, Status } from "./const.ts";
import trust from "./extension-trust.json" with { type: "json" };

const HOME = Deno.env.get("HOME")!;
const APPLE_MANIFEST = "/Library/Google/Chrome/NativeMessagingHosts/com.apple.passwordmanager.json";
const EXTENSION_ID = "pejdijmoenmkgeppbflobdenhhabjlaj";
const BACKGROUND = "background.js";

export interface Browser {
  id: string;
  name: string;
  bin: string;
  profile: string;
  dataPath: string;
  brewCask: string;
}

function browser(id: string, name: string, app: string, dataDir: string, brewCask: string): Browser {
  return {
    id,
    name,
    bin: `/Applications/${app}.app/Contents/MacOS/${app}`,
    profile: `${BROWSER_PROFILE_PATH}/${id}`,
    dataPath: `${HOME}/Library/Application Support/${dataDir}`,
    brewCask,
  };
}

export const BROWSERS = [
  browser("chromium", "Ungoogled Chromium", "Chromium", "Chromium", "ungoogled-chromium"),
  browser("edge", "Microsoft Edge", "Microsoft Edge", "Microsoft Edge", "microsoft-edge"),
  browser("brave", "Brave", "Brave Browser", "BraveSoftware/Brave-Browser", "brave-browser"),
  browser("chrome", "Google Chrome", "Google Chrome", "Google/Chrome", "google-chrome"),
];

function exists(path: string): boolean {
  try {
    Deno.statSync(path);
    return true;
  } catch {
    return false;
  }
}

function directories(path: string): string[] {
  try {
    return [...Deno.readDirSync(path)].filter((entry) => entry.isDirectory).map((entry) => entry.name);
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) return [];
    throw error;
  }
}

function remove(path: string): void {
  try {
    Deno.removeSync(path, { recursive: true });
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
  }
}

function copyDirectory(source: string, target: string): void {
  Deno.mkdirSync(target, { recursive: true });
  for (const entry of Deno.readDirSync(source)) {
    const from = `${source}/${entry.name}`;
    const to = `${target}/${entry.name}`;
    if (entry.isDirectory) {
      copyDirectory(from, to);
    } else if (entry.isFile) {
      Deno.copyFileSync(from, to);
    }
  }
}

function extensionSource(): string | undefined {
  const explicit = Deno.env.get("APW_EXTENSION_SOURCE") ?? `${Deno.execPath().replace(/\/[^/]+$/, "")}/APWExtension`;
  if (exists(`${explicit}/${BACKGROUND}`)) return explicit;
  for (const { dataPath } of BROWSERS) {
    for (const profile of directories(dataPath)) {
      const base = `${dataPath}/${profile}/Extensions/${EXTENSION_ID}`;
      const version = directories(base).sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).at(-1);
      if (!version) continue;
      const path = `${base}/${version}`;
      if (exists(`${path}/${BACKGROUND}`)) return path;
    }
  }
}

async function validateExtension(source: string): Promise<void> {
  if (Deno.lstatSync(source).isSymlink) throw new APWError(Status.INVALID_PARAM, "unsafe_extension_source");
  for (const [name, expected] of Object.entries(trust.file_hashes)) {
    const path = `${source}/${name}`;
    const parts = name.split("/");
    for (let i = 1; i <= parts.length; i++) {
      if (Deno.lstatSync(`${source}/${parts.slice(0, i).join("/")}`).isSymlink) {
        throw new APWError(Status.INVALID_PARAM, "unsafe_extension_source");
      }
    }
    const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", Deno.readFileSync(path)));
    if (Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("") !== expected) {
      throw new APWError(Status.INVALID_PARAM, "extension_verification_failed");
    }
  }
  function walk(path: string, prefix = ""): void {
    for (const entry of Deno.readDirSync(path)) {
      const name = prefix + entry.name;
      if (entry.isSymlink) throw new APWError(Status.INVALID_PARAM, "unsafe_extension_source");
      if (entry.isDirectory) walk(`${path}/${entry.name}`, name + "/");
      else if (!(name in trust.file_hashes) && name !== "ap-source-verification.json") {
        throw new APWError(Status.INVALID_PARAM, "extension_verification_failed");
      }
    }
  }
  walk(source);
}

async function buildExtension(config: { port: number; token: string }): Promise<void> {
  const background = `${EXTENSION_PATH}/${BACKGROUND}`;
  const orig = `${background}.orig`;

  {
    const source = extensionSource();
    if (!source) {
      throw new APWError(
        Status.GENERIC_ERROR,
        "Apple Passwords extension not found. Install it from the Chrome Web Store.",
      );
    }
    await validateExtension(source);
    remove(EXTENSION_PATH);
    Deno.mkdirSync(EXTENSION_PATH, { recursive: true });
    copyDirectory(source, EXTENSION_PATH);
    remove(`${EXTENSION_PATH}/_metadata`);
    Deno.copyFileSync(background, orig);
    writeConfig({ extensionVersion: source.split("/").at(-1)!, extensionPath: source });
  }

  Deno.writeTextFileSync(
    background,
    `${Deno.readTextFileSync(orig)}\nself.APW_CONFIG = ${JSON.stringify(config)};\n${bridgeSource}\n`,
  );
}

export function installedBrowsers(): Browser[] {
  return BROWSERS.filter(({ bin }) => exists(bin));
}

async function debuggerUrl(port: number): Promise<string> {
  const endpoint = `http://127.0.0.1:${port}/json/version`;
  for (let attempt = 0; attempt < 60; attempt++) {
    const data = await fetch(endpoint).then((response) => response.json()).catch(() => ({}));
    if (data.webSocketDebuggerUrl) return data.webSocketDebuggerUrl;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Browser DevTools endpoint did not start");
}

async function loadExtension(port: number): Promise<void> {
  const socket = new WebSocket(await debuggerUrl(port));
  try {
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("Extensions.loadUnpacked timed out")), 15_000);
      const finish = (error?: Error) => {
        clearTimeout(timer);
        error ? reject(error) : resolve();
      };
      socket.onerror = () => finish(new Error("DevTools connection failed"));
      socket.onopen = () =>
        socket.send(JSON.stringify({
          id: 1,
          method: "Extensions.loadUnpacked",
          params: { path: EXTENSION_PATH },
        }));
      socket.onmessage = (event) => {
        const message = JSON.parse(event.data as string);
        if (message.id === 1) finish(message.error && new Error(message.error.message));
      };
    });
  } finally {
    socket.close();
  }
}

export function browserArguments(browser: Browser, mode = Deno.env.get("APW_BROWSER_MODE") ?? "headless"): string[] {
  if (mode !== "headless" && mode !== "visible") throw new APWError(Status.INVALID_PARAM, "apple_browser_mode_invalid");
  return [
    `--user-data-dir=${browser.profile}`,
    "--remote-debugging-port=0",
    "--remote-debugging-address=127.0.0.1",
    "--enable-unsafe-extension-debugging",
    ...(mode === "headless" ? ["--headless=new"] : []),
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    ...(mode === "visible" ? ["about:blank"] : []),
  ];
}

export async function launchBrowser(
  browser: Browser,
  config: { port: number; token: string },
): Promise<Deno.ChildProcess> {
  // Reject unsupported modes before any extension or profile mutation.
  const args = browserArguments(browser);
  await buildExtension(config);
  remove(browser.profile);
  const hosts = `${browser.profile}/NativeMessagingHosts`;
  Deno.mkdirSync(hosts, { recursive: true });
  Deno.copyFileSync(APPLE_MANIFEST, `${hosts}/com.apple.passwordmanager.json`);

  const child = new Deno.Command(browser.bin, {
    args,
    stdout: "null",
    stderr: "null",
  }).spawn();

  try {
    // Read the endpoint written by this browser in this freshly created profile,
    // so a random-port collision cannot attach us to another user's browser.
    let port = 0;
    for (let attempt = 0; attempt < 60; attempt++) {
      try {
        const lines = Deno.readTextFileSync(`${browser.profile}/DevToolsActivePort`).split("\n");
        port = Number(lines[0]);
        if (port > 0 && port < 65536 && lines[1]?.startsWith("/devtools/browser/")) break;
        port = 0;
      } catch { /* starting */ }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    if (!port) throw new APWError(Status.SERVER_ERROR);
    await loadExtension(port);
    return child;
  } catch (error) {
    child.kill("SIGTERM");
    throw error;
  }
}
