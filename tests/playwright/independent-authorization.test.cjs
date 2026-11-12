const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { spawn, spawnSync } = require("node:child_process");
const {
  createAuthorization, loadIndependentAuthorization, claimIndependentAuthorization, digest,
  validateSyntheticIsolationProof, validateOperationCorrelation, createSingleUserDevSuccessor
} = require("./independent-authorization.cjs");
const {
  ACTIONS, STATUSES, REFERENCE_LABELS, reserveOneShot, isSingleUserDevDirectReadBlocked
} = require("./lifecycle-support.cjs");
const {
  createContinuationAuthorization, loadContinuationAuthorization,
  claimContinuationOperation, reserveContinuationDispatch,
  completeContinuationOperation, readOperation, validateReadback
} = require("./continuation-authorization.cjs");

const now = Date.parse("2030-01-02T10:00:00Z");
const configuration = { workers: 1, retries: 0, repeatEach: 1, retry: 0, repeatEachIndex: 0 };
const write = (file, value) => fs.writeFileSync(file, JSON.stringify(value));
const events = file => fs.readFileSync(file, "utf8").trim().split("\n").map(JSON.parse);

function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "bso-independent-test-"));
  t.after(() => fs.rmSync(directory, { recursive: true }));
  const journalPath = path.join(directory, "historical.json");
  const scopePath = path.join(directory, "historical-scope.json");
  const reportPath = path.join(directory, "report.json");
  const marker = "11111111-1111-4111-8111-111111111111";
  const base = {
    appUrl: "https://orgsynthetic.crm4.dynamics.com/main.aspx?appid=22222222-2222-4222-8222-222222222222",
    organizationId: "33333333-3333-4333-8333-333333333333",
    environmentId: "44444444-4444-4444-8444-444444444444", expectedUpn: "owner@example.invalid"
  };
  const syntheticIsolation = {
    actorId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    scopeId: marker,
    positionId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    sourceId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    taId: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
    locationId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
  };
  const original = {
    authorizationId: "historical", marker,
    candidateName: `[SYNTHETIC-E2E] Playwright ${marker}`,
    candidateEmail: `pw-${marker}@example.invalid`, candidateId: null,
    attempts: [], status: "STOPPED_NO_RETRY_RECONCILE_ONLY",
    loginRecovery: { dispatchesAtResume: 0 }
  };
  write(journalPath, original);
  fs.writeFileSync(`${journalPath}.login-recovery-claim`, "consumed");
  write(reportPath, { lifecycle: "FAIL", dispatchedOperations: [], baselineCounts: null, counts: null });
  const scope = {
    ...base, authorizationId: "historical", ownerMutationApproval: true,
    identityScope: "OWNER_APPROVED_ELEVATED_FUNCTIONAL_LIFECYCLE",
    authenticationCallbackOrigin: "https://synthetic.crm4.dynamics.com",
    maximumCandidates: 1, noRetries: true, expiresAt: "2020-01-01T00:00:00Z",
    actions: ACTIONS, referenceLabels: REFERENCE_LABELS
  };
  write(scopePath, scope);
  write(`${journalPath}.release.json`, {
    transition: "STALE_LOGIN_CLAIM_RELEASED_ZERO_DISPATCH",
    authorizationId: original.authorizationId, marker, dispatches: 0, candidateId: null,
    journalHash: digest(journalPath), claimHash: digest(`${journalPath}.login-recovery-claim`),
    evidence: [0, 1].map(() => ({ reportPath, sha256: digest(reportPath) }))
  });
  const prior = {
    ...original, recoveryContinuation: {
      transition: "RELEASE_CONSUMED_ONCE", pid: 2147483647,
      releaseHash: digest(`${journalPath}.release.json`)
    }
  };
  fs.writeFileSync(`${journalPath}.continuation.jsonl`, `${JSON.stringify(prior)}\n`.repeat(2));
  const paths = [journalPath, `${journalPath}.login-recovery-claim`, `${journalPath}.release.json`,
    `${journalPath}.continuation.jsonl`, reportPath, scopePath];
  write(`${journalPath}.recovery-eligible.json`, {
    transition: "RECOVERY_ELIGIBLE", authorizationId: original.authorizationId, marker,
    dispatches: 0, candidateId: null, activeLifecycleProcesses: 0,
    evidence: paths.map(file => ({ path: file, sha256: digest(file) }))
  });
  const consumed = {
    ...prior, recoveryEligibility: {
      transition: "RECOVERY_ELIGIBILITY_CONSUMED_ONCE", pid: 2147483647,
      eligibilityHash: digest(`${journalPath}.recovery-eligible.json`)
    }
  };
  fs.writeFileSync(`${journalPath}.eligible-continuation.jsonl`, `${JSON.stringify(consumed)}\n`.repeat(2));
  const allPaths = [...new Set([journalPath, `${journalPath}.login-recovery-claim`,
    `${journalPath}.release.json`, `${journalPath}.continuation.jsonl`,
    `${journalPath}.recovery-eligible.json`, `${journalPath}.eligible-continuation.jsonl`,
    scopePath, reportPath])];
  const evidence = allPaths.map(file => ({ path: file, sha256: digest(file) }));
  const request = {
    authorizedAt: "2030-01-02T09:00:00Z",
    ownerDecisionText: "Synthetic fixture: authorize one independent four-operation attempt, no retries.",
    history: { journalPath, scopePath, reportPath, evidence },
    scope: {
      ...scope, authorizationId: "independent-01", environmentName: "VN LMV IT internal DEV",
      identityScope: "BSO_ONLY", expectedUpn: "bso@example.invalid",
      actorId: syntheticIsolation.actorId, syntheticIsolation,
      maximumInvocations: 1, retries: 0, callOutcome: "Answered",
      readbackOnlyAfterOperations: true, expiresAt: "2030-01-02T10:30:00Z"
    }
  };
  const file = path.join(directory, "independent-01.authorization.json");
  let proofSequence = 0;
  const makeProof = (at = now) => ({
    correlationId: `12121212-1212-4121-8121-${String(++proofSequence).padStart(12, "0")}`,
    contract: JSON.stringify({
      version: 2, boundary: "ScopedCandidateCoreApi", nativeWritesDenied: true,
      readback: "CallerOwnedScope", organizationId: base.organizationId,
      environmentId: base.environmentId, actorId: syntheticIsolation.actorId,
      scopeId: marker, candidateId: marker, positionId: syntheticIsolation.positionId,
      sourceId: syntheticIsolation.sourceId, taId: syntheticIsolation.taId,
      locationId: syntheticIsolation.locationId,
      validUntil: new Date(at + 120_000).toISOString(), calendarEnabled: false
    })
  });
  return {
    file, request, base, original, evidence,
    create: () => createAuthorization(file, request, base, now),
    makeProof,
    claim: (config = configuration, at = now) =>
      claimIndependentAuthorization(file, base, config, makeProof(at), at)
  };
}

function singleUserDevFixture(t) {
  const f = fixture(t);
  const marker = f.original.marker;
  const binding = {
    actorId: f.request.scope.actorId,
    candidateId: marker,
    locationId: f.request.scope.syntheticIsolation.locationId,
    positionId: f.request.scope.syntheticIsolation.positionId,
    scopeId: "22222222-2222-4222-8222-222222222222",
    sourceId: f.request.scope.syntheticIsolation.sourceId,
    taId: f.request.scope.syntheticIsolation.taId
  };
  f.base.expectedActorId = binding.actorId;
  f.request.ownerDecisionText = "Synthetic fixture: authorize one SingleUserDev lifecycle invocation.";
  f.request.marker = marker;
  f.request.candidateName = `[SYNTHETIC-E2E] Playwright ${marker}`;
  f.request.candidateEmail = `pw-${marker}@example.invalid`;
  f.request.scope = {
    ...f.request.scope,
    authorizationId: "singleuserdev-01",
    identityScope: "SINGLE_USER_DEV",
    expectedUpn: f.base.expectedUpn,
    actorId: binding.actorId,
    syntheticIsolation: binding,
    authenticationCallbackOrigin: new URL(f.base.appUrl).origin,
    excludedCorrelations: ["fe902569-29b8-4af0-89c8-508190769e94"]
  };
  const contract = (overrides = {}, at = now) => JSON.stringify({
    version: 4, boundary: "SingleUserDevCandidateCoreApi", mode: "SingleUserDev",
    nativeWritesDenied: false, scopedReads: true, globalGuardsRequired: false,
    readback: "CallerOwnedScope", organizationId: f.base.organizationId,
    environmentId: f.base.environmentId, actorId: binding.actorId, scopeId: binding.scopeId,
    candidateId: binding.scopeId, positionId: binding.positionId, sourceId: binding.sourceId,
    taId: binding.taId, locationId: binding.locationId,
    validUntil: new Date(at + 120_000).toISOString(), calendarEnabled: false, ...overrides
  });
  let proofSequence = 0;
  f.makeProof = (at = now, overrides = {}) => ({
    correlationId: `13131313-1313-4131-8131-${String(++proofSequence).padStart(12, "0")}`,
    contract: contract(overrides, at)
  });
  f.proofContract = contract;
  f.file = path.join(path.dirname(f.file), "singleuserdev-01.authorization.json");
  f.create = () => createAuthorization(f.file, f.request, f.base, now);
  f.claim = (config = configuration, at = now) =>
    claimIndependentAuthorization(f.file, f.base, config, f.makeProof(at), at);
  return f;
}

