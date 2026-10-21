'use strict';
// Electron 28 removed ipcRenderer.sendTo(), but the vendor preloads still use it
// for window-to-window messaging (preference -> main window for locale/theme,
// main <-> background for HID events). Patch it back on top of ipcRenderer.send
// and let the main process deliver the message; see the __compat-send-to
// handler in index.js.
//
// This runs as a session preload so it is applied before any window preload.
const { ipcRenderer } = require('electron');

if (typeof ipcRenderer.sendTo !== 'function') {
  ipcRenderer.sendTo = function sendTo(webContentsId, channel, ...args) {
    ipcRenderer.send('__compat-send-to', webContentsId, channel, ...args);
  };
}
