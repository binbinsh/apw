import { APWError, DATA_PATH, SOCKET_PATH, Status } from "./const.ts";
import { type Browser, launchBrowser } from "./browser.ts";
import type { APWResponse, Message } from "./types.ts";
import { validatePaths, writeAll } from "./private.ts";

const REQUEST_TIMEOUT_MS = 30_000;

type ExtensionMessage = APWResponse | { token: string };

interface Pending {
  id: string;
  resolve: (value: APWResponse) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

class ExtensionSession {
  private ws: WebSocket | null = null;
  private pending: Pending | null = null;
  private chain: Promise<unknown> = Promise.resolve();

  constructor(private token: string) {}
  get ready(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  private rejectPending(error: Error): void {
    if (!this.pending) return;
    clearTimeout(this.pending.timer);
    this.pending.reject(error);
    this.pending = null;
  }

  accept(ws: WebSocket): void {
    if (this.ws) {
      ws.close(4001, "Already connected");
      return;
    }
    ws.addEventListener("message", (event) => {
      let message: ExtensionMessage;
      try {
        message = JSON.parse(event.data as string);
      } catch {
        ws.close(4002, "Bad JSON");
        return;
      }

      if (this.ws !== ws) {
        if (!("token" in message) || message.token !== this.token) {
          ws.close(4003, "Unauthorized");
          return;
        }
        this.ws = ws;
        console.info("[apw] extension connected");
        return;
      }

      if (!("token" in message) && this.pending && this.pending.id === message.id) {
        const pending = this.pending;
        this.pending = null;
        clearTimeout(pending.timer);
        pending.resolve(message as APWResponse);
      }
    });

    ws.addEventListener("close", () => {
      if (this.ws !== ws) return;
      this.ws = null;
      this.rejectPending(new Error("Extension disconnected"));
      console.info("[apw] extension disconnected");
    });
  }

  request(message: Message): Promise<APWResponse> {
    const result = this.chain.then(() => {
      const ws = this.ws;
      if (!ws) throw new APWError(Status.INVALID_SESSION);
      return new Promise<APWResponse>((resolve, reject) => {
        const id = crypto.randomUUID();
        const timer = setTimeout(
          () => this.rejectPending(new Error("Extension response timed out")),
          REQUEST_TIMEOUT_MS,
        );
        this.pending = { id, resolve, reject, timer };
        ws.send(JSON.stringify({ ...message, id }));
      });
    });
    this.chain = result.catch(() => {});
    return result;
  }
}

async function handleCliConnection(
  conn: Deno.Conn,
  session: ExtensionSession,
  details: { browser: Browser; pid: number; stop(): void },
): Promise<void> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  const buf = new Uint8Array(1024 * 64);
  let text = "";
  const send = async (response: APWResponse) => {
    try {
      await writeAll(conn, encoder.encode(`${JSON.stringify(response)}\n`));
    } catch (e) {
      if ((e as { code?: string }).code !== "EPIPE") throw e;
    }
  };

