const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { authDirectory, loadApproval } = require("./local-settings.cjs");

const ACTIONS = Object.freeze([
  "CreateCandidate", "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled"
]);
const STATUSES = Object.freeze([100010000, 100010001, 100010002, 100010003]);
const REFERENCE_LABELS = Object.freeze({
  position: "[DEV] Software Engineer",
  source: "[DEV] Internal Test Source",
  ta: "[DEV] Synthetic Interviewer",
  location: "[DEV] Test Location"
});
const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const requireCondition = (condition, code) => { if (!condition) throw new Error(code); };

function loadLifecycleApproval() {
  const base = loadApproval();
  const file = process.env.BSO_UAT_LIFECYCLE_APPROVAL_FILE;
  if (!file) return { approved: false };
  requireCondition(path.isAbsolute(file), "UAT_ABSOLUTE_LIFECYCLE_APPROVAL_FILE_REQUIRED");
  const scope = JSON.parse(fs.readFileSync(file, "utf8"));
  if (scope.ownerMutationApproval !== true) return { approved: false };
  if (scope.authenticationCallbackOrigin) {
    const callback = new URL(scope.authenticationCallbackOrigin);
    requireCondition(callback.protocol === "https:" && !callback.username && !callback.password &&
      callback.origin === scope.authenticationCallbackOrigin &&
      /^[a-z0-9-]+\.crm[0-9]*\.dynamics\.com$/i.test(callback.hostname),
    "UAT_INVALID_AUTHENTICATION_CALLBACK_ORIGIN");
  }
  requireCondition(scope.authorizationId === "owner-lifecycle-20261109-01" &&
    scope.appUrl === base.appUrl && scope.organizationId === base.organizationId &&
    scope.expectedUpn?.toLowerCase() === base.expectedUpn.toLowerCase() &&
    scope.identityScope === "OWNER_APPROVED_ELEVATED_FUNCTIONAL_LIFECYCLE" &&
    scope.maximumCandidates === 1 && scope.noRetries === true &&
    JSON.stringify(scope.actions) === JSON.stringify(ACTIONS) &&
    scope.referenceLabels && Object.keys(scope.referenceLabels).length === Object.keys(REFERENCE_LABELS).length &&
    Object.entries(REFERENCE_LABELS).every(([key, label]) => scope.referenceLabels[key] === label) &&
    Number.isFinite(Date.parse(scope.expiresAt)) && Date.parse(scope.expiresAt) > Date.now(),
  "UAT_INVALID_LIFECYCLE_APPROVAL");
  return { ...base, approved: true, lifecycleScope: scope };
}

function reserveOneShot(approval) {
  const file = path.join(authDirectory, `${approval.lifecycleScope.authorizationId}.json`);
  if (process.env.BSO_UAT_RESUME_ZERO_DISPATCH === "owner-authorized-login-recovery") {
    const record = JSON.parse(fs.readFileSync(file, "utf8"));
    requireCondition(record.authorizationId === approval.lifecycleScope.authorizationId &&
      record.status === "STOPPED_NO_RETRY_RECONCILE_ONLY" &&
      Array.isArray(record.attempts) && record.attempts.length === 0 && record.candidateId === null &&
      GUID.test(record.marker) &&
      record.candidateName === `[SYNTHETIC-E2E] Playwright ${record.marker}` &&
      record.candidateEmail === `pw-${record.marker}@example.invalid` &&
      !record.loginRecovery, "UAT_RESUME_REQUIRES_UNCHANGED_ZERO_DISPATCH_JOURNAL");
    // Keep the original marker/history; a separate exclusive claim prevents parallel resumption.
    fs.writeFileSync(`${file}.login-recovery-claim`, "owner-authorized-login-recovery",
      { flag: "wx", mode: 0o600 });
    record.loginRecovery = {
      authorizedAt: "2026-11-09T04:17:34.064Z",
      priorStatus: record.status,
      dispatchesAtResume: 0
    };
    fs.writeFileSync(file, JSON.stringify(record, null, 2));
    return { record, save: () => fs.writeFileSync(file, JSON.stringify(record, null, 2)) };
  }
  const marker = randomUUID();
  const record = {
    authorizationId: approval.lifecycleScope.authorizationId,
    marker,
    candidateName: `[SYNTHETIC-E2E] Playwright ${marker}`,
    candidateEmail: `pw-${marker}@example.invalid`,
    candidateId: null,
    attempts: [],
    status: "RESERVED_NO_DISPATCH"
  };
  // Default mode never reuses a reserved authorization.
  try {
    fs.writeFileSync(file, JSON.stringify(record, null, 2), { flag: "wx", mode: 0o600 });
  } catch (error) {
    if (error.code === "EEXIST") throw new Error("UAT_AUTHORIZATION_ALREADY_RESERVED_NO_RERUN");
    throw error;
  }
  return { record, save: () => fs.writeFileSync(file, JSON.stringify(record, null, 2)) };
}

