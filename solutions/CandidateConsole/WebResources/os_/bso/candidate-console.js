(() => {
  "use strict";

  const STATUS_LABELS = {
    100010000: "Need Call Candidate",
    100010001: "Candidate Answered",
    100010002: "Waiting Manual Scheduling",
    100010003: "Round 1 Scheduled",
    100010004: "Offer Extended",
    100010005: "Candidate Failed"
  };
  const OUTCOME_LABELS = {
    100010000: "Answered",
    100010001: "No Answer",
    100010002: "Call Back Requested"
  };
  const STATUS = {
    needCall: 100010000,
    answered: 100010001,
    waitingManualScheduling: 100010002,
    round1Scheduled: 100010003,
    offerExtended: 100010004,
    candidateFailed: 100010005
  };
  // Mirrors the Candidate Core RecordCall transition; the server remains authoritative.
  function canRecordCall(status) {
    return status === STATUS.needCall;
  }
  const INTERVIEW_RESULT_LABELS = {
    100000000: "Pending",
    100000001: "Pass",
    100000002: "Fail"
  };
  const INTERVIEW_RESULT = {
    pending: 100000000,
    pass: 100000001,
    fail: 100000002
  };
  const SCHEDULE_STATUS_LABELS = {
    100000000: "PROPOSED",
    100000001: "ACTIVE / SCHEDULED",
    100000002: "CANCELLED",
    100000003: "SUPERSEDED"
  };
  const SCHEDULE_STATUS = {
    proposed: 100000000,
    scheduled: 100000001,
    cancelled: 100000002,
    superseded: 100000003
  };
  const OUTCOME = {
    answered: 100010000,
    noAnswer: 100010001,
    callBackRequested: 100010002
  };
  const TABLES = {
    candidate: {
      logicalName: "os_sr_cand",
      entitySetName: "os_sr_cands",
      id: "",
      correlation: "os_sr_cand_corid",
      number: "os_sr_cand_cnum",
      name: "os_sr_cand_nm",
      email: "os_sr_cand_eml",
      phone: "os_sr_cand_phn",
      cvUrl: "os_sr_cand_cvurl",
      status: "os_sr_cand_stat",
      position: "_os_sr_cand_pos_value",
      positionNavigation: "os_sr_cand_pos",
      source: "_os_sr_cand_csrc_value",
      sourceNavigation: "os_sr_cand_csrc",
      assignedTa: "_os_sr_cand_ta_value",
      assignedTaNavigation: "os_sr_cand_ta"
    },
    call: {
      logicalName: "os_sr_call",
      entitySetName: "os_sr_calls",
      id: "",
      candidate: "_os_sr_call_cand_value",
      candidateNavigation: "os_sr_call_cand",
      correlation: "os_sr_call_corid",
      outcome: "os_sr_call_out",
      contactedAt: "os_sr_call_ctat",
      contactedByNavigation: "os_sr_call_ctby",
      notes: "os_sr_call_nts",
      reference: "os_sr_call_ref"
    },
    history: {
      logicalName: "os_sr_csh",
      entitySetName: "os_sr_cshs",
      id: "",
      candidate: "_os_sr_csh_cand_value",
      candidateNavigation: "os_sr_csh_cand",
      actorNavigation: "os_sr_csh_actr",
      correlation: "os_sr_csh_corid",
      previous: "os_sr_csh_prevstat",
      current: "os_sr_csh_newstat",
      action: "os_sr_csh_cact",
      changedAt: "os_sr_csh_chg",
      reason: "os_sr_csh_rsn"
    },
    interview: {
      logicalName: "os_sr_intv",
      entitySetName: "os_sr_intvs",
      id: "",
      candidate: "_os_sr_intv_cand_value",
      candidateNavigation: "os_sr_intv_cand",
      ta: "_os_sr_intv_ta_value",
      taNavigation: "os_sr_intv_ta",
      location: "_os_sr_intv_loc_value",
      locationNavigation: "os_sr_intv_loc",
      round: "os_sr_intv_rnd",
      round1: 100000000,
      start: "os_sr_intv_strt",
      end: "os_sr_intv_end",
      notes: "os_sr_intv_nts",
      result: "os_sr_intv_res",
      resultRecordedAt: "os_sr_intv_recat",
      resultNotes: "os_sr_intv_rnts",
      status: "os_sr_intv_stat",
      reason: "os_sr_intv_rsn",
      changedAt: "os_sr_intv_chg"
    }
  };

  let selectedCandidate = null;
  let selectedSchedule = null;
  let proposedSchedule = null;
  let scheduleRows = [];
  let scheduleMode = "new";
  let scheduleRetryBlockedCandidateId = null;
  let resultRetryBlockedCandidateId = null;
  let currentRows = [];
  let busy = false;
  let syntheticQueryBlocked = false;
  let environmentPolicy = Object.freeze({ allowed: false, reason: "CONFIGURATION_MISSING" });
  const CORE_API_ACTIONS = new Set([
    "CreateCandidate", "UpdateCandidate", "RecordCall", "ProceedToScheduling",
    "MarkRound1Scheduled", "RecordPass", "RecordFail", "RequestReschedule", "CancelRound1"
  ]);
  const CORE_API_PARAMETER_NAMES = new Set([
    "ActionType", "SyntheticScopeId", "CandidateId", "ExpectedStatus", "CorrelationId", "CandidateName",
    "CandidateEmail", "CandidatePhone", "CandidateCvUrl", "PositionId", "CandidateSourceId",
    "AssignedTaId", "ProfileFieldMask", "Reason",
    "CallOutcome", "ContactedAt", "Notes", "InterviewerId", "LocationId", "StartAt",
    "EndAt", "ResultNotes"
  ]);
  const PROFILE_FIELD_ORDER = [
    "CandidateName", "CandidateEmail", "CandidatePhone", "PositionId",
    "CandidateSourceId", "CandidateCvUrl", "AssignedTaId"
  ];

  function canonicalProfileFieldMask(changedFields) {
    const changed = new Set(changedFields);
    return PROFILE_FIELD_ORDER.filter((field) => changed.has(field)).join(",");
  }

  const $ = (id) => document.getElementById(id);
  const globalContext = () => {
    if (typeof GetGlobalContext === "function") return GetGlobalContext();
    if (window.parent && window.parent.Xrm && window.parent.Xrm.Utility) {
      return window.parent.Xrm.Utility.getGlobalContext();
    }
    if (window.Xrm && window.Xrm.Utility) return window.Xrm.Utility.getGlobalContext();
    throw new Error("Model-driven app context is unavailable.");
  };
  const xrm = () => {
    if (!isCandidateCoreEnabled()) throw new Error("CONSOLE_DATA_ACCESS_BLOCKED");
    if (window.parent && window.parent.Xrm && window.parent.Xrm.WebApi) return window.parent.Xrm;
    if (window.Xrm && window.Xrm.WebApi) return window.Xrm;
    throw new Error("Model-driven app data services are unavailable.");
  };

  function showNotice(message, isError = false) {
    const notice = $("notice");
    notice.textContent = message;
    notice.classList.toggle("error", isError);
    notice.hidden = false;
  }

  function resolveEnvironmentPolicy() {
    try {
      const context = globalContext();
      const policy = window.BsoRsCandidateConsolePolicy;
      if (!policy || typeof policy.resolve !== "function") {
        return Object.freeze({ allowed: false, reason: "CONFIGURATION_POLICY_UNAVAILABLE" });
      }
      return policy.resolve(window.BsoRsCandidateConsoleConfiguration, {
        organizationUrl: context.getClientUrl(),
        organizationId: context.organizationSettings.organizationId
      });
    } catch {
      return Object.freeze({ allowed: false, reason: "CONFIGURATION_CONTEXT_UNAVAILABLE" });
    }
  }

  function isCandidateCoreEnabled() {
    if (environmentPolicy.allowed !== true) return false;
    if (!environmentPolicy.syntheticDataOnly) return true;
    if (syntheticQueryBlocked) return false;
    const policy = window.BsoRsCandidateConsolePolicy;
    try {
      return Boolean(policy && typeof policy.hasSyntheticIsolation === "function" &&
        policy.hasSyntheticIsolation() === true);
    } catch {
      return false;
    }
  }

  function isDevConfiguration() {
    return isCandidateCoreEnabled() && environmentPolicy.mode === "DEV";
  }

  function isDevFallbackEnabled() {
    return isCandidateCoreEnabled() && environmentPolicy.directWriteFallbackAvailable === true &&
      $("dev-fallback-toggle").checked;
  }

  function updateWorkflowPathLabel() {
    const supportedEnvironment = isCandidateCoreEnabled();
    const fallback = isDevFallbackEnabled();
    $("workflow-path-badge").textContent = !supportedEnvironment
      ? environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly
        ? syntheticQueryBlocked ? "SYNTHETIC QUERY BLOCKED" : "SYNTHETIC DATA ACCESS BLOCKED"
        : environmentPolicy.reason === "BLOCK_UNRECOGNIZED_ENVIRONMENT"
          ? "BLOCK_UNRECOGNIZED_ENVIRONMENT"
          : "CONFIGURATION BLOCKED"
      : fallback
      ? "DEV DIRECT-WRITE FALLBACK"
      : "CANDIDATE CORE PATH";
    $("environment-mode-badge").textContent = environmentPolicy.allowed === true
      ? environmentPolicy.mode
      : "ENVIRONMENT CONFIGURATION REQUIRED";
    $("real-data-badge").textContent = supportedEnvironment && !environmentPolicy.syntheticDataOnly
      ? "PRODUCTION CONFIGURATION"
      : "SYNTHETIC DATA ONLY";
    document.querySelectorAll("[data-workflow-label]").forEach((label) => {
      label.textContent = !supportedEnvironment
        ? environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly
          ? "Unavailable until synthetic data isolation is established"
          : "Unavailable until environment configuration is valid"
        : fallback ? "DEV direct-write fallback" : "Candidate Core / os_sr_cact";
    });
    $("dev-fallback-control").hidden = !supportedEnvironment ||
      environmentPolicy.directWriteFallbackAvailable !== true;
    $("dev-fallback-toggle").disabled = !supportedEnvironment || busy ||
      environmentPolicy.directWriteFallbackAvailable !== true;
  }

  function currentUserId() {
    const userId = globalContext().userSettings.userId;
    if (typeof userId !== "string" ||
        !/^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$/i.test(userId)) {
      throw new Error("DEV_DIRECT_WRITE_USER_CONTEXT_INVALID");
    }
    return userId.replace(/[{}]/g, "");
  }

  function isSyntheticCandidateMarkers(candidate) {
    return Boolean(candidate &&
      typeof candidate[TABLES.candidate.name] === "string" &&
      candidate[TABLES.candidate.name].startsWith("[SYNTHETIC-E2E]") &&
      typeof candidate[TABLES.candidate.email] === "string" &&
      /^[^@\s]+@[^@\s]+\.invalid$/i.test(candidate[TABLES.candidate.email]));
  }

  function isCandidateAllowedByDataMode(candidate) {
    return isCandidateCoreEnabled() &&
      (!environmentPolicy.syntheticDataOnly || isSyntheticCandidateMarkers(candidate));
  }

  function isReferenceAllowedByDataMode(label) {
    const policy = window.BsoRsCandidateConsolePolicy;
    return Boolean(policy && typeof policy.allowsReference === "function" &&
      policy.allowsReference(label, environmentPolicy.syntheticDataOnly));
  }

  function isSyntheticInput(name, email) {
    return typeof name === "string" && name.startsWith("[SYNTHETIC-E2E]") &&
      typeof email === "string" && /^[^@\s]+@[^@\s]+\.invalid$/i.test(email);
  }

  function logSafeFailure(category, error) {
    if (environmentPolicy.diagnosticsMode !== "SAFE") return;
    const numericCode = Number(error && error.errorCode);
    const code = Number.isFinite(numericCode) && numericCode !== 0
      ? `:0x${(numericCode >>> 0).toString(16).padStart(8, "0").toUpperCase()}`
      : "";
    const operationFailure = error && typeof error.operationFailure === "string"
      ? `:${error.operationFailure}`
      : "";
    console.error(`${category}${code}${operationFailure}`);
  }

  function failureMessage(category, partial = false) {
    const messages = {
      CANDIDATE_CREATE_FAILED: "Candidate create failed or its outcome is uncertain. The list was refreshed; verify before trying again.",
      CANDIDATE_READBACK_FAILED: "Candidate was created, but readback failed. Refresh to reconcile before trying again.",
      CALL_LOG_CREATE_FAILED: "Call Log create failed or its outcome is uncertain. Current data was refreshed; verify before trying again.",
      CANDIDATE_STATUS_UPDATE_FAILED: "Candidate status update failed after the Call Log write. Partial DEV data may exist; current data was refreshed.",
      STATUS_HISTORY_CREATE_FAILED: "Status History create failed after the Candidate status update. Partial DEV data exists; current data was refreshed.",
      CANDIDATE_READ_FAILED: "Candidate could not be read before the call. Current data was refreshed.",
      CANDIDATE_LIST_REFRESH_FAILED: "The write completed, but the Candidate list could not be refreshed.",
      CANDIDATE_DETAIL_READ_FAILED: "The write completed, but Candidate details could not be refreshed.",
      WAITING_STATUS_UPDATE_FAILED: "Candidate status update failed.",
      WAITING_STATUS_HISTORY_CREATE_FAILED: "Status History create failed after the Candidate status update.",
      DEV_DIRECT_WRITE_RECONCILIATION_FAILED: "The write failed and current data could not be fully refreshed."
    };
    const message = messages[category] || "The DEV write failed. Current data was refreshed where possible.";
    return partial ? `${message} Do not retry blindly.` : message;
  }

  function hideNotice() {
    $("notice").hidden = true;
    $("notice").textContent = "";
    $("notice").classList.remove("error");
  }

  function setBusy(value) {
    busy = value;
    $("dev-fallback-toggle").disabled =
      value || !isCandidateCoreEnabled() || environmentPolicy.directWriteFallbackAvailable !== true;
    document.querySelectorAll("button[data-action]").forEach((button) => {
      button.disabled = value || !isCandidateCoreEnabled() ||
        (button.id === "submit-call" &&
          (!selectedCandidate || !canRecordCall(selectedCandidate[TABLES.candidate.status]))) ||
        (button.id === "waiting-status-button" && button.hidden) ||
        (button.id === "schedule-round1-button" &&
          (button.hidden || !selectedCandidate ||
            selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
            Boolean(selectedSchedule) ||
            scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id])) ||
        (button.id === "record-interview-result-button" &&
          (button.hidden || !canRecordInterviewResult())) ||
        (button.id === "save-schedule" &&
          (!selectedCandidate ||
            (scheduleMode === "reschedule"
              ? !canManageSchedule()
              : selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
                Boolean(selectedSchedule)) ||
            scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id])) ||
        (button.id === "save-interview-result" &&
          (!selectedCandidate || !canRecordInterviewResult())) ||
        (button.id === "reschedule-round1-button" &&
          (button.hidden || !canManageSchedule())) ||
        (button.id === "cancel-round1-button" &&
          (button.hidden || !canManageSchedule())) ||
        (button.id === "confirm-cancellation" &&
          (!selectedCandidate || !canManageSchedule()));
    });
  }

  function formatDate(value) {
    if (!value) return "";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleString();
  }

  function sameInstant(actual, expected) {
    const actualTime = Date.parse(actual);
    const expectedTime = Date.parse(expected);
    return Number.isFinite(actualTime) && Number.isFinite(expectedTime) &&
      Math.floor(actualTime / 1000) === Math.floor(expectedTime / 1000);
  }

  function formatted(record, attribute, fallback = "") {
    const label = record[`${attribute}@OData.Community.Display.V1.FormattedValue`];
    return label == null ? fallback : String(label);
  }

  function choiceLabel(record, attribute, labels) {
    const label = formatted(record, attribute);
    if (label) return label;
    const value = record[attribute];
    return value == null ? "" : (labels[value] || String(value));
  }

  function newCorrelationId() {
    if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
      return globalThis.crypto.randomUUID();
    }
    const bytes = new Uint8Array(16);
    globalThis.crypto.getRandomValues(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  async function invokeCandidateCore(action, values = {}, correlationId = newCorrelationId()) {
    if (environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly) {
      await verifyServerIsolation();
    }
    if (!isCandidateCoreEnabled()) throw new Error("CANDIDATE_CORE_ENVIRONMENT_REJECTED");
    if (!CORE_API_ACTIONS.has(action)) throw new Error("CANDIDATE_CORE_ACTION_INVALID");
    const request = { ...values, ActionType: action, CorrelationId: correlationId };
    if (environmentPolicy.syntheticDataOnly) {
      const scope = window.BsoRsCandidateConsolePolicy.getSyntheticScope();
      if (!scope) throw new Error("SYNTHETIC_VERIFIER_UNAVAILABLE");
      request.SyntheticScopeId = scope.scopeId;
    }
    const parameterNames = Object.keys(request);
    if (parameterNames.some((name) =>
      !CORE_API_PARAMETER_NAMES.has(name))) {
      throw new Error("CANDIDATE_CORE_PARAMETER_INVALID");
    }
    if (request.CandidateId) request.CandidateId = normalizeGuid(request.CandidateId);
    // Xrm.WebApi.online.execute emits an undefined Edm.Guid for this action when optional inputs are omitted.
    const response = await fetch("/api/data/v9.2/os_sr_cact", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json; charset=utf-8",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0"
      },
      body: JSON.stringify(request)
    });
    const responseText = await response.text();
    let result;
    try {
      result = responseText ? JSON.parse(responseText) : null;
    } catch {
      throw new Error("CANDIDATE_CORE_RESPONSE_INVALID");
    }
    if (!response.ok) {
      const error = new Error("CANDIDATE_CORE_REQUEST_REJECTED");
      const errorCode = result && result.error && result.error.code;
      if (typeof errorCode === "string" && /^0x[0-9a-f]{8}$/i.test(errorCode)) {
        error.errorCode = Number.parseInt(errorCode.slice(2), 16);
      }
      const errorMessage = result && result.error && result.error.message;
      const operationFailure = typeof errorMessage === "string"
        ? errorMessage.match(/CANDIDATE_CORE_OPERATION_REJECTED:(?:CREATE_CANDIDATE:)?(INPUT_VALIDATION|REFERENCE_VALIDATION|RECEIPT_READ|CANDIDATE_CREATE|CANDIDATE_READBACK|RECEIPT_CREATE|RESPONSE):(0x[0-9a-f]{8}|TIMEOUT|PLUGIN_EXECUTION|INVALID_OPERATION|SERVICE_FAULT|OTHER|REFERENCE_NOT_AVAILABLE)/i)
        : null;
      if (operationFailure) {
        const safeCode = operationFailure[2].startsWith("0x")
          ? `0x${operationFailure[2].slice(2).toUpperCase()}`
          : operationFailure[2];
        error.operationFailure = `${operationFailure[1]}:${safeCode}`;
      }
      throw error;
    }
    if (!result || !["Applied", "DuplicateReplay"].includes(result.ResultCode)) {
      throw new Error("CANDIDATE_CORE_RESULT_INVALID");
    }
    return { correlationId, result };
  }

  async function resolveCreatedCandidate(correlationId, expectedName, expectedEmail) {
    const c = TABLES.candidate;
    const correlation = String(correlationId).replace(/'/g, "''");
    const filter = candidateReferenceScope(candidateScope(`${c.correlation} eq '${correlation}'`));
    const rows = await retrieveAll(c.logicalName,
      `?$select=${candidateColumns().concat(c.correlation).join(",")}` +
      `&$filter=${encodeURIComponent(filter)}&$top=2`);
    requireSyntheticCandidates(rows);
    const matches = rows.filter((candidate) =>
      candidate[c.correlation] === correlationId &&
      candidate[c.name] === expectedName &&
      candidate[c.email] === expectedEmail &&
      isCandidateAllowedByDataMode(candidate)
    );
    if (matches.length !== 1 || matches[0][c.status] !== STATUS.needCall ||
        !matches[0][c.number]) {
      throw new Error("CANDIDATE_CORE_CREATE_READBACK_INVALID");
    }
    return matches[0];
  }

  async function refreshCoreCandidate(candidateId) {
    await refreshCandidates();
    if (!(await openCandidate(candidateId))) {
      throw new Error("CANDIDATE_CORE_DETAIL_REFRESH_FAILED");
    }
  }

  async function reportCandidateCoreFailure(action, candidateId, error) {
    logSafeFailure(`CANDIDATE_CORE_${action}_FAILED`, error);
    try {
      await refreshCandidates();
      if (candidateId) await openCandidate(candidateId);
    } catch (reconcileError) {
      logSafeFailure("CANDIDATE_CORE_RECONCILIATION_FAILED", reconcileError);
      showNotice(`${action} failed or its outcome is uncertain. Current server state could not be fully refreshed; do not retry until it is reconciled.`, true);
      return;
    }
    const operationFailure = error && typeof error.operationFailure === "string"
      ? ` (${error.operationFailure})`
      : "";
    showNotice(`${action} failed or its outcome is uncertain${operationFailure}. Current server state was refreshed; verify it before retrying.`, true);
  }

  function assertCandidateCoreStatus(result, expectedStatus) {
    if (Number(result.CurrentStatus) !== expectedStatus) {
      throw new Error("CANDIDATE_CORE_STATUS_RESULT_MISMATCH");
    }
  }

  function normalizeGuid(value) {
    if (typeof value !== "string" ||
        !/^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$/i.test(value)) {
      throw new Error("DEV_DIRECT_WRITE_INVALID_RECORD_REFERENCE");
    }
    return value.replace(/[{}]/g, "");
  }

  function sameOptionalGuid(actual, expected) {
    if (!actual && !expected) return true;
    return Boolean(actual && expected &&
      normalizeGuid(actual).toLowerCase() === normalizeGuid(expected).toLowerCase());
  }

  function isValidCandidateCvUrl(value) {
    if (!value) return true;
    try {
      const url = new URL(value);
      return url.protocol === "https:" && !url.username && !url.password;
    } catch {
      return false;
    }
  }

  async function retrieveAll(tableLogicalName, query) {
    try {
      const api = xrm().WebApi;
      let response = await api.retrieveMultipleRecords(tableLogicalName, query);
      if (!isCandidateCoreEnabled()) throw new Error("CONSOLE_DATA_ACCESS_BLOCKED");
      const results = [...response.entities];
      while (response.nextLink) {
        response = await api.retrieveMultipleRecords(tableLogicalName, response.nextLink);
        if (!isCandidateCoreEnabled()) throw new Error("CONSOLE_DATA_ACCESS_BLOCKED");
        results.push(...response.entities);
      }
      return results;
    } catch (error) {
      if (environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly) {
        blockSyntheticQuery();
      }
      throw error;
    }
  }

  function blockSyntheticQuery() {
    syntheticQueryBlocked = true;
    updateWorkflowPathLabel();
    $("create-button").disabled = true;
    $("refresh-button").disabled = true;
    document.querySelectorAll("button[data-action]").forEach((button) => { button.disabled = true; });
    showNotice("Synthetic data could not be verified. Candidate Management is closed; contact support before retrying.", true);
  }

  function filterAttribute(value) {
    if (typeof value !== "string" || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value)) {
      throw new Error("CONSOLE_QUERY_ATTRIBUTE_INVALID");
    }
    return value;
  }

  function candidateScope(filter = "", navigation = "") {
    if (!environmentPolicy.syntheticDataOnly) return filter;
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.syntheticCandidateFilter !== "function") {
      throw new Error("SYNTHETIC_QUERY_POLICY_UNAVAILABLE");
    }
    const markers = policy.syntheticCandidateFilter(navigation);
    return filter ? `${filter} and ${markers}` : markers;
  }

  function referenceScope(filter, nameAttribute) {
    if (!environmentPolicy.syntheticDataOnly) return filter;
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.syntheticReferenceFilter !== "function") {
      throw new Error("SYNTHETIC_QUERY_POLICY_UNAVAILABLE");
    }
    const marker = policy.syntheticReferenceFilter(nameAttribute);
    return filter ? `${filter} and ${marker}` : marker;
  }

  function candidateReferenceScope(filter) {
    if (!environmentPolicy.syntheticDataOnly) return filter;
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.syntheticReferenceFilter !== "function") {
      throw new Error("SYNTHETIC_QUERY_POLICY_UNAVAILABLE");
    }
    const c = TABLES.candidate;
    const references = [
      [c.position, c.positionNavigation, "os_sr_pos_ttl"],
      [c.source, c.sourceNavigation, "os_sr_csrc_nm"],
      [c.assignedTa, c.assignedTaNavigation, "os_sr_ta_nm"]
    ];
    const linked = references.map(([lookup, navigation, name]) =>
      `(${lookup} eq null or ${policy.syntheticReferenceFilter(name, navigation)})`);
    return [filter, ...linked].filter(Boolean).join(" and ");
  }

  function candidateColumns() {
    const c = TABLES.candidate;
    const columns = [
      c.id, c.number, c.name, c.email, c.phone, c.cvUrl, c.status, c.position, c.source,
      c.assignedTa, "createdon"
    ];
    if (!environmentPolicy.syntheticDataOnly) columns.push("_ownerid_value");
    return columns;
  }

  async function retrieveScopedSingle(tableName, select, filter) {
    const rows = await retrieveAll(tableName,
      `${select}&$filter=${encodeURIComponent(filter)}&$top=2`);
    if (rows.length !== 1) {
      blockSyntheticQuery();
      throw new Error("CONSOLE_SCOPED_RECORD_NOT_AVAILABLE");
    }
    return rows[0];
  }

  async function retrieveCandidateRecord(candidateId, select) {
    const c = TABLES.candidate;
    if (!environmentPolicy.syntheticDataOnly) {
      return select === undefined
        ? xrm().WebApi.retrieveRecord(c.logicalName, candidateId)
        : xrm().WebApi.retrieveRecord(c.logicalName, candidateId, select);
    }
    const filter = candidateReferenceScope(candidateScope(
      `${filterAttribute(c.id)} eq ${normalizeGuid(candidateId)}`));
    let columns = candidateColumns();
    if (select !== undefined) {
      if (!select.startsWith("?$select=") || select.includes("&")) {
        throw new Error("CONSOLE_QUERY_SELECT_INVALID");
      }
      columns = select.slice("?$select=".length).split(",");
      for (const marker of [c.name, c.email]) {
        if (!columns.includes(marker)) columns.push(marker);
      }
    }
    const candidate = await retrieveScopedSingle(c.logicalName, `?$select=${columns.join(",")}`, filter);
    requireSyntheticCandidates([candidate]);
    return candidate;
  }

  async function retrieveReferenceRecord(tableName, recordId, metadata, select, activeOnly) {
    if (!environmentPolicy.syntheticDataOnly) {
      return xrm().WebApi.retrieveRecord(tableName, recordId, select);
    }
    const idFilter = `${filterAttribute(metadata.PrimaryIdAttribute)} eq ${normalizeGuid(recordId)}`;
    const filter = referenceScope(activeOnly ? `${idFilter} and statecode eq 0` : idFilter,
      metadata.PrimaryNameAttribute);
    return retrieveScopedSingle(tableName, select, filter);
  }

  async function retrieveInterviewRecord(recordId, candidateId, select, expectedReferences) {
    const interview = TABLES.interview;
    if (!environmentPolicy.syntheticDataOnly) {
      return xrm().WebApi.retrieveRecord(interview.logicalName, recordId, select);
    }
    let filter = candidateScope(
      `${filterAttribute(interview.id)} eq ${normalizeGuid(recordId)} and ` +
      `${interview.candidate} eq ${normalizeGuid(candidateId)}`,
      interview.candidateNavigation
    );
    if (expectedReferences) {
      filter += ` and ${interview.ta} eq ${normalizeGuid(expectedReferences.ta)} and ` +
        `${interview.location} eq ${normalizeGuid(expectedReferences.location)}`;
    }
    return retrieveScopedSingle(interview.logicalName, select, filter);
  }

  function relatedCandidateFilter(table, candidateId, extra = "") {
    const id = environmentPolicy.syntheticDataOnly ? normalizeGuid(candidateId) : candidateId;
    const filter = `${table.candidate} eq ${id}${extra ? ` and ${extra}` : ""}`;
    return candidateScope(filter, table.candidateNavigation);
  }

  function requireSyntheticCandidates(rows) {
    if (environmentPolicy.syntheticDataOnly && rows.some((row) => !isSyntheticCandidateMarkers(row))) {
      blockSyntheticQuery();
      throw new Error("SYNTHETIC_CANDIDATE_RESPONSE_INVALID");
    }
  }

  function appendCell(row, value) {
    const cell = document.createElement("td");
    cell.textContent = value == null ? "" : String(value);
    row.appendChild(cell);
    return cell;
  }

  function renderCandidateRows(rows) {
    currentRows = rows;
    const search = $("candidate-search").value.trim().toLocaleLowerCase();
    const status = $("candidate-status-filter").value;
    const visibleRows = rows.filter((candidate) => {
      const searchMatches = !search || [
        candidate[TABLES.candidate.number],
        candidate[TABLES.candidate.name],
        candidate[TABLES.candidate.email]
      ].some((value) => String(value || "").toLocaleLowerCase().includes(search));
      const statusMatches = !status || String(candidate[TABLES.candidate.status]) === status;
      return searchMatches && statusMatches;
    });
    const body = $("candidate-rows");
    body.replaceChildren();
    if (!visibleRows.length) {
      const row = document.createElement("tr");
      const cell = appendCell(row, rows.length ? "No candidates match the current search and status filter." : "No synthetic candidates found. Create one to get started.");
      cell.colSpan = 11;
      cell.className = "empty";
      body.appendChild(row);
      return;
    }
    for (const candidate of visibleRows) {
      const row = document.createElement("tr");
      row.className = "candidate-row";
      row.tabIndex = 0;
      if (selectedCandidate && selectedCandidate[TABLES.candidate.id] === candidate[TABLES.candidate.id]) {
        row.classList.add("selected");
      }
      row.addEventListener("click", () => {
        if (!busy) openCandidate(candidate[TABLES.candidate.id]);
      });
      row.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          if (!busy) openCandidate(candidate[TABLES.candidate.id]);
        }
      });
      appendCell(row, candidate[TABLES.candidate.number]);
      appendCell(row, candidate[TABLES.candidate.name]);
      appendCell(row, candidate[TABLES.candidate.email]);
      appendCell(row, candidate[TABLES.candidate.phone]);
      appendCell(row, formatted(candidate, TABLES.candidate.position));
      appendCell(row, formatted(candidate, TABLES.candidate.source));
      appendCell(row, formatted(candidate, TABLES.candidate.assignedTa));
      appendCell(row, choiceLabel(candidate, TABLES.candidate.status, STATUS_LABELS));
      appendCell(row, formatted(candidate, "_ownerid_value"));
      appendCell(row, formatDate(candidate.createdon));
      const actions = document.createElement("td");
      actions.className = "actions";
      const open = document.createElement("button");
      open.type = "button";
      open.className = "button button-secondary button-small";
      open.dataset.action = "";
      open.textContent = "Open";
      open.disabled = busy;
      open.addEventListener("click", (event) => {
        event.stopPropagation();
        openCandidate(candidate[TABLES.candidate.id]);
      });
      const call = document.createElement("button");
      call.type = "button";
      call.className = "button button-primary button-small";
      call.dataset.action = "";
      call.textContent = "Record Call";
      call.hidden = !canRecordCall(candidate[TABLES.candidate.status]);
      call.disabled = busy;
      call.addEventListener("click", (event) => {
        event.stopPropagation();
        showCallPanel(candidate);
      });
      actions.append(open, call);
      row.appendChild(actions);
      body.appendChild(row);
    }
  }

  async function refreshCandidates() {
    const c = TABLES.candidate;
    const select = `?$select=${candidateColumns().join(",")}`;
    const syntheticFilter = environmentPolicy.syntheticDataOnly
      ? `&$filter=${encodeURIComponent(candidateReferenceScope(candidateScope()))}`
      : "";
    const rows = await retrieveAll(
      c.logicalName,
      `${select}${syntheticFilter}&$orderby=createdon desc`
    );
    requireSyntheticCandidates(rows);
    renderCandidateRows(rows.filter(isCandidateAllowedByDataMode));
  }

  function addDetailItem(container, label, value) {
    const wrapper = document.createElement("div");
    wrapper.className = "detail-item";
    const term = document.createElement("dt");
    term.textContent = label;
    const detail = document.createElement("dd");
    detail.textContent = value || "";
    wrapper.append(term, detail);
    container.appendChild(wrapper);
  }

  function addDetailLink(container, label, value) {
    const wrapper = document.createElement("div");
    wrapper.className = "detail-item";
    const term = document.createElement("dt");
    term.textContent = label;
    const detail = document.createElement("dd");
    if (typeof value === "string" && value) {
      try {
        const url = new URL(value);
        if (url.protocol === "https:" && !url.username && !url.password) {
          const link = document.createElement("a");
          link.href = url.href;
          link.textContent = url.href;
          link.target = "_blank";
          link.rel = "noopener noreferrer";
          detail.appendChild(link);
        } else {
          detail.textContent = value;
        }
      } catch {
        detail.textContent = value;
      }
    }
    wrapper.append(term, detail);
    container.appendChild(wrapper);
  }

  async function getLookupName(tableLogicalName, id) {
    if (!id) return "";
    const entityMetadata = await xrm().Utility.getEntityMetadata(tableLogicalName);
    const primaryName = entityMetadata.PrimaryNameAttribute;
    const record = await retrieveReferenceRecord(tableLogicalName, id.replace(/[{}]/g, ""),
      entityMetadata, `?$select=${primaryName}`, false);
    if (environmentPolicy.syntheticDataOnly && !isReferenceAllowedByDataMode(record[primaryName])) {
      blockSyntheticQuery();
      throw new Error("SYNTHETIC_REFERENCE_RESPONSE_INVALID");
    }
    return record[primaryName] || "";
  }

  async function renderCandidateDetails(candidate) {
    const details = $("candidate-details");
    details.replaceChildren();
    const lookups = await Promise.all([
      getLookupName("os_sr_pos", candidate[TABLES.candidate.position]),
      getLookupName("os_sr_csrc", candidate[TABLES.candidate.source]),
      getLookupName("os_sr_ta", candidate[TABLES.candidate.assignedTa])
    ]);
    addDetailItem(details, "Candidate Number", candidate[TABLES.candidate.number]);
    addDetailItem(details, "Candidate Name", candidate[TABLES.candidate.name]);
    addDetailItem(details, "Email", candidate[TABLES.candidate.email]);
    addDetailItem(details, "Phone", candidate[TABLES.candidate.phone]);
    addDetailItem(details, "Status", choiceLabel(candidate, TABLES.candidate.status, STATUS_LABELS));
    addDetailItem(details, "Position", lookups[0]);
    addDetailItem(details, "Candidate Source", lookups[1]);
    addDetailItem(details, "Assigned TA", lookups[2]);
    addDetailLink(details, "Candidate CV URL", candidate[TABLES.candidate.cvUrl]);
    addDetailItem(details, "Owner", formatted(candidate, "_ownerid_value"));
    addDetailItem(details, "Created On", formatDate(candidate.createdon));
  }

  async function renderCallHistory(candidateId) {
    const c = TABLES.call;
    const rows = await retrieveAll(c.logicalName,
      `?$select=${[c.id, c.outcome, c.contactedAt, c.notes, c.reference].join(",")}` +
      `&$filter=${encodeURIComponent(relatedCandidateFilter(c, candidateId))}` +
      `&$orderby=${c.contactedAt} desc`);
    const body = $("call-history-rows");
    body.replaceChildren();
    if (!rows.length) {
      const row = document.createElement("tr");
      const cell = appendCell(row, "No call history.");
      cell.colSpan = 3;
      cell.className = "empty";
      body.appendChild(row);
      return;
    }
    for (const call of rows) {
      const row = document.createElement("tr");
      appendCell(row, formatDate(call[c.contactedAt]));
      appendCell(row, choiceLabel(call, c.outcome, OUTCOME_LABELS));
      appendCell(row, call[c.notes]);
      body.appendChild(row);
    }
  }

  async function renderStatusHistory(candidateId) {
    const h = TABLES.history;
    const rows = await retrieveAll(h.logicalName,
      `?$select=${[h.id, h.previous, h.current, h.changedAt, h.reason, "createdon"].join(",")}` +
      `&$filter=${encodeURIComponent(relatedCandidateFilter(h, candidateId))}` +
      `&$orderby=${h.changedAt} desc`);
    const body = $("status-history-rows");
    body.replaceChildren();
    if (!rows.length) {
      const row = document.createElement("tr");
      const cell = appendCell(row, "No status history.");
      cell.colSpan = 4;
      cell.className = "empty";
      body.appendChild(row);
      return;
    }
    for (const history of rows) {
      const row = document.createElement("tr");
      appendCell(row, STATUS_LABELS[history[h.previous]] || String(history[h.previous] ?? ""));
      appendCell(row, STATUS_LABELS[history[h.current]] || String(history[h.current] ?? ""));
      appendCell(row, formatDate(history[h.changedAt] || history.createdon));
      appendCell(row, history[h.reason]);
      body.appendChild(row);
    }
  }

  async function renderSchedulingDetails(candidateId) {
    const interview = TABLES.interview;
    const rows = await retrieveAll(interview.logicalName,
      `?$select=${[interview.id, interview.round, interview.start, interview.end, interview.notes, interview.ta, interview.location, interview.result, interview.resultRecordedAt, interview.resultNotes, interview.status, interview.reason, interview.changedAt, "createdon"].join(",")}` +
      `&$filter=${encodeURIComponent(relatedCandidateFilter(interview, candidateId,
        `${interview.round} eq ${interview.round1}`))}` +
      `&$orderby=createdon desc`);
    const body = $("schedule-history-rows");
    body.replaceChildren();
    scheduleRows = rows;
    const activeSchedules = rows.filter(isActiveSchedule);
    const proposedSchedules = rows.filter((row) => row[interview.status] === SCHEDULE_STATUS.proposed);
    const unknownScheduleStates = rows.some((row) => !isKnownScheduleState(row));
    selectedSchedule = activeSchedules.length === 1 ? activeSchedules[0] : null;
    proposedSchedule = proposedSchedules.length === 1 ? proposedSchedules[0] : null;
    if (!rows.length) {
      const row = document.createElement("tr");
      const cell = appendCell(row, "No Round 1 schedule.");
      cell.colSpan = 12;
      cell.className = "empty";
      body.appendChild(row);
    } else {
      const names = await Promise.all(rows.map((schedule) => Promise.all([
        getLookupName("os_sr_ta", schedule[interview.ta]),
        getLookupName("os_sr_loc", schedule[interview.location])
      ])));
      rows.forEach((schedule, index) => {
        const row = document.createElement("tr");
        appendCell(row, choiceLabel(schedule, interview.round, { [interview.round1]: "Round 1" }));
        appendCell(row, names[index][0]);
        appendCell(row, `${formatDate(schedule[interview.start])} – ${formatDate(schedule[interview.end])}`);
        appendCell(row, names[index][1]);
        appendCell(row, scheduleStatusLabel(schedule));
        appendCell(row, formatDate(schedule[interview.changedAt]));
        appendCell(row, schedule[interview.notes]);
        appendCell(row, schedule[interview.reason]);
        appendCell(row, formatDate(schedule.createdon));
        appendCell(row, choiceLabel(schedule, interview.result, INTERVIEW_RESULT_LABELS) || "Pending");
        appendCell(row, formatDate(schedule[interview.resultRecordedAt]));
        appendCell(row, schedule[interview.resultNotes]);
        body.appendChild(row);
      });
      if (activeSchedules.length > 1 || proposedSchedules.length > 1 || unknownScheduleStates) {
        const warning = document.createElement("tr");
        const cell = appendCell(warning, "Schedule state is ambiguous. No scheduling action is available until the records are reconciled.");
        cell.colSpan = 12;
        cell.className = "empty";
        body.appendChild(warning);
      }
    }
    const canSchedule = selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.waitingManualScheduling &&
      isCandidateAllowedByDataMode(selectedCandidate) &&
      activeSchedules.length === 0 &&
      proposedSchedules.length <= 1 &&
      !unknownScheduleStates;
    $("schedule-round1-button").hidden = !canSchedule;
    $("schedule-round1-button").disabled = busy || !canSchedule ||
      scheduleRetryBlockedCandidateId === candidateId;
    const canRecord = selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled &&
      isCandidateAllowedByDataMode(selectedCandidate) &&
      activeSchedules.length === 1 &&
      proposedSchedules.length === 0 &&
      !unknownScheduleStates &&
      isPendingInterviewResult(selectedSchedule) &&
      resultRetryBlockedCandidateId !== candidateId;
    $("record-interview-result-button").hidden = !canRecord;
    $("record-interview-result-button").disabled = busy || !canRecord;
    if (canRecord) {
      $("record-interview-result-button").removeAttribute("title");
    } else if (resultRetryBlockedCandidateId === candidateId) {
      $("record-interview-result-button").title = "A previous submission needs reconciliation. Reload and verify the persisted result before another action.";
    } else {
      $("record-interview-result-button").removeAttribute("title");
    }
    if (selectedSchedule) {
      $("schedule-round1-button").title = "An active Round 1 schedule already exists.";
    } else if (scheduleRetryBlockedCandidateId === candidateId) {
      $("schedule-round1-button").title = "A previous submission needs reconciliation. Reload before trying again.";
    } else {
      $("schedule-round1-button").removeAttribute("title");
    }
    const canManage = Boolean(selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled &&
      isCandidateAllowedByDataMode(selectedCandidate) &&
      activeSchedules.length === 1 &&
      proposedSchedules.length === 0 &&
      !unknownScheduleStates &&
      isPendingInterviewResult(selectedSchedule));
    $("reschedule-round1-button").hidden = !canManage;
    $("cancel-round1-button").hidden = !canManage;
    $("reschedule-round1-button").disabled = busy || !canManage;
    $("cancel-round1-button").disabled = busy || !canManage;
  }

  function isActiveSchedule(schedule) {
    const status = schedule && schedule[TABLES.interview.status];
    return status == null || status === SCHEDULE_STATUS.scheduled;
  }

  function isKnownScheduleState(schedule) {
    const status = schedule && schedule[TABLES.interview.status];
    return status == null || Object.values(SCHEDULE_STATUS).includes(status);
  }

  function scheduleStatusLabel(schedule) {
    const status = schedule[TABLES.interview.status];
    return status == null
      ? "ACTIVE / SCHEDULED"
      : (SCHEDULE_STATUS_LABELS[status] ||
        choiceLabel(schedule, TABLES.interview.status, SCHEDULE_STATUS_LABELS));
  }

  function canManageSchedule() {
    return Boolean(selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled &&
      isCandidateAllowedByDataMode(selectedCandidate) &&
      scheduleRows.filter(isActiveSchedule).length === 1 &&
      !scheduleRows.some((row) => !isKnownScheduleState(row)) &&
      !scheduleRows.some((row) => row[TABLES.interview.status] === SCHEDULE_STATUS.proposed) &&
      selectedSchedule &&
      isPendingInterviewResult(selectedSchedule));
  }

  async function openCandidate(candidateId) {
    hideNotice();
    try {
      const candidate = currentRows.find((row) => row[TABLES.candidate.id] === candidateId) ||
        await retrieveCandidateRecord(candidateId);
      if (!isCandidateAllowedByDataMode(candidate)) throw new Error("CONSOLE_CANDIDATE_NOT_AVAILABLE");
      selectedCandidate = candidate;
      selectedSchedule = null;
      proposedSchedule = null;
      scheduleRows = [];
      $("scheduling-panel").hidden = true;
      $("edit-candidate-panel").hidden = true;
      $("edit-candidate-button").hidden = !isCandidateAllowedByDataMode(candidate);
      $("interview-result-panel").hidden = true;
      $("cancellation-panel").hidden = true;
      $("schedule-round1-button").hidden = true;
      $("record-interview-result-button").hidden = true;
      $("reschedule-round1-button").hidden = true;
      $("cancel-round1-button").hidden = true;
      $("detail-heading").textContent = candidate[TABLES.candidate.name] || "Candidate";
      $("detail-panel").hidden = false;
      const callAllowed = canRecordCall(candidate[TABLES.candidate.status]);
      $("call-entry-panel").hidden = !callAllowed;
      $("call-candidate-label").textContent =
        `${candidate[TABLES.candidate.number] || ""} ${candidate[TABLES.candidate.name] || ""}`.trim();
      $("submit-call").disabled = busy || !callAllowed;
      const canMoveToWaiting = candidate[TABLES.candidate.status] === STATUS.answered;
      const canSchedule = candidate[TABLES.candidate.status] === STATUS.waitingManualScheduling &&
        isCandidateAllowedByDataMode(candidate);
      $("waiting-status-button").hidden = !canMoveToWaiting;
      $("waiting-status-button").disabled = busy || !canMoveToWaiting;
      $("schedule-round1-button").hidden = !canSchedule;
      $("schedule-round1-button").disabled = busy || !canSchedule;
      $("record-interview-result-button").hidden = true;
      $("interview-result-panel").hidden = true;
      renderCandidateRows(currentRows);
      await Promise.all([
        renderCandidateDetails(candidate),
        renderCallHistory(candidateId),
        renderStatusHistory(candidateId),
        renderSchedulingDetails(candidateId)
      ]);
      $("interview-result-panel").hidden = true;
      $("detail-panel").scrollIntoView({ behavior: "smooth", block: "start" });
      return true;
    } catch {
      logSafeFailure("DEV_DIRECT_WRITE_CANDIDATE_DETAIL_READ_FAILED");
      showNotice("Candidate details could not be loaded. Refresh and try again.", true);
      return false;
    }
  }

  async function reconcileAfterFailure(candidateId) {
    let reconciled = true;
    try {
      await refreshCandidates();
    } catch (error) {
      reconciled = false;
      logSafeFailure("DEV_DIRECT_WRITE_RECONCILIATION_FAILED", error);
    }
    const id = candidateId || (selectedCandidate && selectedCandidate[TABLES.candidate.id]);
    if (id && !(await openCandidate(id))) reconciled = false;
    return reconciled;
  }

  function addOption(select, value, label) {
    const option = document.createElement("option");
    option.value = value;
    option.textContent = label;
    select.appendChild(option);
  }

  async function loadLookupOptions(tableName, selectIds, emptyLabels) {
    const ids = Array.isArray(selectIds) ? selectIds : [selectIds];
    const labels = Array.isArray(emptyLabels) ? emptyLabels : ids.map(() => emptyLabels);
    if (ids.length !== labels.length) throw new Error("REFERENCE_SELECTOR_CONFIGURATION_INVALID");
    const metadata = await xrm().Utility.getEntityMetadata(tableName);
    const primaryName = metadata.PrimaryNameAttribute;
    const filter = referenceScope("statecode eq 0", primaryName);
    const rows = await retrieveAll(tableName,
      `?$select=${metadata.PrimaryIdAttribute},${primaryName},statecode` +
      `&$filter=${encodeURIComponent(filter)}&$orderby=${primaryName} asc`);
    if (environmentPolicy.syntheticDataOnly && rows.some((row) => {
      try {
        normalizeGuid(row[metadata.PrimaryIdAttribute]);
        return row.statecode !== 0 || !isReferenceAllowedByDataMode(row[primaryName]);
      } catch {
        return true;
      }
    })) {
      blockSyntheticQuery();
      throw new Error("SYNTHETIC_REFERENCE_RESPONSE_INVALID");
    }
    const selects = ids.map((id) => $(id));
    selects.forEach((select, index) => {
      select.replaceChildren();
      addOption(select, "", labels[index]);
    });
    for (const row of rows) {
      const id = row[metadata.PrimaryIdAttribute];
      const label = row[primaryName];
      if (!id || !isReferenceAllowedByDataMode(label)) continue;
      selects.forEach((select) => addOption(select, id, label));
    }
  }

  function showSchedulingPanel(mode = "new") {
    if (busy || !selectedCandidate) return;
    if (mode === "reschedule" ? !canManageSchedule() :
        selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
        !isCandidateAllowedByDataMode(selectedCandidate) ||
        scheduleRows.filter(isActiveSchedule).length > 0) {
      showNotice(mode === "reschedule"
        ? "Reschedule Round 1 requires exactly one active, pending Round 1 schedule."
        : "Schedule Round 1 is available only for synthetic candidates in Waiting Manual Scheduling with no active schedule.", true);
      return;
    }
    if (scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id]) {
      showNotice("A previous Round 1 schedule submission needs reconciliation. Refresh or reload before trying again.", true);
      return;
    }
    scheduleMode = mode === "reschedule"
      ? "reschedule"
      : (proposedSchedule ? "promote" : "new");
    $("scheduling-form").reset();
    $("scheduling-reason").required = scheduleMode === "reschedule";
    $("scheduling-reason-field").hidden = scheduleMode !== "reschedule";
    $("scheduling-heading").textContent = scheduleMode === "reschedule"
      ? "Reschedule Round 1"
      : scheduleMode === "promote"
        ? "Confirm Proposed Round 1 Schedule"
        : "Schedule Round 1";
    $("scheduling-candidate").value =
      `${selectedCandidate[TABLES.candidate.number] || ""} ${selectedCandidate[TABLES.candidate.name] || ""}`.trim();
    $("scheduling-panel").hidden = false;
    $("cancellation-panel").hidden = true;
    setBusy(false);
    $("scheduling-panel").scrollIntoView({ behavior: "smooth", block: "center" });
    $("scheduling-ta").focus();
  }

  function showCancellationPanel() {
    if (busy || !canManageSchedule()) {
      showNotice("Cancel Round 1 requires exactly one active, pending Round 1 schedule.", true);
      return;
    }
    $("cancellation-form").reset();
    $("cancellation-panel").hidden = false;
    $("scheduling-panel").hidden = true;
    $("cancellation-panel").scrollIntoView({ behavior: "smooth", block: "center" });
    $("cancellation-reason").focus();
  }

  function localDateTime(dateValue, timeValue) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dateValue) || !/^\d{2}:\d{2}$/.test(timeValue)) {
      return null;
    }
    const dateTime = new Date(`${dateValue}T${timeValue}:00`);
    if (Number.isNaN(dateTime.getTime()) ||
        dateTime.getFullYear() !== Number(dateValue.slice(0, 4)) ||
        dateTime.getMonth() !== Number(dateValue.slice(5, 7)) - 1 ||
        dateTime.getDate() !== Number(dateValue.slice(8, 10))) {
      return null;
    }
    return dateTime;
  }

  async function getActiveReference(tableName, value) {
    const id = normalizeGuid(value);
    const metadata = await xrm().Utility.getEntityMetadata(tableName);
    if (!metadata.PrimaryIdAttribute || !metadata.PrimaryNameAttribute || !metadata.EntitySetName) {
      throw new Error("CANDIDATE_REFERENCE_METADATA_INVALID");
    }
    const reference = await retrieveReferenceRecord(tableName, id, metadata,
      `?$select=${[metadata.PrimaryIdAttribute, metadata.PrimaryNameAttribute, "statecode"].join(",")}`,
      true);
    if (reference.statecode !== 0 ||
        typeof reference[metadata.PrimaryNameAttribute] !== "string" ||
        !isReferenceAllowedByDataMode(reference[metadata.PrimaryNameAttribute])) {
      if (environmentPolicy.syntheticDataOnly) blockSyntheticQuery();
      throw new Error("CANDIDATE_REFERENCE_NOT_AVAILABLE");
    }
    return { id, entitySetName: metadata.EntitySetName };
  }

  async function getSelectedActiveReference(tableName, selectId) {
    const value = $(selectId).value;
    return value ? getActiveReference(tableName, value) : null;
  }

  async function findRound1Schedules(candidateId) {
    const interview = TABLES.interview;
    return retrieveAll(interview.logicalName,
      `?$select=${[interview.id, interview.round, interview.start, interview.result, interview.status, interview.reason, interview.changedAt].join(",")}` +
      `&$filter=${encodeURIComponent(relatedCandidateFilter(interview, candidateId,
        `${interview.round} eq ${interview.round1}`))}` +
      `&$orderby=createdon desc`);
  }

  function isPendingInterviewResult(schedule) {
    return Boolean(schedule &&
      (schedule[TABLES.interview.result] == null ||
        schedule[TABLES.interview.result] === INTERVIEW_RESULT.pending));
  }

  function canRecordInterviewResult() {
    return Boolean(selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled &&
      isCandidateAllowedByDataMode(selectedCandidate) &&
      selectedSchedule &&
      isActiveSchedule(selectedSchedule) &&
      isPendingInterviewResult(selectedSchedule) &&
      resultRetryBlockedCandidateId !== selectedCandidate[TABLES.candidate.id]);
  }

  function showInterviewResultPanel() {
    if (busy || !canRecordInterviewResult()) return;
    $("interview-result-form").reset();
    $("interview-result-candidate").textContent =
      `${selectedCandidate[TABLES.candidate.number] || ""} ${selectedCandidate[TABLES.candidate.name] || ""}`.trim();
    $("interview-result-panel").hidden = false;
    $("interview-result-panel").scrollIntoView({ behavior: "smooth", block: "center" });
    $("interview-result-choice").focus();
  }

  async function recordInterviewResultThroughCore(event) {
    event.preventDefault();
    if (busy || !selectedCandidate || !canRecordInterviewResult()) return;
    hideNotice();
    const c = TABLES.candidate;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    const result = Number($("interview-result-choice").value);
    if (!isCandidateCoreEnabled() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Interview results are unavailable for this candidate under the configured data mode.", true);
      return;
    }
    if (![INTERVIEW_RESULT.pass, INTERVIEW_RESULT.fail].includes(result)) {
      showNotice("Choose Pass or Fail.", true);
      return;
    }

    const action = result === INTERVIEW_RESULT.pass ? "RecordPass" : "RecordFail";
    const expectedStatus = result === INTERVIEW_RESULT.pass
      ? STATUS.offerExtended
      : STATUS.candidateFailed;
    setBusy(true);
    try {
      const { result: response } = await invokeCandidateCore(action, {
        CandidateId: candidateId,
        ExpectedStatus: STATUS.round1Scheduled,
        ResultNotes: $("interview-result-notes").value.trim() || undefined
      });
      assertCandidateCoreStatus(response, expectedStatus);
      $("interview-result-form").reset();
      $("interview-result-panel").hidden = true;
      await refreshCoreCandidate(candidateId);
      showNotice(result === INTERVIEW_RESULT.pass
        ? "Round 1 result saved: Pass. Candidate moved to Offer Extended."
        : "Round 1 result saved: Fail. Candidate moved to Candidate Failed.");
    } catch (error) {
      await reportCandidateCoreFailure(action, candidateId, error);
    } finally {
      setBusy(false);
    }
  }

  async function recordInterviewResult(event) {
    if (!isDevFallbackEnabled()) return recordInterviewResultThroughCore(event);
    event.preventDefault();
    if (busy || !selectedCandidate || !canRecordInterviewResult()) return;
    hideNotice();
    const c = TABLES.candidate;
    const interview = TABLES.interview;
    const history = TABLES.history;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    const scheduleId = normalizeGuid(selectedSchedule[interview.id]);
    if (!isDevConfiguration() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Interview results are unavailable for this candidate under the configured data mode.", true);
      return;
    }
    const result = Number($("interview-result-choice").value);
    if (![INTERVIEW_RESULT.pass, INTERVIEW_RESULT.fail].includes(result)) {
      showNotice("Choose Pass or Fail.", true);
      return;
    }

    setBusy(true);
    let category = "INTERVIEW_RESULT_CANDIDATE_READ_FAILED";
    let resultUpdateAttempted = false;
    let resultReadbackConfirmed = false;
    let candidateStatusUpdateAttempted = false;
    let candidateStatusUpdated = false;
    let historyCreated = false;
    try {
      const current = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(current) || current[c.status] !== STATUS.round1Scheduled) {
        await reconcileAfterFailure(candidateId);
        showNotice("Candidate is no longer Round 1 Scheduled. No interview result was written.", true);
        return;
      }

      category = "INTERVIEW_RESULT_SCHEDULE_READ_FAILED";
      const schedules = await findRound1Schedules(candidateId);
      const activeSchedules = schedules.filter(isActiveSchedule);
      if (schedules.some((row) => !isKnownScheduleState(row)) ||
          activeSchedules.length !== 1 ||
          normalizeGuid(activeSchedules[0][interview.id]) !== scheduleId ||
          !isPendingInterviewResult(activeSchedules[0])) {
        await reconcileAfterFailure(candidateId);
        showNotice("Exactly one active pending Round 1 schedule could not be verified. No interview result was written.", true);
        return;
      }

      const recordedAt = new Date().toISOString();
      const notes = $("interview-result-notes").value.trim();
      const payload = {
        [interview.result]: result,
        [interview.resultRecordedAt]: recordedAt
      };
      if (notes) payload[interview.resultNotes] = notes;

      category = "INTERVIEW_RESULT_UPDATE_FAILED";
      resultUpdateAttempted = true;
      await xrm().WebApi.updateRecord(interview.logicalName, scheduleId, payload);

      category = "INTERVIEW_RESULT_READBACK_FAILED";
      const saved = await retrieveInterviewRecord(
        scheduleId,
        candidateId,
        `?$select=${[interview.id, interview.candidate, interview.round, interview.result, interview.resultRecordedAt, interview.resultNotes].join(",")}`
      );
      const savedRecordedAt = Date.parse(saved[interview.resultRecordedAt]);
      const expectedRecordedAt = Date.parse(recordedAt);
      const readbackChecks = {
        candidate: typeof saved[interview.candidate] === "string" &&
          normalizeGuid(saved[interview.candidate]) === candidateId,
        round: saved[interview.round] === interview.round1,
        result: saved[interview.result] === result,
        recordedAt: Number.isFinite(savedRecordedAt) &&
          Math.floor(savedRecordedAt / 1000) === Math.floor(expectedRecordedAt / 1000),
        notes: !notes || saved[interview.resultNotes] === notes
      };
      const failedReadbackChecks = Object.keys(readbackChecks)
        .filter((check) => !readbackChecks[check]);
      if (failedReadbackChecks.length) {
        category = `INTERVIEW_RESULT_READBACK_${failedReadbackChecks.join("_").toUpperCase()}_MISMATCH`;
        throw new Error("DEV_DIRECT_WRITE_INTERVIEW_RESULT_READBACK_MISMATCH");
      }
      resultReadbackConfirmed = true;

      category = "INTERVIEW_RESULT_CANDIDATE_STATUS_READ_FAILED";
      const beforeStatusUpdate = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(beforeStatusUpdate) ||
          beforeStatusUpdate[c.status] !== STATUS.round1Scheduled) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_STATUS_CHANGED_AFTER_RESULT");
      }
      const nextStatus = result === INTERVIEW_RESULT.pass
        ? STATUS.offerExtended
        : STATUS.candidateFailed;
      candidateStatusUpdateAttempted = true;

      category = "INTERVIEW_RESULT_CANDIDATE_STATUS_UPDATE_FAILED";
      await xrm().WebApi.updateRecord(c.logicalName, candidateId, {
        [c.status]: nextStatus
      });
      candidateStatusUpdated = true;

      category = "INTERVIEW_RESULT_STATUS_HISTORY_CREATE_FAILED";
      await xrm().WebApi.createRecord(history.logicalName, {
        [`${history.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${history.actorNavigation}@odata.bind`]: `/systemusers(${currentUserId()})`,
        [history.previous]: STATUS.round1Scheduled,
        [history.current]: nextStatus,
        [history.changedAt]: new Date().toISOString(),
        [history.correlation]: newCorrelationId(),
        [history.action]: result === INTERVIEW_RESULT.pass ? "RecordRound1Pass" : "RecordRound1Fail",
        [history.reason]: "DEV Candidate Management / Record Interview Result"
      });
      historyCreated = true;

      category = "INTERVIEW_RESULT_REFRESH_FAILED";
      $("interview-result-form").reset();
      $("interview-result-panel").hidden = true;
      await refreshCandidates();
      if (!(await openCandidate(candidateId))) {
        throw new Error("DEV_DIRECT_WRITE_INTERVIEW_RESULT_DETAIL_REFRESH_FAILED");
      }
      showNotice(result === INTERVIEW_RESULT.pass
        ? "Round 1 result saved: Pass. Candidate moved to Offer Extended."
        : "Round 1 result saved: Fail. Candidate moved to Candidate Failed.");
    } catch (error) {
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      if (resultUpdateAttempted) resultRetryBlockedCandidateId = candidateId;
      const reconciled = await reconcileAfterFailure(candidateId);
      let message;
      if (!resultUpdateAttempted) {
        message = "Interview result was not submitted. Verify the Candidate and schedule, then try again.";
      } else if (!resultReadbackConfirmed) {
        message = "Interview result update or readback is uncertain. Candidate status was not changed; refresh and reconcile before any retry.";
      } else if (!candidateStatusUpdateAttempted || !candidateStatusUpdated) {
        message = "Interview result was persisted, but the Candidate status update failed or is uncertain. The result remains; no Status History was fabricated. Reconcile before retrying.";
      } else if (!historyCreated) {
        message = "Interview result and Candidate status were persisted, but Status History creation failed or is uncertain. No compensation or retry was performed; reconcile the current state.";
      } else {
        message = "Interview result, Candidate status, and Status History were saved, but the UI refresh failed. Refresh to verify the current server state.";
      }
      showNotice(reconciled ? message : `${message} Server-state refresh was incomplete.`, true);
    } finally {
      setBusy(false);
    }
  }

  async function createScheduleThroughCore(event) {
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    if (scheduleMode === "reschedule" && !canManageSchedule()) return;
    hideNotice();
    const c = TABLES.candidate;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    if (!isCandidateCoreEnabled() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Scheduling is unavailable for this candidate under the configured data mode.", true);
      return;
    }
    const start = localDateTime($("scheduling-date").value, $("scheduling-time").value);
    const end = localDateTime($("scheduling-date").value, $("scheduling-end-time").value);
    if (!start || !end || start.getTime() <= Date.now() || end <= start) {
      showNotice("Choose a future date and an End Time later than the Start Time on the same date.", true);
      return;
    }
    let action = "MarkRound1Scheduled";
    let expectedStatus = STATUS.round1Scheduled;
    const inputs = {};
    if (scheduleMode === "reschedule") {
      const reason = $("scheduling-reason").value.trim();
      if (!reason) {
        showNotice("Enter a Reschedule Reason.", true);
        return;
      }
      action = "RequestReschedule";
      expectedStatus = STATUS.needCall;
      inputs.Reason = reason;
    } else if (selectedCandidate[c.status] !== STATUS.waitingManualScheduling) {
      showNotice("Round 1 can be scheduled only from Waiting Manual Scheduling.", true);
      return;
    }

    setBusy(true);
    try {
      const ta = await getActiveReference("os_sr_ta", $("scheduling-ta").value);
      const location = await getActiveReference("os_sr_loc", $("scheduling-location").value);
      inputs.InterviewerId = ta.id;
      inputs.LocationId = location.id;
      inputs.StartAt = start.toISOString();
      inputs.EndAt = end.toISOString();
      inputs.Notes = $("scheduling-notes").value.trim() || undefined;
      const { result } = await invokeCandidateCore(action, {
        CandidateId: candidateId,
        ExpectedStatus: selectedCandidate[c.status],
        ...inputs
      });
      assertCandidateCoreStatus(result, expectedStatus);
      $("scheduling-form").reset();
      $("scheduling-panel").hidden = true;
      scheduleMode = "new";
      await refreshCoreCandidate(candidateId);
      showNotice(action === "RequestReschedule"
        ? "Round 1 rescheduled. The previous schedule is preserved as Superseded, the replacement is Proposed, and the Candidate returned to Need Call Candidate."
        : "Round 1 schedule saved and Candidate moved to Round 1 Scheduled.");
    } catch (error) {
      await reportCandidateCoreFailure(action, candidateId, error);
    } finally {
      setBusy(false);
    }
  }

  async function createSchedule(event) {
    if (!isDevFallbackEnabled()) return createScheduleThroughCore(event);
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    if (scheduleMode === "reschedule") {
      await rescheduleRound1();
      return;
    }
    hideNotice();
    const c = TABLES.candidate;
    const interview = TABLES.interview;
    const history = TABLES.history;
    let candidateId;
    try {
      candidateId = normalizeGuid(selectedCandidate[c.id]);
    } catch (error) {
      logSafeFailure("DEV_DIRECT_WRITE_INVALID_CANDIDATE_REFERENCE", error);
      showNotice("Candidate reference is invalid. Refresh the list and select the Candidate again.", true);
      return;
    }
    if (!isDevConfiguration() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Scheduling is unavailable for this candidate under the configured data mode.", true);
      return;
    }
    if (selectedCandidate[c.status] !== STATUS.waitingManualScheduling) {
      showNotice("Round 1 can be scheduled only from Waiting Manual Scheduling.", true);
      return;
    }
    const start = localDateTime($("scheduling-date").value, $("scheduling-time").value);
    const end = localDateTime($("scheduling-date").value, $("scheduling-end-time").value);
    if (!start || !end || start.getTime() <= Date.now() || end <= start) {
      showNotice("Choose a future date and an End Time later than the Start Time on the same date.", true);
      return;
    }
    if (selectedSchedule || scheduleRetryBlockedCandidateId === candidateId) {
      showNotice("A previous Round 1 schedule submission needs reconciliation. Refresh or reload before trying again.", true);
      return;
    }

    setBusy(true);
    let category = "SCHEDULE_CANDIDATE_READ_FAILED";
    let scheduleCreateAttempted = false;
    let scheduleReadbackConfirmed = false;
    let statusUpdateAttempted = false;
    let statusUpdated = false;
    let historyCreated = false;
    try {
      const current = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(current)) {
        showNotice("Scheduling is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
        return;
      }
      if (current[c.status] !== STATUS.waitingManualScheduling) {
        await reconcileAfterFailure(candidateId);
        showNotice("Candidate status changed. No schedule was created; refresh and verify the current state.", true);
        return;
      }
      const existingSchedules = await findRound1Schedules(candidateId);
      const activeSchedules = existingSchedules.filter(isActiveSchedule);
      const proposals = existingSchedules.filter((row) => row[interview.status] === SCHEDULE_STATUS.proposed);
      if (existingSchedules.some((row) => !isKnownScheduleState(row)) ||
          activeSchedules.length || proposals.length > 1 ||
          (scheduleMode === "promote" && proposals.length !== 1) ||
          (scheduleMode === "promote" && !isPendingInterviewResult(proposals[0])) ||
          (scheduleMode === "new" && proposals.length !== 0)) {
        await reconcileAfterFailure(candidateId);
        showNotice("Round 1 schedule state changed or is ambiguous. No schedule was written; reconcile the Candidate state.", true);
        return;
      }
      const ta = await getActiveReference("os_sr_ta", $("scheduling-ta").value);
      const location = await getActiveReference("os_sr_loc", $("scheduling-location").value);
      const userId = currentUserId();
      const changedAt = new Date().toISOString();
      const payload = {
        [`${interview.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${interview.taNavigation}@odata.bind`]: `/${ta.entitySetName}(${ta.id})`,
        [`${interview.locationNavigation}@odata.bind`]: `/${location.entitySetName}(${location.id})`,
        [interview.round]: interview.round1,
        [interview.result]: INTERVIEW_RESULT.pending,
        [interview.status]: SCHEDULE_STATUS.scheduled,
        [interview.changedAt]: changedAt,
        [interview.start]: start.toISOString(),
        [interview.end]: end.toISOString()
      };
      const notes = $("scheduling-notes").value.trim();
      if (notes) payload[interview.notes] = notes;

      category = "SCHEDULE_CREATE_FAILED";
      scheduleCreateAttempted = true;
      let persistedScheduleId = scheduleMode === "promote"
        ? normalizeGuid(proposals[0][interview.id])
        : null;
      if (persistedScheduleId) {
        delete payload[`${interview.candidateNavigation}@odata.bind`];
        delete payload[interview.result];
        await xrm().WebApi.updateRecord(interview.logicalName, persistedScheduleId, payload);
      } else {
        const result = await xrm().WebApi.createRecord(interview.logicalName, payload);
        persistedScheduleId = result && typeof result.id === "string" ? normalizeGuid(result.id) : null;
      }
      if (!persistedScheduleId) throw new Error("DEV_DIRECT_WRITE_SCHEDULE_ID_MISSING");

      category = "SCHEDULE_READBACK_FAILED";
      const saved = await retrieveInterviewRecord(
        persistedScheduleId,
        candidateId,
        `?$select=${[interview.id, interview.round, interview.result, interview.status, interview.changedAt, interview.candidate, interview.ta, interview.location, interview.start, interview.end, interview.notes].join(",")}`,
        { ta: ta.id, location: location.id }
      );
      if (normalizeGuid(saved[interview.candidate]) !== candidateId ||
          normalizeGuid(saved[interview.ta]) !== ta.id ||
          normalizeGuid(saved[interview.location]) !== location.id ||
          saved[interview.round] !== interview.round1 ||
          saved[interview.result] !== INTERVIEW_RESULT.pending ||
          saved[interview.status] !== SCHEDULE_STATUS.scheduled ||
          !sameInstant(saved[interview.changedAt], changedAt) ||
          Date.parse(saved[interview.start]) !== start.getTime() ||
          Date.parse(saved[interview.end]) !== end.getTime()) {
        throw new Error("DEV_DIRECT_WRITE_SCHEDULE_READBACK_MISMATCH");
      }
      scheduleReadbackConfirmed = true;

      category = "SCHEDULE_CANDIDATE_STATUS_UPDATE_FAILED";
      const beforeStatusUpdate = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(beforeStatusUpdate) ||
          beforeStatusUpdate[c.status] !== STATUS.waitingManualScheduling) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_STATUS_CHANGED_AFTER_SCHEDULE");
      }
      statusUpdateAttempted = true;
      await xrm().WebApi.updateRecord(c.logicalName, candidateId, {
        [c.status]: STATUS.round1Scheduled
      });
      statusUpdated = true;

      category = "SCHEDULE_STATUS_HISTORY_CREATE_FAILED";
      await xrm().WebApi.createRecord(history.logicalName, {
        [`${history.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${history.actorNavigation}@odata.bind`]: `/systemusers(${userId})`,
        [history.previous]: STATUS.waitingManualScheduling,
        [history.current]: STATUS.round1Scheduled,
        [history.changedAt]: new Date().toISOString(),
        [history.correlation]: newCorrelationId(),
        [history.action]: "ScheduleRound1",
        [history.reason]: "DEV Candidate Management / Schedule Round 1"
      });
      historyCreated = true;

      category = "SCHEDULE_REFRESH_FAILED";
      $("scheduling-form").reset();
      $("scheduling-panel").hidden = true;
      await refreshCandidates();
      if (!(await openCandidate(candidateId))) {
        throw new Error("DEV_DIRECT_WRITE_SCHEDULE_DETAIL_REFRESH_FAILED");
      }
      showNotice(scheduleMode === "promote"
        ? "Proposed Round 1 schedule confirmed and Candidate moved to Round 1 Scheduled."
        : "Round 1 schedule saved and Candidate moved to Round 1 Scheduled.");
    } catch (error) {
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      if (scheduleCreateAttempted) scheduleRetryBlockedCandidateId = candidateId;
      const reconciled = await reconcileAfterFailure(candidateId);
      let message;
      if (!scheduleCreateAttempted) {
        message = "Schedule could not be submitted. No schedule write was attempted; verify the selected DEV references and try again.";
      } else if (!scheduleReadbackConfirmed) {
        message = "Schedule creation or readback is uncertain. Candidate status was not updated; refresh and reconcile before any retry.";
      } else if (!statusUpdateAttempted || !statusUpdated) {
        message = "Schedule was persisted, but the Candidate status update failed or is uncertain. The schedule remains; no Status History was fabricated. Reconcile before retrying.";
      } else if (!historyCreated) {
        message = "Schedule and Candidate status were persisted, but Status History creation failed or is uncertain. No compensation or retry was performed; reconcile the current state.";
      } else {
        message = "Schedule, Candidate status, and Status History were saved, but the UI refresh failed. Refresh to verify the current server state.";
      }
      showNotice(reconciled ? message : `${message} Server-state refresh was incomplete.`, true);
    } finally {
      setBusy(false);
    }
  }

  async function rescheduleRound1() {
    if (busy || !selectedCandidate || !canManageSchedule()) return;
    hideNotice();
    const c = TABLES.candidate;
    const interview = TABLES.interview;
    const history = TABLES.history;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    const previousScheduleId = normalizeGuid(selectedSchedule[interview.id]);
    const reason = $("scheduling-reason").value.trim();
    const start = localDateTime($("scheduling-date").value, $("scheduling-time").value);
    const end = localDateTime($("scheduling-date").value, $("scheduling-end-time").value);
    if (!reason) {
      showNotice("Enter a Reschedule Reason.", true);
      return;
    }
    if (!start || !end || start.getTime() <= Date.now() || end <= start) {
      showNotice("Choose a future date and an End Time later than the Start Time on the same date.", true);
      return;
    }
    if (!isDevConfiguration() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Rescheduling is unavailable for this candidate under the configured data mode.", true);
      return;
    }

    setBusy(true);
    let category = "RESCHEDULE_CANDIDATE_READ_FAILED";
    let scheduleUpdateAttempted = false;
    let oldScheduleReadbackConfirmed = false;
    let proposalCreateAttempted = false;
    let proposalReadbackConfirmed = false;
    let candidateStatusUpdateAttempted = false;
    let candidateStatusUpdated = false;
    let historyCreated = false;
    try {
      const current = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(current) || current[c.status] !== STATUS.round1Scheduled) {
        await reconcileAfterFailure(candidateId);
        showNotice("Reschedule is available only while the synthetic Candidate is Round 1 Scheduled.", true);
        return;
      }

      category = "RESCHEDULE_SCHEDULE_READ_FAILED";
      const schedules = await findRound1Schedules(candidateId);
      const activeSchedules = schedules.filter(isActiveSchedule);
      if (schedules.some((row) => !isKnownScheduleState(row)) ||
          activeSchedules.length !== 1 ||
          normalizeGuid(activeSchedules[0][interview.id]) !== previousScheduleId ||
          !isPendingInterviewResult(activeSchedules[0])) {
        await reconcileAfterFailure(candidateId);
        showNotice("Exactly one active pending Round 1 schedule could not be verified. No reschedule was written.", true);
        return;
      }

      const ta = await getActiveReference("os_sr_ta", $("scheduling-ta").value);
      const location = await getActiveReference("os_sr_loc", $("scheduling-location").value);
      const userId = currentUserId();
      const changedAt = new Date().toISOString();
      category = "RESCHEDULE_OLD_SCHEDULE_UPDATE_FAILED";
      scheduleUpdateAttempted = true;
      await xrm().WebApi.updateRecord(interview.logicalName, previousScheduleId, {
        [interview.status]: SCHEDULE_STATUS.superseded,
        [interview.reason]: reason,
        [interview.changedAt]: changedAt
      });

      category = "RESCHEDULE_OLD_SCHEDULE_READBACK_FAILED";
      const superseded = await retrieveInterviewRecord(
        previousScheduleId,
        candidateId,
        `?$select=${[interview.id, interview.candidate, interview.round, interview.result, interview.status, interview.reason, interview.changedAt].join(",")}`
      );
      if (normalizeGuid(superseded[interview.candidate]) !== candidateId ||
          superseded[interview.round] !== interview.round1 ||
          superseded[interview.status] !== SCHEDULE_STATUS.superseded ||
          superseded[interview.reason] !== reason ||
          !sameInstant(superseded[interview.changedAt], changedAt) ||
          !isPendingInterviewResult(superseded)) {
        throw new Error("DEV_DIRECT_WRITE_SUPERSEDED_SCHEDULE_READBACK_MISMATCH");
      }
      oldScheduleReadbackConfirmed = true;

      const payload = {
        [`${interview.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${interview.taNavigation}@odata.bind`]: `/${ta.entitySetName}(${ta.id})`,
        [`${interview.locationNavigation}@odata.bind`]: `/${location.entitySetName}(${location.id})`,
        [interview.round]: interview.round1,
        [interview.result]: INTERVIEW_RESULT.pending,
        [interview.status]: SCHEDULE_STATUS.proposed,
        [interview.reason]: reason,
        [interview.changedAt]: changedAt,
        [interview.start]: start.toISOString(),
        [interview.end]: end.toISOString()
      };
      const notes = $("scheduling-notes").value.trim();
      if (notes) payload[interview.notes] = notes;

      category = "RESCHEDULE_PROPOSAL_CREATE_FAILED";
      proposalCreateAttempted = true;
      const created = await xrm().WebApi.createRecord(interview.logicalName, payload);
      const proposalId = created && typeof created.id === "string" ? normalizeGuid(created.id) : null;
      if (!proposalId) throw new Error("DEV_DIRECT_WRITE_RESCHEDULE_PROPOSAL_ID_MISSING");

      category = "RESCHEDULE_PROPOSAL_READBACK_FAILED";
      const proposal = await retrieveInterviewRecord(
        proposalId,
        candidateId,
        `?$select=${[interview.id, interview.candidate, interview.round, interview.ta, interview.location, interview.result, interview.status, interview.reason, interview.changedAt, interview.start, interview.end].join(",")}`,
        { ta: ta.id, location: location.id }
      );
      if (normalizeGuid(proposal[interview.candidate]) !== candidateId ||
          normalizeGuid(proposal[interview.ta]) !== ta.id ||
          normalizeGuid(proposal[interview.location]) !== location.id ||
          proposal[interview.round] !== interview.round1 ||
          proposal[interview.result] !== INTERVIEW_RESULT.pending ||
          proposal[interview.status] !== SCHEDULE_STATUS.proposed ||
          proposal[interview.reason] !== reason ||
          !sameInstant(proposal[interview.changedAt], changedAt) ||
          Date.parse(proposal[interview.start]) !== start.getTime() ||
          Date.parse(proposal[interview.end]) !== end.getTime()) {
        throw new Error("DEV_DIRECT_WRITE_RESCHEDULE_PROPOSAL_READBACK_MISMATCH");
      }
      proposalReadbackConfirmed = true;

      category = "RESCHEDULE_CANDIDATE_STATUS_UPDATE_FAILED";
      const beforeStatusUpdate = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(beforeStatusUpdate) ||
          beforeStatusUpdate[c.status] !== STATUS.round1Scheduled) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_STATUS_CHANGED_DURING_RESCHEDULE");
      }
      candidateStatusUpdateAttempted = true;
      await xrm().WebApi.updateRecord(c.logicalName, candidateId, {
        [c.status]: STATUS.needCall
      });
      candidateStatusUpdated = true;

      category = "RESCHEDULE_STATUS_HISTORY_CREATE_FAILED";
      await xrm().WebApi.createRecord(history.logicalName, {
        [`${history.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${history.actorNavigation}@odata.bind`]: `/systemusers(${userId})`,
        [history.previous]: STATUS.round1Scheduled,
        [history.current]: STATUS.needCall,
        [history.changedAt]: new Date().toISOString(),
        [history.correlation]: newCorrelationId(),
        [history.action]: "RescheduleRound1",
        [history.reason]: `DEV Candidate Management / Reschedule Round 1: ${reason}`
      });
      historyCreated = true;

      category = "RESCHEDULE_REFRESH_FAILED";
      $("scheduling-form").reset();
      $("scheduling-panel").hidden = true;
      scheduleMode = "new";
      await refreshCandidates();
      if (!(await openCandidate(candidateId))) {
        throw new Error("DEV_DIRECT_WRITE_RESCHEDULE_DETAIL_REFRESH_FAILED");
      }
      showNotice("Round 1 rescheduled. The previous schedule is preserved as Superseded, the replacement is Proposed, and the Candidate returned to Need Call Candidate.");
    } catch (error) {
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      if (scheduleUpdateAttempted || proposalCreateAttempted) {
        scheduleRetryBlockedCandidateId = candidateId;
      }
      const reconciled = await reconcileAfterFailure(candidateId);
      let message;
      if (!scheduleUpdateAttempted) {
        message = "Reschedule was not submitted. No schedule write was attempted; verify the Candidate and selected DEV references.";
      } else if (!oldScheduleReadbackConfirmed) {
        message = "The previous schedule update or readback is uncertain. No replacement was submitted and no Candidate status change was attempted.";
      } else if (!proposalCreateAttempted || !proposalReadbackConfirmed) {
        message = "The previous schedule is preserved as Superseded; replacement persistence is incomplete or uncertain. Candidate status was not changed. Do not retry blindly.";
      } else if (!candidateStatusUpdateAttempted || !candidateStatusUpdated) {
        message = "The superseded schedule and Proposed replacement were persisted, but the Candidate status update failed or is uncertain. No Status History was fabricated.";
      } else if (!historyCreated) {
        message = "Schedules and Candidate status were persisted, but Status History creation failed or is uncertain. No compensation or retry was performed.";
      } else {
        message = "Reschedule data was persisted, but the UI refresh failed. Refresh to verify the current server state.";
      }
      showNotice(reconciled ? message : `${message} Server-state refresh was incomplete.`, true);
    } finally {
      setBusy(false);
    }
  }

  async function cancelRound1ThroughCore(event) {
    event.preventDefault();
    if (busy || !selectedCandidate || !canManageSchedule()) return;
    hideNotice();
    const c = TABLES.candidate;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    const reason = $("cancellation-reason").value.trim();
    if (!reason) {
      showNotice("Enter a Cancellation Reason.", true);
      return;
    }
    if (!isCandidateCoreEnabled() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Cancellation is unavailable for this candidate under the configured data mode.", true);
      return;
    }
    setBusy(true);
    try {
      const { result } = await invokeCandidateCore("CancelRound1", {
        CandidateId: candidateId,
        ExpectedStatus: STATUS.round1Scheduled,
        Reason: reason
      });
      assertCandidateCoreStatus(result, STATUS.needCall);
      $("cancellation-form").reset();
      $("cancellation-panel").hidden = true;
      await refreshCoreCandidate(candidateId);
      showNotice("Round 1 schedule cancelled and preserved. Candidate returned to Need Call Candidate.");
    } catch (error) {
      await reportCandidateCoreFailure("CancelRound1", candidateId, error);
    } finally {
      setBusy(false);
    }
  }

  async function cancelRound1(event) {
    if (!isDevFallbackEnabled()) return cancelRound1ThroughCore(event);
    event.preventDefault();
    if (busy || !selectedCandidate || !canManageSchedule()) return;
    hideNotice();
    const c = TABLES.candidate;
    const interview = TABLES.interview;
    const history = TABLES.history;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    const scheduleId = normalizeGuid(selectedSchedule[interview.id]);
    const reason = $("cancellation-reason").value.trim();
    if (!reason) {
      showNotice("Enter a Cancellation Reason.", true);
      return;
    }
    if (!isDevConfiguration() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Cancellation is unavailable for this candidate under the configured data mode.", true);
      return;
    }

    setBusy(true);
    let category = "CANCELLATION_CANDIDATE_READ_FAILED";
    let scheduleUpdateAttempted = false;
    let scheduleReadbackConfirmed = false;
    let candidateStatusUpdateAttempted = false;
    let candidateStatusUpdated = false;
    let historyCreated = false;
    try {
      const current = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(current) || current[c.status] !== STATUS.round1Scheduled) {
        await reconcileAfterFailure(candidateId);
        showNotice("Cancel Round 1 is available only while the synthetic Candidate is Round 1 Scheduled.", true);
        return;
      }

      category = "CANCELLATION_SCHEDULE_READ_FAILED";
      const schedules = await findRound1Schedules(candidateId);
      const activeSchedules = schedules.filter(isActiveSchedule);
      if (schedules.some((row) => !isKnownScheduleState(row)) ||
          schedules.some((row) => row[interview.status] === SCHEDULE_STATUS.proposed) ||
          activeSchedules.length !== 1 ||
          normalizeGuid(activeSchedules[0][interview.id]) !== scheduleId ||
          !isPendingInterviewResult(activeSchedules[0])) {
        await reconcileAfterFailure(candidateId);
        showNotice("Exactly one active pending Round 1 schedule could not be verified. No cancellation was written.", true);
        return;
      }

      const changedAt = new Date().toISOString();
      const userId = currentUserId();
      category = "CANCELLATION_SCHEDULE_UPDATE_FAILED";
      scheduleUpdateAttempted = true;
      await xrm().WebApi.updateRecord(interview.logicalName, scheduleId, {
        [interview.status]: SCHEDULE_STATUS.cancelled,
        [interview.reason]: reason,
        [interview.changedAt]: changedAt
      });

      category = "CANCELLATION_SCHEDULE_READBACK_FAILED";
      const cancelled = await retrieveInterviewRecord(
        scheduleId,
        candidateId,
        `?$select=${[interview.id, interview.candidate, interview.round, interview.result, interview.status, interview.reason, interview.changedAt].join(",")}`
      );
      if (normalizeGuid(cancelled[interview.candidate]) !== candidateId ||
          cancelled[interview.round] !== interview.round1 ||
          cancelled[interview.status] !== SCHEDULE_STATUS.cancelled ||
          cancelled[interview.reason] !== reason ||
          !sameInstant(cancelled[interview.changedAt], changedAt) ||
          !isPendingInterviewResult(cancelled)) {
        throw new Error("DEV_DIRECT_WRITE_CANCELLED_SCHEDULE_READBACK_MISMATCH");
      }
      scheduleReadbackConfirmed = true;

      category = "CANCELLATION_CANDIDATE_STATUS_UPDATE_FAILED";
      const beforeStatusUpdate = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(beforeStatusUpdate) ||
          beforeStatusUpdate[c.status] !== STATUS.round1Scheduled) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_STATUS_CHANGED_DURING_CANCELLATION");
      }
      candidateStatusUpdateAttempted = true;
      await xrm().WebApi.updateRecord(c.logicalName, candidateId, {
        [c.status]: STATUS.needCall
      });
      candidateStatusUpdated = true;

      category = "CANCELLATION_STATUS_HISTORY_CREATE_FAILED";
      await xrm().WebApi.createRecord(history.logicalName, {
        [`${history.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${history.actorNavigation}@odata.bind`]: `/systemusers(${userId})`,
        [history.previous]: STATUS.round1Scheduled,
        [history.current]: STATUS.needCall,
        [history.changedAt]: new Date().toISOString(),
        [history.correlation]: newCorrelationId(),
        [history.action]: "CancelRound1",
        [history.reason]: `DEV Candidate Management / Cancel Round 1: ${reason}`
      });
      historyCreated = true;

      category = "CANCELLATION_REFRESH_FAILED";
      $("cancellation-form").reset();
      $("cancellation-panel").hidden = true;
      await refreshCandidates();
      if (!(await openCandidate(candidateId))) {
        throw new Error("DEV_DIRECT_WRITE_CANCELLATION_DETAIL_REFRESH_FAILED");
      }
      showNotice("Round 1 schedule cancelled and preserved. Candidate returned to Need Call Candidate.");
    } catch (error) {
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      if (scheduleUpdateAttempted) scheduleRetryBlockedCandidateId = candidateId;
      const reconciled = await reconcileAfterFailure(candidateId);
      let message;
      if (!scheduleUpdateAttempted) {
        message = "Cancellation was not submitted. No schedule write was attempted; verify the Candidate and reason.";
      } else if (!scheduleReadbackConfirmed) {
        message = "Schedule cancellation or readback is uncertain. Candidate status was not changed.";
      } else if (!candidateStatusUpdateAttempted || !candidateStatusUpdated) {
        message = "The schedule is preserved as Cancelled, but the Candidate status update failed or is uncertain. No Status History was fabricated.";
      } else if (!historyCreated) {
        message = "The schedule and Candidate status were persisted, but Status History creation failed or is uncertain. No compensation or retry was performed.";
      } else {
        message = "Cancellation was persisted, but the UI refresh failed. Refresh to verify the current server state.";
      }
      showNotice(reconciled ? message : `${message} Server-state refresh was incomplete.`, true);
    } finally {
      setBusy(false);
    }
  }

  async function loadTableMetadata(table) {
    const metadata = await xrm().Utility.getEntityMetadata(table.logicalName);
    table.id = metadata.PrimaryIdAttribute;
    if (!table.id || !metadata.EntitySetName) throw new Error("Table metadata is incomplete.");
    table.entitySetName = metadata.EntitySetName;
  }

  async function showCallPanel(candidate) {
    if (!isCandidateAllowedByDataMode(candidate)) {
      showNotice("This action is unavailable for the selected candidate under the configured data mode.", true);
      return;
    }
    if (!canRecordCall(candidate[TABLES.candidate.status])) {
      showNotice("Record Call is available only when the Candidate status is Need Call Candidate.", true);
      return;
    }
    if (await openCandidate(candidate[TABLES.candidate.id])) {
      $("call-entry-panel").scrollIntoView({ behavior: "smooth", block: "center" });
      $("call-outcome").focus();
    }
  }

  async function createCandidateThroughCore(event) {
    event.preventDefault();
    if (busy) return;
    hideNotice();
    const candidateName = $("candidate-name").value.trim();
    const candidateEmail = $("candidate-email").value.trim();
    const candidatePhone = $("candidate-phone").value.trim();
    const candidateCvUrl = $("candidate-cv-url").value.trim();
    if (!candidateName || !candidateEmail) {
      showNotice("Candidate Name and Email are required.", true);
      return;
    }
    if (!isValidCandidateCvUrl(candidateCvUrl)) {
      showNotice("Candidate CV URL must be an HTTPS URL without embedded credentials.", true);
      return;
    }
    if (environmentPolicy.syntheticDataOnly && !isSyntheticInput(candidateName, candidateEmail)) {
      showNotice("The configured data mode accepts only synthetic names and reserved .invalid email addresses.", true);
      return;
    }
    if (!isCandidateCoreEnabled()) {
      showNotice("Candidate Core is unavailable until valid environment configuration is loaded.", true);
      return;
    }

    setBusy(true);
    let candidateId = null;
    let coreInvoked = false;
    try {
      const c = TABLES.candidate;
      const correlationId = newCorrelationId();
      const [position, source, assignedTa] = await Promise.all([
        getSelectedActiveReference("os_sr_pos", "candidate-position"),
        getSelectedActiveReference("os_sr_csrc", "candidate-source"),
        getSelectedActiveReference("os_sr_ta", "candidate-assigned-ta")
      ]);
      const inputs = {
        CandidateName: candidateName,
        CandidateEmail: candidateEmail
      };
      if (candidatePhone) inputs.CandidatePhone = candidatePhone;
      if (candidateCvUrl) inputs.CandidateCvUrl = candidateCvUrl;
      if (position) inputs.PositionId = position.id;
      if (source) inputs.CandidateSourceId = source.id;
      if (assignedTa) inputs.AssignedTaId = assignedTa.id;
      coreInvoked = true;
      await invokeCandidateCore("CreateCandidate", inputs, correlationId);
      const candidate = await resolveCreatedCandidate(correlationId, candidateName, candidateEmail);
      if ((candidate[c.phone] || "") !== candidatePhone ||
          (candidate[c.cvUrl] || "") !== candidateCvUrl ||
          !sameOptionalGuid(candidate[c.position], position && position.id) ||
          !sameOptionalGuid(candidate[c.source], source && source.id) ||
          !sameOptionalGuid(candidate[c.assignedTa], assignedTa && assignedTa.id)) {
        throw new Error("CANDIDATE_CORE_CREATE_PROFILE_READBACK_INVALID");
      }
      candidateId = normalizeGuid(candidate[c.id]);
      $("candidate-form").reset();
      $("candidate-search").value = "";
      $("candidate-status-filter").value = "";
      await refreshCoreCandidate(candidateId);
      showNotice("Candidate created successfully through Candidate Core.");
    } catch (error) {
      if (coreInvoked) {
        await reportCandidateCoreFailure("CreateCandidate", candidateId, error);
      } else {
        logSafeFailure("CANDIDATE_CORE_REFERENCE_REVALIDATION_FAILED", error);
        showNotice("A selected reference is no longer active or available under the configured data policy. Refresh and try again.", true);
      }
    } finally {
      setBusy(false);
    }
  }

  async function createCandidate(event) {
    if (!isDevFallbackEnabled()) return createCandidateThroughCore(event);
    event.preventDefault();
    if (busy) return;
    hideNotice();
    const candidateName = $("candidate-name").value.trim();
    const candidateEmail = $("candidate-email").value.trim();
    const candidatePhone = $("candidate-phone").value.trim();
    const candidateCvUrl = $("candidate-cv-url").value.trim();
    if (!candidateName || !candidateEmail) {
      showNotice("Candidate Name and Email are required.", true);
      return;
    }
    if (!candidateName.startsWith("[SYNTHETIC-E2E]") ||
        !/^[^@\s]+@[^@\s]+\.invalid$/i.test(candidateEmail)) {
      showNotice("This DEV console accepts only [SYNTHETIC-E2E] names and reserved .invalid email addresses.", true);
      return;
    }
    if (!isValidCandidateCvUrl(candidateCvUrl)) {
      showNotice("Candidate CV URL must be an HTTPS URL without embedded credentials.", true);
      return;
    }
    if (!isDevConfiguration()) {
      showNotice("DEV direct writes are unavailable in this environment.", true);
      return;
    }
    setBusy(true);
    const c = TABLES.candidate;
    let category = "CANDIDATE_CREATE_FAILED";
    let candidateId = null;
    let candidateCreated = false;
    let writeDispatched = false;
    try {
      const payload = {
        [c.name]: candidateName,
        [c.email]: candidateEmail,
        [c.status]: STATUS.needCall
      };
      if (candidatePhone) payload[c.phone] = candidatePhone;
      if (candidateCvUrl) payload[c.cvUrl] = candidateCvUrl;
      const [position, source, assignedTa] = await Promise.all([
        getSelectedActiveReference("os_sr_pos", "candidate-position"),
        getSelectedActiveReference("os_sr_csrc", "candidate-source"),
        getSelectedActiveReference("os_sr_ta", "candidate-assigned-ta")
      ]);
      if (position) {
        payload[`${c.positionNavigation}@odata.bind`] =
          `/${position.entitySetName}(${position.id})`;
      }
      if (source) {
        payload[`${c.sourceNavigation}@odata.bind`] =
          `/${source.entitySetName}(${source.id})`;
      }
      if (assignedTa) {
        payload[`${c.assignedTaNavigation}@odata.bind`] =
          `/${assignedTa.entitySetName}(${assignedTa.id})`;
      }
      writeDispatched = true;
      const result = await xrm().WebApi.createRecord(c.logicalName, payload);
      candidateId = result && typeof result.id === "string" ? normalizeGuid(result.id) : null;
      candidateCreated = Boolean(candidateId);
      if (!candidateId) {
        category = "CANDIDATE_READBACK_FAILED";
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_ID_MISSING");
      }

      category = "CANDIDATE_READBACK_FAILED";
      const candidate = await retrieveCandidateRecord(
        candidateId,
        `?$select=${candidateColumns().join(",")}`
      );
      if (!isCandidateAllowedByDataMode(candidate) || candidate[c.status] !== STATUS.needCall ||
          !candidate[c.number]) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_READBACK_INVALID");
      }
      $("candidate-form").reset();
      $("candidate-search").value = "";
      $("candidate-status-filter").value = "";
      category = "CANDIDATE_LIST_REFRESH_FAILED";
      await refreshCandidates();
      category = "CANDIDATE_DETAIL_READ_FAILED";
      if (!(await openCandidate(candidate[c.id]))) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_DETAIL_READ_FAILED");
      }
      showNotice("Candidate created successfully.");
    } catch (error) {
      if (!writeDispatched) {
        logSafeFailure("DEV_DIRECT_WRITE_REFERENCE_REVALIDATION_FAILED", error);
        showNotice("A selected reference is no longer active or available under the configured data policy. Refresh and try again.", true);
        return;
      }
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      const reconciled = await reconcileAfterFailure(candidateId);
      const message = candidateCreated && category === "CANDIDATE_READBACK_FAILED"
        ? "Candidate was created, but readback failed. Refresh to reconcile before trying again."
        : failureMessage(category, candidateCreated);
      showNotice(reconciled ? message : `${message} Reconciliation did not fully complete.`, true);
    } finally {
      setBusy(false);
    }
  }

  function setCurrentReferenceOption(selectId, referenceId) {
    const select = $(selectId);
    const id = referenceId ? normalizeGuid(referenceId) : "";
    const existing = Array.from(select.options).find((option) =>
      option.value.toLowerCase() === id.toLowerCase());
    if (id && !existing) {
      const option = document.createElement("option");
      option.value = id;
      option.textContent = "Current reference (not selectable by policy)";
      select.insertBefore(option, select.options[1] || null);
    }
    select.value = existing ? existing.value : id;
  }

  function showEditCandidatePanel() {
    if (busy || !selectedCandidate || !isCandidateAllowedByDataMode(selectedCandidate)) return;
    const c = TABLES.candidate;
    $("edit-candidate-name").value = selectedCandidate[c.name] || "";
    $("edit-candidate-email").value = selectedCandidate[c.email] || "";
    $("edit-candidate-phone").value = selectedCandidate[c.phone] || "";
    $("edit-candidate-cv-url").value = selectedCandidate[c.cvUrl] || "";
    setCurrentReferenceOption("edit-candidate-position", selectedCandidate[c.position]);
    setCurrentReferenceOption("edit-candidate-source", selectedCandidate[c.source]);
    setCurrentReferenceOption("edit-candidate-assigned-ta", selectedCandidate[c.assignedTa]);
    $("edit-candidate-panel").hidden = false;
    $("edit-candidate-panel").scrollIntoView({ behavior: "smooth", block: "start" });
    $("edit-candidate-name").focus();
  }

  async function updateCandidateThroughCore(event) {
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    hideNotice();
    const c = TABLES.candidate;
    if (!isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Candidate Core is unavailable for this Candidate under the configured data mode.", true);
      return;
    }
    let candidateId;
    try {
      candidateId = normalizeGuid(selectedCandidate[c.id]);
    } catch (error) {
      logSafeFailure("CANDIDATE_CORE_INVALID_CANDIDATE_REFERENCE", error);
      showNotice("Candidate reference is invalid. Refresh and select the Candidate again.", true);
      return;
    }
    const candidateName = $("edit-candidate-name").value.trim();
    const candidateEmail = $("edit-candidate-email").value.trim();
    const candidatePhone = $("edit-candidate-phone").value.trim();
    const candidateCvUrl = $("edit-candidate-cv-url").value.trim();
    if (!candidateName || !candidateEmail) {
      showNotice("Candidate Name and Email are required.", true);
      return;
    }
    if (environmentPolicy.syntheticDataOnly && !isSyntheticInput(candidateName, candidateEmail)) {
      showNotice("The configured data mode accepts only synthetic names and reserved .invalid email addresses.", true);
      return;
    }
    if (!isValidCandidateCvUrl(candidateCvUrl)) {
      showNotice("Candidate CV URL must be an HTTPS URL without embedded credentials.", true);
      return;
    }

    const inputs = {
      CandidateId: candidateId,
      ExpectedStatus: Number(selectedCandidate[c.status])
    };
    const baseline = {};
    const changedProfileFields = new Set();
    const addTextChange = (inputName, attribute, value, optional) => {
      const current = optional
        ? (selectedCandidate[attribute] || null)
        : (selectedCandidate[attribute] || "");
      const next = optional ? (value || null) : value;
      if (current !== next) {
        if (next !== null) inputs[inputName] = next;
        baseline[attribute] = current;
        changedProfileFields.add(inputName);
      }
    };
    const addLookupChange = (inputName, attribute, selectId) => {
      const selectedId = $(selectId).value;
      const next = selectedId ? normalizeGuid(selectedId) : null;
      const current = selectedCandidate[attribute]
        ? normalizeGuid(selectedCandidate[attribute])
        : null;
      if (!sameOptionalGuid(current, next)) {
        if (next !== null) inputs[inputName] = next;
        baseline[attribute] = current;
        changedProfileFields.add(inputName);
      }
    };
    addTextChange("CandidateName", c.name, candidateName, false);
    addTextChange("CandidateEmail", c.email, candidateEmail, false);
    addTextChange("CandidatePhone", c.phone, candidatePhone, true);
    addTextChange("CandidateCvUrl", c.cvUrl, candidateCvUrl, true);
    addLookupChange("PositionId", c.position, "edit-candidate-position");
    addLookupChange("CandidateSourceId", c.source, "edit-candidate-source");
    addLookupChange("AssignedTaId", c.assignedTa, "edit-candidate-assigned-ta");
    inputs.ProfileFieldMask = canonicalProfileFieldMask(changedProfileFields);
    if (Object.keys(baseline).length === 0) {
      showNotice("No profile changes to save.");
      return;
    }
    if (!Number.isInteger(inputs.ExpectedStatus)) {
      showNotice("Candidate status could not be verified. Refresh the Candidate and try again.", true);
      return;
    }

    setBusy(true);
    let coreInvoked = false;
    try {
      const attributes = Object.keys(baseline);
      const latest = await retrieveCandidateRecord(
        candidateId,
        `?$select=${attributes.join(",")}`
      );
      for (const attribute of attributes) {
        const isLookup = [c.position, c.source, c.assignedTa].includes(attribute);
        const current = isLookup
          ? (latest[attribute] ? normalizeGuid(latest[attribute]) : null)
          : (latest[attribute] == null ? (baseline[attribute] == null ? null : "") : latest[attribute]);
        const expected = baseline[attribute];
        if (isLookup ? !sameOptionalGuid(current, expected) : current !== expected) {
          await refreshCoreCandidate(candidateId);
          showNotice("Candidate profile changed since it was opened. Review the refreshed values before saving.", true);
          return;
        }
      }

      await Promise.all([
        inputs.PositionId ? getActiveReference("os_sr_pos", inputs.PositionId) : null,
        inputs.CandidateSourceId ? getActiveReference("os_sr_csrc", inputs.CandidateSourceId) : null,
        inputs.AssignedTaId ? getActiveReference("os_sr_ta", inputs.AssignedTaId) : null
      ]);
      coreInvoked = true;
      await invokeCandidateCore("UpdateCandidate", inputs, newCorrelationId());
      await refreshCoreCandidate(candidateId);
      showNotice("Candidate profile updated through Candidate Core.");
    } catch (error) {
      if (coreInvoked) {
        await reportCandidateCoreFailure("UpdateCandidate", candidateId, error);
      } else {
        logSafeFailure("CANDIDATE_PROFILE_PRECHECK_FAILED", error);
        showNotice("Candidate profile could not be verified; no update was sent. Refresh and try again.", true);
      }
    } finally {
      setBusy(false);
    }
  }

  async function recordCallThroughCore(event) {
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    hideNotice();
    const c = TABLES.candidate;
    let candidateId;
    try {
      candidateId = normalizeGuid(selectedCandidate[c.id]);
    } catch (error) {
      logSafeFailure("CANDIDATE_CORE_INVALID_CANDIDATE_REFERENCE", error);
      showNotice("Candidate reference is invalid. Refresh the list and select the Candidate again.", true);
      return;
    }
    if (!isCandidateCoreEnabled() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Candidate Core is unavailable for this candidate under the configured data mode.", true);
      return;
    }
    if (!canRecordCall(selectedCandidate[c.status])) {
      showNotice("Record Call is available only when the Candidate status is Need Call Candidate.", true);
      return;
    }
    const outcome = Number($("call-outcome").value);
    if (![OUTCOME.noAnswer, OUTCOME.answered, OUTCOME.callBackRequested].includes(outcome)) {
      showNotice("Choose a supported call outcome.", true);
      return;
    }
    const currentStatus = selectedCandidate[c.status];
    const expectedStatus = outcome === OUTCOME.answered && currentStatus === STATUS.needCall
      ? STATUS.answered
      : currentStatus;
    setBusy(true);
    try {
      const { result } = await invokeCandidateCore("RecordCall", {
        CandidateId: candidateId,
        ExpectedStatus: currentStatus,
        CallOutcome: outcome,
        ContactedAt: new Date().toISOString(),
        Notes: $("call-notes").value.trim() || undefined
      });
      assertCandidateCoreStatus(result, expectedStatus);
      $("call-form").reset();
      await refreshCoreCandidate(candidateId);
      showNotice("Call recorded through Candidate Core.");
    } catch (error) {
      await reportCandidateCoreFailure("RecordCall", candidateId, error);
    } finally {
      setBusy(false);
    }
  }

  async function recordCall(event) {
    if (!isDevFallbackEnabled()) return recordCallThroughCore(event);
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    hideNotice();
    const c = TABLES.candidate;
    const call = TABLES.call;
    const history = TABLES.history;
    let candidateId;
    try {
      candidateId = normalizeGuid(selectedCandidate[c.id]);
    } catch (error) {
      logSafeFailure("DEV_DIRECT_WRITE_INVALID_CANDIDATE_REFERENCE", error);
      showNotice("Candidate reference is invalid. Refresh the list and select the Candidate again.", true);
      return;
    }
    if (!isDevConfiguration()) {
      showNotice("DEV direct writes are unavailable in this environment.", true);
      return;
    }
    if (!isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("DEV direct write is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
      return;
    }
    const outcome = Number($("call-outcome").value);
    if (![OUTCOME.noAnswer, OUTCOME.answered, OUTCOME.callBackRequested].includes(outcome)) {
      showNotice("Choose a supported DEV call outcome.", true);
      return;
    }
    let category = "CANDIDATE_READ_FAILED";
    let callCreated = false;
    let statusUpdated = false;
    setBusy(true);
    try {
      const current = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(current)) {
        showNotice("DEV direct write is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
        return;
      }
      const previousStatus = current[c.status];
      if ([STATUS.offerExtended, STATUS.candidateFailed].includes(previousStatus)) {
        showNotice("No further workflow actions are available for this Candidate in the current DEV scope.", true);
        return;
      }
      const correlationId = newCorrelationId();
      category = "CALL_LOG_CREATE_FAILED";
      const userId = currentUserId();
      const payload = {
        [`${call.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${call.contactedByNavigation}@odata.bind`]: `/systemusers(${userId})`,
        [call.outcome]: outcome,
        [call.contactedAt]: new Date().toISOString(),
        [call.correlation]: correlationId
      };
      const notes = $("call-notes").value.trim();
      if (notes) payload[call.notes] = notes;

      await xrm().WebApi.createRecord(call.logicalName, payload);
      callCreated = true;

      if (outcome === OUTCOME.answered && previousStatus === STATUS.needCall) {
        category = "CANDIDATE_STATUS_UPDATE_FAILED";
        await xrm().WebApi.updateRecord(c.logicalName, candidateId, {
          [c.status]: STATUS.answered
        });
        statusUpdated = true;

        category = "STATUS_HISTORY_CREATE_FAILED";
        const historyPayload = {
          [`${history.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
          [`${history.actorNavigation}@odata.bind`]: `/systemusers(${userId})`,
          [history.previous]: STATUS.needCall,
          [history.current]: STATUS.answered,
          [history.changedAt]: new Date().toISOString(),
          [history.correlation]: correlationId,
          [history.action]: "RecordCall",
          [history.reason]: "DEV Candidate Management / Record Call"
        };
        await xrm().WebApi.createRecord(history.logicalName, historyPayload);
      }
      $("call-notes").value = "";
      category = "CANDIDATE_LIST_REFRESH_FAILED";
      await refreshCandidates();
      category = "CANDIDATE_DETAIL_READ_FAILED";
      if (!(await openCandidate(candidateId))) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_DETAIL_READ_FAILED");
      }
      showNotice(outcome === OUTCOME.answered && previousStatus !== STATUS.needCall
        ? "Call recorded. Candidate status was preserved because it was not Need Call Candidate."
        : "Call recorded successfully.");
    } catch (error) {
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      const reconciled = await reconcileAfterFailure(candidateId);
      const partial = callCreated || statusUpdated;
      const message = failureMessage(category, partial);
      showNotice(reconciled ? message : `${message} Reconciliation did not fully complete.`, true);
    } finally {
      setBusy(false);
    }
  }

  async function moveToWaitingManualSchedulingThroughCore() {
    if (busy || !selectedCandidate) return;
    hideNotice();
    const c = TABLES.candidate;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    if (!isCandidateCoreEnabled() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("Candidate Core is unavailable for this candidate under the configured data mode.", true);
      return;
    }
    if (selectedCandidate[c.status] !== STATUS.answered) {
      showNotice("Only a Candidate Answered record can move to Waiting Manual Scheduling.", true);
      return;
    }
    setBusy(true);
    try {
      const { result } = await invokeCandidateCore("ProceedToScheduling", {
        CandidateId: candidateId,
        ExpectedStatus: STATUS.answered
      });
      assertCandidateCoreStatus(result, STATUS.waitingManualScheduling);
      await refreshCoreCandidate(candidateId);
      showNotice("Candidate moved to Waiting Manual Scheduling through Candidate Core.");
    } catch (error) {
      await reportCandidateCoreFailure("ProceedToScheduling", candidateId, error);
    } finally {
      setBusy(false);
    }
  }

  async function moveToWaitingManualScheduling() {
    if (!isDevFallbackEnabled()) return moveToWaitingManualSchedulingThroughCore();
    if (busy || !selectedCandidate) return;
    hideNotice();
    const c = TABLES.candidate;
    const history = TABLES.history;
    let candidateId;
    try {
      candidateId = normalizeGuid(selectedCandidate[c.id]);
    } catch (error) {
      logSafeFailure("DEV_DIRECT_WRITE_INVALID_CANDIDATE_REFERENCE", error);
      showNotice("Candidate reference is invalid. Refresh the list and select the Candidate again.", true);
      return;
    }
    if (!isDevConfiguration() || !isCandidateAllowedByDataMode(selectedCandidate)) {
      showNotice("This transition is unavailable for this candidate under the configured data mode.", true);
      return;
    }

    setBusy(true);
    let category = "CANDIDATE_READ_FAILED";
    let statusUpdated = false;
    try {
      const current = await retrieveCandidateRecord(
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isCandidateAllowedByDataMode(current)) {
        showNotice("This transition is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
        return;
      }
      if (current[c.status] !== STATUS.answered) {
        const reconciled = await reconcileAfterFailure(candidateId);
        showNotice(
          reconciled
            ? "Move to Waiting Manual Scheduling is available only from Candidate Answered."
            : "Candidate status changed; reconciliation did not fully complete.",
          true
        );
        return;
      }

      const correlationId = newCorrelationId();
      const userId = currentUserId();
      category = "WAITING_STATUS_UPDATE_FAILED";
      await xrm().WebApi.updateRecord(c.logicalName, candidateId, {
        [c.status]: STATUS.waitingManualScheduling
      });
      statusUpdated = true;

      category = "WAITING_STATUS_HISTORY_CREATE_FAILED";
      await xrm().WebApi.createRecord(history.logicalName, {
        [`${history.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${history.actorNavigation}@odata.bind`]: `/systemusers(${userId})`,
        [history.previous]: STATUS.answered,
        [history.current]: STATUS.waitingManualScheduling,
        [history.changedAt]: new Date().toISOString(),
        [history.correlation]: correlationId,
        [history.action]: "MoveToWaitingManualScheduling",
        [history.reason]: "DEV Candidate Management / Move to Waiting Manual Scheduling"
      });

      category = "CANDIDATE_LIST_REFRESH_FAILED";
      await refreshCandidates();
      category = "CANDIDATE_DETAIL_READ_FAILED";
      if (!(await openCandidate(candidateId))) {
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_DETAIL_READ_FAILED");
      }
      showNotice("Candidate moved to Waiting Manual Scheduling.");
    } catch (error) {
      logSafeFailure(`DEV_DIRECT_WRITE_${category}`, error);
      const reconciled = await reconcileAfterFailure(candidateId);
      const partial = statusUpdated;
      const message = failureMessage(category, partial);
      showNotice(reconciled ? message : `${message} Reconciliation did not fully complete.`, true);
    } finally {
      setBusy(false);
    }
  }

  function bindEvents() {
    const forceSubmit = (buttonId, formId) => {
      const button = $(buttonId);
      const form = $(formId);
      button.addEventListener("click", (event) => {
        if (button.disabled || busy) return;
        event.preventDefault();
        form.requestSubmit();
      });
    };
    forceSubmit("create-button", "candidate-form");
    forceSubmit("save-candidate-profile", "edit-candidate-form");
    forceSubmit("submit-call", "call-form");
    forceSubmit("save-schedule", "scheduling-form");
    forceSubmit("confirm-cancellation", "cancellation-form");
    forceSubmit("save-interview-result", "interview-result-form");

    $("candidate-form").addEventListener("submit", createCandidate);
    $("edit-candidate-button").addEventListener("click", showEditCandidatePanel);
    $("edit-candidate-form").addEventListener("submit", updateCandidateThroughCore);
    $("call-form").addEventListener("submit", recordCall);
    $("scheduling-form").addEventListener("submit", createSchedule);
    $("cancellation-form").addEventListener("submit", cancelRound1);
    $("interview-result-form").addEventListener("submit", recordInterviewResult);
    $("candidate-search").addEventListener("input", () => renderCandidateRows(currentRows));
    $("candidate-status-filter").addEventListener("change", () => renderCandidateRows(currentRows));
    $("dev-fallback-toggle").addEventListener("change", updateWorkflowPathLabel);
    $("refresh-button").addEventListener("click", async () => {
      hideNotice();
      try {
        await refreshCandidates();
        if (selectedCandidate) await openCandidate(selectedCandidate[TABLES.candidate.id]);
      } catch {
        showNotice("Candidate list could not be refreshed.", true);
      }
    });
    $("close-detail").addEventListener("click", () => {
      $("detail-panel").hidden = true;
      $("call-entry-panel").hidden = true;
      $("edit-candidate-panel").hidden = true;
      $("waiting-status-button").hidden = true;
      $("schedule-round1-button").hidden = true;
      $("record-interview-result-button").hidden = true;
      $("reschedule-round1-button").hidden = true;
      $("cancel-round1-button").hidden = true;
      $("scheduling-panel").hidden = true;
      $("cancellation-panel").hidden = true;
      $("interview-result-panel").hidden = true;
      selectedCandidate = null;
      selectedSchedule = null;
      renderCandidateRows(currentRows);
    });
    $("waiting-status-button").addEventListener("click", moveToWaitingManualScheduling);
    $("schedule-round1-button").addEventListener("click", showSchedulingPanel);
    $("record-interview-result-button").addEventListener("click", showInterviewResultPanel);
    $("reschedule-round1-button").addEventListener("click", () => showSchedulingPanel("reschedule"));
    $("cancel-round1-button").addEventListener("click", showCancellationPanel);
  }

  async function verifyServerIsolation() {
    const context = globalContext();
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.verifySyntheticIsolation !== "function") {
      throw new Error("SYNTHETIC_VERIFIER_UNAVAILABLE");
    }
    return policy.verifySyntheticIsolation(window.BsoRsCandidateConsoleConfiguration, {
      organizationUrl: context.getClientUrl(),
      organizationId: context.organizationSettings.organizationId,
      actorId: context.userSettings && context.userSettings.userId
    });
  }

  async function initialize() {
    bindEvents();
    environmentPolicy = resolveEnvironmentPolicy();
    updateWorkflowPathLabel();
    if (environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly) {
      try {
        await verifyServerIsolation();
      } catch {
        $("create-button").disabled = true;
        $("refresh-button").disabled = true;
        document.querySelectorAll("button[data-action]").forEach((button) => { button.disabled = true; });
        showNotice("Candidate Management is blocked until server-side synthetic data isolation is established: the verifier is unavailable or rejected this scope.", true);
        return;
      }
    }
    if (!isCandidateCoreEnabled()) {
      $("create-button").disabled = true;
      $("refresh-button").disabled = true;
      document.querySelectorAll("button[data-action]").forEach((button) => {
        button.disabled = true;
      });
      showNotice(environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly
        ? "Candidate Management is blocked until server-side synthetic data isolation is established."
        : environmentPolicy.reason === "BLOCK_UNRECOGNIZED_ENVIRONMENT"
          ? "BLOCK_UNRECOGNIZED_ENVIRONMENT"
          : "Candidate Management is blocked because environment configuration is missing or invalid.", true);
      return;
    }
    let loadStage = "the model-driven app context";
    try {
      globalContext();
      loadStage = "Candidate, Call Log, and Status History metadata";
      await Promise.all([
        loadTableMetadata(TABLES.candidate),
        loadTableMetadata(TABLES.call),
        loadTableMetadata(TABLES.history),
        loadTableMetadata(TABLES.interview)
      ]);
      loadStage = "Position and Candidate Source options";
      await Promise.all([
        loadLookupOptions("os_sr_pos", ["candidate-position", "edit-candidate-position"],
          ["No position selected", "No position selected"]),
        loadLookupOptions("os_sr_csrc", ["candidate-source", "edit-candidate-source"],
          ["No source selected", "No source selected"]),
        loadLookupOptions("os_sr_ta",
          ["candidate-assigned-ta", "edit-candidate-assigned-ta", "scheduling-ta"],
          ["No TA assigned", "No TA assigned", "Select interviewer"]),
        loadLookupOptions("os_sr_loc", "scheduling-location", "Select location")
      ]);
      loadStage = "the Candidate list";
      const statusFilter = $("candidate-status-filter");
      for (const [value, label] of Object.entries(STATUS_LABELS)) {
        addOption(statusFilter, value, label);
      }
      await refreshCandidates();
    } catch {
      if (environmentPolicy.syntheticDataOnly) blockSyntheticQuery();
      showNotice(`Candidate Management could not load ${loadStage}. Confirm app access and try again.`, true);
      document.querySelectorAll("button[data-action]").forEach((button) => {
        button.disabled = true;
      });
      const row = document.createElement("tr");
      const cell = appendCell(row, "Candidate data is unavailable.");
      cell.colSpan = 11;
      cell.className = "empty";
      $("candidate-rows").replaceChildren(row);
    }
  }

  document.addEventListener("DOMContentLoaded", initialize);
})();
