const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { releaseStaleClaim, consumeReleasedClaim } = require("./zero-dispatch-recovery.cjs");

const digest = file => createHash("sha256").update(fs.readFileSync(file)).digest("hex");
function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "bso-recovery-test-"));
  t.after(() => fs.rmSync(directory, { recursive: true }));
  const file = path.join(directory, "journal.json");
  const marker = "11111111-1111-4111-8111-111111111111";
  const record = {
    authorizationId: "synthetic-approval", marker,
    candidateName: `[SYNTHETIC-E2E] Playwright ${marker}`,
    candidateEmail: `pw-${marker}@example.invalid`, candidateId: null, attempts: [],
    status: "STOPPED_NO_RETRY_RECONCILE_ONLY", loginRecovery: { dispatchesAtResume: 0 }
  };
  fs.writeFileSync(file, JSON.stringify(record));
  fs.writeFileSync(`${file}.login-recovery-claim`, "synthetic-claim");
  const reports = [0, 1].map(index => {
    const report = path.join(directory, `report-${index}.json`);
    fs.writeFileSync(report, JSON.stringify({
      lifecycle: "FAIL", dispatchedOperations: [], baselineCounts: null, counts: null
    }));
    return report;
  });
  const journalHash = digest(file);
  const claimHash = digest(`${file}.login-recovery-claim`);
  return { file, record, reports, journalHash, claimHash,
    release: (processes = () => []) =>
      releaseStaleClaim(file, journalHash, claimHash, processes, reports) };
}
test("Release and consume once, preserving original bytes and append-only dispatch history", t => {
  const f = fixture(t);
  f.release();
  assert.throws(() => f.release());
  const journal = consumeReleasedClaim(f.file, f.record.authorizationId);
  assert.equal(journal.record.marker, f.record.marker);
  journal.record.attempts.push({ correlation: "synthetic", outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN" });
  journal.save();
  const snapshots = fs.readFileSync(`${f.file}.continuation.jsonl`, "utf8").trim().split("\n").map(JSON.parse);
  assert.equal(snapshots.length, 2);
  assert.equal(snapshots[0].attempts.length, 0);
  assert.equal(snapshots[1].attempts.length, 1);
  assert.equal(digest(f.file), f.journalHash);
  assert.equal(digest(`${f.file}.login-recovery-claim`), f.claimHash);
  assert.throws(() => consumeReleasedClaim(f.file, f.record.authorizationId));
});
test("Release refuses active lifecycle processes", t => {
  const f = fixture(t);
  assert.throws(() => f.release(() => [123]));
  assert.equal(fs.existsSync(`${f.file}.release.json`), false);
});
for (const change of [
  record => record.attempts.push({ outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN" }),
  record => { record.candidateId = "synthetic-id"; },
  record => { record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN"; },
  record => { record.marker = "22222222-2222-4222-8222-222222222222"; }
]) {
  test("Changed dispatch/identity/uncertainty state cannot be released", t => {
    const f = fixture(t);
    change(f.record);
    fs.writeFileSync(f.file, JSON.stringify(f.record));
    assert.throws(() => f.release());
  });
}
test("Release refuses report evidence of dispatch and consumption refuses tampering", t => {
  const f = fixture(t);
  fs.writeFileSync(f.reports[0], JSON.stringify({
    lifecycle: "FAIL", dispatchedOperations: ["CreateCandidate"], baselineCounts: null, counts: null
  }));
  assert.throws(() => f.release());
  fs.writeFileSync(f.reports[0], JSON.stringify({
    lifecycle: "FAIL", dispatchedOperations: [], baselineCounts: null, counts: null
  }));
  f.release();
  fs.appendFileSync(f.reports[0], " ");
  assert.throws(() => consumeReleasedClaim(f.file, f.record.authorizationId));
});
test("Missing release, wrong authorization and changed claim all fail closed", t => {
  const f = fixture(t);
  assert.throws(() => consumeReleasedClaim(f.file, f.record.authorizationId));
  f.release();
  assert.throws(() => consumeReleasedClaim(f.file, "other-approval"));
  fs.appendFileSync(`${f.file}.login-recovery-claim`, "changed");
  assert.throws(() => consumeReleasedClaim(f.file, f.record.authorizationId));
});
