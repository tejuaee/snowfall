// Snowfall for Windows and Linux — the same overlay as Snow.swift, in Electron.
//
// One transparent, click-through, always-on-top window per display, each hosting the
// canvas page in ../index.html. A tray icon carries the same menu as the macOS ❄.
// The page itself is untouched: preload.js gives it the `window.webkit` bridge it
// already talks to, and everything else goes through the page's window.* hooks.
//
// Run:  cd desktop && npm install && npm start      (stop: npm run stop)

"use strict";

const { app, BrowserWindow, Menu, Tray, nativeImage, ipcMain, powerMonitor, screen } =
  require("electron");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const ROOT = path.join(__dirname, "..");
const PAGE = path.join(ROOT, "index.html");
const SETTINGS_PAGE = path.join(ROOT, "settings.html");
const PRELOAD = path.join(__dirname, "preload.js");

// ---- one instance only -------------------------------------------------------

// Two copies would stack two overlays on every screen. A second launch either stops
// the first (`--stop`) or does nothing.
const stopRequested = process.argv.includes("--stop");
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else if (stopRequested) {
  console.log("No snow was falling.");
  app.quit();
} else {
  app.on("second-instance", (_event, argv) => {
    if (argv.includes("--stop")) quit();
  });
  // Linux compositors sometimes hand out an opaque visual to a transparent window
  // created the instant the app is ready; a short wait avoids a black screen.
  app.whenReady().then(() => setTimeout(start, process.platform === "linux" ? 400 : 0));
}

// Under Wayland an app may neither place a window on a given display nor keep it
// above others, which is all an overlay does — so run through XWayland.
if (process.platform === "linux" && !process.env.SNOWFALL_WAYLAND) {
  app.commandLine.appendSwitch("ozone-platform", "x11");
}

// Menu bar accessory on macOS too, should anyone run this there.
if (process.platform === "darwin" && app.dock) app.dock.hide();

// Closing the settings window must not end the app.
app.on("window-all-closed", () => {});

// ---- remembered state ----------------------------------------------------------

const DEFAULT_SETTINGS = {
  settle: true,            // whether snow lies at all
  maxDepthPercent: 100,    // how much of the screen it may bury
  autoPlowPercent: 0,      // plough itself at this depth; 0 = only on demand
  plowCrossSeconds: 7,     // how long the truck takes to cross the screen
  truckPercent: 7,         // truck height as a share of the screen
  plowDirection: 0         // 0 alternates, ±1 always from that side
};

const statePath = () => path.join(app.getPath("userData"), "state.json");

function loadState() {
  try {
    return JSON.parse(fs.readFileSync(statePath(), "utf8"));
  } catch {
    return {};
  }
}

let state = {};

function saveState() {
  try {
    fs.mkdirSync(path.dirname(statePath()), { recursive: true });
    const tmp = statePath() + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(state));
    fs.renameSync(tmp, statePath());      // never leave half a file behind
  } catch (err) {
    console.error("snowfall: could not save state:", err.message);
  }
}

// ---- one overlay per display -------------------------------------------------

class Overlay {
  constructor(display, index) {
    this.display = display;
    this.index = index;
    this.paused = false;
    this.lastFrames = -1;
    this.stalls = 0;
    this.reloads = 0;
    this.lastReload = 0;

    const { x, y, width, height } = display.bounds;
    this.win = new BrowserWindow({
      x, y, width, height,
      show: false,
      frame: false,
      transparent: true,
      backgroundColor: "#00000000",
      hasShadow: false,
      resizable: false,
      movable: false,
      minimizable: false,
      maximizable: false,
      fullscreenable: false,
      skipTaskbar: true,
      focusable: false,          // never takes focus from what you're doing
      alwaysOnTop: true,
      webPreferences: {
        preload: PRELOAD,
        contextIsolation: true,
        sandbox: true,
        spellcheck: false,
        // An overlay is always "in the background" as far as Chromium is concerned;
        // throttled timers would leave it at a frame a second.
        backgroundThrottling: false,
        // No "persist:" prefix: an in-memory session, so no cache or cookies on disk.
        partition: "snowfall"
      }
    });

    this.win.setAlwaysOnTop(true, "screen-saver");
    this.win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
    this.win.setIgnoreMouseEvents(true);          // clicks pass straight through
    this.win.setMenu(null);

    this.win.once("ready-to-show", () => this.win.showInactive());
    this.win.webContents.on("did-finish-load", () => this.restore());

    // Chromium runs the page in its own process, which can die in a long session.
    this.win.webContents.on("render-process-gone", () => this.reload());

    this.load();
  }

