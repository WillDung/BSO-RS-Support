"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const executable = path.join(__dirname, "..", "AvailabilityQuerySdk", "bin", "Debug", "net48",
  "AvailabilityQuerySdk.Tests.exe");

function invokeGuard(input) {
  if (!fs.existsSync(executable)) {
    throw new Error("Build tests\\AvailabilityQuerySdk\\AvailabilityQuerySdk.Tests.csproj before integration tests.");
  }
  const result = spawnSync(executable, ["--calendar-bridge"], {
    input: JSON.stringify(input), encoding: "utf8", timeout: 30000, maxBuffer: 1024 * 1024
  });
  if (result.error || result.status !== 0) {
    throw new Error("The offline Availability Query guard bridge failed; run its focused SDK tests.");
  }
  let output;
  try {
    output = JSON.parse(result.stdout);
  } catch {
    throw new Error("The offline Availability Query guard bridge did not return JSON.");
  }
  if (!output || typeof output.accepted !== "boolean") {
    throw new Error("The offline Availability Query guard bridge returned an invalid envelope.");
  }
  return output;
}

module.exports = { invokeGuard };
