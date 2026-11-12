const fs = require("node:fs");
const path = require("node:path");
const { createHash, randomUUID } = require("node:crypto");
const {
  loadIndependentAuthorization, validateSyntheticIsolationProof, readAttempt, digest
} = require("./independent-authorization.cjs");
const { GUID, STATUSES } = require("./lifecycle-support.cjs");

const ACTIONS = Object.freeze(["RecordCall", "ProceedToScheduling"]);
const RECEIPT_UNAVAILABLE = "NOT_AVAILABLE_VIA_SINGLE_USER_DEV_SCOPED_API";
const hash = value => createHash("sha256").update(value).digest("hex");
const json = value => JSON.stringify(value);
const read = file => JSON.parse(fs.readFileSync(file, "utf8"));
const same = (left, right) => json(left) === json(right);
const canonical = value => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === "object"
    ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]))
    : value;
const canonicalSame = (left, right) => same(canonical(left), canonical(right));
const fail = code => { throw new Error(code); };
const requireCondition = (condition, code) => { if (!condition) fail(code); };
const linkPath = predecessorFile => `${predecessorFile}.continuation-authorization.json`;
const operationPath = (file, action) => `${file}.${action}.jsonl`;

function durableWrite(file, value, flag = "wx") {
  const fd = fs.openSync(file, flag, 0o600);
  try {
    fs.writeFileSync(fd, `${json(value)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

function exclusiveWrite(file, value, code) {
  try {
    durableWrite(file, value);
  } catch (error) {
    if (error.code === "EEXIST") fail(code);
    throw error;
  }
}

function appendLine(file, value) {
  const fd = fs.openSync(file, "a");
  try {
    fs.writeFileSync(fd, `${json(value)}\n`);
    fs.fsyncSync(fd);
  } finally {
    fs.closeSync(fd);
  }
}

function readJournal(file, authorizationHash, action) {
  const text = fs.readFileSync(file, "utf8");
  requireCondition(text.endsWith("\n") && text.length > 1,
    "UAT_CONTINUATION_JOURNAL_INCOMPLETE");
  const events = text.slice(0, -1).split("\n").map(line => JSON.parse(line));
  let previousHash = null;
  for (const [sequence, event] of events.entries()) {
    const { sha256, ...entry } = event;
    requireCondition(event.sequence === sequence && event.previousHash === previousHash &&
      event.authorizationHash === authorizationHash &&
      (action === undefined || event.action === action) &&
      hash(json(entry)) === sha256,
    "UAT_CONTINUATION_JOURNAL_INVALID");
    previousHash = sha256;
  }
  return events;
}

function requireInactive(pid) {
  requireCondition(Number.isInteger(pid) && pid > 0,
    "UAT_CONTINUATION_PROCESS_STATE_UNKNOWN");
  try {
    process.kill(pid, 0);
  } catch (error) {
    if (error.code === "ESRCH") return;
    fail("UAT_CONTINUATION_PROCESS_STATE_UNKNOWN");
  }
  fail("UAT_CONTINUATION_PREDECESSOR_ACTIVE");
}

function predecessorSlotPath(file, authorization) {
  return authorization.version === 2
    ? path.join(path.dirname(file),
      `singleuserdev-${authorization.marker.toLowerCase()}.authorization-slot.json`)
    : authorization.generationSlotPath;
}

function loadPredecessor(file, base, now) {
  requireCondition(path.isAbsolute(file), "UAT_CONTINUATION_PREDECESSOR_PATH_INVALID");
  const raw = read(file);
  const expiresAt = Date.parse(raw.scope?.expiresAt || "");
  requireCondition(Number.isFinite(expiresAt) && expiresAt <= now,
    "UAT_CONTINUATION_PREDECESSOR_NOT_EXPIRED");
  const authorization = loadIndependentAuthorization(file, base, expiresAt - 1);
  const journalFile = `${file}.attempt.jsonl`;
  requireCondition(fs.existsSync(journalFile),
    "UAT_CONTINUATION_PREDECESSOR_JOURNAL_MISSING");
  const events = readAttempt(journalFile, file);
  const final = events.at(-1);
  const record = final?.record;
  requireCondition(final?.type === "ATTEMPT_STATE_APPENDED" &&
    record?.status === "STOPPED_NO_RETRY_RECONCILE_ONLY" &&
    record.authorizationId === authorization.scope.authorizationId &&
    record.attemptId === authorization.attemptId &&
    record.marker === authorization.marker &&
    record.candidateId === null &&
    record.attempts?.length === 1 &&
    record.attempts[0].action === "CreateCandidate" &&
    record.attempts[0].classification === "APPROVED_BUSINESS_OPERATION" &&
    record.attempts[0].outcome === "DISPATCH_RESERVED_OUTCOME_UNKNOWN" &&
    GUID.test(record.attempts[0].correlation || ""),
  "UAT_CONTINUATION_PREDECESSOR_DISPATCH_MISMATCH");
  requireInactive(final.pid);
  const slot = predecessorSlotPath(file, authorization);
  requireCondition(slot && fs.existsSync(slot),
    "UAT_CONTINUATION_PREDECESSOR_SLOT_MISSING");
  return {
    authorization, events, journalFile, journalHash: digest(journalFile),
    slotFile: slot, slotHash: digest(slot), runnerPid: final.pid,
    createCorrelation: record.attempts[0].correlation.toLowerCase(),
    proofCorrelation: events[0].record.syntheticProof.correlationId.toLowerCase()
  };
}

function validateReadback(authorization, state, phase, callCorrelation = null,
  operationCorrelation = null) {
  const fields = [
    "candidateCount", "candidateId", "marker", "name", "email", "createCorrelation",
    "status", "ownerId", "positionId", "sourceId", "taId", "callCount", "scheduleCount",
    "historyCount", "callOutcome", "callCorrelation", "callId", "history"
  ];
  requireCondition(state && canonicalSame(Object.keys(state).sort(), fields.slice().sort()),
    "UAT_CONTINUATION_CANDIDATE_READBACK_SHAPE_MISMATCH");
  requireCondition(Number.isInteger(state.candidateCount) && state.candidateCount === 1 &&
    GUID.test(state.candidateId || "") &&
    state.candidateId.toLowerCase() === authorization.scope.candidateId.toLowerCase(),
  "UAT_CONTINUATION_CANDIDATE_ID_MISMATCH");
  requireCondition(state.marker === authorization.marker,
    "UAT_CONTINUATION_MARKER_MISMATCH");
  requireCondition(state.name === authorization.candidateName,
    "UAT_CONTINUATION_CANDIDATE_NAME_MISMATCH");
  requireCondition(state.email === authorization.candidateEmail,
    "UAT_CONTINUATION_CANDIDATE_EMAIL_MISMATCH");
  requireCondition(state.createCorrelation.toLowerCase() ===
    authorization.scope.createCorrelation.toLowerCase(),
  "UAT_CONTINUATION_CREATE_CORRELATION_MISMATCH");
  requireCondition(GUID.test(state.ownerId || "") &&
    state.ownerId.toLowerCase() === authorization.scope.actorId.toLowerCase() &&
    state.positionId.toLowerCase() ===
      authorization.scope.syntheticIsolation.positionId.toLowerCase() &&
    state.sourceId.toLowerCase() ===
      authorization.scope.syntheticIsolation.sourceId.toLowerCase() &&
    state.taId.toLowerCase() === authorization.scope.syntheticIsolation.taId.toLowerCase(),
  "UAT_CONTINUATION_CANDIDATE_SCOPE_MISMATCH");
  requireCondition(Array.isArray(state.history) && state.history.length === state.historyCount &&
    Number.isInteger(state.callCount) && Number.isInteger(state.scheduleCount),
  "UAT_CONTINUATION_CANDIDATE_COUNTS_MISMATCH");

  const historyValid = (row, previousStatus, newStatus, correlation) =>
    row && canonicalSame(Object.keys(row).sort(),
      ["id", "correlation", "previousStatus", "newStatus", "actorId"].sort()) &&
    GUID.test(row.id || "") && GUID.test(row.actorId || "") &&
    row.actorId.toLowerCase() === authorization.scope.actorId.toLowerCase() &&
    row.previousStatus === previousStatus && row.newStatus === newStatus &&
    row.correlation.toLowerCase() === correlation.toLowerCase();

  if (phase === "BEFORE_CALL") {
    requireCondition(state.status === STATUSES[0] && state.callCount === 0 &&
      state.scheduleCount === 0 && state.historyCount === 0 &&
      state.callOutcome === null && state.callCorrelation === null &&
      state.callId === null && state.history.length === 0,
    "UAT_CONTINUATION_PRE_CALL_STATE_MISMATCH");
  } else if (phase === "BEFORE_PROCEED") {
    requireCondition(GUID.test(callCorrelation || "") &&
      state.status === STATUSES[1] && state.callCount === 1 &&
      state.scheduleCount === 0 && state.historyCount === 1 &&
      state.callOutcome === 100010000 &&
      state.callCorrelation.toLowerCase() === callCorrelation.toLowerCase() &&
      GUID.test(state.callId || "") &&
      historyValid(state.history[0], STATUSES[0], STATUSES[1], callCorrelation),
    "UAT_CONTINUATION_PRE_PROCEED_STATE_MISMATCH");
  } else if (phase === "AFTER_CALL") {
    requireCondition(state.status === STATUSES[1] && state.callCount === 1 &&
      state.scheduleCount === 0 && state.historyCount === 1 &&
      state.callOutcome === 100010000 &&
      state.callCorrelation.toLowerCase() === callCorrelation?.toLowerCase() &&
      GUID.test(state.callId || "") &&
      historyValid(state.history[0], STATUSES[0], STATUSES[1], callCorrelation),
    "UAT_CONTINUATION_CALL_READBACK_MISMATCH");
  } else if (phase === "AFTER_PROCEED") {
    requireCondition(GUID.test(callCorrelation || "") &&
      GUID.test(operationCorrelation || "") &&
      state.status === STATUSES[2] && state.callCount === 1 &&
      state.scheduleCount === 0 && state.historyCount === 2 &&
      state.callOutcome === 100010000 &&
      state.callCorrelation.toLowerCase() === callCorrelation.toLowerCase() &&
      GUID.test(state.callId || "") &&
      historyValid(state.history[0], STATUSES[0], STATUSES[1], callCorrelation) &&
      historyValid(state.history[1], STATUSES[1], STATUSES[2],
        operationCorrelation),
    "UAT_CONTINUATION_PROCEED_READBACK_MISMATCH");
  } else {
    fail("UAT_CONTINUATION_READBACK_PHASE_INVALID");
  }
  return state;
}

function expectedScope(prior, request, createCorrelation, proofCorrelation,
  predecessorProofCorrelation) {
  const scope = JSON.parse(json(prior.scope));
  scope.authorizationId = request.authorizationId;
  scope.expiresAt = request.expiresAt;
  scope.actions = [...ACTIONS];
  scope.maximumCandidates = 0;
  scope.maximumInvocations = ACTIONS.length;
  scope.candidateId = request.candidateId.toLowerCase();
  scope.createCorrelation = createCorrelation;
  scope.excludedCorrelations = [...new Set([
    ...(prior.scope.excludedCorrelations || []).map(value => value.toLowerCase()),
    createCorrelation,
    predecessorProofCorrelation,
    proofCorrelation
  ])];
  return scope;
}

function validateReconciliation(predecessor, evidence, base, authorizedAt, now) {
  const keys = ["version", "checkedAt", "whoAmI", "proofObservation", "candidate",
    "counts", "receiptReadback"];
  const readbackKeys = [
    "candidateCount", "candidateId", "marker", "name", "email", "createCorrelation",
    "status", "ownerId", "positionId", "sourceId", "taId", "callCount", "scheduleCount",
    "historyCount", "callOutcome", "callCorrelation", "callId", "history"
  ];
  requireCondition(evidence && canonicalSame(Object.keys(evidence).sort(), keys.sort()) &&
    canonicalSame(Object.keys(evidence.whoAmI || {}).sort(), ["actorId", "organizationId"].sort()) &&
    canonicalSame(Object.keys(evidence.counts || {}).sort(),
      ["candidates", "calls", "schedules", "history"].sort()) &&
    canonicalSame(Object.keys(evidence.candidate || {}).sort(), readbackKeys.sort()),
  "UAT_CONTINUATION_RECONCILIATION_SHAPE_MISMATCH");
  const checkedAt = Date.parse(evidence.checkedAt || "");
  requireCondition(evidence.version === 1 && Number.isFinite(checkedAt) &&
    checkedAt <= authorizedAt && authorizedAt - checkedAt <= 120_000 &&
    checkedAt <= now && now - checkedAt <= 120_000 &&
    evidence.receiptReadback === RECEIPT_UNAVAILABLE &&
    canonicalSame(evidence.counts, { candidates: 1, calls: 0, schedules: 0, history: 0 }) &&
    evidence.whoAmI.organizationId.toLowerCase() ===
      predecessor.authorization.scope.organizationId.toLowerCase() &&
    evidence.whoAmI.actorId.toLowerCase() ===
      predecessor.authorization.scope.actorId.toLowerCase(),
  "UAT_CONTINUATION_RECONCILIATION_MISMATCH");
  const proof = validateSyntheticIsolationProof(evidence.proofObservation,
    predecessor.authorization, checkedAt);
  const initialAuthorization = {
    ...predecessor.authorization,
    scope: {
      ...predecessor.authorization.scope,
      candidateId: evidence.candidate.candidateId,
      createCorrelation: predecessor.createCorrelation
    }
  };
  validateReadback(initialAuthorization, evidence.candidate, "BEFORE_CALL");
  requireCondition(evidence.candidate.createCorrelation.toLowerCase() ===
    predecessor.createCorrelation &&
    evidence.candidate.status === STATUSES[0],
  "UAT_CONTINUATION_CREATE_NOT_RECONCILED");
  return proof.correlationId;
}

function validateRequest(request, predecessor, base, now) {
  requireCondition(request && canonicalSame(Object.keys(request).sort(), [
      "ownerMutationApproval", "ownerDecisionText", "authorizedAt", "marker",
      "candidateId", "createCorrelation", "authorizationId", "expiresAt", "reconciliation"
    ].sort()) &&
    request.ownerMutationApproval === true &&
    typeof request.ownerDecisionText === "string" && request.ownerDecisionText.trim().length > 0 &&
    Number.isFinite(Date.parse(request.authorizedAt)) &&
    Date.parse(request.authorizedAt) <= now &&
    now - Date.parse(request.authorizedAt) <= 120_000 &&
    Date.parse(predecessor.authorization.scope.expiresAt) <= Date.parse(request.authorizedAt) &&
    request.marker === predecessor.authorization.marker &&
    request.createCorrelation.toLowerCase() === predecessor.createCorrelation &&
    GUID.test(request.candidateId || ""),
  "UAT_CONTINUATION_OWNER_DECISION_OR_TARGET_MISMATCH");
  const proofCorrelation = validateReconciliation(
    predecessor, request.reconciliation, base, Date.parse(request.authorizedAt), now);
  const expiration = Date.parse(request.expiresAt || "");
  requireCondition(/^[a-z0-9][a-z0-9-]{0,95}$/.test(request.authorizationId || "") &&
    request.authorizationId !== predecessor.authorization.scope.authorizationId &&
    Number.isFinite(expiration) && expiration > now &&
    expiration - Date.parse(request.authorizedAt) <= 2 * 60 * 60 * 1000,
  "UAT_CONTINUATION_WINDOW_INVALID");
  return {
    proofCorrelation,
    scope: expectedScope(predecessor.authorization, request,
      predecessor.createCorrelation, proofCorrelation, predecessor.proofCorrelation)
  };
}

function recordLink(file, record) {
  return {
    authorizationFile: file,
    authorizationHash: digest(file),
    authorizationId: record.scope.authorizationId,
    predecessorAuthorizationFile: record.predecessor.authorizationFile,
    predecessorAuthorizationHash: record.predecessor.authorizationHash,
    predecessorJournalFile: record.predecessor.journalFile,
    predecessorJournalHash: record.predecessor.journalHash,
    attemptId: record.attemptId,
    createdAt: record.createdAt
  };
}

function validateRecord(file, record, base, now) {
  requireCondition(record.version === 1 &&
    record.kind === "OWNER_AUTHORIZED_SINGLE_USER_DEV_CONTINUATION" &&
    record.ownerMutationApproval === true &&
    typeof record.ownerDecisionText === "string" && record.ownerDecisionText.trim().length > 0 &&
    GUID.test(record.attemptId || "") && record.scope &&
    record.scope.identityScope === "SINGLE_USER_DEV" &&
    record.scope.ownerMutationApproval === true &&
    record.scope.appUrl === base.appUrl &&
    record.scope.organizationId === base.organizationId &&
    record.scope.environmentId === base.environmentId &&
    record.scope.expectedUpn?.toLowerCase() === base.expectedUpn.toLowerCase() &&
    record.scope.actorId.toLowerCase() === base.expectedActorId.toLowerCase() &&
    record.marker === record.scope.syntheticIsolation.candidateId &&
    record.candidateId === record.scope.candidateId &&
    record.createCorrelation === record.scope.createCorrelation &&
    record.reconciliation && record.predecessor &&
    Date.parse(record.scope.expiresAt) > now &&
    Date.parse(record.scope.expiresAt) - Date.parse(record.authorizedAt) <= 2 * 60 * 60 * 1000,
  "UAT_CONTINUATION_AUTHORIZATION_INVALID");
  requireCondition(file === path.join(path.dirname(file),
    `${record.scope.authorizationId}.continuation.json`),
  "UAT_CONTINUATION_AUTHORIZATION_PATH_INVALID");
  const predecessor = loadPredecessor(record.predecessor.authorizationFile, base, now);
  requireCondition(record.predecessor.authorizationHash === digest(
      record.predecessor.authorizationFile) &&
    record.predecessor.journalFile === predecessor.journalFile &&
    record.predecessor.journalHash === predecessor.journalHash &&
    record.predecessor.slotFile === predecessor.slotFile &&
    record.predecessor.slotHash === predecessor.slotHash &&
    record.predecessor.runnerPid === predecessor.runnerPid &&
    record.predecessor.createCorrelation === predecessor.createCorrelation &&
    record.predecessor.proofCorrelation === predecessor.proofCorrelation &&
    record.createCorrelation === predecessor.createCorrelation &&
    record.marker === predecessor.authorization.marker &&
    record.candidateName === predecessor.authorization.candidateName &&
    record.candidateEmail === predecessor.authorization.candidateEmail &&
    record.candidateId === record.reconciliation.candidate.candidateId.toLowerCase(),
  "UAT_CONTINUATION_PREDECESSOR_EVIDENCE_CHANGED");
  const request = {
    ownerMutationApproval: record.ownerMutationApproval,
    ownerDecisionText: record.ownerDecisionText,
    authorizedAt: record.authorizedAt,
    marker: record.marker,
    candidateId: record.candidateId,
    createCorrelation: record.createCorrelation,
    authorizationId: record.scope.authorizationId,
    expiresAt: record.scope.expiresAt,
    reconciliation: record.reconciliation
  };
  const validated = validateRequest(request, predecessor, base,
    Date.parse(record.createdAt));
  requireCondition(canonicalSame(record.scope, validated.scope) &&
    record.proofCorrelation === validated.proofCorrelation &&
    record.reconciliationHash === hash(json(canonical(record.reconciliation))),
  "UAT_CONTINUATION_SCOPE_OR_RECONCILIATION_CHANGED");
  const link = read(linkPath(record.predecessor.authorizationFile));
  requireCondition(same(link, recordLink(file, record)),
    "UAT_CONTINUATION_LINK_MISMATCH");
  requireInactive(record.predecessor.runnerPid);
  return record;
}

function createContinuationAuthorization(file, predecessorFile, request, base,
  now = Date.now()) {
  requireCondition(path.isAbsolute(file) && path.isAbsolute(predecessorFile) &&
    path.dirname(file) === path.dirname(predecessorFile) && !fs.existsSync(file),
  "UAT_CONTINUATION_AUTHORIZATION_PATH_INVALID");
  const predecessor = loadPredecessor(predecessorFile, base, now);
  const validated = validateRequest(request, predecessor, base, now);
  requireCondition(file === path.join(path.dirname(predecessorFile),
    `${request.authorizationId}.continuation.json`) &&
    !fs.existsSync(linkPath(predecessorFile)),
  "UAT_CONTINUATION_ALREADY_ISSUED");
  const createdAt = new Date(now).toISOString();
  const record = {
    version: 1,
    kind: "OWNER_AUTHORIZED_SINGLE_USER_DEV_CONTINUATION",
    createdAt,
    authorizedAt: request.authorizedAt,
    ownerDecisionText: request.ownerDecisionText,
    ownerMutationApproval: true,
    attemptId: randomUUID().toLowerCase(),
    marker: predecessor.authorization.marker,
    candidateName: predecessor.authorization.candidateName,
    candidateEmail: predecessor.authorization.candidateEmail,
    candidateId: request.candidateId.toLowerCase(),
    createCorrelation: predecessor.createCorrelation,
    scope: validated.scope,
    proofCorrelation: validated.proofCorrelation,
    reconciliationHash: hash(json(canonical(request.reconciliation))),
    reconciliation: request.reconciliation,
    predecessor: {
      authorizationFile: predecessorFile,
      authorizationHash: digest(predecessorFile),
      journalFile: predecessor.journalFile,
      journalHash: predecessor.journalHash,
      slotFile: predecessor.slotFile,
      slotHash: predecessor.slotHash,
      runnerPid: predecessor.runnerPid,
      createCorrelation: predecessor.createCorrelation,
      proofCorrelation: predecessor.proofCorrelation
    }
  };
  const bytes = `${json(record)}\n`;
  const link = {
    authorizationFile: file,
    authorizationHash: hash(bytes),
    authorizationId: record.scope.authorizationId,
    predecessorAuthorizationFile: predecessorFile,
    predecessorAuthorizationHash: record.predecessor.authorizationHash,
    predecessorJournalFile: predecessor.journalFile,
    predecessorJournalHash: predecessor.journalHash,
    attemptId: record.attemptId,
    createdAt
  };
  exclusiveWrite(linkPath(predecessorFile), link, "UAT_CONTINUATION_ALREADY_ISSUED");
  exclusiveWrite(file, record, "UAT_CONTINUATION_AUTHORIZATION_ALREADY_EXISTS");
  return loadContinuationAuthorization(file, base, now);
}

function loadContinuationAuthorization(file, base, now = Date.now()) {
  requireCondition(path.isAbsolute(file) && fs.existsSync(file),
    "UAT_CONTINUATION_AUTHORIZATION_MISSING");
  return validateRecord(file, read(file), base, now);
}

function readOperation(file, action) {
  requireCondition(ACTIONS.includes(action), "UAT_CONTINUATION_ACTION_NOT_ALLOWED");
  const journalFile = operationPath(file, action);
  if (!fs.existsSync(journalFile)) return null;
  const events = readJournal(journalFile, digest(file), action);
  return { file: journalFile, events, last: events.at(-1) };
}

function appendOperationEvent(claim, type, fields, now = Date.now()) {
  const journal = readOperation(claim.authorizationFile, claim.action);
  requireCondition(journal?.last.sha256 === claim.previousHash,
    "UAT_CONTINUATION_OPERATION_JOURNAL_CHANGED");
  const entry = {
    type,
    sequence: journal.events.length,
    previousHash: claim.previousHash,
    authorizationHash: claim.authorizationHash,
    action: claim.action,
    correlation: claim.correlation,
    at: new Date(now).toISOString(),
    pid: process.pid,
    ...fields
  };
  const event = { ...entry, sha256: hash(json(entry)) };
  appendLine(journal.file, event);
  claim.previousHash = event.sha256;
  return event;
}

function claimContinuationOperation(file, action, base, proofObservation, state,
  now = Date.now()) {
  requireCondition(ACTIONS.includes(action), "UAT_CONTINUATION_ACTION_NOT_ALLOWED");
  const authorization = loadContinuationAuthorization(file, base, now);
  const proof = validateSyntheticIsolationProof(proofObservation, authorization, now);
  const proofCorrelation = proof.correlationId.toLowerCase();
  requireCondition(!authorization.scope.excludedCorrelations.some(value =>
    value.toLowerCase() === proofCorrelation),
  "UAT_CONTINUATION_PROOF_CORRELATION_REPLAY");

  let callCorrelation = null;
  if (action === "RecordCall") {
    validateReadback(authorization, state, "BEFORE_CALL");
  } else {
    const call = readOperation(file, "RecordCall");
    requireCondition(call?.last.type === "ACTION_APPLIED" &&
      call.last.outcome === "APPLIED",
    "UAT_CONTINUATION_PRIOR_ACTION_NOT_CONFIRMED");
    callCorrelation = call.last.correlation;
    validateReadback(authorization, state, "BEFORE_PROCEED", callCorrelation);
  }

  const correlation = randomUUID().toLowerCase();
  requireCondition(GUID.test(correlation) &&
    correlation !== proofCorrelation &&
    !authorization.scope.excludedCorrelations.some(value =>
      value.toLowerCase() === correlation),
  "UAT_CONTINUATION_CORRELATION_INVALID");
  const journalFile = operationPath(file, action);
  const entry = {
    type: "OPERATION_CLAIMED_ONCE",
    sequence: 0,
    previousHash: null,
    authorizationHash: digest(file),
    action,
    correlation,
    proofCorrelation,
    at: new Date(now).toISOString(),
    pid: process.pid,
    proofHash: hash(proof.contract),
    readbackHash: hash(json(canonical(state))),
    callCorrelation
  };
  const event = { ...entry, sha256: hash(json(entry)) };
  exclusiveWrite(journalFile, event, "UAT_CONTINUATION_ACTION_ALREADY_CLAIMED");
  return {
    authorizationFile: file,
    authorizationHash: digest(file),
    action,
    correlation,
    proofCorrelation,
    proofHash: hash(proof.contract),
    proofValidUntil: Date.parse(JSON.parse(proof.contract).validUntil),
    expiresAt: authorization.scope.expiresAt,
    readbackHash: entry.readbackHash,
    callCorrelation,
    previousHash: event.sha256
  };
}

function reserveContinuationDispatch(claim, base, proofObservation, state, now = Date.now()) {
  requireCondition(Date.parse(claim.expiresAt) > now,
    "UAT_CONTINUATION_AUTHORIZATION_EXPIRED");
  const authorization = loadContinuationAuthorization(claim.authorizationFile, base, now);
  requireCondition(digest(claim.authorizationFile) === claim.authorizationHash,
    "UAT_CONTINUATION_AUTHORIZATION_CHANGED");
  const proof = validateSyntheticIsolationProof(proofObservation, authorization, now);
  requireCondition(proof.correlationId.toLowerCase() === claim.proofCorrelation &&
    hash(proof.contract) === claim.proofHash &&
    Date.parse(JSON.parse(proof.contract).validUntil) === claim.proofValidUntil &&
    Date.parse(JSON.parse(proof.contract).validUntil) > now + 30_000 &&
    hash(json(canonical(state))) === claim.readbackHash,
  "UAT_CONTINUATION_DISPATCH_PREFLIGHT_CHANGED");
  validateReadback(authorization, state,
    claim.action === "RecordCall" ? "BEFORE_CALL" : "BEFORE_PROCEED",
    claim.callCorrelation);
  const journal = readOperation(claim.authorizationFile, claim.action);
  requireCondition(journal?.last.type === "OPERATION_CLAIMED_ONCE",
    "UAT_CONTINUATION_OPERATION_ALREADY_DISPATCHED");
  return appendOperationEvent(claim, "DISPATCH_RESERVED_OUTCOME_UNKNOWN", {
    outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN",
    proofCorrelation: claim.proofCorrelation,
    readbackHash: claim.readbackHash
  }, now);
}

function completeContinuationOperation(claim, base, response, state, now = Date.now()) {
  const journal = readOperation(claim.authorizationFile, claim.action);
  requireCondition(journal?.last.type === "DISPATCH_RESERVED_OUTCOME_UNKNOWN" &&
    journal.last.outcome === "DISPATCH_RESERVED_OUTCOME_UNKNOWN",
  "UAT_CONTINUATION_OPERATION_NOT_RESERVED");
  const currentStatus = claim.action === "RecordCall" ? STATUSES[1] : STATUSES[2];
  const previousStatus = claim.action === "RecordCall" ? STATUSES[0] : STATUSES[1];
  const body = response?.body;
  requireCondition(response?.httpStatus === 200 &&
    response.operationCorrelation?.toLowerCase() === claim.correlation &&
    body?.ResultCode === "Applied" &&
    body.CurrentStatus === currentStatus && body.PreviousStatus === previousStatus &&
    GUID.test(body.StatusHistoryId || "") &&
    (claim.action !== "RecordCall" || GUID.test(body.CallLogId || "")),
  "UAT_CONTINUATION_OPERATION_RESPONSE_INVALID");
  const authorization = loadContinuationAuthorization(claim.authorizationFile, base, now);
  validateReadback(authorization, state,
    claim.action === "RecordCall" ? "AFTER_CALL" : "AFTER_PROCEED",
    claim.action === "RecordCall" ? claim.correlation : claim.callCorrelation,
    claim.action === "ProceedToScheduling" ? claim.correlation : null);
  const lastHistory = state.history.at(-1);
  requireCondition(lastHistory.id.toLowerCase() === body.StatusHistoryId.toLowerCase() &&
    lastHistory.correlation.toLowerCase() === claim.correlation &&
    (claim.action !== "RecordCall" ||
      state.callId.toLowerCase() === body.CallLogId.toLowerCase()),
  "UAT_CONTINUATION_OPERATION_READBACK_MISMATCH");
  const responseProjection = {
    httpStatus: response.httpStatus,
    resultCode: body.ResultCode,
    previousStatus: body.PreviousStatus,
    currentStatus: body.CurrentStatus,
    callLogId: body.CallLogId || null,
    statusHistoryId: body.StatusHistoryId,
    operationCorrelation: claim.correlation
  };
  return appendOperationEvent(claim, "ACTION_APPLIED", {
    outcome: "APPLIED",
    response: responseProjection,
    readbackHash: hash(json(canonical(state)))
  }, now);
}

module.exports = {
  ACTIONS, RECEIPT_UNAVAILABLE, createContinuationAuthorization,
  loadContinuationAuthorization, validateReadback, claimContinuationOperation,
  reserveContinuationDispatch, completeContinuationOperation, readOperation
};