  load() {
    this.win.loadFile(PAGE, { query: { overlay: "1" } });
  }

  get alive() {
    return !this.win.isDestroyed() && !this.win.webContents.isDestroyed();
  }

  run(js) {
    if (!this.alive) return Promise.resolve(null);
    return this.win.webContents.executeJavaScript(js, true).catch(() => null);
  }

  /// Everything a freshly loaded page needs to look like the one it replaced.
  restore() {
    this.lastFrames = -1;
    this.pushIntensity();
    this.applySettings();
    const pile = state.piles && state.piles[this.index];
    if (pile) this.run(`window.setPile && window.setPile(${pile});`);
    if (this.paused) this.setPaused(true);
    if (snowballMode) this.setInteractive(true);
  }

  reload() {
    // Try, but do not spin: a page that will not come back should not be hammered
    // every twenty seconds for days.
    if (Date.now() - this.lastReload < 10000 || this.reloads >= 8 || !this.alive) return;
    this.reloads += 1;
    this.lastReload = Date.now();
    this.load();
  }

  async checkStalled() {
    const frames = await this.run("window.__snowState ? window.__snowState().frames : null");
    if (typeof frames !== "number") {
      this.stalls += 1;
      return this.stalls >= 2;
    }
    const stalled = !this.paused && this.lastFrames >= 0 && frames === this.lastFrames;
    this.lastFrames = frames;
    this.stalls = stalled ? this.stalls + 1 : 0;
    if (!stalled) this.reloads = 0;
    return this.stalls >= 2;
  }

  pushIntensity() {
    this.run(`window.setPowerSaver && window.setPowerSaver(${powerSaving});
              window.setIntensity && window.setIntensity(${intensity});`);
  }

  applySettings() {
    this.run(`window.applySettings && window.applySettings(${JSON.stringify(settings)});`);
  }

  sendPlow() { this.run("window.sendPlow && window.sendPlow();"); }
  clearPile() { this.run("window.clearPile && window.clearPile();"); }

  setPaused(paused) {
    this.paused = paused;
    this.run(`window.setPaused && window.setPaused(${paused});`);
  }

  async readPile() {
    const json = await this.run("JSON.stringify(window.getPile ? window.getPile() : [])");
    return typeof json === "string" && json.length > 2 ? json : null;
  }

  /// Snowball Mode is the one time the overlay stops being click-through. While it is
  /// listening for the mouse it also stops covering the taskbar or panel, or the tray
  /// icon — one of the ways out — would become unclickable.
  setInteractive(on) {
    if (!this.alive) return;
    this.win.setIgnoreMouseEvents(!on);
    this.win.setFocusable(on);
    this.win.setBounds(on ? this.display.workArea : this.display.bounds);
    this.run(`window.setInteractive && window.setInteractive(${on});`);
    if (on) this.win.focus();            // or Escape never reaches the page
    else this.win.blur();
  }

  close() {
    if (!this.win.isDestroyed()) this.win.destroy();
  }
}

// ---- the app -----------------------------------------------------------------

let overlays = [];
let tray = null;
let settingsWindow = null;
let intensity = 2;            // 1 light · 2 medium · 3 blizzard
let settings = { ...DEFAULT_SETTINGS };
let easeOffOnBattery = true;
let powerSaving = false;
let snowballMode = false;
let snowing = true;
let locked = false;
let suspended = false;

