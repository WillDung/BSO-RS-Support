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

module.exports = { releaseStaleClaim, consumeReleasedClaim };