function singleUserDevReconciliation(f, at = Date.parse("2030-01-02T11:00:00Z")) {
  const observation = f.makeProof(at);
  const proof = JSON.parse(observation.contract);
  const binding = f.request.scope.syntheticIsolation;
  return {
    version: 1, checkedAt: new Date(at).toISOString(), marker: f.original.marker,
    whoAmI: { actorId: binding.actorId, organizationId: f.base.organizationId },
    proof: { correlationId: observation.correlationId, ...proof },
    readCounts: { candidates: 0, calls: 0, history: 0, schedules: 0 },
    references: {
      position: { id: binding.positionId, label: REFERENCE_LABELS.position, statecode: 0, rowCount: 1 },
      source: { id: binding.sourceId, label: REFERENCE_LABELS.source, statecode: 0, rowCount: 1 },
      ta: { id: binding.taId, label: REFERENCE_LABELS.ta, statecode: 0, rowCount: 1 },
      location: { id: binding.locationId, label: REFERENCE_LABELS.location, statecode: 0, rowCount: 1 }
    },
    receiptReadback: "NOT_EXPOSED_FOR_SINGLE_USER_DEV",
    attemptJournal: { state: "UNCLAIMED", dispatchCount: 0, journalHash: null }
  };
}

function singleUserDevSuccessorRequest(f, reconciliation, at = Date.parse("2030-01-02T11:00:00Z")) {
  const scope = JSON.parse(JSON.stringify(f.request.scope));
  scope.authorizationId = "singleuserdev-02";
  scope.expiresAt = new Date(at + 60 * 60 * 1000).toISOString();
  scope.excludedCorrelations = [...new Set([
    ...scope.excludedCorrelations.map(value => value.toLowerCase()),
    reconciliation.proof.correlationId.toLowerCase()
  ])];
  return {
    authorizedAt: new Date(at).toISOString(),
    ownerDecisionText: "Synthetic fixture: issue one bounded successor after read-only zero-dispatch reconciliation.",
    marker: f.original.marker, candidateName: f.request.candidateName,
    candidateEmail: f.request.candidateEmail, scope
  };
}

function createFixtureSuccessor(f, at = Date.parse("2030-01-02T11:00:00Z")) {
  const prior = f.create();
  const reconciliation = singleUserDevReconciliation(f, at);
  const request = singleUserDevSuccessorRequest(f, reconciliation, at);
  const file = path.join(path.dirname(f.file), `${request.scope.authorizationId}.authorization.json`);
  const authorization = createSingleUserDevSuccessor(
    file, f.file, request, f.base, reconciliation, at);
  return { prior, authorization, file, request, reconciliation, at };
}

test("A v4 SingleUserDev proof and exact owner-bound authorization are accepted", t => {
  const f = singleUserDevFixture(t);
  const authorization = f.create();
  const proof = validateSyntheticIsolationProof(f.makeProof(), authorization, now);
  assert.equal(authorization.scope.identityScope, "SINGLE_USER_DEV");
  assert.equal(authorization.scope.syntheticIsolation.actorId, f.base.expectedActorId);
  assert.equal(authorization.scope.syntheticIsolation.candidateId, authorization.marker);
  assert.equal(authorization.scope.syntheticIsolation.scopeId,
    JSON.parse(proof.contract).candidateId);
  assert.equal(proof.correlationId.startsWith("13131313-"), true);
  assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
  f.claim();
  assert.throws(f.claim, error => error.code === "EEXIST");
});

for (const [label, change] of [
  ["wrong owner", f => { f.request.scope.expectedUpn = "other@example.invalid"; }],
  ["wrong marker", f => { f.request.marker = "99999999-9999-4999-8999-999999999999"; }],
  ["missing excluded old correlation", f => { f.request.scope.excludedCorrelations = []; }],
  ["unapproved callback origin", f => {
    f.request.scope.authenticationCallbackOrigin = "https://login.example.invalid";
  }]
]) {
  test(`SingleUserDev authorization rejects ${label}`, t => {
    const f = singleUserDevFixture(t);
    change(f);
    assert.throws(f.create, /UAT_SINGLE_USER_DEV_SCOPE_OR_TARGET_MISMATCH/);
    assert.equal(fs.existsSync(f.file), false);
  });
}

for (const [label, overrides] of [
  ["wrong proof version", { version: 2 }],
  ["wrong owner proof", { actorId: "99999999-9999-4999-8999-999999999999" }],
  ["wrong child scope proof", { candidateId: "99999999-9999-4999-8999-999999999999" }],
  ["wrong reference proof", { positionId: "99999999-9999-4999-8999-999999999999" }]
]) {
  test(`SingleUserDev proof rejects ${label}`, t => {
    const f = singleUserDevFixture(t);
    const authorization = f.create();
    assert.throws(() => validateSyntheticIsolationProof({
      ...f.makeProof(), contract: f.proofContract(overrides)
    }, authorization, now), /UAT_SINGLE_USER_DEV_PROOF_SCOPE_OR_FRESHNESS_MISMATCH/);
  });
}

test("Missing and expired SingleUserDev authorizations are rejected", t => {
  const f = singleUserDevFixture(t);
  assert.throws(() => loadIndependentAuthorization(f.file, f.base, now));
  f.request.scope.expiresAt = "2030-01-02T09:59:59Z";
  assert.throws(f.create, /UAT_INDEPENDENT_AUTHORIZATION_EXPIRED/);
  assert.equal(fs.existsSync(f.file), false);
});

test("Expired SingleUserDev authorization cannot be claimed or dispatched", t => {
  const f = singleUserDevFixture(t);
  f.create();
  const expiredAt = Date.parse(f.request.scope.expiresAt) + 1;
  assert.throws(() => f.claim(configuration, expiredAt),
    /UAT_INDEPENDENT_AUTHORIZATION_EXPIRED/);
  assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
});

test("Unresolved SingleUserDev dispatch blocks slot succession", t => {
  const f = singleUserDevFixture(t);
  f.create();
  const journal = f.claim();
  journal.record.attempts.push({
    action: "CreateCandidate", correlation: "55555555-5555-4555-8555-555555555555",
    outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
  });
  journal.record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
  journal.save();
  const at = Date.parse("2030-01-02T11:00:00Z");
  const reconciliation = singleUserDevReconciliation(f, at);
  const request = singleUserDevSuccessorRequest(f, reconciliation, at);
  const nextPath = path.join(path.dirname(f.file), `${request.scope.authorizationId}.authorization.json`);
  const linkPath = `${path.dirname(f.file)}\\singleuserdev-${f.original.marker}.authorization-slot.json.successor-authorization.json`;
  assert.throws(() => createSingleUserDevSuccessor(
    nextPath, f.file, request, f.base, reconciliation, at),
  /UAT_PRIOR_DISPATCH_OR_AMBIGUITY/);
  assert.equal(fs.existsSync(linkPath), false);
  assert.equal(fs.existsSync(nextPath), false);
});

test("A reconciled zero-dispatch SingleUserDev authorization is immutably superseded", t => {
  const f = singleUserDevFixture(t);
  const { prior, authorization, file, reconciliation, at } = createFixtureSuccessor(f);
  const priorHash = digest(f.file);
  const markerSlotPath = path.join(path.dirname(f.file),
    `singleuserdev-${f.original.marker}.authorization-slot.json`);
  const priorSlotHash = digest(markerSlotPath);
  assert.equal(authorization.version, 3);
  assert.equal(authorization.predecessor.attemptState, "UNCLAIMED");
  assert.equal(authorization.predecessor.dispatchCount, 0);
  assert.equal(authorization.reconciliation.receiptReadback,
    "NOT_EXPOSED_FOR_SINGLE_USER_DEV");
  assert.notEqual(authorization.scope.authorizationId, f.request.scope.authorizationId);
  assert.notEqual(authorization.attemptId, prior.attemptId);
  assert.equal(Date.parse(authorization.scope.expiresAt) - Date.parse(authorization.authorizedAt),
    60 * 60 * 1000);
  assert.equal(authorization.scope.syntheticIsolation.scopeId,
    f.request.scope.syntheticIsolation.scopeId);
  assert.equal(digest(f.file), priorHash);
  assert.equal(digest(markerSlotPath), priorSlotHash);
  assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
  assert.equal(fs.existsSync(`${file}.attempt.jsonl`), false);
  assert.throws(() => loadIndependentAuthorization(f.file, f.base, at - 60 * 60 * 1000),
    /UAT_SINGLE_USER_DEV_AUTHORIZATION_SUPERSEDED/);
  const proof = validateSyntheticIsolationProof(
    f.makeProof(at), authorization, at);
  const record = { syntheticProof: proof, attempts: [] };
  for (const correlation of [
    "fe902569-29b8-4af0-89c8-508190769e94",
    reconciliation.proof.correlationId
  ]) {
    assert.throws(() => validateOperationCorrelation(correlation, record, authorization),
      /UAT_OPERATION_CORRELATION_REPLAY_REJECTED/);
  }
  assert.equal(authorization.marker, f.original.marker);
});

