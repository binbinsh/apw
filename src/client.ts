import { Action, APWError, Command, SOCKET_PATH, Status } from "./const.ts";
import type { APWResponse, DecryptedData, Message, PasswordEntry, Payload, TOTPEntry } from "./types.ts";
import { validatePaths, writeAll } from "./private.ts";

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function passwordHost(value: string): string {
  if (!value || Array.from(value).some((c) => c.charCodeAt(0) <= 32)) throw new APWError(Status.INVALID_PARAM);
  try {
    const url = new URL(value.includes("://") ? value : `https://${value}`);
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password) throw new Error();
    return url.host;
  } catch {
    throw new APWError(Status.INVALID_PARAM);
  }
}

function otpFrameURL(value: string): string {
  try {
    const url = new URL(value.includes("://") ? value : `https://${value}`);
    if (!["http:", "https:"].includes(url.protocol) || !url.hostname || url.username || url.password || value.length > 8192) throw new Error();
    return url.toString();
  } catch { throw new APWError(Status.INVALID_PARAM); }
}

async function readLine(conn: Deno.Conn): Promise<string> {
  const buf = new Uint8Array(64 * 1024);
  let text = "";
  while (!text.includes("\n")) {
    const n = await conn.read(buf);
    if (n === null) break;
    text += decoder.decode(buf.subarray(0, n), { stream: true });
    if (text.length > 1024 * 1024) throw new APWError(Status.SERVER_ERROR);
  }
  return text.split("\n", 1)[0];
}

export const APWMessages = {
  getLoginNamesForURL(url: string): Message {
    return {
      cmd: Command.GET_LOGIN_NAMES_FOR_URL,
      qid: "CmdGetLoginNames4URL",
      tabId: 1,
      frameId: 1,
      url: passwordHost(url),
      body: { ACT: Action.GHOST_SEARCH, URL: passwordHost(url) },
    };
  },

  getPasswordForURL(url: string, loginName = ""): Message {
    return {
      cmd: Command.GET_PASSWORD_FOR_LOGIN_NAME,
      qid: "CmdGetPassword4LoginName",
      tabId: 0,
      frameId: 0,
      url: passwordHost(url),
      body: { ACT: Action.SEARCH, URL: passwordHost(url), USR: loginName },
    };
  },

  saveAccountForURL(url: string, loginName: string, password: string): Message {
    return {
      cmd: Command.SET_PASSWORD_FOR_LOGIN_NAME_AND_URL,
      qid: "CmdSetPassword4LoginName_URL",
      tabId: 0,
      frameId: 0,
      body: {
        ACT: Action.MAYBE_ADD,
        URL: "",
        USR: "",
        PWD: "",
        NURL: passwordHost(url),
        NUSR: loginName,
        NPWD: password,
      },
    };
  },

  getOTPForURL(url: string, username?: string): Message {
    return {
      cmd: Command.DID_FILL_ONE_TIME_CODE,
      qid: "CmdDidFillOneTimeCode",
      tabId: 0,
      frameId: 0,
      body: {
        ACT: Action.SEARCH,
        TYPE: "oneTimeCodes",
        frameURLs: [otpFrameURL(url)],
        ...(username !== undefined ? { username } : {}),
      },
    };
  },

  listOTPForURL(url: string): Message {
    return {
      cmd: Command.GET_ONE_TIME_CODES,
      qid: "CmdGetOneTimeCodes",
      tabId: 0,
      frameId: 0,
      body: {
        ACT: Action.GHOST_SEARCH,
        TYPE: "oneTimeCodes",
        frameURLs: [otpFrameURL(url)],
      },
    };
  },
};

export function entriesFrom(data: DecryptedData): unknown[] {
  if (!data || typeof data.STATUS !== "number") {
    throw new APWError(Status.SERVER_ERROR, "apple_native_response_invalid");
  }
  if (data.STATUS === Status.NO_RESULTS) return [];
  if (data.STATUS !== Status.SUCCESS) {
    throw new APWError(data.STATUS as Status, data.STATUS === Status.SERVER_ERROR ? "apple_native_operation_failed" : undefined);
  }
  if (Array.isArray(data.Entries)) return data.Entries;
  return Object.entries(data)
    .filter(([key]) => key.startsWith("Entry_"))
    .sort(([a], [b]) => a.localeCompare(b, undefined, { numeric: true }))
    .map(([, value]) => value);
}

