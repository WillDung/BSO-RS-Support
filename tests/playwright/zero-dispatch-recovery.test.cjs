const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createHash } = require("node:crypto");
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { spawn } = require("node:child_process");
const {
  releaseStaleClaim, consumeReleasedClaim, establishConsumedRecovery, consumeEligibleRecovery
} = require("./zero-dispatch-recovery.cjs");

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

function consumedFixture(t) {
  const f = fixture(t);
  f.release();
  const journal = consumeReleasedClaim(f.file, f.record.authorizationId);
  journal.save();
  const reportPath = path.join(path.dirname(f.file), "consumed-report.json");
  fs.writeFileSync(reportPath, JSON.stringify({
    lifecycle: "FAIL", dispatchedOperations: [], baselineCounts: null, counts: null,
    failure: "UAT_UNEXPECTED_BUSINESS_OR_PROVIDER_REQUEST"
  }));
  const scopePath = path.join(path.dirname(f.file), "scope.json");
  fs.writeFileSync(scopePath, JSON.stringify({
    authorizationId: f.record.authorizationId, ownerMutationApproval: true,
    maximumCandidates: 1, noRetries: true,
    actions: ["CreateCandidate", "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled"]
  }));
  const paths = [f.file, `${f.file}.login-recovery-claim`, `${f.file}.release.json`,
    `${f.file}.continuation.jsonl`, reportPath, scopePath];
  const hashes = paths.map(digest);
  return { ...f, journal, reportPath, scopePath, paths, hashes,
    establish: (probe = () => []) =>
      establishConsumedRecovery(f.file, hashes, reportPath, scopePath, probe) };
}

test("Consumed pre-dispatch attempt gains one eligible continuation without changing any prior evidence", t => {
  const f = consumedFixture(t);
  f.establish();
  const event = JSON.parse(fs.readFileSync(`${f.file}.recovery-eligible.json`, "utf8"));
  assert.equal(event.transition, "RECOVERY_ELIGIBLE");
  assert.deepEqual(f.paths.map(digest), f.hashes);
  const journal = consumeEligibleRecovery(f.file, f.record.authorizationId, f.scopePath);
  assert.equal(journal.record.marker, f.record.marker);
  assert.deepEqual(journal.record.attempts, []);
  assert.deepEqual(journal.record.loginRecovery, f.record.loginRecovery);
  assert.equal(journal.record.recoveryContinuation.transition, "RELEASE_CONSUMED_ONCE");
  journal.record.attempts.push({ correlation: "original-logical-correlation", outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN" });
  journal.save();
  const lines = fs.readFileSync(`${f.file}.eligible-continuation.jsonl`, "utf8").trim().split("\n").map(JSON.parse);
  assert.deepEqual(lines[0].attempts, []);
  assert.equal(lines[1].attempts[0].correlation, "original-logical-correlation");
  assert.deepEqual(f.paths.map(digest), f.hashes);
  assert.throws(() => f.establish());
  assert.throws(() => consumeEligibleRecovery(f.file, f.record.authorizationId, f.scopePath));
});

for (const outcome of ["APPLIED", "DISPATCH_RESERVED_OUTCOME_UNKNOWN"]) {
  test(`Consumed recovery rejects a historical ${outcome} dispatch even if last snapshot omits it`, t => {
    const f = consumedFixture(t);
    const lines = fs.readFileSync(`${f.file}.continuation.jsonl`, "utf8").trim().split("\n").map(JSON.parse);
    lines[0].attempts.push({ correlation: "preserve-do-not-replay", outcome });
    fs.writeFileSync(`${f.file}.continuation.jsonl`, lines.map(JSON.stringify).join("\n") + "\n");
    const hashes = f.paths.map(digest);
    assert.throws(() => establishConsumedRecovery(f.file, hashes, f.reportPath, f.scopePath, () => []));
    assert.equal(fs.existsSync(`${f.file}.recovery-eligible.json`), false);
  });
}

test("Consumed recovery refuses changed marker, acknowledgment, incomplete log and altered scope", t => {
  for (const change of [
    snapshot => { snapshot.marker = "22222222-2222-4222-8222-222222222222"; },
    snapshot => { snapshot.candidateId = "candidate-acknowledgment"; },
    snapshot => { snapshot.serverAcknowledgment = "unexpected"; },
    snapshot => { snapshot.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN"; }
  ]) {
    const f = consumedFixture(t);
    const snapshot = JSON.parse(fs.readFileSync(`${f.file}.continuation.jsonl`, "utf8").split("\n")[0]);
    change(snapshot);
    fs.appendFileSync(`${f.file}.continuation.jsonl`, `${JSON.stringify(snapshot)}\n`);
    assert.throws(() => establishConsumedRecovery(f.file, f.paths.map(digest), f.reportPath, f.scopePath, () => []));
  }
  const f = consumedFixture(t);
  fs.appendFileSync(`${f.file}.continuation.jsonl`, '{"incomplete":');
  assert.throws(() => establishConsumedRecovery(f.file, f.paths.map(digest), f.reportPath, f.scopePath, () => []));
  const other = consumedFixture(t);
  fs.writeFileSync(other.scopePath, JSON.stringify({ authorizationId: other.record.authorizationId }));
  assert.throws(() => establishConsumedRecovery(other.file, other.paths.map(digest),
    other.reportPath, other.scopePath, () => []));
});

test("Consumed recovery refuses active owner, evidence mutation and repeat attempts", t => {
  const f = consumedFixture(t);
  assert.throws(() => f.establish(() => [41312]));
  f.establish();
  assert.throws(() => f.establish());
  fs.appendFileSync(`${f.file}.continuation.jsonl`, " ");
  assert.throws(() => consumeEligibleRecovery(f.file, f.record.authorizationId, f.scopePath));
  assert.equal(fs.existsSync(`${f.file}.eligible-continuation.jsonl`), false);
});

function child(code) {
  return new Promise((resolve, reject) => {
    const process = spawn(global.process.execPath, ["-e", code], { stdio: "ignore" });
    process.once("error", reject);
    process.once("exit", resolve);
  });
}
test("Concurrent eligibility and consumption each have exactly one exclusive winner", async t => {
  const f = consumedFixture(t);
  const modulePath = JSON.stringify(require.resolve("./zero-dispatch-recovery.cjs"));
  const establish = `const {establishConsumedRecovery}=require(${modulePath}); try {
    establishConsumedRecovery(${JSON.stringify(f.file)},${JSON.stringify(f.hashes)},
    ${JSON.stringify(f.reportPath)},${JSON.stringify(f.scopePath)},()=>[]); } catch { process.exit(1); }`;
  assert.deepEqual((await Promise.all([child(establish), child(establish)])).sort(), [0, 1]);
  const consume = `const {consumeEligibleRecovery}=require(${modulePath}); try {
    consumeEligibleRecovery(${JSON.stringify(f.file)},${JSON.stringify(f.record.authorizationId)},
    ${JSON.stringify(f.scopePath)}); } catch { process.exit(1); }`;
  assert.deepEqual((await Promise.all([child(consume), child(consume)])).sort(), [0, 1]);
  assert.deepEqual(f.paths.map(digest), f.hashes);
});
