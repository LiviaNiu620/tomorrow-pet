const { spawn } = require("node:child_process");
const electron = require("electron");
const child = spawn(electron, ["."], {
  stdio: "inherit",
  env: { ...process.env, DANGO_SMOKE_TEST: "1" },
});
const timeout = setTimeout(() => {
  console.error("Smoke test timed out");
  child.kill();
  process.exitCode = 1;
}, 90000);
child.on("error", (error) => {
  clearTimeout(timeout);
  console.error(error);
  process.exitCode = 1;
});
child.on("exit", (code) => {
  clearTimeout(timeout);
  process.exitCode = code ?? 1;
});
