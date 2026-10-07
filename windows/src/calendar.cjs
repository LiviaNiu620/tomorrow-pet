"use strict";
function parseCalendar(source, now = new Date()) {
  const ical = require("node-ical");
  const events = ical.sync.parseICS(source);
  const from = new Date(now);
  from.setDate(from.getDate() - 7);
  const until = new Date(now);
  until.setDate(until.getDate() + 60);
  const result = [];
  for (const event of Object.values(events)) {
    if (
      event.type !== "VEVENT" ||
      !event.start ||
      !event.end ||
      event.status === "CANCELLED"
    )
      continue;
    const dates = event.rrule
      ? event.rrule.between(from, until, true, (_, i) => i < 10000)
      : [event.start];
    if (dates.length >= 10000) throw new Error("日历重复频率过高");
    for (const date of dates) {
      const exclusion =
        event.exdate &&
        Object.values(event.exdate).some(
          (x) => new Date(x).getTime() === date.getTime(),
        );
      if (exclusion) continue;
      const key = date.toISOString().slice(0, 10);
      const override = event.recurrences?.[key];
      if (override?.status === "CANCELLED") continue;
      const item = override || event;
      const start = override?.start || date,
        end =
          override?.end ||
          new Date(
            start.getTime() + event.end.getTime() - event.start.getTime(),
          );
      result.push({
        id: `ics:${event.uid}:${date.toISOString()}`,
        title: String(item.summary || "未命名日程"),
        startDate: start.toISOString(),
        endDate: end.toISOString(),
        isAllDay: item.datetype === "date" || item.start?.dateOnly === true,
        calendarTitle: "导入日历",
        source: "ics",
      });
      if (result.length > 10000)
        throw new Error("日历事件过多，请缩小导出范围");
    }
  }
  return result;
}
module.exports = { parseCalendar };
