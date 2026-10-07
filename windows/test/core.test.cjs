const test = require("node:test"),
  assert = require("node:assert/strict"),
  fs = require("node:fs"),
  os = require("node:os"),
  path = require("node:path");
const c = require("../src/core.cjs"),
  ai = require("../src/ai.cjs"),
  { atomicWrite, readState } = require("../src/storage.cjs");
function fixture() {
  return c.defaults();
}
test("natural capture preserves task meaning and applies local dates", () => {
  const s = fixture();
  const t = c.parseCapture(
    "明天下午3点 写摘要 #工作 45m !高",
    s,
    new Date(2026, 9, 7, 10),
  );
  assert.equal(t.title, "写摘要");
  assert.equal(c.dayKey(t.plannedDate), "2026-10-08");
  assert.equal(t.scheduledMinute, 900);
  assert.equal(t.estimatedMinutes, 45);
  assert.equal(t.priority, "high");
  assert.equal(t.areaID, s.areas[1].id);
});
test("task creation and updates can each be undone once", () => {
  const s = fixture();
  c.applyAction(s, "addTask", { text: "写记录" });
  const id = s.tasks[0].id;
  c.applyAction(s, "updateTask", {
    id,
    patch: { title: "写复盘", plannedDate: "2026-10-08", scheduledMinute: 540 },
  });
  assert.equal(s.tasks[0].status, "planned");
  c.applyAction(s, "undo");
  assert.equal(s.tasks[0].title, "写记录");
  c.applyAction(s, "undo");
  assert.equal(s.tasks.length, 0);
});
test("invalid empty titles and times are rejected", () => {
  const s = fixture();
  assert.throws(() => c.parseCapture("明天 #工作 !高", s));
  assert.throws(() => c.parseCapture("25:00 不合法", s));
  assert.throws(() =>
    c.validateTask(c.newTask({ title: "x", scheduledMinute: 1440 })),
  );
});
test("trash can restore original waiting state", () => {
  const s = fixture();
  s.tasks.push(c.newTask({ title: "等待回复", status: "waiting" }));
  const id = s.tasks[0].id;
  c.applyAction(s, "trashTask", { id });
  assert.equal(s.tasks[0].status, "trashed");
  c.applyAction(s, "restoreTask", { id });
  assert.equal(s.tasks[0].status, "waiting");
});
test("monthly recurrence clamps month ends", () => {
  const t = c.newTask({
    title: "报表",
    plannedDate: "2026-01-31",
    recurrence: { frequency: "monthly", interval: 1, weekdays: [] },
  });
  assert.equal(c.nextDate(t), "2026-02-28");
});
test("weekly recurrence supports multiple weekdays and interval", () => {
  const t = c.newTask({
    title: "读书",
    plannedDate: "2026-10-05",
    recurrence: { frequency: "weekly", interval: 2, weekdays: [2, 4] },
  });
  assert.equal(c.nextDate(t), "2026-10-07");
  t.plannedDate = "2026-10-07";
  assert.equal(c.nextDate(t), "2026-10-19");
});
test("completion creates one next occurrence and undo restores series", () => {
  const s = fixture();
  s.tasks.push(
    c.newTask({
      title: "每天读书",
      plannedDate: "2026-10-07",
      recurrence: { frequency: "daily", interval: 1, weekdays: [] },
    }),
  );
  const id = s.tasks[0].id;
  c.applyAction(s, "toggleTask", { id });
  assert.equal(s.tasks.length, 2);
  assert.equal(c.dayKey(s.tasks[1].plannedDate), "2026-10-08");
  c.applyAction(s, "toggleTask", { id });
  c.applyAction(s, "toggleTask", { id });
  assert.equal(s.tasks.length, 2);
});
test("recurrence end date prevents next instance", () => {
  assert.equal(
    c.nextDate(
      c.newTask({
        title: "x",
        plannedDate: "2026-10-07",
        recurrence: {
          frequency: "daily",
          interval: 1,
          weekdays: [],
          endDate: "2026-10-07",
        },
      }),
    ),
    null,
  );
});
test("focus uses elapsed time and completion is idempotent", () => {
  const s = fixture();
  c.applyAction(s, "focusStart", { minutes: 25 }, 1000);
  assert.equal(c.tickFocus(s, 1500999), false);
  assert.equal(c.tickFocus(s, 1501000), true);
  assert.equal(c.tickFocus(s, 1601000), false);
  assert.equal(s.sessions.length, 1);
  assert.equal(s.sessions[0].minutes, 25);
});
test("pause and resume excludes paused time", () => {
  const s = fixture();
  c.applyAction(s, "focusStart", { minutes: 25 }, 1000);
  c.applyAction(s, "focusPause", {}, 61000);
  assert.equal(s.focus.remainingMs, 1440000);
  c.applyAction(s, "focusStart", {}, 200000);
  assert.equal(s.focus.endsAt, 1640000);
});
test("habit completion is separated by date", () => {
  const s = fixture(),
    id = s.habits[0].id;
  c.applyAction(s, "toggleHabit", { id, date: "2026-10-07" });
  assert.deepEqual(s.completions["2026-10-07"], [id]);
  assert.equal(s.completions["2026-10-08"], undefined);
});
test("monthly Sunday items only appear on last Sunday", () => {
  const s = fixture();
  assert(c.habitItems(s, "2026-10-25").some((h) => h.scope === "monthEnd"));
  assert(!c.habitItems(s, "2026-10-18").some((h) => h.scope === "monthEnd"));
});
test("week goals are stored independently", () => {
  const s = fixture();
  c.applyAction(s, "week", { date: "2026-10-07", goals: ["A"] });
  c.applyAction(s, "week", { date: "2026-10-14", goals: ["B"] });
  assert.equal(s.weeks["2026-10-05"].goals[0], "A");
  assert.equal(s.weeks["2026-10-12"].goals[0], "B");
});
test("scheduling avoids overlapping fixed ranges and other tasks", () => {
  assert.deepEqual(
    c.placeTasks(
      [30, 60],
      [
        { start: 420, end: 540 },
        { start: 550, end: 600 },
        { start: 600, end: 630 },
      ],
    ),
    [630, 660],
  );
});
test("Mac tasks import keeps IDs, dates and timeline fields", () => {
  const s = fixture(),
    t = c.newTask({
      title: "Mac task",
      scheduledMinute: 600,
      plannedDate: "2026-10-07",
      weeklyGoalIndex: 1,
    });
  c.importData(s, { tasks: [t], areas: s.areas });
  c.importData(s, { tasks: [{ ...t, title: "updated" }] });
  assert.equal(s.tasks.length, 1);
  assert.equal(s.tasks[0].scheduledMinute, 600);
  assert.equal(s.tasks[0].title, "updated");
});
test("atomic storage keeps backup and refuses to overwrite corrupt input on load", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dango-unit-"));
  try {
    const file = path.join(dir, "state.json");
    atomicWrite(file, fixture());
    const s = readState(file, fixture);
    s.tasks.push(c.newTask({ title: "saved" }));
    atomicWrite(file, s);
    assert(fs.existsSync(`${file}.bak`));
    fs.writeFileSync(file, "broken");
    assert.throws(() => readState(file, fixture), /原文件已保留/);
    assert.equal(fs.readFileSync(file, "utf8"), "broken");
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
test("AI rejects omitted inputs and invented existing tasks", () => {
  const context = {
      active_tasks: [],
      user_input_items: [{ input_item_id: "input" }],
    },
    p = {
      summary: "x",
      top_three: [],
      additional_tasks: [],
      workload_assessment: "ok",
      notes: "",
    };
  assert.throws(() => ai.validatePlan(p, context));
  p.top_three = [
    {
      title: "x",
      area: "工作",
      reason: "x",
      estimated_minutes: 30,
      priority: "high",
      source: "existing_task",
      task_id: "fake",
      input_item_id: null,
    },
  ];
  assert.throws(() => ai.validatePlan(p, context));
});
test("AI validates mapped inputs and excludes sensitive event extras", () => {
  const s = fixture();
  s.events = [
    {
      title: "会议",
      startDate: "2026-10-08T09:00:00",
      endDate: "2026-10-08T10:00:00",
      attendees: ["secret"],
      location: "secret",
    },
  ];
  const p = ai.payload(s, "2026-10-08", "读书");
  assert(!JSON.stringify(p).includes("secret"));
  const plan = {
    summary: "x",
    top_three: [
      {
        title: "读书",
        area: "学习",
        reason: "x",
        estimated_minutes: 30,
        priority: "high",
        source: "user_input",
        task_id: null,
        input_item_id: p.user_input_items[0].input_item_id,
      },
    ],
    additional_tasks: [],
    workload_assessment: "ok",
    notes: "",
  };
  assert(ai.validatePlan(plan, p).top_three[0].id);
});