async function readRows(page, origin, table, columns, filter) {
  return page.evaluate(async ({ origin, table, columns, filter }) => {
    const query = new URLSearchParams({
      "$select": columns.join(","), "$filter": filter, "$count": "true", "$top": "6"
    });
    const response = await fetch(`${origin}/api/data/v9.2/${table}?${query}`,
      { credentials: "same-origin", headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error("UAT_SCOPED_READ_FAILED");
    const json = await response.json();
    if (!Array.isArray(json.value) || json["@odata.nextLink"] ||
        json["@odata.count"] !== json.value.length) throw new Error("UAT_SCOPED_READ_INCOMPLETE");
    return json.value;
  }, { origin, table, columns, filter });
}

const TABLES = Object.freeze([
  ["candidate", "os_sr_cands", "os_sr_cand", [
    "os_sr_candid", "os_sr_cand_cnum", "os_sr_cand_nm", "os_sr_cand_eml", "os_sr_cand_stat",
    "os_sr_cand_corid", "_ownerid_value", "_os_sr_cand_pos_value",
    "_os_sr_cand_csrc_value", "_os_sr_cand_ta_value"
  ]],
  ["call", "os_sr_calls", "os_sr_call", [
    "os_sr_callid", "os_sr_call_corid", "os_sr_call_out", "os_sr_call_ctat", "_os_sr_call_ctby_value"
  ]],
  ["schedule", "os_sr_intvs", "os_sr_intv", [
    "os_sr_intvid", "os_sr_intv_rnd", "os_sr_intv_stat", "os_sr_intv_strt", "os_sr_intv_end",
    "_os_sr_intv_ta_value", "_os_sr_intv_loc_value", "statecode", "os_sr_intv_res"
  ]],
  ["history", "os_sr_cshs", "os_sr_csh", [
    "os_sr_cshid", "os_sr_csh_corid", "os_sr_csh_prevstat", "os_sr_csh_newstat", "_os_sr_csh_actr_value"
  ]],
  ["receipt", "os_sr_oprcs", "os_sr_oprc", [
    "os_sr_oprcid", "os_sr_oprc_corid", "os_sr_oprc_cact", "os_sr_oprc_prevstat",
    "os_sr_oprc_newstat", "os_sr_oprc_callref", "os_sr_oprc_histref"
  ]]
]);

async function readEvidence(page, origin, record) {
  const evidence = {};
  const selector = `os_sr_cand_nm eq '${record.candidateName}' or os_sr_cand_eml eq '${record.candidateEmail}'`;
  for (const [name, table, stem, columns] of TABLES) {
    const filter = name === "candidate" ? selector
      : record.candidateId ? `_${stem}_cand_value eq ${record.candidateId}`
        : `${stem}_cand/os_sr_cand_nm eq '${record.candidateName}'`;
    evidence[name] = await readRows(page, origin, table, columns, filter);
  }
  return evidence;
}

function counts(evidence) {
  return Object.fromEntries(Object.entries(evidence).map(([table, rows]) => [table, rows.length]));
}

function validateEvidence(evidence, record, completed, userId, references, schedule) {
  const expected = { candidate: 1, call: completed >= 2 ? 1 : 0,
    schedule: completed === 4 ? 1 : 0, history: completed - 1, receipt: completed };
  requireCondition(JSON.stringify(counts(evidence)) === JSON.stringify(expected), "UAT_EXACT_COUNTS_MISMATCH");
  const candidate = evidence.candidate[0];
  requireCondition(candidate.os_sr_candid === record.candidateId &&
    candidate.os_sr_cand_nm === record.candidateName &&
    candidate.os_sr_cand_eml === record.candidateEmail &&
    candidate.os_sr_cand_stat === STATUSES[completed - 1] &&
    /^CAND-[0-9]+$/.test(candidate.os_sr_cand_cnum) &&
    candidate._ownerid_value === userId &&
    candidate.os_sr_cand_corid === record.attempts[0].correlation &&
    candidate._os_sr_cand_pos_value === references.position &&
    candidate._os_sr_cand_csrc_value === references.source &&
    candidate._os_sr_cand_ta_value === references.ta, "UAT_CANDIDATE_READBACK_MISMATCH");
  for (let index = 0; index < completed; index++) {
    const attempt = record.attempts[index];
    const receipts = evidence.receipt.filter(row => row.os_sr_oprc_corid === attempt.correlation);
    requireCondition(receipts.length === 1 && receipts[0].os_sr_oprc_cact === ACTIONS[index] &&
      receipts[0].os_sr_oprc_newstat === STATUSES[index] &&
      (receipts[0].os_sr_oprc_prevstat ?? null) === (index === 0 ? null : STATUSES[index - 1]),
    "UAT_RECEIPT_EVIDENCE_MISMATCH");
    if (index > 0) {
      const histories = evidence.history.filter(row => row.os_sr_csh_corid === attempt.correlation);
      requireCondition(histories.length === 1 &&
        histories[0].os_sr_csh_prevstat === STATUSES[index - 1] &&
        histories[0].os_sr_csh_newstat === STATUSES[index] &&
        histories[0]._os_sr_csh_actr_value === userId &&
        receipts[0].os_sr_oprc_histref === histories[0].os_sr_cshid &&
        attempt.response.StatusHistoryId?.toLowerCase() === histories[0].os_sr_cshid,
      "UAT_HISTORY_EVIDENCE_MISMATCH");
    }
  }
  if (completed >= 2) {
    const call = evidence.call[0];
    requireCondition(call.os_sr_call_out === 100010000 && call._os_sr_call_ctby_value === userId &&
      call.os_sr_call_corid === record.attempts[1].correlation &&
      Date.parse(call.os_sr_call_ctat) === Date.parse(record.attempts[1].contactedAt) &&
      record.attempts[1].response.CallLogId?.toLowerCase() === call.os_sr_callid &&
      evidence.receipt.find(row => row.os_sr_oprc_cact === "RecordCall").os_sr_oprc_callref === call.os_sr_callid,
    "UAT_CALL_EVIDENCE_MISMATCH");
  }
  if (completed === 4) {
    const row = evidence.schedule[0];
    requireCondition(row.os_sr_intv_rnd === 100000000 && row.os_sr_intv_stat === 100000001 &&
      row.statecode === 0 && row.os_sr_intv_res === 100000000 &&
      row._os_sr_intv_ta_value === references.ta && row._os_sr_intv_loc_value === references.location &&
      Date.parse(row.os_sr_intv_strt) === Date.parse(schedule.start) &&
      Date.parse(row.os_sr_intv_end) === Date.parse(schedule.end), "UAT_SCHEDULE_EVIDENCE_MISMATCH");
  }
}

module.exports = {
  ACTIONS, STATUSES, REFERENCE_LABELS, GUID, requireCondition, loadLifecycleApproval,
  reserveOneShot, readRows, readEvidence, counts, validateEvidence
};
