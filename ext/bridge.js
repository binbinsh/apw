(function apwBridge() {
  self.APW_BRIDGE_V2?.dispose();
  const { port, token } = self.APW_CONFIG;
  const OK = 0, INVALID_SESSION = 9, SERVER_ERROR = 100;
  let ws, pending, stopped = false, reconnectTimer;
  const observedPort = g_nativeAppPort;
  const events = [], HISTORY_LIMIT = 32, COUNT_LIMIT = 2147483647;
  let eventCount = 0, droppedEvents = 0;
  const safeCommand = (cmd) => Number.isInteger(cmd) && (cmd >= 0 && cmd <= 19 || cmd === 1984) ? cmd : null;
  function observe(event, fields = {}) {
    eventCount = Math.min(COUNT_LIMIT, eventCount + 1);
    if (events.length === HISTORY_LIMIT) {
      events.shift();
      droppedEvents = Math.min(COUNT_LIMIT, droppedEvents + 1);
    }
    // Callers pass only fixed enums, booleans, safe command numbers and timing.
    // Never retain messages, request IDs, frame IDs, URLs or payloads.
    events.push({ event, timestamp_ms: Date.now(), ...fields });
  }
  const elapsed = () => pending ? Math.max(0, Math.round(performance.now() - pending.started)) : null;
  if (!Number.isInteger(self.APW_BRIDGE_FRAME_COUNTER)) {
    self.APW_BRIDGE_FRAME_COUNTER = 1000000 + crypto.getRandomValues(new Uint32Array(1))[0] % 1000000000;
  }
  const send = (message) => ws?.readyState === WebSocket.OPEN && ws.send(JSON.stringify(message));
  const fail = (id, status, error) => send({ id, status, error: String(error) });
  const waiting = () => ({ STATUS: OK, APW_WAIT_TOKEN: pending.token });
  function pulse() {
    if (!pending?.id) return;
    pending.pulseTimer = setTimeout(() => {
      if (!pending?.id || pending.done) return;
      send({ id: pending.id, data: waiting() });
      pending.id = null;
    }, 20000);
  }
  function deliver(id, result) {
    if (result.error) return fail(id, SERVER_ERROR, result.error);
    try {
      const data = result.packet.payload
        ? JSON.parse(g_secretSession.parseSMSG(result.packet.payload.SMSG))
        : { STATUS: result.packet.STATUS ?? SERVER_ERROR };
      observe("reply_forwarded", { request_cmd: result.requestCmd, reply_cmd: result.replyCmd,
        request_elapsed_ms: result.duration });
      send({ id, data });
    } catch (_) {
      observe("reply_parse_failed", { request_cmd: result.requestCmd, reply_cmd: result.replyCmd,
        request_elapsed_ms: result.duration });
      fail(id, SERVER_ERROR, "native_reply_invalid");
    }
  }
  function finish(result) {
    if (!pending) return;
    clearTimeout(pending.timer);
    clearTimeout(pending.pulseTimer);
    if (pending.id) {
      const id = pending.id;
      clearPending();
      deliver(id, result);
    } else {
      // At most one encrypted packet in RAM, only between local connections.
      // No password is decrypted until the owning continuation receives it.
      pending.done = result;
      pending.timer = setTimeout(clearPending, 5000);
    }
  }

  const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  async function until(test, ms) {
    const deadline = Date.now() + ms;
    while (Date.now() < deadline) {
      if (test()) return true;
      await delay(50);
    }
    return false;
  }
  async function request(message) {
    if (message.op === "status") {
      const paired = g_theState === "SessionKeySet";
      return send({ id: message.id, data: { STATUS: OK, paired, state: g_theState, native_channel_ready: paired, native_reply_correlation: "frame_v2" } });
    }
    // Reserved local continuation messages must never be posted to Apple.
    if (message.qid === "APWLocalWait" || "apwWaitToken" in message) {
      if (message.cmd !== 0 || message.qid !== "APWLocalWait" ||
        typeof message.apwWaitToken !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(message.apwWaitToken)) {
        return fail(message.id, SERVER_ERROR, "native_wait_invalid");
      }
      if (!pending?.token || message.apwWaitToken !== pending.token) return fail(message.id, SERVER_ERROR, "native_wait_expired");
      if (pending.id) return fail(message.id, SERVER_ERROR, "busy");
      if (pending.done) {
        const result = pending.done;
        clearPending();
        return deliver(message.id, result);
      }
      pending.id = message.id;
      pulse();
      return;
    }
    if ("apwWaitMS" in message && (message.cmd !== 5 || !Number.isInteger(message.apwWaitMS) ||
      message.apwWaitMS < 26000 || message.apwWaitMS > 90000)) return fail(message.id, SERVER_ERROR, "native_wait_invalid");
    if (message.cmd === 2) {
      if (pending) return fail(message.id, SERVER_ERROR, "busy");
      try {
        if (message.pin == null) {
          if (g_theState !== ContextState.NotInSession) resetTheSession(ContextState.NotInSession);
          ChallengePIN();
          if (!await until(() => g_theState === "MSG1Set", 10000)) {
            return fail(message.id, SERVER_ERROR, "challenge_failed");
          }
          return send({ id: message.id, data: { STATUS: OK, ready: true } });
        }
        if (g_theState !== "MSG1Set") return fail(message.id, INVALID_SESSION, "challenge_not_ready");
        PINSet(String(message.pin));
        await until(() => g_theState === "SessionKeySet" || g_theState === "NotInSession", 20000);
        if (g_theState !== "SessionKeySet") return fail(message.id, INVALID_SESSION, "pair_failed");
        return send({ id: message.id, data: { STATUS: OK, paired: true } });
      } catch (_) {
        return fail(message.id, SERVER_ERROR, "pair_failed");
      }
    }
    if (g_theState !== "SessionKeySet") return fail(message.id, INVALID_SESSION, "unpaired");
    if (pending) return fail(message.id, SERVER_ERROR, "busy");
    if (self.APW_BRIDGE_FRAME_COUNTER >= 2147483646) return fail(message.id, SERVER_ERROR, "native_frame_exhausted");
    const frameId = ++self.APW_BRIDGE_FRAME_COUNTER;
    pending = {
      id: message.id,
      cmd: message.cmd,
      frameId,
      started: performance.now(),
      token: message.apwWaitMS ? crypto.randomUUID() : null,
      timer: setTimeout(() => {
        observe("request_timeout", { request_cmd: safeCommand(pending?.cmd), request_elapsed_ms: elapsed() });
        // Each request has a distinct echoed frame. A late response cannot
        // consume a later request, so timeout does not invalidate pairing.
        finish({ error: "native_timeout" });
      }, message.apwWaitMS ?? 25000),
    };
    if (pending.token) pulse();
    try {
      const SMSG = g_secretSession.createSMSG(JSON.stringify(message.body));
      observe("request_sent", { request_cmd: safeCommand(message.cmd), request_elapsed_ms: elapsed() });
      g_nativeAppPort.postMessage({
        cmd: message.cmd,
        tabId: message.tabId,
        frameId,
        url: message.url,
        payload: JSON.stringify({ QID: message.qid, SMSG }),
      });
    } catch (error) {
      observe("request_send_failed", { request_cmd: safeCommand(pending?.cmd), request_elapsed_ms: elapsed() });
      finish({ error: "native_request_failed" });
    }
  }

  function clearPending() {
    if (pending) { clearTimeout(pending.timer); clearTimeout(pending.pulseTimer); }
    pending = null;
  }
  function reply(message) {
    const requestCmd = safeCommand(pending?.cmd), replyCmd = safeCommand(message?.cmd);
    const active = !!pending && !pending.done;
    const frameMatches = active && message?.frameId === pending.frameId;
    const commandMatches = active && (message?.cmd === pending.cmd || [5, 6].includes(pending.cmd) && message?.cmd === 4);
    const duration = elapsed();
    observe("reply_observed", { request_cmd: requestCmd, reply_cmd: replyCmd,
      request_pending: active, frame_matches: frameMatches, command_matches: commandMatches,
      request_elapsed_ms: duration });
    // macOS replies to a cmd-6 save with cmd 4. This is only a response;
    // the native client must still prove the write through exact readback.
    if (!active || !frameMatches || !commandMatches) {
      observe("reply_ignored", { request_cmd: requestCmd, reply_cmd: replyCmd,
        reason: !active ? "no_pending_request" : !frameMatches ? "frame_mismatch" : "command_mismatch",
        request_elapsed_ms: duration });
      return;
    }
    // Copy only the bounded encrypted envelope, never arbitrary native fields.
    let envelope = message.payload?.SMSG;
    if (message.payload) {
      if (typeof envelope === "string") {
        if (envelope.length > 1024 * 1024) return finish({ error: "native_reply_invalid" });
      } else if (envelope && typeof envelope.TID === "string" && typeof envelope.SDATA === "string" &&
        envelope.TID.length + envelope.SDATA.length <= 1024 * 1024) {
        envelope = { TID: envelope.TID, SDATA: envelope.SDATA };
      } else return finish({ error: "native_reply_invalid" });
    }
    finish({ requestCmd, replyCmd, duration, packet: message.payload
      ? { payload: { SMSG: envelope } } : { STATUS: message.STATUS } });
  }

  function connect() {
    if (stopped) return;
    ws = new WebSocket(`ws://127.0.0.1:${port}`);
    ws.onopen = () => send({ token });
    ws.onerror = () => ws.close();
    ws.onclose = () => {
      clearPending();
      if (!stopped) reconnectTimer = setTimeout(connect, 3000);
    };
    ws.onmessage = ({ data }) => request(JSON.parse(data));
  }
  if (!g_nativeAppPort) connectToBackgroundNativeAppAndSetUpListeners();
  g_nativeAppPort?.onMessage?.addListener(reply);
  connect();
  // WebSocket traffic keeps the MV3 worker and pairing state alive while idle.
  const heartbeat = setInterval(() => send({ heartbeat: true }), 2000);
  self.APW_BRIDGE_V2 = { version: "frame_v2", diagnostics() {
    return { schema: "apw-native-reply-diagnostics-v1", event_count: eventCount,
      dropped_events: droppedEvents, native_port_identity_unchanged: g_nativeAppPort === observedPort,
      events: events.map((event) => ({ ...event })) };
  }, dispose() {
    stopped = true;
    clearTimeout(reconnectTimer);
    clearInterval(heartbeat);
    if (pending?.id) fail(pending.id, SERVER_ERROR, "bridge_replaced");
    clearPending();
    g_nativeAppPort?.onMessage?.removeListener?.(reply);
    if (ws) { ws.onclose = null; ws.close(); }
  } };
})();
