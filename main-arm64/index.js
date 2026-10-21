'use strict';
// arm64 main process for Hexcore Link -- reimplementation.
// The original dist/main/index.jsc is V8 bytecode bound to x86_64 and cannot be
// loaded on arm64, so this file reimplements the main-process IPC contract that
// the (architecture-independent) preloads and renderers expect.
const { app, BrowserWindow, ipcMain, dialog, Tray, Menu, nativeTheme,
        screen, session, protocol, webContents } = require('electron');
const path = require('path');
const fs = require('fs');

const RENDERER_DIR = path.join(__dirname, '../renderers');
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.map': 'application/json; charset=utf-8',
};

// The renderers are ES modules loaded under a strict CSP. Serving them over
// file:// blocks module loading, so the original build registers a privileged
// app:// scheme; we do the same.
protocol.registerSchemesAsPrivileged([
  { scheme: 'app',
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, stream: true } },
  // Sentry's renderer SDK talks to the main process over this scheme.
  { scheme: 'sentry-ipc',
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true, bypassCSP: true } },
]);
const PRELOAD_DIR = path.join(__dirname, '../preloads');
const isDev = !app.isPackaged;

let mainWindow = null;
let preferenceWindow = null;
let updaterWindow = null;
let tray = null;
let cachedDisplays = [];

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------
const logDir = () => path.join(app.getPath('userData'), 'logs');
function log(...args) {
  try {
    fs.mkdirSync(logDir(), { recursive: true });
    fs.appendFileSync(path.join(logDir(), 'main.log'),
      `${new Date().toISOString()} ${args.map(String).join(' ')}\n`);
  } catch (_) { /* logging must never throw */ }
}
function safeJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) { return fallback; }
}
function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}


const winStateFile = () => path.join(app.getPath('userData'), 'window-state.json');

