/**
 * Mewt DualKey — browser tester (demo + Web Serial).
 * Same LED codes as mewt_dualkey.ps1 / mewt_dualkey.ino: 0, 1, 2, 101.
 */

const BAUD = 9600;
const STREAM_MS = 150;

const state = {
  muted: true,
  level: 5,
  threshold: 8,
  useMic: false,
  micLevel: 0,
  streamToDevice: true,
  serialPort: null,
  serialWriter: null,
  serialReaderLoop: null,
  streamTimer: null,
  logMax: 200,
};

const els = {};

function $(id) {
  return document.getElementById(id);
}

function logLine(dir, text) {
  const box = els.log;
  const t = new Date().toISOString().slice(11, 23);
  box.textContent += `[${t}] ${dir} ${text}\n`;
  const lines = box.textContent.split("\n");
  if (lines.length > state.logMax) {
    box.textContent = lines.slice(-state.logMax).join("\n");
  }
  box.scrollTop = box.scrollHeight;
}

function computeLedCode() {
  if (state.muted) return 0;
  const level = state.useMic ? state.micLevel : state.level;
  const v = level >= state.threshold ? 2 : 1;
  return v;
}

function applyLedPreview(code) {
  const left = els.ledLeft;
  const right = els.ledRight;
  left.className = "led";
  right.className = "led";

  switch (code) {
    case 0:
      right.classList.add("on-green");
      break;
    case 1:
      left.classList.add("on-red");
      break;
    case 2:
      left.classList.add("on-red");
      right.classList.add("on-red");
      break;
    default:
      break;
  }

  els.codePill.textContent = `Host → device: ${code}`;
}

function refreshUi() {
  const code = computeLedCode();
  applyLedPreview(code);
  els.levelVal.textContent = state.useMic ? String(Math.round(state.micLevel)) : String(state.level);
  els.threshVal.textContent = String(state.threshold);
  els.chkMuted.checked = state.muted;
  els.rangeLevel.value = String(state.level);
  els.rangeThresh.value = String(state.threshold);
  els.chkMic.checked = state.useMic;
  els.chkStream.checked = state.streamToDevice;
  els.rangeLevel.disabled = state.useMic;

  queueSerialSend(code);
}

let serialSendQueued = null;

function queueSerialSend(code) {
  serialSendQueued = code;
}

async function flushSerialIfNeeded() {
  if (!state.serialWriter || !state.streamToDevice) return;
  const code = serialSendQueued;
  if (code === null || code === undefined) return;
  try {
    const enc = new TextEncoder();
    await state.serialWriter.write(enc.encode(`${code}\n`));
  } catch (e) {
    logLine("!!", String(e.message || e));
    void disconnectSerial();
  }
}

async function sendSerialLine(text) {
  if (!state.serialWriter) {
    logLine("!!", "Not connected");
    return;
  }
  try {
    const enc = new TextEncoder();
    await state.serialWriter.write(enc.encode(`${text}\n`));
    logLine("TX", text);
  } catch (e) {
    logLine("!!", String(e.message || e));
  }
}

function startStreamTimer() {
  stopStreamTimer();
  state.streamTimer = setInterval(() => {
    flushSerialIfNeeded();
  }, STREAM_MS);
}

function stopStreamTimer() {
  if (state.streamTimer) {
    clearInterval(state.streamTimer);
    state.streamTimer = null;
  }
}

async function connectSerial() {
  if (!("serial" in navigator)) return;
  try {
    const port = await navigator.serial.requestPort();
    await port.open({ baudRate: BAUD });
    state.serialPort = port;
    state.serialWriter = port.writable.getWriter();

    els.serialStatus.textContent = "Serial connected — streaming LED codes if enabled.";
    els.serialStatus.classList.add("connected");
    els.btnConnect.disabled = true;
    els.btnDisconnect.disabled = false;
    logLine("--", `Opened ${BAUD} baud`);

    startStreamTimer();
    void readSerialLoop(port);

    refreshUi();
    flushSerialIfNeeded();
  } catch (e) {
    if (e.name !== "NotFoundError") {
      logLine("!!", String(e.message || e));
    }
  }
}

async function readSerialLoop(port) {
  const decoder = new TextDecoder();
  let buffer = "";
  const reader = port.readable.getReader();
  try {
    while (true) {
      let chunk;
      try {
        chunk = await reader.read();
      } catch {
        break;
      }
      const { value, done } = chunk;
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split(/\r?\n/);
      buffer = parts.pop() || "";
      for (const line of parts) {
        const t = line.trim();
        if (t.length) logLine("RX", t);
      }
    }
  } finally {
    try {
      reader.releaseLock();
    } catch {
      /* ignore */
    }
  }
}

