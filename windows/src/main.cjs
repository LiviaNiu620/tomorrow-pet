"use strict";
const {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  safeStorage,
  Notification,
  Menu,
  Tray,
  nativeImage,
  globalShortcut,
} = require("electron");
const path = require("node:path"),
  fs = require("node:fs"),
  { pathToFileURL } = require("node:url"),
  { randomUUID } = require("node:crypto");
const core = require("./core.cjs"),
  { atomicWrite, readState } = require("./storage.cjs"),
  { generate } = require("./ai.cjs");
const smoke = process.env.DANGO_SMOKE_TEST === "1";
app.setName("Tomorrow Pet");
app.setPath(
  "userData",
  smoke
    ? fs.mkdtempSync(path.join(app.getPath("temp"), "dango-smoke-"))
    : path.join(app.getPath("appData"), "TomorrowPet-Windows"),
);
const directory = app.getPath("userData"),
  file = path.join(directory, "dango.json"),
  keyFile = path.join(directory, "credentials.json");
let state,
  mainWindow,
  petWindow,
  tray,
  quitting = false;
const drafts = new Map();
let generating = false;
const html = (name) => path.join(__dirname, "../ui", name);
const allowed = new Set(
  ["index.html", "pet.html"].map((x) => pathToFileURL(html(x)).href),
);
function publicState() {
  return {
    ...state,
    undo: undefined,
    canUndo: state.undo.length > 0,
    hasKey: fs.existsSync(keyFile),
    version: app.getVersion(),
    dataPath: directory,
  };
}
function broadcast() {
  const value = publicState();
  for (const w of [mainWindow, petWindow])
    if (w && !w.isDestroyed()) w.webContents.send("state:changed", value);
}
function transaction(fn) {
  const next = structuredClone(state);
  fn(next);
  next.revision = (next.revision || 0) + 1;
  atomicWrite(file, next);
  state = next;
  broadcast();
  return publicState();
}
function wrap(channel, handler) {
  ipcMain.handle(channel, async (event, ...args) => {
    if (!allowed.has(event.senderFrame?.url)) throw new Error("不允许的窗口");
    try {
      return { ok: true, value: await handler(...args) };
    } catch (error) {
      return { ok: false, error: error.message || "操作失败" };
    }
  });
}
function secureWindow(options) {
  const w = new BrowserWindow({
    ...options,
    icon: html("icon.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      webSecurity: true,
    },
  });
  w.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  w.webContents.on("will-navigate", (e) => e.preventDefault());
  w.webContents.session.setPermissionRequestHandler((_, __, callback) =>
    callback(false),
  );
  return w;
}
function showMain(section) {
  if (!mainWindow || mainWindow.isDestroyed()) {
    mainWindow = secureWindow({
      width: 1380,
      height: 900,
      minWidth: 960,
      minHeight: 680,
      title: "明日团子",
      backgroundColor: "#e8ede3",
      show: false,
    });
    mainWindow.loadFile(html("index.html"));
    mainWindow.once("ready-to-show", () => {
      if (!smoke) mainWindow.show();
      if (section) mainWindow.webContents.send("navigate", section);
    });
    mainWindow.on("close", (event) => {
      if (!quitting) {
        event.preventDefault();
        mainWindow.hide();
      }
    });
  } else {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
    if (section) mainWindow.webContents.send("navigate", section);
  }
}
function updatePet() {
  if (state.settings.pet) {
    if (!petWindow || petWindow.isDestroyed()) {
      petWindow = secureWindow({
        width: 210,
        height: 230,
        frame: false,
        transparent: true,
        resizable: false,
        alwaysOnTop: true,
        skipTaskbar: true,
        show: false,
      });
      petWindow.loadFile(html("pet.html"));
      petWindow.once("ready-to-show", () => petWindow.showInactive());
    } else petWindow.showInactive();
  } else if (petWindow && !petWindow.isDestroyed()) petWindow.hide();
}
function notify(title, body) {
  if (Notification.isSupported()) {
    const n = new Notification({ title, body, icon: html("icon.png") });
    n.on("click", () => showMain("today"));
    n.show();
  }
}
function key() {
  if (!fs.existsSync(keyFile)) return "";
  if (!safeStorage.isEncryptionAvailable())
    throw new Error("系统密钥加密不可用");
  const value = JSON.parse(fs.readFileSync(keyFile, "utf8"));
  return safeStorage.decryptString(Buffer.from(value.encrypted, "base64"));
}
function registerIPC() {
  wrap("state:load", () => publicState());
  wrap("state:action", (name, payload) => {
    const result = transaction((s) => core.applyAction(s, name, payload));
    if (name === "settings") updatePet();
    return result;
  });
  wrap("window:main", () => {
    showMain();
    return true;
  });
  wrap("key:save", (value) => {
    if (typeof value !== "string" || value.length > 1000)
      throw new Error("密钥无效");
    if (!value.trim()) {
      if (fs.existsSync(keyFile)) fs.unlinkSync(keyFile);
    } else {
      if (
        !safeStorage.isEncryptionAvailable() ||
        safeStorage.getSelectedStorageBackend?.() === "basic_text"
      )
        throw new Error("系统加密不可用，未保存密钥");
      atomicWrite(keyFile, {
        encrypted: safeStorage.encryptString(value.trim()).toString("base64"),
      });
    }
    broadcast();
    return publicState();
  });
  wrap("data:export", async () => {
    const result = await dialog.showSaveDialog(mainWindow, {
      title: "导出团子备份（不含密钥）",
      defaultPath: `Dango-${core.dayKey()}.json`,
      filters: [{ name: "JSON", extensions: ["json"] }],
    });
    if (result.canceled) return false;
    const { undo, focus, ...data } = state;
    fs.writeFileSync(result.filePath, JSON.stringify(data, null, 2));
    return true;
  });
  wrap("data:import", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "导入团子备份或 Mac 的 task-store / daily-sop / journal",
      properties: ["openFile"],
      filters: [{ name: "JSON", extensions: ["json"] }],
    });
    if (result.canceled) return null;
    const selected = result.filePaths[0];
    if (fs.statSync(selected).size > 10 * 1024 * 1024)
      throw new Error("备份不能大于 10 MB");
    const data = JSON.parse(fs.readFileSync(selected, "utf8"));
    const next = core.importData(structuredClone(state), data);
    validateImported(next);
    const confirmation = await dialog.showMessageBox(mainWindow, {
      type: "question",
      message: `合并后共有 ${next.tasks.length} 个任务和 ${next.habits.length} 项习惯。相同 ID 的记录将更新。`,
      buttons: ["取消", "导入"],
      defaultId: 0,
      cancelId: 0,
    });
    if (confirmation.response !== 1) return null;
    atomicWrite(file, next);
    state = next;
    broadcast();
    return publicState();
  });
  wrap("calendar:import", async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      title: "导入 Calendar 导出的 .ics 文件",
      properties: ["openFile"],
      filters: [{ name: "iCalendar", extensions: ["ics"] }],
    });
    if (result.canceled) return null;
    if (fs.statSync(result.filePaths[0]).size > 5 * 1024 * 1024)
      throw new Error("日历文件过大");
    const events = require("./calendar.cjs").parseCalendar(
      fs.readFileSync(result.filePaths[0], "utf8"),
    );
    const confirmation = await dialog.showMessageBox(mainWindow, {
      type: "question",
      message: `导入 ${events.length} 个日程，将替换此前导入的日历快照。`,
      buttons: ["取消", "导入"],
      defaultId: 0,
      cancelId: 0,
    });
    if (confirmation.response !== 1) return null;
    return transaction((s) => {
      s.events = events;
    });
  });
  wrap("plan:generate", async (date, input) => {
    core.localDay(date);
    if (generating) throw new Error("已有计划正在生成");
    generating = true;
    try {
      const plan = await generate(state, date, input, key());
      const id = randomUUID();
      drafts.clear();
      drafts.set(id, { plan, date });
      return { id, date, ...plan };
    } finally {
      generating = false;
    }
  });
  wrap("plan:accept", (id, selected) => {
    const draft = drafts.get(id);
    if (!draft) throw new Error("草稿已过期，请重新生成");
    if (!Array.isArray(selected) || !selected.length)
      throw new Error("请选择任务");
    const all = [...draft.plan.top_three, ...draft.plan.additional_tasks];
    if (selected.some((x) => !all.some((t) => t.id === x)))
      throw new Error("任务选择无效");
    const chosen = all.filter((x) => selected.includes(x.id));
    const result = transaction((s) => {
      if (s.acceptedPlans.includes(id)) throw new Error("此计划已保存");
      s.undo.push(structuredClone(s.tasks));
      s.undo = s.undo.slice(-20);
      const busy = s.tasks
        .filter(
          (t) =>
            core.active(t) &&
            t.plannedDate &&
            core.dayKey(t.plannedDate) === draft.date &&
            t.scheduledMinute != null,
        )
        .map((t) => ({
          start: t.scheduledMinute,
          end: t.scheduledMinute + (t.estimatedMinutes || 30),
        }));
      for (const e of s.events.filter(
        (x) =>
          !x.isAllDay &&
          core.dayKey(x.startDate) <= draft.date &&
          core.dayKey(x.endDate) >= draft.date,
      )) {
        const start = core.localDay(draft.date).getTime();
        busy.push({
          start: Math.max(0, (new Date(e.startDate) - start) / 60000),
          end: Math.min(1440, (new Date(e.endDate) - start) / 60000),
        });
      }
      for (const b of s.blocks || require("./blocks.json")) {
        const date = core.localDay(draft.date);
        if (
          b.scope === "everyday" ||
          (date.getDay() === 0 &&
            (b.scope === "sunday" ||
              new Date(
                date.getFullYear(),
                date.getMonth(),
                date.getDate() + 7,
              ).getMonth() !== date.getMonth()))
        )
          busy.push(b);
      }
      const placements = core.placeTasks(
        chosen.map((t) => t.estimated_minutes),
        busy,
      );
      chosen.forEach((item, i) => {
        let t = s.tasks.find((x) => x.id === item.task_id);
        if (item.task_id && !t) throw new Error("原任务已删除，请重新生成");
        if (t && !core.active(t))
          throw new Error("原任务状态已改变，请重新生成");
        if (!t) {
          t = core.newTask({
            title: item.title,
            notes: item.reason,
            source: "openAI",
          });
          s.tasks.push(t);
        }
        Object.assign(t, {
          plannedDate: core.localDay(draft.date).toISOString(),
          status: "planned",
          estimatedMinutes: item.estimated_minutes,
          scheduledMinute: placements[i],
          priority: item.priority,
          areaID: s.areas.find((a) => a.name === item.area)?.id || t.areaID,
          focusDate: draft.plan.top_three.some((x) => x.id === item.id)
            ? core.localDay(draft.date).toISOString()
            : null,
        });
      });
      s.acceptedPlans = [...s.acceptedPlans, id].slice(-50);
    });
    drafts.delete(id);
    return result;
  });
}
function validateImported(s) {
  if (
    s.habits.length > 5000 ||
    s.events.length > 10000 ||
    s.sessions.length > 100000
  )
    throw new Error("备份记录数量超限");
  for (const b of s.blocks || []) {
    if (
      !Number.isInteger(b.start) ||
      !Number.isInteger(b.end) ||
      b.start < 0 ||
      b.end > 1440 ||
      b.start >= b.end
    )
      throw new Error("SOP 时段无效");
  }
  for (const h of s.habits)
    if (
      typeof h.id !== "string" ||
      typeof h.title !== "string" ||
      !["everyday", "sunday", "monthEnd"].includes(h.scope)
    )
      throw new Error("习惯数据格式无效");
  for (const key of ["weeks", "completions", "reviews"]) {
    if (!s[key] || typeof s[key] !== "object" || Array.isArray(s[key]))
      throw new Error("备份格式无效");
    for (const date of Object.keys(s[key])) core.localDay(date);
  }
  for (const e of s.events) {
    core.dayKey(e.startDate);
    core.dayKey(e.endDate);
    if (typeof e.title !== "string") throw new Error("日历数据格式无效");
  }
  for (const v of Object.values(s.completions))
    if (!Array.isArray(v) || v.some((x) => typeof x !== "string"))
      throw new Error("打卡数据格式无效");
  for (const w of Object.values(s.weeks))
    if (!Array.isArray(w.goals) || w.goals.some((x) => typeof x !== "string"))
      throw new Error("目标格式无效");
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", () => showMain());
  app.whenReady().then(() => {
    try {
      state = readState(file, core.defaults);
      state.undo ||= [];
      state.acceptedPlans ||= [];
      state.events ||= [];
      state.reminderSent ||= {};
      validateImported(state);
      if (core.tickFocus(state)) atomicWrite(file, state);
    } catch (error) {
      dialog.showErrorBox("数据未能载入", error.message);
      app.quit();
      return;
    }
    app.setAppUserModelId("com.tomorrowpet.windows");
    Menu.setApplicationMenu(
      Menu.buildFromTemplate([
        {
          label: "文件",
          submenu: [
            { label: "打开明日团子", click: () => showMain() },
            {
              label: "设置",
              accelerator: "CmdOrCtrl+,",
              click: () => showMain("settings"),
            },
            { type: "separator" },
            {
              label: "退出",
              accelerator: "CmdOrCtrl+Q",
              click: () => {
                quitting = true;
                app.quit();
              },
            },
          ],
        },
        { role: "editMenu" },
        { role: "viewMenu" },
      ]),
    );
    registerIPC();
    showMain();
    if (smoke) {
      runSmoke().catch((error) => {
        console.error(error);
        app.exit(1);
      });
      return;
    }
    updatePet();
    tray = new Tray(nativeImage.createFromPath(html("tray.png")));
    tray.setToolTip("明日团子");
    tray.setContextMenu(
      Menu.buildFromTemplate([
        { label: "打开明日团子", click: () => showMain() },
        { label: "随手记", click: () => showMain("capture") },
        { label: "开始 / 暂停专注", click: () => showMain("focus") },
        { type: "separator" },
        {
          label: "退出",
          click: () => {
            quitting = true;
            app.quit();
          },
        },
      ]),
    );
    tray.on("double-click", () => showMain());
    globalShortcut.register("CommandOrControl+Shift+Space", () =>
      showMain("capture"),
    );
    setInterval(() => {
      try {
        if (state.focus?.status === "running") {
          if (Date.now() >= state.focus.endsAt) {
            transaction((s) => core.tickFocus(s));
            notify("完成一颗团子", "专注完成，休息一下吧。");
          } else broadcast();
        }
        if (state.settings.reminders) {
          const now = new Date(),
            time = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`,
            date = core.dayKey(now),
            target =
              now.getDay() === 0
                ? state.settings.weeklyTime
                : state.settings.dailyTime;
          const stamp = `${date}:${target}`;
          if (time === target && !state.reminderSent[stamp]) {
            transaction((s) => {
              s.reminderSent = { [stamp]: true };
            });
            notify(
              "团子来找你安排明天了",
              now.getDay() === 0
                ? "看看本周方向，给下周留出空间。"
                : "安排三个重点，给明天留一点从容。",
            );
          }
        }
      } catch (error) {
        console.error("Background update failed:", error.message);
      }
    }, 1000).unref();
  });
  app.on("activate", () => showMain());
  app.on("before-quit", () => {
    quitting = true;
    globalShortcut.unregisterAll();
  });
  app.on("window-all-closed", () => {});
}

async function runSmoke() {
  const loaded = new Promise((resolve, reject) => {
    mainWindow.webContents.once("did-finish-load", resolve);
    mainWindow.webContents.once("did-fail-load", (_, code, description) =>
      reject(new Error(`${code}: ${description}`)),
    );
  });
  const errors = [];
  mainWindow.webContents.on("console-message", (details) => {
    if (details.level === "error") errors.push(details.message);
  });
  await loaded;
  for (let i = 0; i < 100; i++) {
    if (
      await mainWindow.webContents.executeJavaScript(
        "Boolean(document.querySelector('h1'))",
      )
    )
      break;
    await new Promise((r) => setTimeout(r, 100));
  }
  const output = path.join(__dirname, "../dist-smoke");
  fs.mkdirSync(output, { recursive: true });
  for (const page of [
    "today",
    "week",
    "library",
    "habits",
    "review",
    "focus",
    "settings",
  ]) {
    const result = await mainWindow.webContents.executeJavaScript(
      `navigate('${page}'); ({title:document.querySelector('h1')?.textContent,overflow:document.documentElement.scrollWidth>innerWidth})`,
    );
    if (!result.title || result.overflow)
      throw new Error(`Invalid layout on ${page}: ${JSON.stringify(result)}`);
    await new Promise((r) => setTimeout(r, 60));
    const image = await mainWindow.webContents.capturePage();
    fs.writeFileSync(path.join(output, `${page}.png`), image.toPNG());
  }
  const response = await mainWindow.webContents.executeJavaScript(
    "window.dango.action('addTask',{text:'明天 写自动验收记录 #学习 30m !高'})",
  );
  if (!response.ok || response.value.tasks.length !== 1)
    throw new Error("IPC create failed");
  await mainWindow.webContents.executeJavaScript(
    "window.dango.action('undo',{})",
  );
  if (errors.length) throw new Error(errors.join("\n"));
  console.log(
    "Electron smoke passed: 7 pages, IPC create/undo, no horizontal overflow.",
  );
  quitting = true;
  app.quit();
}