// ---------------------------------------------------------------------------
// windows
// ---------------------------------------------------------------------------
// A saved rect can refer to a display that is no longer attached. Restoring it
// verbatim parks the window off-screen, where it still renders but never gets a
// click, so only reuse a rect that overlaps a display that exists right now.
function restoreBounds(state) {
  const width = Math.max(900, Math.min(state.width || 1200, 4000));
  const height = Math.max(600, Math.min(state.height || 800, 4000));
  if (typeof state.x !== 'number' || typeof state.y !== 'number') return { width, height };
  const reachable = screen.getAllDisplays().some((d) => {
    const b = d.workArea;
    const overlapX = Math.min(state.x + width, b.x + b.width) - Math.max(state.x, b.x);
    const overlapY = Math.min(state.y + height, b.y + b.height) - Math.max(state.y, b.y);
    return overlapX > 200 && overlapY > 80;
  });
  return reachable ? { width, height, x: state.x, y: state.y } : { width, height };
}
function createWindow(page, opts = {}) {
  const state = safeJson(winStateFile(), {});
  const restored = restoreBounds(state);
  const win = new BrowserWindow({
    width: opts.width || restored.width,
    height: opts.height || restored.height,
    x: opts.x !== undefined ? opts.x : restored.x,
    y: opts.y !== undefined ? opts.y : restored.y,
    minWidth: opts.minWidth || 900,
    minHeight: opts.minHeight || 600,
    show: opts.show !== undefined ? opts.show : true,
    frame: opts.frame !== undefined ? opts.frame : false,
    titleBarStyle: 'hiddenInset',
    backgroundColor: nativeTheme.shouldUseDarkColors ? '#1e1e1e' : '#ffffff',
    webPreferences: {
      preload: path.join(PRELOAD_DIR, opts.preload || 'app.cjs'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      // The renderer calls api.obins.net with axios/XHR from the app:// origin;
      // the vendor API refuses OPTIONS preflight, so CORS cannot be satisfied.
      // This is a locally packaged app with no remote content, so relaxing
      // same-origin checks here is safe and matches working behaviour.
      webSecurity: false,
    },
    ...opts.window,
  });

  log('WINDOW-CREATE', page, 'preload=' + (opts.preload || 'app.cjs'));
  win.webContents.on('did-start-loading', () => log('WINDOW-LOADING', page));
  win.webContents.on('did-finish-load', () => log('WINDOW-LOADED', page));
  win.webContents.on('preload-error', (_e, p, err) => log('PRELOAD-ERROR', p, err && err.message));
  win.on('close', () => log('WINDOW-CLOSE', page));
  win.on('closed', () => log('WINDOW-CLOSED', page));
  win.webContents.on('destroyed', () => log('WEBCONTENTS-DESTROYED', page));
  win.loadURL(`app://bundle/${page}`);
  win.once('ready-to-show', () => {
    if (opts.show === false) return;
    win.show();
    if (opts.focus !== false) win.focus();
  });

  win.on('close', () => {
    try {
      const b = win.getBounds();
      writeJson(winStateFile(), { ...safeJson(winStateFile(), {}), ...b });
    } catch (_) {}
  });

  if (opts.devTools) win.webContents.openDevTools({ mode: 'detach' });
  return win;
}

function openPreference() {
  if (preferenceWindow && !preferenceWindow.isDestroyed()) {
    preferenceWindow.show();
    preferenceWindow.focus();
    return preferenceWindow;
  }
  preferenceWindow = createWindow('preference.html', {
    width: 1000, height: 720, preload: 'preference.cjs',
  });
  preferenceWindow.on('closed', () => { preferenceWindow = null; });
  return preferenceWindow;
}

function openUpdater(show = true) {
  if (updaterWindow && !updaterWindow.isDestroyed()) {
    if (show) { updaterWindow.show(); updaterWindow.focus(); }
    return updaterWindow;
  }
  if (process.env.HEXCORE_NO_UPDATER) return null;
  updaterWindow = createWindow('updater.html', {
    width: 560, height: 420, preload: 'updater.cjs',
    show, focus: false,
  });
  updaterWindow.on('closed', () => { updaterWindow = null; });
  return updaterWindow;
}

function createMainWindow() {
  log('MAIN-WINDOW creating');
  try {
    mainWindow = createWindow('app.html', {
      preload: 'app.cjs', devTools: isDev, show: true, focus: true,
    });
  } catch (e) {
    log('MAIN-WINDOW create failed', e && e.stack);
  }
  log('MAIN-WINDOW created', !!mainWindow, mainWindow && !mainWindow.isDestroyed());
  mainWindow.on('closed', () => { mainWindow = null; });

  // The renderer sends `renderer-ready` with timing info once mounted.
  mainWindow.webContents.once('did-finish-load', () => {
    mainWindow.webContents.send('native-theme', nativeTheme.shouldUseDarkColors ? 'dark' : 'light');
    pushWindowState(mainWindow);
  });
  for (const ev of ['maximize', 'unmaximize', 'enter-full-screen', 'leave-full-screen', 'focus', 'blur']) {
    mainWindow.on(ev, () => pushWindowState(mainWindow));
  }
  return mainWindow;
}

// ---------------------------------------------------------------------------
// background window: the app runs an invisible window that owns HID + uiohook
// so device events keep flowing when the UI is hidden. The original preload
// (background.cjs) does the actual work; we only host it.
// ---------------------------------------------------------------------------
let backgroundWindow = null;
function createBackgroundWindow() {
  backgroundWindow = new BrowserWindow({
    show: false,
    width: 1, height: 1,
    skipTaskbar: true,
    webPreferences: {
      preload: path.join(PRELOAD_DIR, 'background.cjs'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      webSecurity: false,
      backgroundThrottling: false,
    },
  });
  log('WINDOW-CREATE background.html preload=background.cjs');
  backgroundWindow.loadURL('app://bundle/background.html');
  backgroundWindow.on('closed', () => { backgroundWindow = null; });
  return backgroundWindow;
}

// ---------------------------------------------------------------------------
// tray
// ---------------------------------------------------------------------------
function buildTray(payload) {
  const devices = (payload && payload.devices) || [];
  if (!tray) {
    const iconPath = path.join(RENDERER_DIR, 'titlebar-icon.png');
    try {
      tray = new Tray(fs.existsSync(iconPath) ? iconPath : path.join(RENDERER_DIR, 'titlebar-icon-red.png'));
    } catch (e) { log('tray create failed', e.message); return; }
    tray.on('click', () => {
      if (!mainWindow) createMainWindow();
      else if (mainWindow.isVisible()) mainWindow.hide();
      else { mainWindow.show(); mainWindow.focus(); }
    });
  }
  const menu = Menu.buildFromTemplate([
    ...devices.map((d) => ({
      label: `${d.product || 'Device'}${d.online === false ? ' (offline)' : ''}`,
      enabled: false,
    })),
    ...(devices.length ? [{ type: 'separator' }] : []),
    { label: 'Open', click: () => { if (!mainWindow) createMainWindow(); mainWindow.show(); } },
    { label: 'Preferences', click: () => openPreference() },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() },
  ]);
  tray.setToolTip('Hexcore Link');
  tray.setContextMenu(menu);
}

// ---------------------------------------------------------------------------
// displays
// ---------------------------------------------------------------------------
function readDisplays() {
  cachedDisplays = screen.getAllDisplays().map((d) => ({
    id: d.id,
    label: d.label,
    bounds: d.bounds,
    workArea: d.workArea,
    scaleFactor: d.scaleFactor,
    rotation: d.rotation,
    internal: d.internal,
    primary: d.id === screen.getPrimaryDisplay().id,
  }));
  return cachedDisplays;
}

// ---------------------------------------------------------------------------
// IPC registration
// ---------------------------------------------------------------------------
function registerIpc() {
  // ---- window control -----------------------------------------------------
  ipcMain.on('change-xMinimize', () => {
    const win = BrowserWindow.getFocusedWindow() || mainWindow;
    if (!win) return;
    if (win.isMaximized()) win.unmaximize(); else win.maximize();
  });

  ipcMain.on('open-preference', () => openPreference());
  ipcMain.on('open-updater', (_e, show) => openUpdater(show !== false));
  ipcMain.on('renderer-ready', (_e, info) => log('renderer-ready', JSON.stringify(info || {})));
  ipcMain.on('launch-timing-stats', (_e, payload) => log('launch-timing', JSON.stringify(payload || {})));
  ipcMain.on('build-tray', (_e, payload) => buildTray(payload));

  // Electron 28 removed ipcRenderer.sendTo(), which the vendor preloads use to
  // message sibling windows directly. compat-preload re-implements it as a
  // send to the main process; deliver it to the target renderer here. Restrict
  // both ends to this app's own windows so a compromised renderer cannot
  // address arbitrary webContents.
  ipcMain.on('__compat-send-to', (event, targetId, channel, ...args) => {
    if (typeof channel !== 'string') return;
    const ids = Object.values(windowIds());
    if (!ids.includes(event.sender.id) || !ids.includes(targetId)) return;
    const target = webContents.fromId(targetId);
    if (target && !target.isDestroyed()) target.send(channel, ...args);
  });

  // ---- theme --------------------------------------------------------------
  // The renderer uses invoke() here, so this must be a handler, not a listener.
  // Only mutate themeSource when the value actually changes: setting it
  // fires nativeTheme 'updated', and echoing that back to the renderer makes
  // it invoke again -- an unbounded ping-pong that wedges the UI thread.
  ipcMain.handle('native-theme', (_e, theme) => {
    if ((theme === 'dark' || theme === 'light') && nativeTheme.themeSource !== theme) {
      nativeTheme.themeSource = theme;
    }
    return nativeTheme.shouldUseDarkColors ? 'dark' : 'light';
  });

  // ---- dialogs ------------------------------------------------------------
  ipcMain.handle('dialog:open', async (_e, options = {}) => {
    const res = await dialog.showOpenDialog(mainWindow || undefined, {
      properties: options.properties || ['openFile'],
      filters: options.filters,
      title: options.title,
    });
    return res.canceled ? { canceled: true, filePaths: [] } : { canceled: false, filePaths: res.filePaths };
  });

  ipcMain.handle('dialog:show-save', async (_e, options = {}) => {
    const res = await dialog.showSaveDialog(mainWindow || undefined, {
      defaultPath: options.defaultPath,
      filters: options.filters,
    });
    return res.canceled ? { canceled: true } : { canceled: false, filePath: res.filePath };
  });

  ipcMain.handle('desktopCapturer', async () => {
    const { desktopCapturer } = require('electron');
    const sources = await desktopCapturer.getSources({ types: ['screen', 'window'], thumbnailSize: { width: 0, height: 0 } });
    return sources.map((s) => ({ id: s.id, name: s.name, display_id: s.display_id }));
  });

  // ---- displays -----------------------------------------------------------
  ipcMain.handle('display-get-list', () => readDisplays());
  ipcMain.handle('getAllDisplays', () => readDisplays());
  ipcMain.handle('display-change-input', (_e, displayId, input) => {
    log('display-change-input', displayId, input);
    return { ok: false, reason: 'ddc-ci not available in this build' };
  });
  ipcMain.handle('display-brightness-value', (_e, displayId) => {
    log('display-brightness-value', displayId);
    return null;
  });
  ipcMain.handle('display-brightness-step', (_e, displayId, step) => {
    log('display-brightness-step', displayId, step);
    return null;
  });
  ipcMain.handle('display-brightness-enabled', (_e, displayId, enabled) => {
    log('display-brightness-enabled', displayId, enabled);
    return { ok: false };
  });

  // ---- audio / volume (backed by the preload's own HID path) --------------
  ipcMain.handle('volumeStep', (_e, step) => {
    log('volumeStep', step);
    return null;
  });
  ipcMain.handle('volumeSet', (_e, value) => {
    log('volumeSet', value);
    return null;
  });
  ipcMain.handle('volumeEnable', (_e, enabled) => {
    log('volumeEnable', enabled);
    return null;
  });

  // ---- backlight / brightness --------------------------------------------
  ipcMain.handle('backlightBrightness', (_e, pathOrId, value) => {
    log('backlightBrightness', pathOrId, value);
    return null;
  });
  ipcMain.handle('write-brightness', (_e, value) => {
    log('write-brightness', value);
    return null;
  });

  // ---- lock keys ----------------------------------------------------------
  ipcMain.handle('lockKeys_setting', (_e, payload) => {
    log('lockKeys_setting', JSON.stringify(payload || {}));
    return { ok: true };
  });

  // ---- wireless pairing ---------------------------------------------------
  ipcMain.handle('wireless-paring', (_e, payload) => {
    log('wireless-paring', JSON.stringify(payload || {}));
    return null;
  });

  // ---- notifications / animation -----------------------------------------
  ipcMain.on('notify-time', (_e, ms) => log('notify-time', ms));
  ipcMain.on('notify-animation', (_e, payload) => log('notify-animation', JSON.stringify(payload || {})));
  ipcMain.on('notify-background-brightness', (_e, payload) => log('notify-background-brightness', payload));

  // ---- hardware monitor ---------------------------------------------------
  ipcMain.on('hardware-monitor:start-server', () => log('hardware-monitor:start-server'));
  ipcMain.on('hardware-monitor:server-stoped', () => log('hardware-monitor:server-stoped'));

  // ---- updater ------------------------------------------------------------
  ipcMain.handle('updater:download_app', async () => {
    log('updater:download_app');
    return { ok: false, reason: 'auto-update disabled in this build' };
  });
  ipcMain.on('updater:notify', (_e, payload) => log('updater:notify', JSON.stringify(payload || {})));
  ipcMain.on('updater:quit_and_install', () => log('updater:quit_and_install'));
  ipcMain.on('updater:will_quit_and_install', () => log('updater:will_quit_and_install'));
}

// ---------------------------------------------------------------------------
// lifecycle
// ---------------------------------------------------------------------------
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) createMainWindow();
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  });

  app.whenReady().then(() => {
    log('main ready', process.arch, app.getVersion());
    registerIpc();

    // The vendor preloads call ipcRenderer.sendTo(), removed in Electron 28.
    // Apply the shim before any window exists.
    session.defaultSession.setPreloads([path.join(__dirname, 'compat-preload.js')]);


    // Sentry's renderer SDK probes this scheme during preload; if nothing
    // answers, the preload throws and the hid/database bridges never get
    // exposed. A minimal in-process handler is enough to satisfy the handshake.
    protocol.handle('sentry-ipc', () => new Response(JSON.stringify({ ok: true }), {
      headers: { 'content-type': 'application/json' },
    }));

    // Electron 25 removed the callback-based protocol APIs; handle() is the
    // replacement and keeps the app:// origin the CSP expects.
    protocol.handle('app', async (request) => {
      const { pathname } = new URL(request.url);
      const rel = decodeURIComponent(pathname).replace(/^\/+/, '') || 'app.html';
      const target = path.resolve(RENDERER_DIR, rel);
      if (target !== RENDERER_DIR && !target.startsWith(RENDERER_DIR + path.sep)) {
        return new Response('forbidden', { status: 403 });
      }
      try {
        const data = await fs.promises.readFile(target);
        return new Response(data, {
          headers: { 'content-type': MIME[path.extname(target)] || 'application/octet-stream' },
        });
      } catch (_) {
        return new Response('not found', { status: 404 });
      }
    });

    // Native theme changes are broadcast so the renderer can restyle.
    // Deliberately not broadcasting here: the renderer polls this value via
    // invoke('native-theme') and broadcasting completes the loop described above.


    screen.on('display-added', () => broadcastDisplays());
    screen.on('display-removed', () => broadcastDisplays());
    screen.on('display-metrics-changed', () => broadcastDisplays());

    // The UI caches window ids on first use, so the background window must
    // exist before the main window starts asking for them.
    createBackgroundWindow();
    createMainWindow();

    app.on('activate', () => {
      if (!mainWindow) createMainWindow();
    });
  });

  function broadcastDisplays() {
    const list = readDisplays();
    for (const w of BrowserWindow.getAllWindows()) {
      try { w.webContents.send('display-get-list', list); } catch (_) {}
    }
  }

  app.on('window-all-closed', () => {
    // Keep running in the tray on macOS, matching the original behaviour.
  });
}

