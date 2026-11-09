const fs = require("node:fs");
const { createHash } = require("node:crypto");

const digest = file => createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const requireSafe = condition => {
  if (!condition) throw new Error("UAT_ZERO_DISPATCH_RECOVERY_REFUSED");
};
function readStopped(file) {
  const record = JSON.parse(fs.readFileSync(file, "utf8"));
  requireSafe(record.status === "STOPPED_NO_RETRY_RECONCILE_ONLY" &&
    record.candidateId === null && Array.isArray(record.attempts) && record.attempts.length === 0 &&
    /^[a-f0-9-]{36}$/.test(record.marker) &&
    record.candidateName === `[SYNTHETIC-E2E] Playwright ${record.marker}` &&
    record.candidateEmail === `pw-${record.marker}@example.invalid` &&
    record.loginRecovery?.dispatchesAtResume === 0);
  return record;
}
function durableWrite(file, value, flag) {
  const fd = fs.openSync(file, flag, 0o600);
  try {
    fs.writeFileSync(fd, `${JSON.stringify(value)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}
function releaseStaleClaim(file, expectedJournalHash, expectedClaimHash, inspectProcesses, evidenceFiles) {
  requireSafe(inspectProcesses().length === 0 && evidenceFiles.length === 2);
  requireSafe(digest(file) === expectedJournalHash &&
    digest(`${file}.login-recovery-claim`) === expectedClaimHash);
  const record = readStopped(file);
  const evidence = evidenceFiles.map(reportPath => {
    const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
    requireSafe(report.lifecycle === "FAIL" && report.dispatchedOperations?.length === 0 &&
      report.baselineCounts === null && report.counts === null);
    return { reportPath, sha256: digest(reportPath) };
  });
  requireSafe(inspectProcesses().length === 0);
  durableWrite(`${file}.release.json`, {
    transition: "STALE_LOGIN_CLAIM_RELEASED_ZERO_DISPATCH",
    at: new Date().toISOString(), authorizationId: record.authorizationId,
    marker: record.marker, journalHash: expectedJournalHash, claimHash: expectedClaimHash,
    dispatches: 0, candidateId: null, activeLifecycleProcesses: 0, evidence
  }, "wx");
}
function consumeReleasedClaim(file, authorizationId) {
  const release = JSON.parse(fs.readFileSync(`${file}.release.json`, "utf8"));
  const record = readStopped(file);
  requireSafe(release.transition === "STALE_LOGIN_CLAIM_RELEASED_ZERO_DISPATCH" &&
    release.authorizationId === authorizationId && record.authorizationId === authorizationId &&
    release.marker === record.marker && release.dispatches === 0 && release.candidateId === null &&
    release.activeLifecycleProcesses === 0 && digest(file) === release.journalHash &&
    digest(`${file}.login-recovery-claim`) === release.claimHash &&
    release.evidence.length === 2 &&
    release.evidence.every(item => digest(item.reportPath) === item.sha256));
  const eventsFile = `${file}.continuation.jsonl`;
  record.recoveryContinuation = {
    transition: "RELEASE_CONSUMED_ONCE", at: new Date().toISOString(),
    pid: process.pid, releaseHash: digest(`${file}.release.json`)
  };
  durableWrite(eventsFile, record, "wx");
  return { record, save: () => durableWrite(eventsFile, record, "a") };
}

function readConsumedPreDispatch(file) {
  const original = readStopped(file);
  requireSafe(JSON.stringify(Object.keys(original).sort()) === JSON.stringify([
    "authorizationId", "attempts", "candidateEmail", "candidateId", "candidateName",
    "loginRecovery", "marker", "status"
  ].sort()));
  const content = fs.readFileSync(`${file}.continuation.jsonl`, "utf8");
  requireSafe(content.endsWith("\n"));
  const snapshots = content.slice(0, -1).split("\n").map(line => JSON.parse(line));
  requireSafe(snapshots.length >= 2);
  for (const snapshot of snapshots) {
    const { recoveryContinuation, ...businessRecord } = snapshot;
    requireSafe(JSON.stringify(businessRecord) === JSON.stringify(original) &&
      recoveryContinuation?.transition === "RELEASE_CONSUMED_ONCE" &&
      recoveryContinuation.releaseHash === digest(`${file}.release.json`) &&
      Number.isInteger(recoveryContinuation.pid) &&
      JSON.stringify(recoveryContinuation) === JSON.stringify(snapshots[0].recoveryContinuation));
  }
  const release = JSON.parse(fs.readFileSync(`${file}.release.json`, "utf8"));
  requireSafe(release.transition === "STALE_LOGIN_CLAIM_RELEASED_ZERO_DISPATCH" &&
    release.authorizationId === original.authorizationId && release.marker === original.marker &&
    release.journalHash === digest(file) &&
    release.claimHash === digest(`${file}.login-recovery-claim`) &&
    release.dispatches === 0 && release.candidateId === null &&
    release.evidence.length === 2 &&
    release.evidence.every(item => digest(item.reportPath) === item.sha256));
  return snapshots.at(-1);
}

function evidenceHashes(file, reportPath, scopePath) {
  return [file, `${file}.login-recovery-claim`, `${file}.release.json`,
    `${file}.continuation.jsonl`, reportPath, scopePath].map(evidencePath => ({
    path: evidencePath, sha256: digest(evidencePath)
  }));
}

function establishConsumedRecovery(file, expectedHashes, reportPath, scopePath, inspectProcesses) {
  requireSafe(inspectProcesses().length === 0);
  const record = readConsumedPreDispatch(file);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  const scope = JSON.parse(fs.readFileSync(scopePath, "utf8"));
  requireSafe(report.lifecycle === "FAIL" && report.dispatchedOperations?.length === 0 &&
    report.baselineCounts === null && report.counts === null &&
    report.failure === "UAT_UNEXPECTED_BUSINESS_OR_PROVIDER_REQUEST" &&
    scope.authorizationId === record.authorizationId && scope.ownerMutationApproval === true &&
    scope.maximumCandidates === 1 && scope.noRetries === true &&
    JSON.stringify(scope.actions) === JSON.stringify([
      "CreateCandidate", "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled"
    ]));
  const evidence = evidenceHashes(file, reportPath, scopePath);
  requireSafe(expectedHashes.length === evidence.length && evidence.every((item, index) =>
    item.sha256 === expectedHashes[index]));
  requireSafe(!fs.existsSync(`${file}.eligible-continuation.jsonl`) && inspectProcesses().length === 0);
  durableWrite(`${file}.recovery-eligible.json`, {
    from: "ATTEMPT_CONSUMED_PRE_DISPATCH", transition: "RECOVERY_ELIGIBLE",
    at: new Date().toISOString(), authorizationId: record.authorizationId,
    marker: record.marker, dispatches: 0, candidateId: null,
    activeLifecycleProcesses: 0, evidence
  }, "wx");
}

function consumeEligibleRecovery(file, authorizationId, scopePath) {
  const eventFile = `${file}.recovery-eligible.json`;
  const event = JSON.parse(fs.readFileSync(eventFile, "utf8"));
  requireSafe(event.from === "ATTEMPT_CONSUMED_PRE_DISPATCH" &&
    event.transition === "RECOVERY_ELIGIBLE" && event.authorizationId === authorizationId &&
    event.dispatches === 0 && event.candidateId === null && event.activeLifecycleProcesses === 0);
  const evidence = evidenceHashes(file, event.evidence[4].path, scopePath);
  requireSafe(JSON.stringify(evidence) === JSON.stringify(event.evidence));
  const record = readConsumedPreDispatch(file);
  requireSafe(record.authorizationId === authorizationId && record.marker === event.marker);
  record.recoveryEligibility = {
    transition: "RECOVERY_ELIGIBILITY_CONSUMED_ONCE", at: new Date().toISOString(),
    pid: process.pid, eligibilityHash: digest(eventFile)
  };
  const eventsFile = `${file}.eligible-continuation.jsonl`;
  durableWrite(eventsFile, record, "wx");
  return { record, save: () => durableWrite(eventsFile, record, "a") };
}

module.exports = {
  releaseStaleClaim, consumeReleasedClaim, establishConsumedRecovery, consumeEligibleRecovery
};
