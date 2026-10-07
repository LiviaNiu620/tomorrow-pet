"use strict";
const fs = require("node:fs");
const path = require("node:path");
function atomicWrite(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(temp, JSON.stringify(value, null, 2), { mode: 0o600 });
    if (fs.existsSync(file)) fs.copyFileSync(file, `${file}.bak`);
    fs.renameSync(temp, file);
  } finally {
    if (fs.existsSync(temp)) fs.unlinkSync(temp);
  }
}
function readState(file, create) {
  if (!fs.existsSync(file)) return create();
  try {
    const s = JSON.parse(fs.readFileSync(file, "utf8"));
    if (
      s.schemaVersion !== 1 ||
      !Array.isArray(s.tasks) ||
      !Array.isArray(s.habits)
    )
      throw new Error("unsupported schema");
    return s;
  } catch {
    throw new Error(
      `无法读取数据文件，请恢复备份后重试：${file}.bak（原文件已保留）`,
    );
  }
}
module.exports = { atomicWrite, readState };
