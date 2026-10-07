"use strict";
const { contextBridge, ipcRenderer } = require("electron");
contextBridge.exposeInMainWorld("dango", {
  load: () => ipcRenderer.invoke("state:load"),
  action: (name, payload) => ipcRenderer.invoke("state:action", name, payload),
  saveKey: (key) => ipcRenderer.invoke("key:save", key),
  exportData: () => ipcRenderer.invoke("data:export"),
  importData: () => ipcRenderer.invoke("data:import"),
  importCalendar: () => ipcRenderer.invoke("calendar:import"),
  generate: (date, input) => ipcRenderer.invoke("plan:generate", date, input),
  acceptPlan: (id, selected) => ipcRenderer.invoke("plan:accept", id, selected),
  openMain: () => ipcRenderer.invoke("window:main"),
  onState: (callback) => {
    const listener = (_, value) => callback(value);
    ipcRenderer.on("state:changed", listener);
    return () => ipcRenderer.removeListener("state:changed", listener);
  },
  onNavigate: (callback) => {
    const listener = (_, value) => callback(value);
    ipcRenderer.on("navigate", listener);
    return () => ipcRenderer.removeListener("navigate", listener);
  },
});
