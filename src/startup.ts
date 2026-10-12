// Standalone apw managed daemon startup. GPL-3.0.
import { spawn } from "node:child_process";
import { closeSync, openSync } from "node:fs";
import { ApplePasswordManager } from "./client.ts";
import { DATA_PATH } from "./const.ts";
import { validatePaths } from "./private.ts";

class Failure extends Error {}
const fail = (code: string): never => {
  throw new Failure(code);
};
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export async function ensureStarted(client = new ApplePasswordManager()): Promise<Record<string, unknown>> {
  validatePaths(true);
  let status = await client.status();
  if (!status.running) {
    const fd = openSync(`${DATA_PATH}/daemon.log`, "a", 0o600);
    try {
      const args = Deno.build.standalone ? [] : ["run", "--frozen", "--allow-all", import.meta.resolve("./cli.ts")];
      const child = spawn(Deno.execPath(), [...args, "start", "--browser", "brave"], {
        detached: true,
        stdio: ["ignore", fd, fd],
        env: Deno.env.toObject(),
      });
      child.unref();
    } finally {
      closeSync(fd);
    }
  }
  const deadline = Date.now() + 40_000;
  while (Date.now() < deadline) {
    status = await client.status();
    if (status.running && status.bridge) return status;
    await delay(100);
  }
  return fail("apple_daemon_unavailable");
}