async function disconnectSerial() {
  stopStreamTimer();
  const port = state.serialPort;
  const writer = state.serialWriter;
  state.serialPort = null;
  state.serialWriter = null;

  try {
    if (port?.readable) {
      await port.readable.cancel();
    }
  } catch {
    /* ignore */
  }
  try {
    if (writer) {
      await writer.close();
    }
  } catch {
    /* ignore */
  }
  try {
    if (port) {
      await port.close();
    }
  } catch {
    /* ignore */
  }
  els.serialStatus.textContent = "Serial disconnected.";
  els.serialStatus.classList.remove("connected");
  els.btnConnect.disabled = false;
  els.btnDisconnect.disabled = true;
  logLine("--", "Closed port");
}

let audioCtx = null;
let micAnalyser = null;
let micSource = null;
let micRaf = null;

function stopMic() {
  if (micRaf) {
    cancelAnimationFrame(micRaf);
    micRaf = null;
  }
  if (micSource) {
    micSource.disconnect();
    micSource = null;
  }
  if (audioCtx) {
    audioCtx.close().catch(() => {});
    audioCtx = null;
  }
  micAnalyser = null;
  state.micLevel = 0;
}

async function startMic() {
  stopMic();
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  audioCtx = new AudioContext();
  micAnalyser = audioCtx.createAnalyser();
  micAnalyser.fftSize = 256;
  micSource = audioCtx.createMediaStreamSource(stream);
  micSource.connect(micAnalyser);
  const data = new Uint8Array(micAnalyser.frequencyBinCount);

  function tick() {
    if (!state.useMic) return;
    micAnalyser.getByteFrequencyData(data);
    let sum = 0;
    for (let i = 0; i < data.length; i++) sum += data[i];
    const avg = sum / data.length;
    state.micLevel = Math.min(99, Math.round(avg * 1.4));
    refreshUi();
    micRaf = requestAnimationFrame(tick);
  }
  tick();
}

function wire() {
  els.ledLeft = $("ledLeft");
  els.ledRight = $("ledRight");
  els.codePill = $("codePill");
  els.chkMuted = $("chkMuted");
  els.rangeLevel = $("rangeLevel");
  els.rangeThresh = $("rangeThresh");
  els.levelVal = $("levelVal");
  els.threshVal = $("threshVal");
  els.chkMic = $("chkMic");
  els.chkStream = $("chkStream");
  els.btnSimPress = $("btnSimPress");
  els.btnConnect = $("btnConnect");
  els.btnDisconnect = $("btnDisconnect");
  els.serialStatus = $("serialStatus");
  els.log = $("log");
  els.btnSend101 = $("btnSend101");
  els.btnSend0 = $("btnSend0");
  els.btnSend1 = $("btnSend1");
  els.btnSend2 = $("btnSend2");

  els.chkMuted.addEventListener("change", () => {
    state.muted = els.chkMuted.checked;
    refreshUi();
  });

  els.rangeLevel.addEventListener("input", () => {
    state.level = Number(els.rangeLevel.value);
    refreshUi();
  });

  els.rangeThresh.addEventListener("input", () => {
    state.threshold = Number(els.rangeThresh.value);
    refreshUi();
  });

  els.chkMic.addEventListener("change", async () => {
    state.useMic = els.chkMic.checked;
    if (state.useMic) {
      try {
        await startMic();
      } catch (e) {
        state.useMic = false;
        els.chkMic.checked = false;
        logLine("!!", `Mic: ${e.message || e}`);
      }
    } else {
      stopMic();
    }
    refreshUi();
  });

  els.chkStream.addEventListener("change", () => {
    state.streamToDevice = els.chkStream.checked;
  });

  els.btnSimPress.addEventListener("click", () => {
    state.muted = !state.muted;
    refreshUi();
  });

  els.btnConnect.addEventListener("click", connectSerial);
  els.btnDisconnect.addEventListener("click", disconnectSerial);

  els.btnSend101.addEventListener("click", () => sendSerialLine("101"));
  els.btnSend0.addEventListener("click", () => sendSerialLine("0"));
  els.btnSend1.addEventListener("click", () => sendSerialLine("1"));
  els.btnSend2.addEventListener("click", () => sendSerialLine("2"));

  window.addEventListener("beforeunload", () => {
    stopMic();
    disconnectSerial();
  });
}

function initBanner() {
  const b = $("browserBanner");
  if ("serial" in navigator) {
    b.classList.add("ok");
    b.textContent =
      "Web Serial is available. Use Chrome or Edge over https:// or http://localhost. Close mewt_dualkey.ps1 before opening the COM port here.";
  } else {
    b.textContent =
      "Web Serial is not available in this browser (try Chrome or Edge). Demo mode still works for LEDs and logic.";
  }
}

document.addEventListener("DOMContentLoaded", () => {
  wire();
  initBanner();
  refreshUi();
  if (!("serial" in navigator)) {
    els.btnConnect.disabled = true;
  }
  els.btnDisconnect.disabled = true;
});