test("A terminal zero-dispatch attempt can be superseded and its proof nonce stays excluded", t => {
  const f = singleUserDevFixture(t);
  f.create();
  const claimSource = `
    const {claimIndependentAuthorization}=require(${JSON.stringify(require.resolve("./independent-authorization.cjs"))});
    const journal=claimIndependentAuthorization(${JSON.stringify(f.file)},${JSON.stringify(f.base)},
      ${JSON.stringify(configuration)},${JSON.stringify(f.makeProof())},${now});
    journal.record.status="STOPPED_NO_RETRY_RECONCILE_ONLY"; journal.save();`;
  assert.equal(spawnSync(process.execPath, ["-e", claimSource], { encoding: "utf8" }).status, 0);
  const oldJournal = events(`${f.file}.attempt.jsonl`);
  const attemptJournal = {
    state: "STOPPED_ZERO_DISPATCH", dispatchCount: 0,
    journalHash: digest(`${f.file}.attempt.jsonl`)
  };
  const at = Date.parse("2030-01-02T11:00:00Z");
  const reconciliation = singleUserDevReconciliation(f, at);
  reconciliation.attemptJournal = attemptJournal;
  const request = singleUserDevSuccessorRequest(f, reconciliation, at);
  request.scope.excludedCorrelations.push(oldJournal[0].record.syntheticProof.correlationId);
  const nextPath = path.join(path.dirname(f.file),
    `${request.scope.authorizationId}.authorization.json`);
  const next = createSingleUserDevSuccessor(
    nextPath, f.file, request, f.base, reconciliation, at);
  const successorProof = validateSyntheticIsolationProof(f.makeProof(at), next, at);
  assert.throws(() => validateOperationCorrelation(
    oldJournal[0].record.syntheticProof.correlationId,
    { syntheticProof: successorProof, attempts: [] }, next),
  /UAT_OPERATION_CORRELATION_REPLAY_REJECTED/);
  assert.ok(next.scope.excludedCorrelations.some(value =>
    value.toLowerCase() === oldJournal[0].record.syntheticProof.correlationId));
  assert.equal(next.predecessor.attemptState, "STOPPED_ZERO_DISPATCH");
  assert.equal(next.predecessor.dispatchCount, 0);
});

for (const [label, mutate] of [
  ["wrong actor", request => { request.scope.actorId = "99999999-9999-4999-8999-999999999999"; }],
  ["wrong child scope", request => {
    request.scope.syntheticIsolation.scopeId = "99999999-9999-4999-8999-999999999999";
  }],
  ["wrong marker", request => { request.marker = "99999999-9999-4999-8999-999999999999"; }]
]) {
  test(`SingleUserDev succession rejects ${label}`, t => {
    const f = singleUserDevFixture(t);
    f.create();
    const at = Date.parse("2030-01-02T11:00:00Z");
    const reconciliation = singleUserDevReconciliation(f, at);
    const request = singleUserDevSuccessorRequest(f, reconciliation, at);
    mutate(request);
    const nextPath = path.join(path.dirname(f.file), `${request.scope.authorizationId}.authorization.json`);
    assert.throws(() => createSingleUserDevSuccessor(
      nextPath, f.file, request, f.base, reconciliation, at));
    assert.equal(fs.existsSync(nextPath), false);
    assert.equal(fs.existsSync(`${path.dirname(f.file)}\\singleuserdev-${f.original.marker}.authorization-slot.json.successor-authorization.json`), false);
  });
}