  try {
    const deadline = setTimeout(() => conn.close(), REQUEST_TIMEOUT_MS);
    try {
      while (!text.includes("\n")) {
        const n = await conn.read(buf);
        if (n === null) break;
        text += decoder.decode(buf.subarray(0, n), { stream: true });
        if (text.length > 1024 * 1024) break;
      }
    } finally {
      clearTimeout(deadline);
    }

    try {
      const message = JSON.parse(text.split("\n", 1)[0]) as Message;
      if ("op" in message && message.op === "status") {
        const state = session.ready ? await session.request({ op: "status" }) : null;
        const data: Record<string, unknown> = state && "data" in state ? state.data : {};
        await send({
          id: "",
          data: {
            STATUS: 0,
            running: true,
            bridge: session.ready,
            paired: data.paired === true,
            native_channel_ready: data.paired === true && data.native_channel_ready !== false,
            ...(data.native_reply_correlation ? { native_reply_correlation: data.native_reply_correlation } : {}),
            browser: details.browser.name,
            browser_pid: details.pid,
            daemon_pid: Deno.pid,
          },
        });
        return;
      }
      if ("op" in message && message.op === "stop") {
        await send({ id: "", data: { STATUS: 0, stopping: true } });
        setTimeout(details.stop, 20);
        return;
      }
      if (!("cmd" in message)) throw new APWError(Status.INVALID_PARAM);
      if (typeof message.cmd !== "number") {
        throw new APWError(Status.INVALID_PARAM);
      }
      await send(await session.request(message));
    } catch (error) {
      const err = error as Error;
      await send({
        id: "",
        status: err instanceof APWError ? err.status : Status.SERVER_ERROR,
        error: "request_failed",
      });
    }
  } finally {
    try {
      conn.close();
    } catch { /* timeout */ }
  }
}

export async function daemon(browser: Browser): Promise<void> {
  validatePaths(true);
  const lockPath = `${DATA_PATH}/daemon.lock`;
  const lockToken = crypto.randomUUID();
  function acquire(): void {
    try {
      const file = Deno.openSync(lockPath, { createNew: true, write: true, mode: 0o600 });
      try {
        file.writeSync(new TextEncoder().encode(JSON.stringify({ pid: Deno.pid, token: lockToken })));
      } finally {
        file.close();
      }
    } catch (e) {
      if (!(e instanceof Deno.errors.AlreadyExists)) throw e;
      try {
        const existing = JSON.parse(Deno.readTextFileSync(lockPath));
        Deno.kill(existing.pid, 0);
      } catch (probe) {
        if (probe instanceof Deno.errors.NotFound) {
          Deno.removeSync(lockPath);
          acquire();
          return;
        }
      }
      throw new APWError(Status.INVALID_SESSION, "apple_daemon_already_running");
    }
  }
  acquire();
  let child: Deno.ChildProcess | undefined;
  let listener: Deno.Listener | undefined;
  let server: Deno.HttpServer | undefined;
  let closing = false;
  let stopped: Promise<void> | undefined;
  const shutdown = (): void => {
    if (closing) return;
    closing = true;
    stopped = (async () => {
      try {
        listener?.close();
      } catch { /* closed */ }
      if (child) {
        try {
          child.kill("SIGTERM");
        } catch { /* gone */ }
        const timer = setTimeout(() => {
          try {
            child!.kill("SIGKILL");
          } catch { /* gone */ }
        }, 5000);
        await child.status.catch(() => {});
        clearTimeout(timer);
      }
      if (server) await server.shutdown().catch(() => {});
    })();
  };
  try {
    const token = crypto.randomUUID();
    const session = new ExtensionSession(token);
    server = Deno.serve({ hostname: "127.0.0.1", port: 0 }, (req) => {
      if (req.headers.get("upgrade")?.toLowerCase() !== "websocket") {
        return new Response("WebSocket upgrade required", { status: 426 });
      }
      const { socket, response } = Deno.upgradeWebSocket(req);
      session.accept(socket);
      return response;
    });
    child = await launchBrowser(browser, { port: (server.addr as Deno.NetAddr).port, token });
    // A lost browser also loses Apple's pairing. Release the owned daemon state
    // so a later auth can start a fresh bridge instead of waiting on a stale one.
    void child.status.then(shutdown, shutdown);
    console.info(`[apw] launched isolated headless ${browser.name}; extension loaded.`);
    for (const signal of ["SIGINT", "SIGTERM"] as const) Deno.addSignalListener(signal, shutdown);
    try {
      Deno.removeSync(SOCKET_PATH);
    } catch (e) {
      if (!(e instanceof Deno.errors.NotFound)) throw e;
    }
    listener = Deno.listen({ transport: "unix", path: SOCKET_PATH });
    Deno.chmodSync(SOCKET_PATH, 0o600);
    console.info(`[apw] Unix socket ready.`);
    try {
      for await (const conn of listener) {
        handleCliConnection(conn, session, { browser, pid: child.pid, stop: shutdown }).catch(() => {});
      }
    } catch (e) {
      if (!closing) throw e;
    }
    await stopped;
  } finally {
    shutdown();
    await stopped;
    for (const signal of ["SIGINT", "SIGTERM"] as const) {
      try {
        Deno.removeSignalListener(signal, shutdown);
      } catch { /* startup failure */ }
    }
    try {
      Deno.removeSync(SOCKET_PATH);
    } catch { /* absent */ }
    try {
      const existing = JSON.parse(Deno.readTextFileSync(lockPath));
      if (existing.token === lockToken) Deno.removeSync(lockPath);
    } catch { /* absent */ }
  }
}
