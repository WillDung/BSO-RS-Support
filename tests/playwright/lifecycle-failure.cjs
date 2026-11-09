const failureCode = (error, fallback = "UAT_LIFECYCLE_ASSERTION_FAILED") => {
  const message = typeof error?.message === "string" ? error.message : "";
  return message.match(/\bUAT_[A-Z_]+\b/)?.[0] || fallback;
};

function safeExpectedActual(error) {
  const result = error?.matcherResult;
  if (!result || typeof result !== "object") return null;
  const sanitize = value => {
    if (typeof value === "boolean" || (typeof value === "number" && Number.isFinite(value))) return value;
    if (typeof value === "string") {
      return [
        "Candidate Management", "Need Call Candidate", "Candidate Answered",
        "Waiting Manual Scheduling", "Round 1 Scheduled"
      ].includes(value) ? value : "[REDACTED_STRING]";
    }
    if (Array.isArray(value)) return value.slice(0, 10).map(sanitize);
    return undefined;
  };
  const expected = sanitize(result.expected);
  const actual = sanitize(result.actual);
  return expected === undefined || actual === undefined ? null : { expected, actual };
}

function safeLocation(error) {
  const stack = typeof error?.stack === "string" ? error.stack : "";
  const match = stack.match(/candidate-lifecycle\.spec\.cjs:(\d+):(\d+)/);
  return match ? {
    file: "candidate-lifecycle.spec.cjs",
    line: Number(match[1]),
    column: Number(match[2])
  } : null;
}

function sanitizeBlockedRequest(request) {
  if (!request) return null;
  const rawHost = typeof request.host === "string" ? request.host : "";
  const host = /^[a-z0-9-]+\.crm\d*\.dynamics\.com$/i.test(rawHost)
    ? "dataverse-organization"
    : rawHost.replace(/\b[0-9a-f]{8}-[0-9a-f-]{27,}\b/gi, "[REDACTED]")
      .replace(/\b[0-9a-f]{24,}\b/gi, "[REDACTED]").slice(0, 255);
  const rawPath = typeof request.path === "string" ? request.path.split(/[?#]/, 1)[0] : "";
  const path = rawPath
    .replace(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, "[REDACTED]")
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, "[REDACTED]")
    .slice(0, 512);
  return {
    classification: request.classification,
    method: request.method,
    host,
    path,
    resourceType: request.resourceType,
    navigation: request.navigation
  };
}

function failureEvidence(error, phase, firstBlockedRequest, requestCategoryCounts, fallback) {
  const code = failureCode(error, fallback);
  const matcherName = error?.matcherResult?.name;
  const assertion = typeof matcherName === "string" && /^[A-Za-z][A-Za-z0-9]*$/.test(matcherName)
    ? matcherName : code;
  const blocked = sanitizeBlockedRequest(firstBlockedRequest);
  return {
    assertion,
    phase,
    code,
    expectedActual: safeExpectedActual(error),
    location: safeLocation(error),
    firstRelevantBlockedRequest: blocked || null,
    requestCategoryCounts: { ...requestCategoryCounts }
  };
}

function captureFailure(state, error, phase, report) {
  if (!state.primaryError) {
    state.primaryError = error instanceof Error ? error : new Error("UAT_LIFECYCLE_ASSERTION_FAILED");
    const fallback = /cleanup|close|report-write|journal-stop-save/.test(phase)
      ? "UAT_RUNNER_CLEANUP_FAILED" : "UAT_LIFECYCLE_ASSERTION_FAILED";
    report.failure = failureCode(state.primaryError, fallback);
    report.failureEvidence = failureEvidence(state.primaryError, phase,
      report.firstRelevantBlockedRequest, report.requestCategoryCounts, fallback);
  } else {
    report.cleanupFailures ??= [];
    report.cleanupFailures.push({
      code: failureCode(error, "UAT_RUNNER_CLEANUP_FAILED"),
      phase,
      location: safeLocation(error)
    });
  }
  return state.primaryError;
}

function refreshFailureEvidence(report) {
  if (!report.failureEvidence) return;
  report.failureEvidence.firstRelevantBlockedRequest =
    sanitizeBlockedRequest(report.firstRelevantBlockedRequest);
  report.failureEvidence.requestCategoryCounts = { ...report.requestCategoryCounts };
}

module.exports = {
  captureFailure, failureCode, failureEvidence, refreshFailureEvidence, sanitizeBlockedRequest
};