test("Concurrent claims on one SingleUserDev successor have one winner", async t => {
  const f = singleUserDevFixture(t);
  const { authorization, file, at } = createFixtureSuccessor(f);
  const observation = f.makeProof(at);
  const source = `
    const {claimIndependentAuthorization}=require(${JSON.stringify(require.resolve("./independent-authorization.cjs"))});
    try { claimIndependentAuthorization(${JSON.stringify(file)},${JSON.stringify(f.base)},
      ${JSON.stringify(configuration)},${JSON.stringify(observation)},${at}); }
    catch (error) { console.error(error.code || error.message); process.exitCode=1; }`;
  const run = () => new Promise(resolve => {
    const child = spawn(process.execPath, ["-e", source], { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    child.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    child.on("close", code => resolve({ code, stderr }));
  });
  const results = await Promise.all([run(), run()]);
  assert.deepEqual(results.map(result => result.code).sort(), [0, 1]);
  assert.equal(results.filter(result => result.code === 1)
    .every(result => result.stderr.includes("EEXIST")), true);
  assert.equal(authorization.scope.identityScope, "SINGLE_USER_DEV");
  assert.equal(events(`${file}.attempt.jsonl`).length, 1);
});

test("Concurrent SingleUserDev successor issuances cannot fork one occupied slot", async t => {
  const f = singleUserDevFixture(t);
  f.create();
  const at = Date.parse("2030-01-02T11:00:00Z");
  const reconciliation = singleUserDevReconciliation(f, at);
  const requests = ["singleuserdev-02", "singleuserdev-03"].map(authorizationId => {
    const request = singleUserDevSuccessorRequest(f, reconciliation, at);
    request.scope.authorizationId = authorizationId;
    return request;
  });
  const run = request => new Promise(resolve => {
    const file = path.join(path.dirname(f.file),
      `${request.scope.authorizationId}.authorization.json`);
    const source = `
      const {createSingleUserDevSuccessor}=require(${JSON.stringify(require.resolve("./independent-authorization.cjs"))});
      try { createSingleUserDevSuccessor(${JSON.stringify(file)},${JSON.stringify(f.file)},
        ${JSON.stringify(request)},${JSON.stringify(f.base)},${JSON.stringify(reconciliation)},${at}); }
      catch (error) { console.error(error.code || error.message); process.exitCode=1; }`;
    const child = spawn(process.execPath, ["-e", source], { stdio: ["ignore", "pipe", "pipe"] });
    let stderr = "";
    child.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    child.on("close", code => resolve({ code, stderr, file }));
  });
  const results = await Promise.all(requests.map(run));
  assert.deepEqual(results.map(result => result.code).sort(), [0, 1]);
  assert.equal(results.filter(result => result.code === 1)
    .every(result => result.stderr.includes("EEXIST") ||
      result.stderr.includes("UAT_SINGLE_USER_DEV_SUCCESSOR_ALREADY_EXISTS")), true);
  assert.equal(results.filter(result => fs.existsSync(result.file)).length, 1);
});

test("Runner loads the exact SingleUserDev authorization and rejects its consumed claim", t => {
  const f = singleUserDevFixture(t);
  f.create();
  const approvalPath = path.join(path.dirname(f.file), "read-only.json");
  write(approvalPath, {
    ...f.base, candidateNumber: "CAND-123456", syntheticReadScopeApproved: true,
    syntheticLifecycleAuthorized: false, identityScope: "OWNER_APPROVED_ELEVATED_READ_ONLY"
  });
  const source = `
    Date.now=()=>${now};
    const {loadLifecycleApproval}=require(${JSON.stringify(require.resolve("./lifecycle-support.cjs"))});
    const approval=loadLifecycleApproval();
    if (approval.identityScope !== "SINGLE_USER_DEV" ||
        approval.expectedActorId !== ${JSON.stringify(f.base.expectedActorId)} ||
        approval.lifecycleScope.syntheticIsolation.scopeId !==
          ${JSON.stringify(f.request.scope.syntheticIsolation.scopeId)}) process.exitCode=2;`;
  const env = {
    ...process.env, BSO_UAT_APPROVAL_FILE: approvalPath,
    BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE: f.file,
    BSO_UAT_ENVIRONMENT_ID: f.base.environmentId,
    BSO_UAT_RESUME_ZERO_DISPATCH: ""
  };
  assert.equal(spawnSync(process.execPath, ["-e", source], { encoding: "utf8", env }).status, 0);
  f.claim();
  const consumed = `
    Date.now=()=>${now};
    const {loadLifecycleApproval}=require(${JSON.stringify(require.resolve("./lifecycle-support.cjs"))});
    try { loadLifecycleApproval(); process.exitCode=2; }
    catch (error) {
      if (error.message !== "UAT_INDEPENDENT_AUTHORIZATION_ALREADY_CLAIMED") process.exitCode=3;
    }`;
  assert.equal(spawnSync(process.execPath, ["-e", consumed], { encoding: "utf8", env }).status, 0);
});

test("Excluded and duplicate SingleUserDev operation correlations are rejected", t => {
  const f = singleUserDevFixture(t);
  const authorization = f.create();
  const record = {
    syntheticProof: validateSyntheticIsolationProof(f.makeProof(), authorization, now),
    attempts: []
  };
  assert.throws(() => validateOperationCorrelation(
    "fe902569-29b8-4af0-89c8-508190769e94", record, authorization),
  /UAT_OPERATION_CORRELATION_REPLAY_REJECTED/);
  const correlation = "66666666-6666-4666-8666-666666666666";
  assert.equal(validateOperationCorrelation(correlation, record, authorization), correlation);
  record.attempts.push({ correlation });
  assert.throws(() => validateOperationCorrelation(correlation, record, authorization),
    /UAT_OPERATION_CORRELATION_REPLAY_REJECTED/);
});

test("An ambiguous SingleUserDev dispatch blocks the next lifecycle operation", t => {
  const f = singleUserDevFixture(t);
  f.create();
  const journal = f.claim();
  journal.record.attempts.push({
    action: ACTIONS[0], correlation: "66666666-6666-4666-8666-666666666666",
    outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
  });
  journal.record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
  journal.save();
  journal.record.attempts.push({
    action: ACTIONS[1], correlation: "77777777-7777-4777-8777-777777777777",
    outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
  });
  assert.throws(journal.save, /UAT_PRIOR_DISPATCH_OR_AMBIGUITY/);
  assert.equal(events(`${f.file}.attempt.jsonl`).at(-1).record.attempts.length, 1);
});

test("SingleUserDev direct reads of Candidate, lifecycle and receipt tables are blocked", () => {
  for (const entitySet of ["os_sr_cands", "os_sr_calls", "os_sr_cshs", "os_sr_intvs", "os_sr_oprcs"]) {
    assert.equal(isSingleUserDevDirectReadBlocked(new URL(
      `https://orgsynthetic.crm4.dynamics.com/api/data/v9.2/${entitySet}`)), true);
    assert.equal(isSingleUserDevDirectReadBlocked(new URL(
      `https://orgsynthetic.crm4.dynamics.com/api/data/v9.0/${entitySet}`)), true);
    assert.equal(isSingleUserDevDirectReadBlocked(new URL(
      `https://orgsynthetic.crm4.dynamics.com/api/data/v9.2/${entitySet}(11111111-1111-4111-8111-111111111111)`)), true);
  }
  assert.equal(isSingleUserDevDirectReadBlocked(new URL(
    "https://orgsynthetic.crm4.dynamics.com/api/data/v9.2/accounts")), false);
});

test("One durable authorization links consumed history, preserves hashes/marker, leaves claim unconsumed", t => {
  const f = fixture(t);
  const record = f.create();
  assert.equal(record.marker, f.original.marker);
  assert.equal(record.candidateName, f.original.candidateName);
  assert.equal(record.candidateEmail, f.original.candidateEmail);
  assert.equal(record.predecessor.authorizationId, "historical");
  assert.equal(record.predecessor.claimPath, `${f.request.history.journalPath}.eligible-continuation.jsonl`);
  assert.match(record.attemptId, /^[0-9a-f-]{36}$/);
  assert.equal(record.ownerDecisionText, f.request.ownerDecisionText);
  assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
  assert.throws(f.create, /UAT_AUTHORIZATION_RECORD_ALREADY_EXISTS/);
  assert.equal(fs.readdirSync(path.dirname(f.file)).filter(name => name.endsWith(".authorization.json")).length, 1);
  for (const item of f.evidence) assert.equal(digest(item.path), item.sha256);
});

test("First claim is exclusive; second invocation rejected, original evidence unchanged", t => {
  const f = fixture(t);
  const authorization = f.create();
  const before = digest(f.file);
  const journal = f.claim();
  assert.equal(journal.record.marker, f.original.marker);
  assert.equal(journal.record.attemptId, authorization.attemptId);
  assert.deepEqual(journal.record.attempts, []);
  const claimHash = digest(`${f.file}.attempt.jsonl`);
  assert.throws(f.claim, error => error.code === "EEXIST");
  assert.equal(digest(f.file), before);
  assert.equal(digest(`${f.file}.attempt.jsonl`), claimHash);
  for (const item of f.evidence) assert.equal(digest(item.path), item.sha256);
});

test("Concurrent processes cannot both acquire the authorization", async t => {
  const f = fixture(t);
  f.create();
  const source = `
    const {claimIndependentAuthorization}=require(${JSON.stringify(require.resolve("./independent-authorization.cjs"))});
    try { claimIndependentAuthorization(${JSON.stringify(f.file)},${JSON.stringify(f.base)},
      ${JSON.stringify(configuration)},${JSON.stringify(f.makeProof())},${now}); process.exitCode=0; }
    catch { process.exitCode=7; }`;
  const start = () => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ["-e", source], { stdio: "ignore" });
    child.on("error", reject);
    child.on("exit", resolve);
  });
  assert.deepEqual((await Promise.all([start(), start()])).sort(), [0, 7]);
  assert.equal(events(`${f.file}.attempt.jsonl`).length, 1);
});

test("Different authorizations cannot fork the same predecessor", t => {
  const f = fixture(t);
  f.create();
  const request = { ...f.request, scope: { ...f.request.scope, authorizationId: "independent-02" } };
  const other = path.join(path.dirname(f.file), "independent-02.authorization.json");
  assert.throws(() => createAuthorization(other, request, f.base, now), error => error.code === "EEXIST");
  assert.equal(fs.existsSync(other), false);
});

test("Missing, expired, future-dated or unapproved authorizations fail closed", t => {
  const f = fixture(t);
  assert.throws(f.claim, /UAT_INDEPENDENT_AUTHORIZATION_MISSING/);
  f.request.scope.expiresAt = "2021-01-01T00:00:00Z";
  assert.throws(f.create, /UAT_INDEPENDENT_AUTHORIZATION_EXPIRED/);
  f.request.scope.expiresAt = "2030-01-02T10:30:00Z";
  f.request.scope.ownerMutationApproval = false;
  assert.throws(f.create, /UAT_INDEPENDENT_SCOPE_OR_TARGET_MISMATCH/);
  f.request.scope.ownerMutationApproval = true;
  f.request.authorizedAt = "2030-01-03T00:00:00Z";
  assert.throws(f.create);
  f.request.authorizedAt = "2030-01-02T09:59:00Z";
  f.create();
  assert.throws(() => claimIndependentAuthorization(f.file, f.base, configuration,
    f.makeProof(Date.parse("2030-01-03T00:00:00Z")),
    Date.parse("2030-01-03T00:00:00Z")), /UAT_INDEPENDENT_AUTHORIZATION_EXPIRED/);
  assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
});

for (const [field, value] of [
  ["actions", [...ACTIONS].reverse()], ["callOutcome", "No Answer"], ["maximumCandidates", 2],
  ["organizationId", "55555555-5555-4555-8555-555555555555"],
  ["environmentId", "55555555-5555-4555-8555-555555555555"],
  ["expectedUpn", "owner@example.invalid"], ["appUrl", "https://other.example.invalid"],
  ["authenticationCallbackOrigin", "https://other.example.invalid"]
]) {
  test(`Scope/target mismatch rejected: ${field}`, t => {
    const f = fixture(t);
    f.request.scope[field] = value;
    assert.throws(f.create, /UAT_INDEPENDENT_SCOPE_OR_TARGET_MISMATCH/);
    assert.equal(fs.existsSync(f.file), false);
  });
}

test("New lifecycle scope is BSO-only and bound to the exact profile actor, marker, and references", t => {
  for (const change of ["elevated", "actor", "profileActor", "scopeMarker", "reference"]) {
    const f = fixture(t);
    if (change === "elevated") f.request.scope.identityScope = "OWNER_APPROVED_ELEVATED_FUNCTIONAL_LIFECYCLE";
    if (change === "actor") f.request.scope.actorId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    if (change === "profileActor") {
      f.request.scope.syntheticIsolation.actorId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    }
    if (change === "scopeMarker") {
      f.request.scope.syntheticIsolation.scopeId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    }
    if (change === "reference") {
      f.request.scope.syntheticIsolation.locationId = f.request.scope.syntheticIsolation.taId;
    }
    assert.throws(f.create, /UAT_INDEPENDENT_SCOPE_OR_TARGET_MISMATCH|UAT_SYNTHETIC_PROFILE_BINDING_MISMATCH/);
    assert.equal(fs.existsSync(f.file), false);
  }
});