function start() {
  state = loadState();
  intensity = [1, 2, 3].includes(state.intensity) ? state.intensity : 2;
  settings = { ...DEFAULT_SETTINGS, ...(state.settings || {}) };
  easeOffOnBattery = state.easeOffOnBattery !== false;
  state.piles = state.piles || {};

  ipcMain.on("snowfall", (_event, body) => received(body));

  buildTray();
  applyPowerState();
  startSnowing();
  observeSystem();

  // Keep the drift on disk so quitting, or a reboot, does not undo an evening of snow.
  setInterval(savePiles, 60 * 1000);
  setInterval(checkHealth, 20 * 1000);

  if (process.argv.includes("--self-test")) selfTest();
}

/// `npm test`: start the snow, wait, and ask every page whether it is drawing.
/// Exits non-zero if any screen is not — the same check ci/check-page.swift makes.
async function selfTest() {
  await new Promise((resolve) => setTimeout(resolve, 4000));
  let ok = overlays.length > 0;
  for (const overlay of overlays) {
    const s = await overlay.run(`window.__snowState ? Object.assign(window.__snowState(), {
      bridge: typeof window.webkit?.messageHandlers?.snowfall?.postMessage === "function"
    }) : null`);
    console.log(`display ${overlay.index}:`, JSON.stringify(s));
    if (!s || s.frames < 10 || s.flakes < 1 || s.errors > 0 || !s.bridge) ok = false;
  }
  console.log(ok ? "all good ❄" : "the snow is not falling");
  tearDown();
  app.exit(ok ? 0 : 1);
}

function startSnowing() {
  tearDown();
  overlays = screen.getAllDisplays().map((display, index) => new Overlay(display, index));
  snowing = true;
  updatePause();
  refreshMenu();
}

function tearDown() {
  overlays.forEach((o) => o.close());
  overlays = [];
}

let rebuildTimer = null;

/// Displays plugged in, unplugged or resized. Rebuilding throws the pages away, and
/// with them the drift, so it is read out first.
function displaysChanged() {
  if (!snowing) return;
  clearTimeout(rebuildTimer);
  rebuildTimer = setTimeout(async () => {
    await savePiles();
    if (snowing) startSnowing();
  }, 500);
}

async function savePiles() {
  const results = await Promise.all(overlays.map((o) => o.readPile()));
  let changed = false;
  results.forEach((json, index) => {
    if (json) { state.piles[index] = json; changed = true; }
  });
  if (changed) saveState();
}

// ---- power and visibility ------------------------------------------------------

function observeSystem() {
  screen.on("display-added", displaysChanged);
  screen.on("display-removed", displaysChanged);
  screen.on("display-metrics-changed", displaysChanged);

  powerMonitor.on("on-battery", () => { applyPowerState(); refreshMenu(); });
  powerMonitor.on("on-ac", () => { applyPowerState(); refreshMenu(); });

  powerMonitor.on("lock-screen", () => { locked = true; updatePause(); });
  powerMonitor.on("unlock-screen", () => { locked = false; updatePause(); });
  powerMonitor.on("suspend", () => { suspended = true; savePiles(); updatePause(); });
  powerMonitor.on("resume", () => { suspended = false; updatePause(); });
}

function onBattery() {
  try { return powerMonitor.isOnBatteryPower(); } catch { return false; }
}

/// On battery the snow runs at 20 fps, 1x pixels and a bit over half the flakes.
function applyPowerState() {
  const saving = easeOffOnBattery && onBattery();
  if (saving === powerSaving) return;
  powerSaving = saving;
  overlays.forEach((o) => o.pushIntensity());
}

function updatePause() {
  const pause = locked || suspended;
  overlays.forEach((o) => { if (o.paused !== pause) o.setPaused(pause); });
}

