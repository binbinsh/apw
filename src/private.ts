// Local apw fork changes, distributed under GPL-3.0; see LICENSE.
import { APWError, DATA_PATH, SOCKET_PATH, Status } from "./const.ts";
import { BROWSERS } from "./browser.ts";

function info(path: string): Deno.FileInfo | undefined {
  try {
    return Deno.lstatSync(path);
  } catch (e) {
    if (e instanceof Deno.errors.NotFound) return;
    throw e;
  }
}
export function validatePaths(create = false): void {
  const root = info(DATA_PATH);
  const fail = (code: string): never => {
    throw new APWError(Status.INVALID_PARAM, code);
  };
  if (root && (!root.isDirectory || root.isSymlink || root.uid !== Deno.uid() || (root.mode! & 0o077))) {
    fail("unsafe_apple_directory");
  }
  if (root) {
    const real = Deno.realPathSync(DATA_PATH);
    for (const browser of BROWSERS) {
      if (real === browser.dataPath || real.startsWith(browser.dataPath + "/")) fail("unsafe_apple_directory");
    }
  }
  if (create && !root) Deno.mkdirSync(DATA_PATH, { recursive: true, mode: 0o700 });
  for (const name of ["browser", "browser/brave", "extension", "daemon.lock", "daemon.log", "config.json"]) {
    if (info(`${DATA_PATH}/${name}`)?.isSymlink) fail("unsafe_apple_directory");
  }
  const socket = info(SOCKET_PATH);
  if (socket && (socket.isSymlink || !socket.isSocket || socket.uid !== Deno.uid() || (socket.mode! & 0o077))) {
    fail("unsafe_apple_socket");
  }
}

export async function writeAll(conn: Deno.Conn, bytes: Uint8Array): Promise<void> {
  for (let offset = 0; offset < bytes.length;) offset += await conn.write(bytes.subarray(offset));
}