test("Only a fresh exact v2 proof is accepted before the one-shot claim", t => {
  for (const change of ["correlation", "version", "actor", "organization", "candidate",
    "reference", "nativeWrites", "calendar", "expired", "tooFar", "malformed"]) {
    const f = fixture(t);
    f.create();
    const observation = f.makeProof();
    const body = JSON.parse(observation.contract);
    if (change === "correlation") observation.correlationId = "00000000-0000-0000-0000-000000000000";
    if (change === "version") body.version = 1;
    if (change === "actor") body.actorId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    if (change === "organization") body.organizationId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    if (change === "candidate") body.candidateId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    if (change === "reference") body.taId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
    if (change === "nativeWrites") body.nativeWritesDenied = false;
    if (change === "calendar") body.calendarEnabled = true;
    if (change === "expired") body.validUntil = new Date(now + 10_000).toISOString();
    if (change === "tooFar") body.validUntil = new Date(now + 126_000).toISOString();
    observation.contract = change === "malformed" ? "{" : JSON.stringify(body);
    assert.throws(() => claimIndependentAuthorization(f.file, f.base, configuration, observation, now));
    assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
  }
});

test("Authorization execution window is bounded to two hours", t => {
  const f = fixture(t);
  f.request.scope.expiresAt = "2030-01-02T12:00:00Z";
  f.request.authorizedAt = "2030-01-02T09:59:00Z";
  assert.throws(f.create, /UAT_INDEPENDENT_AUTHORIZATION_WINDOW_INVALID/);
  assert.equal(fs.existsSync(f.file), false);
});