export class ApplePasswordManager {
  private async sendMessage(message: Message, timeoutMS = 35_000): Promise<APWResponse> {
    validatePaths();
    let conn: Deno.Conn;
    try {
      conn = await Deno.connect({ transport: "unix", path: SOCKET_PATH });
    } catch {
      throw new APWError(Status.INVALID_SESSION);
    }

    const timer = setTimeout(() => {
      try {
        conn.close();
      } catch { /* closed */ }
    }, Math.min(35_000, timeoutMS));
    try {
      await writeAll(conn, encoder.encode(`${JSON.stringify(message)}\n`));
      const response = JSON.parse(await readLine(conn)) as APWResponse;
      if (!("data" in response) && response.status !== Status.SUCCESS) {
        const rawError = (response as { error?: unknown }).error;
        const known: Record<string, string> = {
          native_timeout: "apple_native_timeout",
          native_reply_invalid: "apple_native_reply_invalid",
          native_request_failed: "apple_native_request_failed",
          busy: "apple_native_channel_busy",
          native_frame_exhausted: "apple_native_frame_exhausted",
          native_wait_invalid: "apple_native_wait_invalid",
          native_wait_expired: "apple_native_wait_expired",
        };
        const message = typeof rawError === "string" && Object.hasOwn(known, rawError) ? known[rawError] : undefined;
        throw new APWError(response.status, message);
      }
      return response;
    } finally {
      clearTimeout(timer);
      try {
        conn.close();
      } catch { /* timeout */ }
    }
  }

  private async getPayload(message: Message, waitMS?: number): Promise<Payload> {
    const deadline = performance.now() + (waitMS ?? 35_000);
    let response = await this.sendMessage(message);
    let token: string | undefined;
    let polls = 0;
    while ("data" in response && Object.hasOwn(response.data, "APW_WAIT_TOKEN")) {
      const next = response.data.APW_WAIT_TOKEN;
      if (!waitMS || response.data.STATUS !== Status.SUCCESS ||
        Object.keys(response.data).sort().join(",") !== "APW_WAIT_TOKEN,STATUS" ||
        typeof next !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(next) ||
        (token !== undefined && token !== next)) throw new APWError(Status.SERVER_ERROR, "apple_native_wait_invalid");
      token = next;
      // These are local continuation connections, never repeated Apple fills.
      const remaining = deadline - performance.now();
      if (++polls > 5 || remaining <= 0) throw new APWError(Status.SERVER_ERROR, "apple_native_timeout");
      try {
        response = await this.sendMessage({ cmd: 0, qid: "APWLocalWait", tabId: 0, frameId: 0,
          body: null, apwWaitToken: token }, remaining + 500);
      } catch (error) {
        if (performance.now() >= deadline) throw new APWError(Status.SERVER_ERROR, "apple_native_timeout");
        throw error;
      }
    }
    if (!("data" in response)) throw new APWError(Status.SERVER_ERROR, "apple_native_response_invalid");
    return {
      STATUS: response.data.STATUS as Status,
      Entries: entriesFrom(response.data) as Array<PasswordEntry | TOTPEntry>,
      ...(typeof response.data.RequiresUserAuthenticationToFill === "boolean"
        ? { RequiresUserAuthenticationToFill: response.data.RequiresUserAuthenticationToFill } : {}),
    };
  }

  async checkReady(): Promise<void> {
    try {
      const conn = await Deno.connect({ transport: "unix", path: SOCKET_PATH });
      conn.close();
    } catch {
      throw new APWError(
        Status.INVALID_SESSION,
        "APW is not running or not authorised. Run `apw start` then `apw auth`.",
      );
    }
  }

  async requestChallenge(): Promise<void> {
    const response = await this.sendMessage({ cmd: Command.HANDSHAKE });
    if (!("data" in response) || response.data.ready !== true) throw new APWError(Status.SERVER_ERROR);
  }

  async verifyChallenge(pin: string): Promise<void> {
    const response = await this.sendMessage({ cmd: Command.HANDSHAKE, pin });
    if (!("data" in response) || response.data.paired !== true) {
      throw new APWError(Status.INVALID_SESSION, "apple_pairing_failed");
    }
  }

