const fs = require("node:fs");
const path = require("node:path");
const { runDirectory } = require("./local-settings.cjs");

class SanitizedReporter {
  onBegin() {
    console.log("Headed Candidate Core UAT: one worker; zero retries. Sign in directly in Chromium.");
  }

  onTestEnd(test, result) {
    const codes = [...new Set(result.errors.flatMap(error =>
      (error.message || "").match(/\bUAT_[A-Z_]+\b/g) || []))];
    this.result = { status: result.status, codes };
    console.log(`${test.title}: ${result.status}${codes.length ? ` (${codes.join(", ")})` : ""}`);
  }

  onError() {
    this.runnerError = true;
    console.log("UAT_RUNNER_ERROR: inspect the protected local result; raw browser details suppressed.");
  }

  onEnd(result) {
    fs.writeFileSync(path.join(runDirectory, "runner-summary.json"), JSON.stringify({
      status: result.status,
      test: this.result,
      runnerError: this.runnerError === true,
      retries: 0,
      workers: 1
    }, null, 2));
    console.log(`Protected evidence: ${runDirectory}`);
  }
}

module.exports = SanitizedReporter;