test("Prior dispatch, acknowledgment, partial audit or historical evidence drift blocks creation", t => {
  for (const change of ["dispatch", "candidateId", "partial", "drift"]) {
    const f = fixture(t);
    const file = `${f.request.history.journalPath}.eligible-continuation.jsonl`;
    const snapshots = events(file);
    if (change === "dispatch") snapshots[0].attempts.push({ outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN" });
    if (change === "candidateId") snapshots[0].candidateId = "55555555-5555-4555-8555-555555555555";
    fs.writeFileSync(file, snapshots.map(item => JSON.stringify(item)).join("\n") +
      (change === "partial" ? "" : "\n"));
    if (change === "drift") fs.appendFileSync(f.request.history.scopePath, " ");
    assert.throws(f.create);
  }
});

test("Append-only reservation preserves logical identity and ambiguity blocks any new authorization", t => {
  const f = fixture(t);
  f.create();
  const journal = f.claim();
  const firstLine = fs.readFileSync(`${f.file}.attempt.jsonl`, "utf8");
  journal.record.attempts.push({
    action: ACTIONS[0], correlation: "66666666-6666-4666-8666-666666666666",
    outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
  });
  journal.record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
  journal.save();
  journal.record.status = "STOPPED_NO_RETRY_RECONCILE_ONLY";
  journal.save();
  assert.ok(fs.readFileSync(`${f.file}.attempt.jsonl`, "utf8").startsWith(firstLine));
  assert.equal(events(`${f.file}.attempt.jsonl`)[1].record.attempts[0].correlation,
    "66666666-6666-4666-8666-666666666666");
  assert.throws(f.claim, error => error.code === "EEXIST");
  const request = { ...f.request, previousAuthorizationFile: f.file,
    scope: { ...f.request.scope, authorizationId: "independent-02" } };
  assert.throws(() => createAuthorization(path.join(path.dirname(f.file),
    "independent-02.authorization.json"), request, f.base, now), /UAT_PRIOR_DISPATCH_OR_AMBIGUITY/);
  journal.record.attempts = [];
  assert.throws(journal.save);
});

test("Rewriting marker, correlation or an earlier audit event is rejected", t => {
  const f = fixture(t);
  f.create();
  const journal = f.claim();
  journal.record.marker = "77777777-7777-4777-8777-777777777777";
  assert.throws(journal.save, /UAT_ATTEMPT_IDENTITY_CHANGED/);
  journal.record.marker = f.original.marker;
  fs.appendFileSync(`${f.file}.attempt.jsonl`, "partial");
  assert.throws(journal.save, /UAT_INCOMPLETE_AUDIT_LOG/);
});

test("A reserved correlation cannot be replaced and an uncertain dispatch cannot be followed", t => {
  const f = fixture(t);
  f.create();
  const journal = f.claim();
  const correlation = "66666666-6666-4666-8666-666666666666";
  journal.record.attempts.push({
    action: ACTIONS[0], correlation, outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
  });
  journal.record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
  journal.save();
  const before = digest(`${f.file}.attempt.jsonl`);
  journal.record.attempts[0].correlation = "77777777-7777-4777-8777-777777777777";
  assert.throws(journal.save);
  journal.record.attempts[0].correlation = correlation;
  journal.record.attempts.push({
    action: ACTIONS[1], correlation: "77777777-7777-4777-8777-777777777777",
    outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
  });
  assert.throws(journal.save, /UAT_PRIOR_DISPATCH_OR_AMBIGUITY/);
  assert.equal(digest(`${f.file}.attempt.jsonl`), before);
});

for (const [field, value] of [
  ["workers", 2], ["retries", 1], ["repeatEach", 2], ["retry", 1], ["repeatEachIndex", 1]
]) {
  test(`Zero retries/one invocation enforced before claiming: ${field}`, t => {
    const f = fixture(t);
    f.create();
    assert.throws(() => f.claim({ ...configuration, [field]: value }),
      /UAT_ONE_SHOT_RUNNER_CONFIGURATION_REQUIRED/);
    assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
  });
}

test("Default reservation cannot generate a replacement marker", () => {
  assert.throws(() => reserveOneShot({ lifecycleScope: { authorizationId: "synthetic-unused" } }),
    /UAT_EXPLICIT_AUTHORIZATION_MODE_REQUIRED_NO_MARKER_REGENERATION/);
});

test("Independent selection never falls back to legacy recovery or default reservation", () => {
  const previous = process.env.BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE;
  const recovery = process.env.BSO_UAT_RESUME_ZERO_DISPATCH;
  try {
    process.env.BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE = "";
    process.env.BSO_UAT_RESUME_ZERO_DISPATCH = "owner-authorized-eligible-continuation";
    assert.throws(() => reserveOneShot({}), /UAT_INDEPENDENT_AUTHORIZATION_CANNOT_USE_RECOVERY/);
    delete process.env.BSO_UAT_RESUME_ZERO_DISPATCH;
    assert.throws(() => reserveOneShot({}), /UAT_INDEPENDENT_AUTHORIZATION_CANNOT_USE_RECOVERY/);
  } finally {
    if (previous === undefined) delete process.env.BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE;
    else process.env.BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE = previous;
    if (recovery === undefined) delete process.env.BSO_UAT_RESUME_ZERO_DISPATCH;
    else process.env.BSO_UAT_RESUME_ZERO_DISPATCH = recovery;
  }
});

test("Runner loader and reservation use the new authorization, never the expired historical descriptor", t => {
  const f = fixture(t);
  f.create();
  const approvalPath = path.join(path.dirname(f.file), "read-only.json");
  write(approvalPath, {
    ...f.base, candidateNumber: "CAND-123456", syntheticReadScopeApproved: true,
    syntheticLifecycleAuthorized: false, identityScope: "OWNER_APPROVED_ELEVATED_READ_ONLY"
  });
  const source = `
    Date.now=()=>${now};
    const assert=require("node:assert/strict");
    const {loadLifecycleApproval,reserveOneShot}=require(
      ${JSON.stringify(require.resolve("./lifecycle-support.cjs"))});
    const approval=loadLifecycleApproval();
    assert.equal(approval.lifecycleScope.authorizationId,"independent-01");
    assert.equal(approval.identityScope,"BSO_ONLY");
    assert.equal(approval.expectedUpn,"bso@example.invalid");
    assert.equal(approval.expectedActorId,"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
    const journal=reserveOneShot(approval,${JSON.stringify(configuration)},${JSON.stringify(f.makeProof())});
    assert.equal(journal.record.marker,${JSON.stringify(f.original.marker)});
    assert.throws(()=>reserveOneShot(approval,${JSON.stringify(configuration)},${JSON.stringify(f.makeProof())}));
  `;
  const child = spawnSync(process.execPath, ["-e", source], {
    encoding: "utf8", env: {
      ...process.env, BSO_UAT_APPROVAL_FILE: approvalPath,
      BSO_UAT_LIFECYCLE_APPROVAL_FILE: f.request.history.scopePath,
      BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE: f.file,
      BSO_UAT_ENVIRONMENT_ID: f.base.environmentId, BSO_UAT_RESUME_ZERO_DISPATCH: ""
    }
  });
  assert.equal(child.status, 0, child.stderr);
  for (const item of f.evidence) assert.equal(digest(item.path), item.sha256);
});

test("A previously claimed independent authorization is rejected by the loader", t => {
  const f = fixture(t);
  f.create();
  f.claim();
  const approvalPath = path.join(path.dirname(f.file), "read-only.json");
  write(approvalPath, {
    ...f.base, candidateNumber: "CAND-123456", syntheticReadScopeApproved: true,
    syntheticLifecycleAuthorized: false, identityScope: "OWNER_APPROVED_ELEVATED_READ_ONLY"
  });
  const source = `
    const {loadLifecycleApproval}=require(${JSON.stringify(require.resolve("./lifecycle-support.cjs"))});
    try { loadLifecycleApproval(); process.exitCode=2; }
    catch (error) {
      if (error.message !== "UAT_INDEPENDENT_AUTHORIZATION_ALREADY_CLAIMED") process.exitCode=3;
    }`;
  const child = spawnSync(process.execPath, ["-e", source], {
    encoding: "utf8", env: {
      ...process.env, BSO_UAT_APPROVAL_FILE: approvalPath,
      BSO_UAT_INDEPENDENT_AUTHORIZATION_FILE: f.file,
      BSO_UAT_ENVIRONMENT_ID: f.base.environmentId,
      BSO_UAT_RESUME_ZERO_DISPATCH: ""
    }
  });
  assert.equal(child.status, 0, child.stderr);
  assert.equal(events(`${f.file}.attempt.jsonl`).length, 1);
  for (const item of f.evidence) assert.equal(digest(item.path), item.sha256);
});

test("Independent lifecycle claim is deferred until all read-only and form gates pass", () => {
  const source = fs.readFileSync(path.join(__dirname, "candidate-lifecycle.spec.cjs"), "utf8");
  const baseline = source.indexOf("report.baselineCounts = counts(evidence);");
  const consoleGate = source.indexOf('await expect(frame.locator("#availability-submit")).toBeDisabled();');
  const referenceSelection = source.indexOf("await frame.locator(`#${id}`).selectOption(references[key]);");
  const claim = source.indexOf("journal = reserveOneShot(approval", referenceSelection);
  const create = source.indexOf('await invokeOnce("CreateCandidate"', claim);
  assert.ok(baseline >= 0 && consoleGate > baseline);
  assert.ok(referenceSelection > consoleGate && claim > referenceSelection && create > claim);
});

test("Lifecycle runner preserves BSO v2 and gates either owner scope before claiming", () => {
  const source = fs.readFileSync(path.join(__dirname, "candidate-lifecycle.spec.cjs"), "utf8");
  const identityGate = source.indexOf("identity.userId === approval.expectedActorId.toLowerCase()");
  const bsoOnlyGate = source.indexOf('if (approval.identityScope === "BSO_ONLY")', identityGate);
  const proofGate = source.indexOf("validateSyntheticIsolationProof(syntheticProofObservation");
  const claim = source.indexOf("journal = reserveOneShot(approval", proofGate);
  const firstDispatch = source.indexOf('await invokeOnce("CreateCandidate"', claim);
  assert.ok(identityGate >= 0 && bsoOnlyGate > identityGate);
  assert.ok(proofGate > bsoOnlyGate && claim > proofGate && firstDispatch > claim);
  assert.match(source, /identity\.bsoRole && !identity\.elevated/);
  assert.match(source, /VerifySingleUserDev/);
  assert.match(source, /SCOPED_READ_OPERATION_ALLOWED/);
  assert.match(source, /isSingleUserDevDirectReadBlocked\(url\)/);
  assert.match(source, /body\.SyntheticScopeId === approval\.lifecycleScope\.syntheticIsolation\.scopeId/);
  assert.match(source, /validateOperationCorrelation\(/);
  assert.match(source, /resolveAuthenticationRouting\(/);
  assert.match(source, /organizationOrigin: approval\.origin/);
  assert.match(source, /loadPinnedAuthenticationCallbackOrigin\(\)/);
  assert.match(source, /readEvidence\(page, approval\.origin, record, approval\.independentAuthorizationRecord\)/);
});

test("Four ordered synthetic dispatch/acknowledgment pairs and persistence snapshots can be appended", t => {
  const f = fixture(t);
  f.create();
  const journal = f.claim();
  const firstLine = fs.readFileSync(`${f.file}.attempt.jsonl`, "utf8");
  for (const [index, action] of ACTIONS.entries()) {
    journal.record.attempts.push({
      action, correlation: `88888888-8888-4888-8888-88888888888${index}`,
      classification: "APPROVED_BUSINESS_OPERATION",
      outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
    });
    journal.record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
    journal.save();
    journal.record.attempts[index].response = { ResultCode: "Applied" };
    journal.record.attempts[index].outcome = "APPLIED";
    journal.save();
    journal.record.candidateId = "99999999-9999-4999-8999-999999999999";
    journal.save();
  }
  journal.record.status = "COMPLETED_DO_NOT_RERUN";
  journal.save();
  assert.ok(fs.readFileSync(`${f.file}.attempt.jsonl`, "utf8").startsWith(firstLine));
  assert.equal(events(`${f.file}.attempt.jsonl`).at(-1).record.status, "COMPLETED_DO_NOT_RERUN");
  assert.throws(journal.save, /UAT_TERMINAL_ATTEMPT_NO_CONTINUATION/);
  assert.throws(f.claim, error => error.code === "EEXIST");
});

test("An explicit successor after a stopped zero-dispatch independent attempt preserves the entire chain", t => {
  const f = fixture(t);
  f.create();
  const source = `
    const {claimIndependentAuthorization}=require(${JSON.stringify(require.resolve("./independent-authorization.cjs"))});
    const journal=claimIndependentAuthorization(${JSON.stringify(f.file)},${JSON.stringify(f.base)},
      ${JSON.stringify(configuration)},${JSON.stringify(f.makeProof())},${now});
    journal.record.status="STOPPED_NO_RETRY_RECONCILE_ONLY"; journal.save();`;
  const child = spawnSync(process.execPath, ["-e", source], { encoding: "utf8" });
  assert.equal(child.status, 0, child.stderr);
  const before = [f.file, `${f.file}.attempt.jsonl`].map(digest);
  const request = { ...f.request, previousAuthorizationFile: f.file,
    ownerDecisionText: "Synthetic fixture: a separate explicit owner decision, not a retry.",
    scope: { ...f.request.scope, authorizationId: "independent-02" } };
  const nextPath = path.join(path.dirname(f.file), "independent-02.authorization.json");
  const next = createAuthorization(nextPath, request, f.base, now);
  assert.equal(next.predecessor.authorizationId, "independent-01");
  assert.notEqual(next.attemptId, JSON.parse(fs.readFileSync(f.file)).attemptId);
  assert.equal(next.marker, f.original.marker);
  const journal = claimIndependentAuthorization(nextPath, f.base, configuration, f.makeProof(), now);
  assert.equal(journal.record.marker, f.original.marker);
  assert.deepEqual([f.file, `${f.file}.attempt.jsonl`].map(digest), before);
});

test("A fresh BSO authorization may supersede an expired unclaimed predecessor without reusing it", t => {
  const f = fixture(t);
  f.create();
  const priorHash = digest(f.file);
  const nowAfterExpiry = Date.parse("2030-01-02T11:00:00Z");
  const request = {
    ...f.request, previousAuthorizationFile: f.file,
    authorizedAt: "2030-01-02T10:59:00Z",
    ownerDecisionText: "Synthetic fixture: fresh BSO-only successor authorization.",
    scope: { ...f.request.scope, authorizationId: "independent-02",
      expiresAt: "2030-01-02T11:30:00Z" }
  };
  const nextPath = path.join(path.dirname(f.file), "independent-02.authorization.json");
  const next = createAuthorization(nextPath, request, f.base, nowAfterExpiry);
  assert.equal(next.predecessor.state, "EXPIRED_UNCLAIMED");
  assert.equal(next.predecessor.authorizationId, "independent-01");
  assert.equal(next.marker, f.original.marker);
  assert.equal(digest(f.file), priorHash);
  assert.equal(fs.existsSync(`${f.file}.attempt.jsonl`), false);
  assert.equal(fs.existsSync(`${nextPath}.attempt.jsonl`), false);
});

test("Active preceding independent attempt, missing decision text and tampered authorization fail closed", t => {
  const f = fixture(t);
  f.request.ownerDecisionText = "";
  assert.throws(f.create);
  f.request.ownerDecisionText = "Synthetic fixture: explicit authorization.";
  f.create();
  const journal = f.claim();
  journal.record.status = "STOPPED_NO_RETRY_RECONCILE_ONLY";
  journal.save();
  const request = { ...f.request, previousAuthorizationFile: f.file,
    scope: { ...f.request.scope, authorizationId: "independent-02" } };
  assert.throws(() => createAuthorization(path.join(path.dirname(f.file),
    "independent-02.authorization.json"), request, f.base, now), /UAT_PRECEDING_ATTEMPT_ACTIVE/);
  fs.appendFileSync(f.file, " ");
  assert.throws(() => loadIndependentAuthorization(f.file, f.base, now), /UAT_INDEPENDENT_CHAIN_LINK_MISMATCH/);
});

function continuationFixture(t, authorizationId = "singleuserdev-continuation-01", issue = true) {
  const f = singleUserDevFixture(t);
  const authorizedAt = Date.parse("2030-01-02T11:00:00Z");
  const candidateId = "99999999-9999-4999-8999-999999999999";
  const createCorrelation = "abababab-abab-4bab-8bab-abababababab";
  const prior = f.create();
  const predecessorProof = f.makeProof(now);
  const claimSource = `
    const { claimIndependentAuthorization } = require(${JSON.stringify(
      require.resolve("./independent-authorization.cjs"))});
    const journal = claimIndependentAuthorization(${JSON.stringify(f.file)},
      ${JSON.stringify(f.base)}, ${JSON.stringify(configuration)},
      ${JSON.stringify(predecessorProof)}, ${now});
    journal.record.attempts.push({
      action: "CreateCandidate",
      correlation: ${JSON.stringify(createCorrelation)},
      classification: "APPROVED_BUSINESS_OPERATION",
      outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
    });
    journal.record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
    journal.save();
    journal.record.status = "STOPPED_NO_RETRY_RECONCILE_ONLY";
    journal.save();`;
  const child = spawnSync(process.execPath, ["-e", claimSource], { encoding: "utf8" });
  assert.equal(child.status, 0, child.stderr || child.stdout);

  const proofObservation = f.makeProof(authorizedAt);
  const candidate = {
    candidateCount: 1, candidateId, marker: f.original.marker,
    name: f.request.candidateName, email: f.request.candidateEmail,
    createCorrelation, status: STATUSES[0], ownerId: f.base.expectedActorId,
    positionId: prior.scope.syntheticIsolation.positionId,
    sourceId: prior.scope.syntheticIsolation.sourceId,
    taId: prior.scope.syntheticIsolation.taId,
    callCount: 0, scheduleCount: 0, historyCount: 0,
    callOutcome: null, callCorrelation: null, callId: null, history: []
  };
  const reconciliation = {
    version: 1, checkedAt: new Date(authorizedAt).toISOString(),
    whoAmI: {
      actorId: f.base.expectedActorId, organizationId: f.base.organizationId
    },
    proofObservation, candidate,
    counts: { candidates: 1, calls: 0, schedules: 0, history: 0 },
    receiptReadback: "NOT_AVAILABLE_VIA_SINGLE_USER_DEV_SCOPED_API"
  };
  const request = {
    ownerMutationApproval: true,
    ownerDecisionText: "Synthetic fixture: explicitly authorize Call Answered and Proceed to Scheduling for the reconciled Candidate only.",
    authorizedAt: new Date(authorizedAt).toISOString(),
    marker: f.original.marker, candidateId, createCorrelation,
    authorizationId,
    expiresAt: new Date(authorizedAt + 60 * 60 * 1000).toISOString(),
    reconciliation
  };
  const file = path.join(path.dirname(f.file),
    `${request.authorizationId}.continuation.json`);
  const authorization = issue
    ? createContinuationAuthorization(file, f.file, request, f.base, authorizedAt)
    : null;
  return {
    ...f, prior, file, request, authorization, candidateId, createCorrelation,
    authorizedAt, initialState: candidate
  };
}

function continuationState(f, authorization, phase, callCorrelation = null,
  proceedCorrelation = null) {
  const state = {
    ...f.initialState,
    status: STATUSES[0],
    callCount: 0, scheduleCount: 0, historyCount: 0,
    callOutcome: null, callCorrelation: null, callId: null, history: []
  };
  if (phase === "AFTER_CALL" || phase === "BEFORE_PROCEED" || phase === "AFTER_PROCEED") {
    const historyId = "12121212-1212-4121-8121-121212121212";
    state.status = STATUSES[1];
    state.callCount = 1;
    state.callOutcome = 100010000;
    state.callCorrelation = callCorrelation;
    state.callId = "13131313-1313-4131-8131-131313131313";
    state.historyCount = 1;
    state.history = [{
      id: historyId, correlation: callCorrelation,
      previousStatus: STATUSES[0], newStatus: STATUSES[1],
      actorId: authorization.scope.actorId
    }];
  }
  if (phase === "AFTER_PROCEED") {
    state.status = STATUSES[2];
    state.historyCount = 2;
    state.history.push({
      id: "14141414-1414-4141-8141-141414141414",
      correlation: proceedCorrelation,
      previousStatus: STATUSES[1], newStatus: STATUSES[2],
      actorId: authorization.scope.actorId
    });
  }
  return state;
}

test("A separate continuation binds only the reconciled Candidate and preserves predecessor evidence", t => {
  const f = continuationFixture(t);
  const authorizationBytes = fs.readFileSync(f.file);
  const predecessorBytes = fs.readFileSync(f.file.replace(
    "singleuserdev-continuation-01.continuation.json", "singleuserdev-01.authorization.json"));
  const predecessorJournal = fs.readFileSync(`${f.file.replace(
    "singleuserdev-continuation-01.continuation.json", "singleuserdev-01.authorization.json")}.attempt.jsonl`);
  const loaded = loadContinuationAuthorization(f.file, f.base, f.authorizedAt);
  assert.deepEqual(loaded.scope.actions, ["RecordCall", "ProceedToScheduling"]);
  assert.equal(loaded.scope.maximumCandidates, 0);
  assert.equal(loaded.scope.maximumInvocations, 2);
  assert.equal(loaded.scope.candidateId, f.candidateId);
  assert.equal(loaded.scope.createCorrelation, f.createCorrelation);
  assert.equal(loaded.scope.excludedCorrelations.includes(f.createCorrelation), true);
  assert.equal(loaded.scope.excludedCorrelations.includes(
    f.prior.scope.excludedCorrelations[0]), true);
  const priorFile = f.file.replace(
    "singleuserdev-continuation-01.continuation.json", "singleuserdev-01.authorization.json");
  const predecessorProofCorrelation =
    events(`${priorFile}.attempt.jsonl`)[0].record.syntheticProof.correlationId;
  assert.equal(loaded.scope.excludedCorrelations.includes(predecessorProofCorrelation), true);
  assert.equal(loaded.scope.actions.includes("CreateCandidate"), false);
  assert.deepEqual(fs.readFileSync(f.file), authorizationBytes);
  assert.deepEqual(fs.readFileSync(f.file.replace(
    "singleuserdev-continuation-01.continuation.json", "singleuserdev-01.authorization.json")),
  predecessorBytes);
  assert.deepEqual(fs.readFileSync(`${f.file.replace(
    "singleuserdev-continuation-01.continuation.json", "singleuserdev-01.authorization.json")}.attempt.jsonl`),
  predecessorJournal);
});

test("Continuation issuance rejects wrong scope, mismatched reconciliation, and expired authorization", t => {
  const f = continuationFixture(t);
  const fresh = continuationFixture(t);
  const wrongMarker = { ...fresh.request, marker: "22222222-2222-4222-8222-222222222222" };
  assert.throws(() => createContinuationAuthorization(
    path.join(path.dirname(fresh.file), "bad-marker.continuation.json"),
    fresh.file.replace("singleuserdev-continuation-01.continuation.json",
      "singleuserdev-01.authorization.json"),
    wrongMarker, fresh.base, fresh.authorizedAt),
  /UAT_CONTINUATION_OWNER_DECISION_OR_TARGET_MISMATCH/);
  const priorFile = fresh.file.replace(
    "singleuserdev-continuation-01.continuation.json", "singleuserdev-01.authorization.json");
  const badReadback = { ...fresh.request, reconciliation: {
    ...fresh.request.reconciliation,
    counts: { ...fresh.request.reconciliation.counts, calls: 1 }
  } };
  assert.throws(() => createContinuationAuthorization(
    path.join(path.dirname(fresh.file), "bad-readback.continuation.json"),
    priorFile, badReadback, fresh.base, fresh.authorizedAt),
  /UAT_CONTINUATION_RECONCILIATION_MISMATCH/);
  assert.throws(() => loadContinuationAuthorization(
    f.file, f.base, Date.parse(f.authorization.scope.expiresAt) + 1),
  /UAT_CONTINUATION_AUTHORIZATION_INVALID/);
});

test("Continuation operations are single-use, fail closed when unresolved, and never permit CreateCandidate", t => {
  const f = continuationFixture(t);
  const freshProof = f.makeProof(f.authorizedAt + 1);
  const beforeCall = continuationState(f, f.authorization, "BEFORE_CALL");
  const call = claimContinuationOperation(
    f.file, "RecordCall", f.base, freshProof, beforeCall, f.authorizedAt + 1);
  assert.notEqual(call.correlation, f.createCorrelation);
  assert.throws(() => reserveContinuationDispatch(call, f.base,
    f.makeProof(f.authorizedAt + 2), beforeCall, f.authorizedAt + 2),
  /UAT_CONTINUATION_DISPATCH_PREFLIGHT_CHANGED/);
  assert.throws(() => reserveContinuationDispatch(call, f.base, freshProof,
    { ...beforeCall, status: STATUSES[1] }, f.authorizedAt + 2),
  /UAT_CONTINUATION_DISPATCH_PREFLIGHT_CHANGED/);
  reserveContinuationDispatch(call, f.base, freshProof, beforeCall, f.authorizedAt + 2);
  assert.throws(() => claimContinuationOperation(
    f.file, "RecordCall", f.base, f.makeProof(f.authorizedAt + 3),
    continuationState(f, f.authorization, "BEFORE_CALL"), f.authorizedAt + 3),
  /UAT_CONTINUATION_ACTION_ALREADY_CLAIMED/);
  assert.throws(() => claimContinuationOperation(
    f.file, "ProceedToScheduling", f.base, f.makeProof(f.authorizedAt + 4),
    continuationState(f, f.authorization, "BEFORE_PROCEED", call.correlation),
    f.authorizedAt + 4),
  /UAT_CONTINUATION_PRIOR_ACTION_NOT_CONFIRMED/);
  assert.throws(() => claimContinuationOperation(
    f.file, "CreateCandidate", f.base, f.makeProof(f.authorizedAt + 5),
    continuationState(f, f.authorization, "BEFORE_CALL"), f.authorizedAt + 5),
  /UAT_CONTINUATION_ACTION_NOT_ALLOWED/);
  assert.throws(() => reserveContinuationDispatch(call, f.base, freshProof, beforeCall,
    f.authorizedAt + 6),
    /UAT_CONTINUATION_OPERATION_ALREADY_DISPATCHED/);
});

test("Answered and Proceed continuation validates response, History, persistence and fresh correlations", t => {
  const f = continuationFixture(t);
  const beforeCall = continuationState(f, f.authorization, "BEFORE_CALL");
  const callProof = f.makeProof(f.authorizedAt + 1);
  const call = claimContinuationOperation(
    f.file, "RecordCall", f.base, callProof, beforeCall, f.authorizedAt + 1);
  reserveContinuationDispatch(call, f.base, callProof, beforeCall, f.authorizedAt + 2);
  const afterCall = continuationState(f, f.authorization, "AFTER_CALL", call.correlation);
  const callBody = {
    ResultCode: "Applied", PreviousStatus: STATUSES[0], CurrentStatus: STATUSES[1],
    CallLogId: afterCall.callId, StatusHistoryId: afterCall.history[0].id
  };
  assert.throws(() => completeContinuationOperation(call, f.base,
    { httpStatus: 200, operationCorrelation: f.createCorrelation, body: callBody },
    afterCall, f.authorizedAt + 3),
  /UAT_CONTINUATION_OPERATION_RESPONSE_INVALID/);
  completeContinuationOperation(call, f.base,
    { httpStatus: 200, operationCorrelation: call.correlation, body: callBody },
    afterCall, f.authorizedAt + 3);
  assert.equal(readOperation(f.file, "RecordCall").last.outcome, "APPLIED");

  const beforeProceed = continuationState(f, f.authorization, "BEFORE_PROCEED", call.correlation);
  const proceedProof = f.makeProof(f.authorizedAt + 4);
  const proceed = claimContinuationOperation(
    f.file, "ProceedToScheduling", f.base, proceedProof, beforeProceed,
    f.authorizedAt + 4);
  assert.notEqual(proceed.correlation, call.correlation);
  reserveContinuationDispatch(proceed, f.base, proceedProof, beforeProceed,
    f.authorizedAt + 5);
  const afterProceed = continuationState(f, f.authorization, "AFTER_PROCEED",
    call.correlation, proceed.correlation);
  completeContinuationOperation(proceed, f.base, {
    httpStatus: 200,
    operationCorrelation: proceed.correlation,
    body: {
      ResultCode: "Applied", PreviousStatus: STATUSES[1], CurrentStatus: STATUSES[2],
      StatusHistoryId: afterProceed.history[1].id
    }
  }, afterProceed, f.authorizedAt + 6);
  assert.equal(readOperation(f.file, "ProceedToScheduling").last.outcome, "APPLIED");
  assert.equal(afterProceed.scheduleCount, 0);
  assert.equal(afterProceed.history.length, 2);
  assert.equal(afterProceed.history[1].correlation, proceed.correlation);
  assert.equal(validateReadback(f.authorization, afterProceed, "AFTER_PROCEED",
    call.correlation, proceed.correlation), afterProceed);
});

test("Concurrent continuation issuance has one append-only winner", async t => {
  const f = continuationFixture(t, "unused-continuation", false);
  const priorFile = f.file.replace(
    "unused-continuation.continuation.json", "singleuserdev-01.authorization.json");
  const nextRequest = {
    ...f.request,
    authorizationId: "singleuserdev-continuation-race",
    expiresAt: new Date(f.authorizedAt + 30 * 60 * 1000).toISOString()
  };
  const nextFile = path.join(path.dirname(f.file),
    `${nextRequest.authorizationId}.continuation.json`);
  const source = `
    const { createContinuationAuthorization } = require(${JSON.stringify(
      require.resolve("./continuation-authorization.cjs"))});
    const input = JSON.parse(process.env.BSO_CONTINUATION_TEST_INPUT);
    try {
      createContinuationAuthorization(input.file, input.predecessorFile,
        input.request, input.base, input.now);
      process.stdout.write("CREATED");
    } catch (error) {
      process.stdout.write(String(error.message));
      process.exitCode = 1;
    }`;
  const env = {
    ...process.env,
    BSO_CONTINUATION_TEST_INPUT: JSON.stringify({
      file: nextFile, predecessorFile: priorFile, request: nextRequest,
      base: f.base, now: f.authorizedAt
    })
  };
  const run = () => new Promise(resolve => {
    const child = spawn(process.execPath, ["-e", source], { env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    child.stdout.on("data", chunk => { stdout += chunk; });
    child.on("close", code => resolve({ code, stdout }));
  });
  const results = await Promise.all([run(), run()]);
  assert.equal(results.filter(result => result.code === 0 && result.stdout === "CREATED").length, 1);
  assert.equal(fs.existsSync(nextFile), true);
  assert.equal(fs.existsSync(`${priorFile}.continuation-authorization.json`), true);
});

test("Concurrent per-operation claims have exactly one winner", async t => {
  const f = continuationFixture(t);
  const proofObservation = f.makeProof(f.authorizedAt + 1);
  const state = continuationState(f, f.authorization, "BEFORE_CALL");
  const source = `
    const { claimContinuationOperation } = require(${JSON.stringify(
      require.resolve("./continuation-authorization.cjs"))});
    const input = JSON.parse(process.env.BSO_CONTINUATION_TEST_INPUT);
    try {
      const claim = claimContinuationOperation(input.file, "RecordCall", input.base,
        input.proof, input.state, input.now);
      process.stdout.write(claim.correlation);
    } catch (error) {
      process.stdout.write(String(error.message));
      process.exitCode = 1;
    }`;
  const env = {
    ...process.env,
    BSO_CONTINUATION_TEST_INPUT: JSON.stringify({
      file: f.file, base: f.base, proof: proofObservation, state,
      now: f.authorizedAt + 1
    })
  };
  const run = () => new Promise(resolve => {
    const child = spawn(process.execPath, ["-e", source], { env, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    child.stdout.on("data", chunk => { stdout += chunk; });
    child.on("close", code => resolve({ code, stdout }));
  });
  const results = await Promise.all([run(), run()]);
  assert.equal(results.filter(result => result.code === 0 &&
    /^[0-9a-f-]{36}$/.test(result.stdout)).length, 1);
  assert.equal(readOperation(f.file, "RecordCall").events.length, 1);
});
