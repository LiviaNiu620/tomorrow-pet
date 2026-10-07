const test = require("node:test"),
  assert = require("node:assert/strict"),
  { parseCalendar } = require("../src/calendar.cjs");
test("calendar import expands recurrence and respects exceptions", () => {
  const text = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "BEGIN:VEVENT",
    "UID:demo",
    "DTSTART:20261007T090000Z",
    "DTEND:20261007T100000Z",
    "RRULE:FREQ=DAILY;COUNT=3",
    "EXDATE:20261008T090000Z",
    "SUMMARY:Daily review",
    "END:VEVENT",
    "END:VCALENDAR",
  ].join("\r\n");
  const result = parseCalendar(text, new Date("2026-10-07"));
  assert.equal(result.length, 2);
  assert.equal(result[0].title, "Daily review");
  assert.equal(result[1].startDate, "2026-10-09T09:00:00.000Z");
});
