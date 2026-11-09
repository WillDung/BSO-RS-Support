const base = require("./playwright.config.cjs");

module.exports = {
  ...base,
  testMatch: "candidate-lifecycle.spec.cjs",
  workers: 1,
  retries: 0,
  repeatEach: 1,
  maxFailures: 1
};
