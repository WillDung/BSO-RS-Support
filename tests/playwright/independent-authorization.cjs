const fs = require("node:fs");
const path = require("node:path");
const { createHash, randomUUID } = require("node:crypto");
const { readConsumedPreDispatch } = require("./zero-dispatch-recovery.cjs");
const { ACTIONS, REFERENCE_LABELS, GUID } = require("./lifecycle-support.cjs");
const SINGLE_USER_DEV_EXCLUDED_CORRELATIONS = Object.freeze([
  "fe902569-29b8-4af0-89c8-508190769e94"
]);

const check = (condition, code = "UAT_INDEPENDENT_AUTHORIZATION_REFUSED") => {
  if (!condition) throw new Error(code);
};
const hash = value => createHash("sha256").update(value).digest("hex");
const digest = file => hash(fs.readFileSync(file));
const read = file => JSON.parse(fs.readFileSync(file, "utf8"));
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const absolute = file => check(typeof file === "string" && path.isAbsolute(file));
const claimPath = file => `${file}.attempt.jsonl`;
const clone = value => JSON.parse(JSON.stringify(value));

function durableWrite(file, value, flag) {
  const fd = fs.openSync(file, flag, 0o600);
  try {
    fs.writeFileSync(fd, `${JSON.stringify(value)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

function requireInactive(pid) {
  check(Number.isInteger(pid) && pid > 0);
  try {
    process.kill(pid, 0);
  } catch (error) {
    if (error.code === "ESRCH") return;
    throw new Error("UAT_PRECEDING_PROCESS_STATE_UNKNOWN");
  }
  throw new Error("UAT_PRECEDING_ATTEMPT_ACTIVE");
}

function lines(file) {
  const content = fs.readFileSync(file, "utf8");
  check(content.endsWith("\n") && content.length > 1, "UAT_INCOMPLETE_AUDIT_LOG");
  return content.slice(0, -1).split("\n").map(line => JSON.parse(line));
}

function inspectHistory(history) {
  for (const key of ["journalPath", "scopePath", "reportPath"]) absolute(history[key]);
  const file = history.journalPath;
  const original = read(file);
  const prior = readConsumedPreDispatch(file);
  const eligibilityPath = `${file}.recovery-eligible.json`;
  const eligibility = read(eligibilityPath);
  check(eligibility.transition === "RECOVERY_ELIGIBLE" &&
    eligibility.authorizationId === original.authorizationId &&
    eligibility.marker === original.marker && eligibility.dispatches === 0 &&
    eligibility.candidateId === null && eligibility.activeLifecycleProcesses === 0 &&
    eligibility.evidence.length === 6 &&
    eligibility.evidence[5].path === history.scopePath &&
    eligibility.evidence.every(item => digest(item.path) === item.sha256));
  const consumedPath = `${file}.eligible-continuation.jsonl`;
  const consumed = lines(consumedPath);
  check(consumed.length >= 2);
  for (const snapshot of consumed) {
    const { recoveryEligibility, ...business } = snapshot;
    check(same(business, prior) &&
      recoveryEligibility?.transition === "RECOVERY_ELIGIBILITY_CONSUMED_ONCE" &&
      recoveryEligibility.eligibilityHash === digest(eligibilityPath) &&
      same(recoveryEligibility, consumed[0].recoveryEligibility));
    requireInactive(recoveryEligibility.pid);
  }
  requireInactive(prior.recoveryContinuation.pid);
  const report = read(history.reportPath);
  check(report.lifecycle === "FAIL" && same(report.dispatchedOperations, []) &&
    report.baselineCounts === null && report.counts === null,
  "UAT_PRIOR_DISPATCH_OR_AMBIGUITY");
  const scope = read(history.scopePath);
  check(scope.authorizationId === original.authorizationId && scope.ownerMutationApproval === true &&
    scope.maximumCandidates === 1 && scope.noRetries === true && same(scope.actions, ACTIONS));
  const release = read(`${file}.release.json`);
  const paths = [...new Set([file, `${file}.login-recovery-claim`, `${file}.release.json`,
    `${file}.continuation.jsonl`, eligibilityPath, consumedPath, history.scopePath,
    history.reportPath, ...eligibility.evidence.map(item => item.path),
    ...release.evidence.map(item => item.reportPath)])];
  const evidence = paths.map(filePath => ({ path: filePath, sha256: digest(filePath) }));
  check(same(evidence, history.evidence), "UAT_HISTORICAL_EVIDENCE_CHANGED");
  return { original, scope, consumedPath, consumed: consumed.at(-1) };
}

function validateScope(scope, base, oldScope, now, allowHistoricalElevated = false) {
  const profileBinding = scope.syntheticIsolation;
  const bindingKeys = ["actorId", "locationId", "positionId", "scopeId", "sourceId", "taId"];
  const referenceIds = profileBinding && [
    profileBinding.scopeId, profileBinding.positionId, profileBinding.sourceId,
    profileBinding.taId, profileBinding.locationId
  ];
  const bsoScope = typeof scope.expectedUpn === "string" &&
    scope.identityScope === "BSO_ONLY" &&
    GUID.test(scope.actorId || "") &&
    scope.expectedUpn.toLowerCase() !== base.expectedUpn.toLowerCase() &&
    scope.expectedUpn.toLowerCase() !== oldScope.expectedUpn.toLowerCase() &&
    profileBinding && Object.keys(profileBinding).sort().join(",") === bindingKeys.join(",") &&
    bindingKeys.every(key => GUID.test(profileBinding[key] || "")) &&
    profileBinding.actorId.toLowerCase() === scope.actorId.toLowerCase() &&
    new Set(referenceIds.map(value => value.toLowerCase())).size === referenceIds.length;
  const historicalElevatedScope = typeof scope.expectedUpn === "string" && allowHistoricalElevated &&
    scope.identityScope === "OWNER_APPROVED_ELEVATED_FUNCTIONAL_LIFECYCLE" &&
    scope.expectedUpn.toLowerCase() === base.expectedUpn.toLowerCase() &&
    scope.expectedUpn.toLowerCase() === oldScope.expectedUpn.toLowerCase();
  check(scope.ownerMutationApproval === true &&
    /^[a-z0-9][a-z0-9-]{0,95}$/.test(scope.authorizationId || "") &&
    scope.authorizationId !== oldScope.authorizationId &&
    scope.appUrl === base.appUrl && scope.appUrl === oldScope.appUrl &&
    scope.organizationId === base.organizationId && scope.organizationId === oldScope.organizationId &&
    GUID.test(scope.environmentId || "") && scope.environmentId === base.environmentId &&
    scope.environmentName === "VN LMV IT internal DEV" &&
    typeof scope.expectedUpn === "string" &&
    scope.expectedUpn.trim() === scope.expectedUpn && scope.expectedUpn.includes("@") &&
    (bsoScope || historicalElevatedScope) &&
    scope.authenticationCallbackOrigin === oldScope.authenticationCallbackOrigin &&
    scope.maximumCandidates === 1 && scope.maximumInvocations === 1 &&
    scope.noRetries === true && scope.retries === 0 && scope.callOutcome === "Answered" &&
    scope.readbackOnlyAfterOperations === true &&
    same(scope.actions, ACTIONS) && same(scope.referenceLabels, REFERENCE_LABELS),
  "UAT_INDEPENDENT_SCOPE_OR_TARGET_MISMATCH");
  check(Number.isFinite(Date.parse(scope.expiresAt)) &&
    Date.parse(scope.expiresAt) > now, "UAT_INDEPENDENT_AUTHORIZATION_EXPIRED");
}

function validateRecord(record, base, now, allowHistoricalElevated = false) {
  if (record.scope?.identityScope === "SINGLE_USER_DEV") {
    const createdAt = Date.parse(record.createdAt);
    const authorizedAt = Date.parse(record.authorizedAt);
    const expiresAt = Date.parse(record.scope.expiresAt);
    const maximumWindow = 2 * 60 * 60 * 1000;
    check(record.version === 2 && record.kind === "OWNER_AUTHORIZED_SINGLE_USER_DEV_ATTEMPT" &&
      typeof record.ownerDecisionText === "string" && record.ownerDecisionText.trim().length > 0 &&
      Number.isFinite(createdAt) && createdAt <= now &&
      Number.isFinite(authorizedAt) && authorizedAt <= createdAt &&
      createdAt - authorizedAt <= maximumWindow &&
      GUID.test(record.attemptId || "") && record.history === undefined &&
      record.previousAuthorizationFile === undefined && record.predecessor === undefined,
    "UAT_SINGLE_USER_DEV_AUTHORIZATION_INVALID");
    check(Number.isFinite(expiresAt) && expiresAt > now &&
      expiresAt - authorizedAt <= maximumWindow, "UAT_INDEPENDENT_AUTHORIZATION_EXPIRED");
    validateSingleUserDevScope(record.scope, base, record.marker, record.candidateName,
      record.candidateEmail, record.authorizedAt, now);
    return null;
  }
  const createdAt = Date.parse(record.createdAt);
  const authorizedAt = Date.parse(record.authorizedAt);
  const expiresAt = Date.parse(record.scope?.expiresAt);
  const maximumWindow = 2 * 60 * 60 * 1000;
  const requireBoundedWindow = !allowHistoricalElevated ||
    record.scope?.identityScope === "BSO_ONLY";
  check(record.version === 1 && record.kind === "OWNER_AUTHORIZED_INDEPENDENT_ATTEMPT" &&
    typeof record.ownerDecisionText === "string" && record.ownerDecisionText.trim().length > 0 &&
    Number.isFinite(createdAt) && createdAt <= now &&
    Number.isFinite(authorizedAt) && authorizedAt <= createdAt &&
    Number.isFinite(expiresAt) &&
    GUID.test(record.attemptId || ""));
  check(!requireBoundedWindow ||
    (createdAt - authorizedAt <= maximumWindow && expiresAt - authorizedAt <= maximumWindow),
  "UAT_INDEPENDENT_AUTHORIZATION_WINDOW_INVALID");
  const history = inspectHistory(record.history);
  validateScope(record.scope, base, history.scope, now, allowHistoricalElevated);
  check(record.marker === history.original.marker &&
    record.candidateName === history.original.candidateName &&
    record.candidateEmail === history.original.candidateEmail,
  "UAT_ORIGINAL_MARKER_CHANGED");
  if (record.scope.identityScope === "BSO_ONLY") {
    check(record.scope.actorId.toLowerCase() === record.scope.syntheticIsolation.actorId.toLowerCase() &&
      record.scope.syntheticIsolation.scopeId.toLowerCase() === record.marker.toLowerCase(),
    "UAT_SYNTHETIC_PROFILE_BINDING_MISMATCH");
  }
  return history;
}

function validateSingleUserDevScope(scope, base, marker, candidateName, candidateEmail, authorizedAtText, now) {
  const binding = scope.syntheticIsolation;
  const bindingKeys = ["actorId", "candidateId", "locationId", "positionId", "scopeId", "sourceId", "taId"];
  const referenceIds = binding && [
    binding.positionId, binding.sourceId, binding.taId, binding.locationId
  ];
  check(scope.ownerMutationApproval === true &&
    /^[a-z0-9][a-z0-9-]{0,95}$/.test(scope.authorizationId || "") &&
    scope.appUrl === base.appUrl && scope.organizationId === base.organizationId &&
    scope.environmentId === base.environmentId &&
    scope.environmentName === "VN LMV IT internal DEV" &&
    scope.identityScope === "SINGLE_USER_DEV" &&
    typeof scope.expectedUpn === "string" &&
    scope.expectedUpn.toLowerCase() === base.expectedUpn.toLowerCase() &&
    binding && Object.keys(binding).sort().join(",") === bindingKeys.join(",") &&
    bindingKeys.every(key => GUID.test(binding[key] || "")) &&
    binding.actorId.toLowerCase() === scope.actorId?.toLowerCase() &&
    (!base.expectedActorId || binding.actorId.toLowerCase() === base.expectedActorId.toLowerCase()) &&
    binding.candidateId.toLowerCase() === marker?.toLowerCase() &&
    new Set([binding.actorId, binding.scopeId, binding.candidateId,
      ...referenceIds].map(value => value.toLowerCase())).size === 7 &&
    candidateName === `[SYNTHETIC-E2E] Playwright ${marker}` &&
    candidateEmail === `pw-${marker}@example.invalid` &&
    scope.maximumCandidates === 1 && scope.maximumInvocations === 1 &&
    scope.noRetries === true && scope.retries === 0 &&
    scope.callOutcome === "Answered" && scope.readbackOnlyAfterOperations === true &&
    same(scope.actions, ACTIONS) && same(scope.referenceLabels, REFERENCE_LABELS) &&
    Array.isArray(scope.excludedCorrelations) &&
    scope.excludedCorrelations.every(value => GUID.test(value)) &&
    new Set(scope.excludedCorrelations.map(value => value.toLowerCase())).size ===
      scope.excludedCorrelations.length &&
    SINGLE_USER_DEV_EXCLUDED_CORRELATIONS.every(correlation =>
      scope.excludedCorrelations.some(value => value.toLowerCase() === correlation)),
  "UAT_SINGLE_USER_DEV_SCOPE_OR_TARGET_MISMATCH");
  const authorizedAt = Date.parse(authorizedAtText || "");
  const expiresAt = Date.parse(scope.expiresAt || "");
  const maximumWindow = 2 * 60 * 60 * 1000;
  check(Number.isFinite(authorizedAt) && authorizedAt <= now &&
    Number.isFinite(expiresAt) && expiresAt > now &&
    now - authorizedAt <= maximumWindow && expiresAt - authorizedAt <= maximumWindow,
  "UAT_INDEPENDENT_AUTHORIZATION_EXPIRED");
}

function validateSyntheticIsolationProof(observation, authorization, now = Date.now()) {
  const zeroGuid = "00000000-0000-0000-0000-000000000000";
  check(observation && typeof observation === "object" &&
    GUID.test(observation.correlationId || "") &&
    observation.correlationId.toLowerCase() !== zeroGuid &&
    typeof observation.contract === "string" && observation.contract.length > 0 &&
    observation.contract.length <= 4096,
  "UAT_SYNTHETIC_PROOF_OBSERVATION_INVALID");
  let proof;
  try {
    proof = JSON.parse(observation.contract);
  } catch {
    throw new Error("UAT_SYNTHETIC_PROOF_RESPONSE_INVALID");
  }
  const binding = authorization.scope.syntheticIsolation;
  if (authorization.scope.identityScope === "SINGLE_USER_DEV") {
    const expected = {
      organizationId: authorization.scope.organizationId,
      environmentId: authorization.scope.environmentId,
      actorId: binding.actorId,
      scopeId: binding.scopeId,
      candidateId: authorization.marker,
      positionId: binding.positionId,
      sourceId: binding.sourceId,
      taId: binding.taId,
      locationId: binding.locationId
    };
    const validUntil = Date.parse(proof?.validUntil);
    check(proof?.version === 4 && proof.boundary === "SingleUserDevCandidateCoreApi" &&
      proof.mode === "SingleUserDev" && proof.nativeWritesDenied === false &&
      proof.scopedReads === true && proof.globalGuardsRequired === false &&
      proof.readback === "CallerOwnedScope" && proof.calendarEnabled === false &&
      !authorization.scope.excludedCorrelations.some(value =>
        value.toLowerCase() === observation.correlationId.toLowerCase()) &&
      Object.entries(expected).every(([name, value]) =>
        GUID.test(proof[name] || "") && proof[name].toLowerCase() === value.toLowerCase()) &&
      Number.isFinite(validUntil) && validUntil > now + 30_000 && validUntil <= now + 125_000,
    "UAT_SINGLE_USER_DEV_PROOF_SCOPE_OR_FRESHNESS_MISMATCH");
    return {
      correlationId: observation.correlationId.toLowerCase(),
      contract: observation.contract
    };
  }
  const expected = {
    organizationId: authorization.scope.organizationId,
    environmentId: authorization.scope.environmentId,
    actorId: authorization.scope.actorId,
    scopeId: binding.scopeId,
    candidateId: authorization.marker,
    positionId: binding.positionId,
    sourceId: binding.sourceId,
    taId: binding.taId,
    locationId: binding.locationId
  };
  const validUntil = Date.parse(proof?.validUntil);
  check(proof?.version === 2 && proof.boundary === "ScopedCandidateCoreApi" &&
    proof.nativeWritesDenied === true && proof.readback === "CallerOwnedScope" &&
    proof.calendarEnabled === false &&
    Object.entries(expected).every(([name, value]) =>
      GUID.test(proof[name] || "") && proof[name].toLowerCase() === value.toLowerCase()) &&
    proof.scopeId.toLowerCase() === proof.candidateId.toLowerCase() &&
    Number.isFinite(validUntil) && validUntil > now + 30_000 && validUntil <= now + 125_000,
  "UAT_SYNTHETIC_PROOF_SCOPE_OR_FRESHNESS_MISMATCH");
  return {
    correlationId: observation.correlationId.toLowerCase(),
    contract: observation.contract
  };
}

function readAttempt(file, authorization) {
  const events = lines(file);
  const approval = read(authorization);
  const first = events[0];
  const initial = {
    authorizationId: approval.scope.authorizationId, attemptId: approval.attemptId,
    marker: approval.marker, candidateName: approval.candidateName,
    candidateEmail: approval.candidateEmail, candidateId: null
  };
  if (["BSO_ONLY", "SINGLE_USER_DEV"].includes(approval.scope.identityScope)) {
    initial.syntheticProof = validateSyntheticIsolationProof(
      first.record.syntheticProof, approval, Date.parse(first.at));
  }
  initial.attempts = [];
  initial.status = "RESERVED_NO_DISPATCH";
  let previousHash = null;
  for (const [index, event] of events.entries()) {
    const { sha256, ...entry } = event;
    check(sha256 === hash(JSON.stringify(entry)) && entry.previousHash === previousHash &&
      entry.sequence === index && entry.authorizationHash === digest(authorization) &&
      entry.type === (index === 0 ? "ATTEMPT_CLAIMED_ONCE" : "ATTEMPT_STATE_APPENDED"),
    "UAT_ATTEMPT_AUDIT_INTEGRITY_FAILED");
    check(Number.isInteger(entry.pid) && entry.pid > 0 && entry.pid === events[0].pid);
    if (index === 0) check(same(entry.record, initial));
    else validateSnapshot(entry.record, events[index - 1].record, approval);
    previousHash = sha256;
  }
  return events;
}

function predecessor(record, base, history, now = Date.now()) {
  if (!record.previousAuthorizationFile) {
    return {
      authorizationId: history.original.authorizationId,
      attemptId: history.consumed.recoveryEligibility.eligibilityHash,
      claimPath: history.consumedPath, sha256: digest(history.consumedPath)
    };
  }
  absolute(record.previousAuthorizationFile);
  const prior = read(record.previousAuthorizationFile);
  // Expiry only governs new invocation, not the validity of completed historical evidence.
  validateRecord(prior, base, Date.parse(prior.createdAt), true);
  const priorHistory = inspectHistory(prior.history);
  check(same(prior.history, record.history) && prior.marker === record.marker &&
    prior.scope.authorizationId !== record.scope.authorizationId);
  const linked = predecessor(prior, base, priorHistory, now);
  check(same(linked, prior.predecessor));
  verifyLink(record.previousAuthorizationFile, prior);
  const file = claimPath(record.previousAuthorizationFile);
  if (!fs.existsSync(file)) {
    check(Date.parse(prior.scope.expiresAt) <= now,
      "UAT_PRECEDING_AUTHORIZATION_NOT_EXPIRED");
    return {
      authorizationId: prior.scope.authorizationId, attemptId: prior.attemptId,
      claimPath: null, linkPath: record.previousAuthorizationFile,
      sha256: digest(record.previousAuthorizationFile), state: "EXPIRED_UNCLAIMED"
    };
  }
  const events = readAttempt(file, record.previousAuthorizationFile);
  for (const event of events) {
    check(event.record.candidateId === null && same(event.record.attempts, []),
      "UAT_PRIOR_DISPATCH_OR_AMBIGUITY");
  }
  const last = events.at(-1);
  check(events.length >= 2 && last.record.status === "STOPPED_NO_RETRY_RECONCILE_ONLY",
    "UAT_PRECEDING_ATTEMPT_NOT_STOPPED");
  requireInactive(last.pid);
  return {
    authorizationId: prior.scope.authorizationId, attemptId: prior.attemptId,
    claimPath: file, sha256: digest(file)
  };
}

function verifyLink(file, record) {
  const linkPath = record.predecessor.linkPath || record.predecessor.claimPath;
  const link = read(`${linkPath}.successor-authorization.json`);
  check(link.authorizationFile === file && link.authorizationHash === digest(file) &&
    link.authorizationId === record.scope.authorizationId && link.attemptId === record.attemptId,
  "UAT_INDEPENDENT_CHAIN_LINK_MISMATCH");
}

function loadIndependentAuthorization(file, base, now = Date.now()) {
  absolute(file);
  check(fs.existsSync(file), "UAT_INDEPENDENT_AUTHORIZATION_MISSING");
  const record = read(file);
  if (record.scope?.identityScope === "SINGLE_USER_DEV") {
    validateRecord(record, base, now);
    check(file === path.join(path.dirname(file),
      `${record.scope.authorizationId}.authorization.json`), "UAT_AUTHORIZATION_PATH_MISMATCH");
    const slotPath = path.join(path.dirname(file),
      `singleuserdev-${record.marker.toLowerCase()}.authorization-slot.json`);
    const slot = read(slotPath);
    check(slot.authorizationFile === file && slot.authorizationHash === digest(file) &&
      slot.authorizationId === record.scope.authorizationId &&
      slot.attemptId === record.attemptId && slot.marker === record.marker,
    "UAT_SINGLE_USER_DEV_AUTHORIZATION_SLOT_MISMATCH");
    return record;
  }
  const history = validateRecord(record, base, now);
  check(file === path.join(path.dirname(record.history.journalPath),
    `${record.scope.authorizationId}.authorization.json`), "UAT_AUTHORIZATION_PATH_MISMATCH");
  check(record.scope.identityScope === "BSO_ONLY", "UAT_BSO_ONLY_AUTHORIZATION_REQUIRED");
  check(same(record.predecessor, predecessor(record, base, history, now)),
    "UAT_PREDECESSOR_EVIDENCE_CHANGED");
  verifyLink(file, record);
  return record;
}

function createAuthorization(file, request, base, now = Date.now()) {
  absolute(file);
  check(!fs.existsSync(file), "UAT_AUTHORIZATION_RECORD_ALREADY_EXISTS");
  if (request.scope?.identityScope === "SINGLE_USER_DEV") {
    const record = {
      version: 2, kind: "OWNER_AUTHORIZED_SINGLE_USER_DEV_ATTEMPT",
      createdAt: new Date(now).toISOString(), authorizedAt: request.authorizedAt,
      ownerDecisionText: request.ownerDecisionText, attemptId: randomUUID(),
      scope: clone(request.scope), marker: request.marker,
      candidateName: request.candidateName, candidateEmail: request.candidateEmail
    };
    validateRecord(record, base, now);
    check(file === path.join(path.dirname(file),
      `${record.scope.authorizationId}.authorization.json`), "UAT_AUTHORIZATION_PATH_MISMATCH");
    const bytes = `${JSON.stringify(record)}\n`;
    const slotPath = path.join(path.dirname(file),
      `singleuserdev-${record.marker.toLowerCase()}.authorization-slot.json`);
    durableWrite(slotPath, {
      authorizationFile: file, authorizationHash: hash(bytes),
      authorizationId: record.scope.authorizationId, attemptId: record.attemptId,
      marker: record.marker, at: record.createdAt
    }, "wx");
    durableWrite(file, record, "wx");
    return loadIndependentAuthorization(file, base, now);
  }
  const history = inspectHistory(request.history);
  const record = {
    version: 1, kind: "OWNER_AUTHORIZED_INDEPENDENT_ATTEMPT",
    createdAt: new Date(now).toISOString(), authorizedAt: request.authorizedAt,
    ownerDecisionText: request.ownerDecisionText, attemptId: randomUUID(),
    scope: clone(request.scope), history: clone(request.history),
    previousAuthorizationFile: request.previousAuthorizationFile || null,
    marker: history.original.marker, candidateName: history.original.candidateName,
    candidateEmail: history.original.candidateEmail
  };
  validateRecord(record, base, now);
  check(file === path.join(path.dirname(record.history.journalPath),
    `${record.scope.authorizationId}.authorization.json`), "UAT_AUTHORIZATION_PATH_MISMATCH");
  record.predecessor = predecessor(record, base, history, now);
  const bytes = `${JSON.stringify(record)}\n`;
  // A permanent successor slot serializes different authorizations sharing one consumed attempt.
  // If either write is interrupted, the partial reservation stays blocked; nothing is released.
  const predecessorLinkPath = record.predecessor.linkPath || record.predecessor.claimPath;
  check(typeof predecessorLinkPath === "string" && path.isAbsolute(predecessorLinkPath));
  durableWrite(`${predecessorLinkPath}.successor-authorization.json`, {
    authorizationFile: file, authorizationHash: hash(bytes),
    authorizationId: record.scope.authorizationId, attemptId: record.attemptId,
    at: record.createdAt
  }, "wx");
  durableWrite(file, record, "wx");
  return loadIndependentAuthorization(file, base, now);
}

function requireOneInvocation(configuration) {
  check(configuration && configuration.workers === 1 && configuration.retries === 0 &&
    configuration.repeatEach === 1 && configuration.retry === 0 &&
    configuration.repeatEachIndex === 0, "UAT_ONE_SHOT_RUNNER_CONFIGURATION_REQUIRED");
}

function validateSnapshot(record, previous, authorization) {
  check(same(Object.keys(record).sort(), Object.keys(previous).sort()));
  for (const key of ["authorizationId", "attemptId", "marker", "candidateName",
    "candidateEmail", "syntheticProof"]) {
    check(same(record[key], previous[key]), "UAT_ATTEMPT_IDENTITY_CHANGED");
  }
  check(record.marker === authorization.marker && Array.isArray(record.attempts) &&
    record.attempts.length <= ACTIONS.length &&
    record.attempts.length >= previous.attempts.length &&
    record.attempts.length <= previous.attempts.length + 1 &&
    (previous.candidateId === null || record.candidateId === previous.candidateId) &&
    (record.candidateId === null || GUID.test(record.candidateId)) &&
    ["RESERVED_NO_DISPATCH", "DISPATCH_RESERVED_OUTCOME_UNKNOWN",
      "STOPPED_NO_RETRY_RECONCILE_ONLY", "COMPLETED_DO_NOT_RERUN"].includes(record.status));
  const correlations = new Set();
  if (record.attempts.length > previous.attempts.length) {
    check(previous.attempts.every(attempt => attempt.outcome === "APPLIED"),
      "UAT_PRIOR_DISPATCH_OR_AMBIGUITY");
  }
  for (const [index, attempt] of record.attempts.entries()) {
    check(attempt.action === ACTIONS[index] && GUID.test(attempt.correlation) &&
      !correlations.has(attempt.correlation.toLowerCase()) &&
      ["DISPATCH_RESERVED_OUTCOME_UNKNOWN", "APPLIED"].includes(attempt.outcome));
    validateOperationCorrelation(attempt.correlation, {
      ...record, attempts: record.attempts.slice(0, index)
    }, authorization);
    correlations.add(attempt.correlation.toLowerCase());
    const before = previous.attempts[index];
    if (before) {
      if (before.outcome === "APPLIED") check(same(before, attempt));
      else {
        const { response, outcome, ...identity } = attempt;
        const { outcome: ignored, ...oldIdentity } = before;
        check(same(identity, oldIdentity));
        if (outcome === "APPLIED") check(response?.ResultCode === "Applied");
      }
    } else {
      check(attempt.outcome === "DISPATCH_RESERVED_OUTCOME_UNKNOWN" &&
        record.attempts.slice(0, index).every(item => item.outcome === "APPLIED") &&
        record.status === "DISPATCH_RESERVED_OUTCOME_UNKNOWN");
    }
  }
  check(!["STOPPED_NO_RETRY_RECONCILE_ONLY", "COMPLETED_DO_NOT_RERUN"].includes(previous.status),
    "UAT_TERMINAL_ATTEMPT_NO_CONTINUATION");
  if (record.candidateId !== null) check(record.attempts[0]?.outcome === "APPLIED");
  if (record.status === "COMPLETED_DO_NOT_RERUN") {
    check(record.candidateId !== null && record.attempts.length === 4 &&
      record.attempts.every(attempt => attempt.outcome === "APPLIED"));
  }
}

function claimIndependentAuthorization(file, base, configuration, proofObservation, now = Date.now()) {
  requireOneInvocation(configuration);
  const authorization = loadIndependentAuthorization(file, base, now);
  check(["BSO_ONLY", "SINGLE_USER_DEV"].includes(authorization.scope.identityScope),
    "UAT_UNSUPPORTED_AUTHORIZATION_SCOPE");
  const syntheticProof = validateSyntheticIsolationProof(proofObservation, authorization, now);
  const record = {
    authorizationId: authorization.scope.authorizationId, attemptId: authorization.attemptId,
    marker: authorization.marker, candidateName: authorization.candidateName,
    candidateEmail: authorization.candidateEmail, candidateId: null, syntheticProof,
    attempts: [], status: "RESERVED_NO_DISPATCH"
  };
  const eventsFile = claimPath(file);
  const authorizationHash = digest(file);
  let previousHash = null;
  let sequence = 0;
  let saved = clone(record);
  const append = type => {
    const entry = {
      type, sequence, previousHash, authorizationHash,
      at: new Date(sequence === 0 ? now : Date.now()).toISOString(),
      pid: process.pid, record: clone(record)
    };
    const event = { ...entry, sha256: hash(JSON.stringify(entry)) };
    durableWrite(eventsFile, event, sequence === 0 ? "wx" : "a");
    previousHash = event.sha256;
    sequence++;
    saved = clone(record);
  };
  append("ATTEMPT_CLAIMED_ONCE");
  return {
    record,
    save: () => {
      const last = readAttempt(eventsFile, file).at(-1);
      check(last.sha256 === previousHash && last.sequence === sequence - 1);
      validateSnapshot(record, saved, authorization);
      append("ATTEMPT_STATE_APPENDED");
    }
  };
}

function validateOperationCorrelation(correlationId, record, authorization) {
  const proofCorrelation = record.syntheticProof?.correlationId?.toLowerCase();
  const excluded = authorization.scope.excludedCorrelations || [];
  check(GUID.test(correlationId || "") &&
    correlationId.toLowerCase() !== "00000000-0000-0000-0000-000000000000" &&
    correlationId.toLowerCase() !== proofCorrelation &&
    !excluded.some(value => value.toLowerCase() === correlationId.toLowerCase()) &&
    !record.attempts.some(attempt => attempt.correlation.toLowerCase() === correlationId.toLowerCase()),
  "UAT_OPERATION_CORRELATION_REPLAY_REJECTED");
  return correlationId.toLowerCase();
}

module.exports = {
  createAuthorization, loadIndependentAuthorization, claimIndependentAuthorization,
  requireOneInvocation, inspectHistory, digest, validateSyntheticIsolationProof,
  validateOperationCorrelation
};

if (require.main === module) {
  try {
    check(process.argv.length === 4 && process.argv[2] === "--create" &&
      !process.env.BSO_UAT_RESUME_ZERO_DISPATCH, "UAT_LOCAL_AUTHORIZATION_CREATE_USAGE");
    absolute(process.argv[3]);
    const request = read(process.argv[3]);
    const { loadApproval, protectDirectory, authDirectory } = require("./local-settings.cjs");
    const base = { ...loadApproval(), environmentId: process.env.BSO_UAT_ENVIRONMENT_ID };
    protectDirectory(authDirectory);
    const file = path.join(authDirectory, `${request.scope.authorizationId}.authorization.json`);
    createAuthorization(file, request, base);
    console.log("INDEPENDENT_AUTHORIZATION_CREATED_CLAIM_UNCONSUMED");
  } catch (error) {
    console.error(String(error.message).match(/\bUAT_[A-Z_]+\b/)?.[0] ||
      (error.code === "EEXIST" ? "UAT_AUTHORIZATION_OR_SUCCESSOR_ALREADY_RESERVED" :
        "UAT_LOCAL_AUTHORIZATION_CREATION_FAILED"));
    process.exitCode = 1;
  }
}
