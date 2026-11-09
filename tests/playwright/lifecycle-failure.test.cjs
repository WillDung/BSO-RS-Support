const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  captureFailure, failureEvidence, refreshFailureEvidence, sanitizeBlockedRequest
} = require("./lifecycle-failure.cjs");

test("Failure evidence retains assertion identity, phase, safe values and source location", () => {
  const error = new Error("expect(locator).toHaveCount(2)");
  error.matcherResult = { name: "toHaveCount", expected: 2, actual: 1 };
  error.stack = "Error\n    at tests/playwright/candidate-lifecycle.spec.cjs:120:9";
  const evidence = failureEvidence(error, "candidate-console-initialization", null, { READ_REQUEST_ALLOWED: 7 });
  assert.deepEqual(evidence, {
    assertion: "toHaveCount",
    phase: "candidate-console-initialization",
    code: "UAT_LIFECYCLE_ASSERTION_FAILED",
    expectedActual: { expected: 2, actual: 1 },
    location: { file: "candidate-lifecycle.spec.cjs", line: 120, column: 9 },
    firstRelevantBlockedRequest: null,
    requestCategoryCounts: { READ_REQUEST_ALLOWED: 7 }
  });
});

test("Failure evidence captures arrays while redacting arbitrary assertion strings", () => {
  const error = new Error("unsafe assertion text");
  error.matcherResult = {
    name: "toHaveText",
    expected: ["Round 1 Scheduled", "candidate-private"],
    actual: ["Round 1 Scheduled", "email-private@example.invalid"]
  };
  const evidence = failureEvidence(error, "candidate-console-initialization", null, {});
  assert.deepEqual(evidence.expectedActual, {
    expected: ["Round 1 Scheduled", "[REDACTED_STRING]"],
    actual: ["Round 1 Scheduled", "[REDACTED_STRING]"]
  });
  assert.equal(JSON.stringify(evidence).includes("email-private"), false);
});

test("Failure evidence redacts arbitrary matcher strings and blocked request extras", () => {
  const error = new Error("value must stay private");
  error.matcherResult = { name: "toHaveText", expected: "private-name", actual: "private-email" };
  const evidence = failureEvidence(error, "console-initialization", {
    classification: "UNKNOWN_REQUEST_BLOCKED", method: "POST", host: "crm.example.invalid",
    path: "/AppWebServices/MetadataService.asmx/GetResourceStrings",
    resourceType: "xhr", navigation: false, query: "must-not-be-recorded", payload: "must-not-be-recorded"
  }, { UNKNOWN_REQUEST_BLOCKED: 1 });
  assert.deepEqual(evidence.expectedActual, {
    expected: "[REDACTED_STRING]",
    actual: "[REDACTED_STRING]"
  });
  assert.deepEqual(evidence.firstRelevantBlockedRequest, {
    classification: "UNKNOWN_REQUEST_BLOCKED",
    method: "POST",
    host: "crm.example.invalid",
    path: "/AppWebServices/MetadataService.asmx/GetResourceStrings",
    resourceType: "xhr",
    navigation: false
  });
  assert.equal(JSON.stringify(evidence).includes("private"), false);
  assert.equal(JSON.stringify(evidence).includes("must-not-be-recorded"), false);
});

test("Failure evidence removes organization hostnames and user identifiers from blocked paths", () => {
  const blocked = sanitizeBlockedRequest({
    classification: "UNKNOWN_REQUEST_BLOCKED",
    method: "GET",
    host: "org123.crm4.dynamics.com",
    path: "/v1.0/users/%7B157619ab-fdff-45f9-ab70-709f292dcfc5%7D/photos/120x120/$value",
    resourceType: "xhr",
    navigation: false
  });
  assert.equal(blocked.host, "dataverse-organization");
  assert.equal(blocked.path,
    "/v1.0/users/%7B[REDACTED]%7D/photos/120x120/$value");
  assert.equal(JSON.stringify(blocked).includes("157619ab"), false);
});

test("First failure remains primary when a later cleanup error occurs", () => {
  const state = {};
  const report = {
    requestCategoryCounts: { UNKNOWN_REQUEST_BLOCKED: 1 },
    firstRelevantBlockedRequest: { classification: "UNKNOWN_REQUEST_BLOCKED", method: "POST" }
  };
  const assertion = new Error("UAT_UNKNOWN_REQUEST_BLOCKED");
  const cleanup = new Error("UAT_CONTEXT_CLOSE_FAILED");
  assert.equal(captureFailure(state, assertion, "console-initialization", report), assertion);
  assert.equal(captureFailure(state, cleanup, "runner-cleanup", report), assertion);
  assert.equal(state.primaryError, assertion);
  assert.equal(report.failure, "UAT_UNKNOWN_REQUEST_BLOCKED");
  assert.equal(report.failureEvidence.phase, "console-initialization");
  assert.deepEqual(report.cleanupFailures, [{
    code: "UAT_CONTEXT_CLOSE_FAILED",
    phase: "runner-cleanup",
    location: null
  }]);
});

test("Final blocked-request and category evidence includes requests observed during cleanup", () => {
  const report = {
    requestCategoryCounts: { READ_REQUEST_ALLOWED: 1 },
    firstRelevantBlockedRequest: null,
    failureEvidence: failureEvidence(new Error("UAT_ASSERTION"), "console-entry", null,
      { READ_REQUEST_ALLOWED: 1 })
  };
  report.requestCategoryCounts.UNKNOWN_REQUEST_BLOCKED = 1;
  report.firstRelevantBlockedRequest = {
    classification: "UNKNOWN_REQUEST_BLOCKED", method: "GET",
    host: "org123.crm4.dynamics.com", path: "/AppWebServices/MetadataService.asmx/GetResourceStrings"
  };
  refreshFailureEvidence(report);
  assert.deepEqual(report.failureEvidence.requestCategoryCounts, {
    READ_REQUEST_ALLOWED: 1, UNKNOWN_REQUEST_BLOCKED: 1
  });
  assert.equal(report.failureEvidence.firstRelevantBlockedRequest.host, "dataverse-organization");
});

test("A cleanup error is surfaced when it is the first runner failure", () => {
  const state = {};
  const report = { requestCategoryCounts: {}, firstRelevantBlockedRequest: null };
  const cleanup = new Error("close failed");
  assert.equal(captureFailure(state, cleanup, "browser-context-close", report), cleanup);
  assert.equal(report.failure, "UAT_RUNNER_CLEANUP_FAILED");
  assert.equal(report.failureEvidence.assertion, "UAT_RUNNER_CLEANUP_FAILED");
});
