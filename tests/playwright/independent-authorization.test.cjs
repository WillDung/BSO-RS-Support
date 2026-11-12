const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { spawn, spawnSync } = require("node:child_process");
const {
  createAuthorization, loadIndependentAuthorization, claimIndependentAuthorization, digest,
  validateSyntheticIsolationProof, validateOperationCorrelation
} = require("./independent-authorization.cjs");
const {
  ACTIONS, REFERENCE_LABELS, reserveOneShot, isSingleUserDevDirectReadBlocked
} = require("./lifecycle-support.cjs");

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
    candidateId: marker, positionId: binding.positionId, sourceId: binding.sourceId,
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

test("A v4 SingleUserDev proof and exact owner-bound authorization are accepted", t => {
  const f = singleUserDevFixture(t);
  const authorization = f.create();
  const proof = validateSyntheticIsolationProof(f.makeProof(), authorization, now);
  assert.equal(authorization.scope.identityScope, "SINGLE_USER_DEV");
  assert.equal(authorization.scope.syntheticIsolation.actorId, f.base.expectedActorId);
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
  ["wrong marker proof", { candidateId: "99999999-9999-4999-8999-999999999999" }],
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
  assert.match(source, /approval\.identityScope === "SINGLE_USER_DEV" \? approval\.origin/);
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