  getLoginNamesForURL(url: string): Promise<Payload> {
    if (!url) throw new APWError(Status.INVALID_PARAM, "URL is required");
    return this.getPayload(APWMessages.getLoginNamesForURL(url)).then((payload) => ({
      ...payload,
      Entries: payload.Entries.map((entry) => "USR" in entry ? { ...entry, PWD: "Not Included" } : entry),
    }));
  }

  async getPasswordForURL(url: string, loginName?: string, waitSeconds?: number): Promise<Payload> {
    if (!url) throw new APWError(Status.INVALID_PARAM, "URL is required");
    if (waitSeconds !== undefined && (!Number.isInteger(waitSeconds) || waitSeconds < 26 || waitSeconds > 90)) {
      throw new APWError(Status.INVALID_PARAM, "apple_password_wait_invalid");
    }
    const requestedHost = passwordHost(url).replace(/^www\./, "");
    const waitMS = waitSeconds === undefined ? undefined : waitSeconds * 1000;
    const message = APWMessages.getPasswordForURL(url, loginName);
    const payload = await this.getPayload({ ...message, ...(waitMS === undefined ? {} : { apwWaitMS: waitMS }) }, waitMS);
    payload.Entries = payload.Entries.filter((e) => "USR" in e &&
      (loginName === undefined || e.USR === loginName) && Array.isArray(e.sites) &&
      e.sites.some((site) => {
        try { return passwordHost(site).replace(/^www\./, "") === requestedHost; }
        catch { return false; }
      }));
    return payload;
  }

  async saveAccountForURL(url: string, loginName: string, password: string): Promise<void> {
    if (!url) throw new APWError(Status.INVALID_PARAM, "URL is required");
    const response = await this.sendMessage(APWMessages.saveAccountForURL(url, loginName, password));
    const status = "data" in response ? response.data.STATUS : Status.SERVER_ERROR;
    if (status !== Status.SUCCESS) throw new APWError(status ?? Status.SERVER_ERROR);
    try {
      const entries = (await this.getPasswordForURL(url, loginName)).Entries;
      if (
        entries.length !== 1 || !("USR" in entries[0]) || entries[0].PWD !== password ||
        entries[0].PWD === "Not Included"
      ) {
        throw new Error();
      }
    } catch {
      throw new APWError(Status.SERVER_ERROR, "apple_write_unverified");
    }
  }

  async status(): Promise<Record<string, unknown>> {
    try {
      const response = await this.sendMessage({ op: "status" });
      if (!("data" in response) || response.data.STATUS !== Status.SUCCESS) throw new APWError(Status.SERVER_ERROR);
      return response.data;
    } catch (error) {
      if (error instanceof APWError && error.status === Status.INVALID_SESSION) {
        return { running: false, bridge: false, paired: false };
      }
      throw error;
    }
  }
  async stop(): Promise<void> {
    await this.sendMessage({ op: "stop" });
  }

  async getOTPForURL(url: string, username?: string, interactive = false): Promise<Payload> {
    if (!url) throw new APWError(Status.INVALID_PARAM, "URL is required");
    const metadata = await this.listOTPForURL(url);
    const candidates = metadata.Entries.filter((e): e is TOTPEntry => "username" in e && typeof e.username === "string" &&
      typeof e.domain === "string" && (username === undefined || e.username === username));
    if (!candidates.length) return { ...metadata, Entries: [] };
    const accounts = [...new Set(candidates.map((e) => e.username))];
    if (accounts.length !== 1 || !accounts[0]) throw new APWError(Status.INVALID_PARAM, "apple_otp_account_selection_required");
    if (metadata.RequiresUserAuthenticationToFill === true && !interactive) {
      throw new APWError(Status.INVALID_SESSION, "apple_otp_user_authentication_required");
    }
    const selected = accounts[0];
    const filled = await this.getPayload(APWMessages.getOTPForURL(url, selected));
    return { ...filled, Entries: filled.Entries.filter((e) => "username" in e && e.username === selected && candidates.some((c) => c.domain === e.domain)) };
  }

  listOTPForURL(url: string): Promise<Payload> {
    if (!url) throw new APWError(Status.INVALID_PARAM, "URL is required");
    return this.getPayload(APWMessages.listOTPForURL(url));
  }
}