process.on('uncaughtException', (err) => log('uncaughtException', err && err.stack));
process.on('unhandledRejection', (err) => log('unhandledRejection', String(err)));

// electron-store performs a synchronous handshake from the renderer to learn the
// user-data directory. The preloads instantiate it, so the main process must
// answer or user preferences fail to load.
ipcMain.on('electron-store-get-data', (event) => {
  log('sync-handler electron-store-get-data');
  event.returnValue = {
    defaultCwd: app.getPath('userData'),
    appVersion: app.getVersion(),
  };
});

// The preloads proxy several Electron `app` accessors through a single
// dispatcher channel, and listen for a handful of renderer->main events.
ipcMain.handle('app', (_e, method, ...args) => {
  switch (method) {
    case 'getPath': return app.getPath(args[0]);
    // The preloads resolve bundled assets relative to this path, e.g.
    // `${getAppPath()}/../locales`. It must therefore be the dist directory
    // inside app.asar, not the app root.
    case 'getAppPath': return path.join(app.getAppPath(), 'dist');
    case 'getVersion': return app.getVersion();
    case 'getName': return app.getName();
    default:
      // Never reject: an unresolved renderer promise at startup wedges the UI.
      log('app dispatcher: unknown method', method);
      return null;
  }
});

ipcMain.handle('volumeGet', () => null);

