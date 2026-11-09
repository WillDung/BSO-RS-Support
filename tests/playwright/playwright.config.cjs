const { defineConfig } = require("@playwright/test");
const { protectDirectory, authDirectory, runDirectory } = require("./local-settings.cjs");

protectDirectory(authDirectory);
protectDirectory(runDirectory);
process.env.BSO_UAT_RUN_DIRECTORY = runDirectory;

module.exports = defineConfig({
  testDir: __dirname,
  testMatch: "candidate-core.spec.cjs",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 600_000,
  expect: { timeout: 30_000 },
  preserveOutput: "never",
  outputDir: require("node:path").join(runDirectory, "runner"),
  reporter: [["./sanitized-reporter.cjs"]],
  use: {
    headless: false,
    screenshot: "off",
    trace: "off",
    video: "off"
  }
});