/// Rather than trust that every event arrived, ask the system — and ask each page
/// whether it is still drawing.
async function checkHealth() {
  try {
    const idle = powerMonitor.getSystemIdleState(1);
    if (idle !== "unknown") locked = idle === "locked";
  } catch { /* not available everywhere */ }
  suspended = false;           // if this timer is running, the machine is awake
  updatePause();
  applyPowerState();

  for (const overlay of overlays) {
    if (await overlay.checkStalled()) overlay.reload();
  }

  // Some window managers push other "always on top" windows above ours over time.
  if (!snowballMode) overlays.forEach((o) => o.alive && o.win.moveTop());
}

// ---- tray menu -----------------------------------------------------------------

function buildTray() {
  tray = new Tray(snowflakeIcon());
  tray.setToolTip("Snowfall — snow, plough and snowballs");
  // On Windows a left click does nothing by default; make it open the menu too.
  if (process.platform === "win32") tray.on("click", () => tray.popUpContextMenu());
  refreshMenu();
}

function refreshMenu() {
  if (!tray) return;
  let description;
  if (powerSaving) description = "Easing off — saving power";
  else if (onBattery()) description = "Full snow — on battery";
  else description = "Full snow — plugged in";

  const header = (label) => ({ label, enabled: false });
  const template = [
    { label: description, enabled: false },
    { type: "separator" },
    header("Snow"),
    { label: snowing ? "Stop Snow" : "Start Snow", click: toggleSnow },
    { type: "separator" },
    ...[[1, "Light"], [2, "Medium"], [3, "Blizzard"]].map(([level, label]) => ({
      label,
      type: "radio",
      checked: level === intensity,
      click: () => setIntensity(level)
    })),
    { type: "separator" },
    header("Plough"),
    { label: "Send the Plough", click: sendPlow },
    { label: "Clear the Snow", click: clearSnow },
    { type: "separator" },
    header("Play"),
    { label: "Snowball Mode", type: "checkbox", checked: snowballMode, click: toggleSnowballs },
    { label: "Snow Settings…", click: openSettings },
    { type: "separator" },
    { label: "Ease Off on Battery", type: "checkbox", checked: easeOffOnBattery,
      click: toggleEaseOff },
    { type: "separator" },
    { label: "Quit Snowfall", click: quit }
  ];
  tray.setContextMenu(Menu.buildFromTemplate(template));
}

function toggleSnow() {
  if (snowing) {
    savePiles().then(() => { tearDown(); snowing = false; refreshMenu(); });
  } else {
    startSnowing();
  }
}

function setIntensity(level) {
  intensity = level;
  state.intensity = level;
  saveState();
  overlays.forEach((o) => o.pushIntensity());
  refreshMenu();
}

function sendPlow() { overlays.forEach((o) => o.sendPlow()); }
function clearSnow() { overlays.forEach((o) => o.clearPile()); }

function toggleEaseOff() {
  easeOffOnBattery = !easeOffOnBattery;
  state.easeOffOnBattery = easeOffOnBattery;
  saveState();
  applyPowerState();
  refreshMenu();
}

/// While this is on the overlay swallows every click, which is the point and also the
/// danger, so the page announces it and Escape, a double click or Leave turn it off.
function toggleSnowballs() {
  setSnowballMode(!snowballMode);
}

function setSnowballMode(on) {
  snowballMode = on;
  overlays.forEach((o) => o.setInteractive(on));
  refreshMenu();
}