function broadcast(channel, ...args) {
  for (const w of BrowserWindow.getAllWindows()) {
    try { w.webContents.send(channel, ...args); } catch (_) {}
  }
}

ipcMain.on('change-locale', (_e, locale) => broadcast('change-locale', locale));

// ---------------------------------------------------------------------------
// Renderer-to-renderer routing. The preloads ask for webContents ids once and
// then talk to each other directly with ipcRenderer.sendTo(), so this mapping
// is the backbone of the background (HID worker) <-> UI channel.
// ---------------------------------------------------------------------------
function windowIds() {
  const ids = {};
  if (mainWindow && !mainWindow.isDestroyed()) ids.app = mainWindow.webContents.id;
  if (backgroundWindow && !backgroundWindow.isDestroyed()) ids.background = backgroundWindow.webContents.id;
  if (preferenceWindow && !preferenceWindow.isDestroyed()) ids.preference = preferenceWindow.webContents.id;
  if (updaterWindow && !updaterWindow.isDestroyed()) ids.updater = updaterWindow.webContents.id;
  return ids;
}

ipcMain.handle('get-window-ids', () => {
  const ids = windowIds();
  log('get-window-ids ->', JSON.stringify(ids));
  return ids;
});

ipcMain.on('window-control', (event, action) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (!win) return;
  switch (action) {
    case 'minimize': win.minimize(); break;
    case 'maximize': win.isMaximized() ? win.unmaximize() : win.maximize(); break;
    case 'close': win.close(); break;
    case 'hide': win.hide(); break;
    default: log('window-control unknown action', action);
  }
});

