// The pages were written for WebKit and post their messages to
// window.webkit.messageHandlers.snowfall. Give them that same bridge here, so
// index.html and settings.html run unchanged on every platform.
"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("webkit", {
  messageHandlers: {
    snowfall: {
      postMessage: (message) => ipcRenderer.send("snowfall", message)
    }
  }
});