function openSettings() {
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.show();
    settingsWindow.focus();
    return;
  }
  settingsWindow = new BrowserWindow({
    width: 420,
    height: 580,
    title: "Snowfall",
    resizable: false,
    maximizable: false,
    autoHideMenuBar: true,
    show: false,
    webPreferences: {
      preload: PRELOAD,
      contextIsolation: true,
      sandbox: true,
      partition: "snowfall"
    }
  });
  settingsWindow.setMenu(null);
  settingsWindow.webContents.on("did-finish-load", () => {
    settingsWindow.webContents.executeJavaScript(
      `window.loadSettings && window.loadSettings(${JSON.stringify(settings)});`, true)
      .catch(() => {});
  });
  settingsWindow.once("ready-to-show", () => settingsWindow.show());
  settingsWindow.on("closed", () => { settingsWindow = null; });
  settingsWindow.loadFile(SETTINGS_PAGE);
}

/// Messages from the overlay pages and the settings page. Anything the settings page
/// sends is applied to every screen and written straight to disk.
function received(body) {
  if (!body || typeof body !== "object") return;
  switch (body.type) {
    case "exitSnowball":
      if (snowballMode) setSnowballMode(false);
      break;
    case "settings": {
      const next = { ...DEFAULT_SETTINGS };
      for (const key of Object.keys(DEFAULT_SETTINGS)) {
        const value = body.settings && body.settings[key];
        if (typeof value === typeof DEFAULT_SETTINGS[key]) next[key] = value;
      }
      settings = next;
      state.settings = settings;
      saveState();
      overlays.forEach((o) => o.applySettings());
      break;
    }
    case "snowball":
      if (!snowballMode) setSnowballMode(true);
      break;
    case "plow": sendPlow(); break;
    case "clear": clearSnow(); break;
  }
}

let quitting = false;

async function quit() {
  if (quitting) return;
  quitting = true;
  await savePiles();
  tearDown();
  app.quit();
}

// ---- the tray icon -------------------------------------------------------------

/// A six-armed snowflake drawn into a PNG at start-up, so the repository needs no
/// binary icon. Pale blue with a dark edge, so it reads on light and dark panels.
function snowflakeIcon() {
  const size = 32;
  const rgba = Buffer.alloc(size * size * 4);
  const c = (size - 1) / 2;

  // Distance from point p to segment a–b.
  const dist = (px, py, ax, ay, bx, by) => {
    const dx = bx - ax, dy = by - ay;
    const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)));
    return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
  };

  const segments = [];
  for (let k = 0; k < 6; k++) {
    const a = (k * Math.PI) / 3 - Math.PI / 2;
    const ex = c + Math.cos(a) * 13, ey = c + Math.sin(a) * 13;
    segments.push([c, c, ex, ey]);
    // Two little branches on each arm.
    const bx = c + Math.cos(a) * 8, by = c + Math.sin(a) * 8;
    for (const s of [-1, 1]) {
      const b = a + s * 0.7;
      segments.push([bx, by, bx + Math.cos(b) * 5, by + Math.sin(b) * 5]);
    }
  }

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let d = Infinity;
      for (const s of segments) d = Math.min(d, dist(x, y, ...s));
      const i = (y * size + x) * 4;
      if (d <= 1.3) {            // the flake itself
        rgba.set([225, 242, 255, 255], i);
      } else if (d <= 2.6) {     // its outline
        const alpha = Math.round(255 * Math.min(1, 2.6 - d + 0.4));
        rgba.set([30, 70, 120, alpha], i);
      }
    }
  }

  const image = nativeImage.createFromBuffer(encodePNG(rgba, size, size), { scaleFactor: 2 });
  return process.platform === "darwin" ? image.resize({ width: 18, height: 18 }) : image;
}

function encodePNG(rgba, width, height) {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const sum = Buffer.alloc(4); sum.writeUInt32BE(crc(body));
    return Buffer.concat([len, body, sum]);
  };

  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;      // bit depth
  header[9] = 6;      // RGBA
  const rows = Buffer.alloc((width * 4 + 1) * height);
  for (let y = 0; y < height; y++) {
    rgba.copy(rows, y * (width * 4 + 1) + 1, y * width * 4, (y + 1) * width * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", zlib.deflateSync(rows)),
    chunk("IEND", Buffer.alloc(0))
  ]);
}