ipcMain.on('window-resize', (event, width, height) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (win && Number.isFinite(width) && Number.isFinite(height)) win.setSize(width, height, true);
});

ipcMain.on('set-minimum-size', (event, width, height) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (win && Number.isFinite(width) && Number.isFinite(height)) win.setMinimumSize(width, height);
});

ipcMain.on('show-contextual-menu', (event, items) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  if (!win || !Array.isArray(items)) return;
  const template = items.map((item) =>
    item && item.type === 'separator'
      ? { type: 'separator' }
      : {
          label: String(item && item.label ? item.label : ''),
          enabled: !(item && item.enabled === false),
          click: () => win.webContents.send('contextual-menu-clicked', item && item.id),
        });
  Menu.buildFromTemplate(template).popup({ window: win });
});

ipcMain.on('send-error-report', (event, payload) => {
  log('send-error-report', JSON.stringify(payload || {}).slice(0, 500));
});

ipcMain.handle('download-save-as', async (event, options = {}) => {
  const win = BrowserWindow.fromWebContents(event.sender);
  const res = await dialog.showSaveDialog(win || undefined, {
    defaultPath: options.defaultPath,
    filters: options.filters,
  });
  return res.canceled ? { canceled: true } : { canceled: false, filePath: res.filePath };
});

// Window state pushes used by the titlebar / layout code.
function pushWindowState(win) {
  try {
    win.webContents.send('window-state-changed', {
      maximized: win.isMaximized(),
      fullScreen: win.isFullScreen(),
      focused: win.isFocused(),
    });
  } catch (_) {}
}

