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
  const CANDIDATE_PAGE_SIZE = 10;
  const AVAILABILITY_POLL_INTERVAL_MS = 2000;
  const AVAILABILITY_POLL_ATTEMPTS = 60;
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
  const callRetryBlockedCandidates = new Set();
  const callSchedulingCorrelations = new Map();
  let currentRows = [];
  let candidatePageRequests = [null];
  let candidatePageNumber = 1;
  let candidateTotalCount = null;
  let candidateHasNextPage = false;
  let candidateListRequestId = 0;
  let candidateSearchTimer = null;
  let busy = false;
  let syntheticQueryBlocked = false;
  let isolationExpiryTimer;
  let isolationVerificationPromise;
  let referenceMode = "CONFIGURED";
  let referenceGeneration = 0;
  const round1Availability = {
    generation: 0, capabilityGeneration: 0, providerOperational: false, manualSchedulingOperational: false,
    checking: false, evidence: null, expiryTimer: null
  };
  const referenceRequests = new WeakMap();
  let referencesReady = false;
  let workspaceReady = false;
  let environmentPolicy = Object.freeze({ allowed: false, reason: "CONFIGURATION_MISSING" });
  const CORE_API_ACTIONS = new Set([
    "CreateCandidate", "UpdateCandidate", "RecordCall", "ProceedToScheduling",
    "MarkRound1Scheduled", "RecordManualRound1Schedule", "RecordPass", "RecordFail", "RequestReschedule", "CancelRound1",
    "GetRound1SchedulingCapabilities", "GetRound1Availability"
  ]);
  const SINGLE_USER_DEV_READ_ACTIONS = Object.freeze({
    os_sr_cand: "ReadScopedCandidates",
    os_sr_pos: "ReadScopedPositions",
    os_sr_csrc: "ReadScopedSources",
    os_sr_ta: "ReadScopedTas",
    os_sr_loc: "ReadScopedLocations",
    os_sr_call: "ReadScopedCalls",
    os_sr_csh: "ReadScopedHistory",
    os_sr_intv: "ReadScopedSchedules"
  });
  const SINGLE_USER_DEV_REFERENCE_SCOPE_KEYS = Object.freeze({
    os_sr_pos: "positionId",
    os_sr_csrc: "sourceId",
    os_sr_ta: "taId",
    os_sr_loc: "locationId"
  });
  const REFERENCE_OPTION_LABELS = Object.freeze({
    os_sr_pos: "Position",
    os_sr_csrc: "Candidate Source",
    os_sr_ta: "TA",
    os_sr_loc: "Location"
  });
  const SINGLE_USER_DEV_CHOICE_ATTRIBUTES = new Set([
    "statecode", "os_sr_cand_stat", "os_sr_call_out", "os_sr_csh_prevstat",
    "os_sr_csh_newstat", "os_sr_intv_rnd", "os_sr_intv_res", "os_sr_intv_stat"
  ]);
  const CORE_API_PARAMETER_NAMES = new Set([
    "ActionType", "SyntheticScopeId", "CandidateId", "ExpectedStatus", "CorrelationId", "CandidateName",
    "CandidateEmail", "CandidatePhone", "CandidateCvUrl", "PositionId", "CandidateSourceId",
    "AssignedTaId", "ProfileFieldMask", "Reason",
    "CallOutcome", "ContactedAt", "Notes", "InterviewerId", "LocationId", "StartAt",
    "EndAt", "ResultNotes", "CandidateSearchText", "CandidateStatusFilter",
    "CandidatePageNumber"
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

  function resolveEnvironmentPolicy(selectedMode = referenceMode) {
    try {
      const context = globalContext();
      const policy = window.BsoRsCandidateConsolePolicy;
      if (!policy || typeof policy.resolve !== "function") {
        return Object.freeze({ allowed: false, reason: "CONFIGURATION_POLICY_UNAVAILABLE" });
      }
      return policy.resolve(window.BsoRsCandidateConsoleConfiguration, {
        organizationUrl: context.getClientUrl(),
        organizationId: context.organizationSettings.organizationId
      }, selectedMode);
    } catch {
      return Object.freeze({ allowed: false, reason: "CONFIGURATION_CONTEXT_UNAVAILABLE" });
    }
  }

  function isCandidateCoreEnabled() {
    if (environmentPolicy.allowed !== true) return false;
    if (referenceMode === "NORMAL") return !environmentPolicy.syntheticDataOnly;
    if (!environmentPolicy.syntheticDataOnly) return false;
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
    if (referenceMode === "NORMAL" && environmentPolicy.syntheticDataOnly) {
      $("workflow-path-badge").textContent = "NORMAL REFERENCES ONLY";
      $("real-data-badge").textContent = "CANDIDATE OPERATIONS BLOCKED";
      document.querySelectorAll("[data-workflow-label]").forEach((label) => {
        label.textContent = "Normal Candidate operations are not authorized in this synthetic environment";
      });
    }
    const configuredModeLabel = environmentPolicy.configuredOperationMode === "SingleUserDev"
      ? "SingleUserDev" : "Configured synthetic workflow";
    $("candidate-data-mode").options[0].textContent = configuredModeLabel;
    $("reference-mode-status").textContent = referenceMode === "NORMAL"
      ? environmentPolicy.syntheticDataOnly
        ? "NORMAL: all Active references accessible to your Dataverse account. Candidate reads and writes remain blocked in this synthetic environment."
        : "NORMAL: authenticated Active references; Candidate operations use the normal Candidate Core API and its server-side authorization."
      : `${configuredModeLabel}: server proof and DEV reference restrictions remain required.`;
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
    if (referenceMode === "NORMAL") return typeof label === "string" && Boolean(label.trim());
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
    $("refresh-button").disabled = value || !isCandidateCoreEnabled();
    $("candidate-search").disabled = value;
    $("candidate-status-filter").disabled = value;
    $("candidate-data-mode").disabled = value || environmentPolicy.allowed !== true;
    $("refresh-references").disabled = value || environmentPolicy.allowed !== true ||
      (referenceMode !== "NORMAL" && !isCandidateCoreEnabled());
    $("dev-fallback-toggle").disabled =
      value || !isCandidateCoreEnabled() || environmentPolicy.directWriteFallbackAvailable !== true;
    document.querySelectorAll("button[data-action]").forEach((button) => {
      button.disabled = value || !referencesReady || !workspaceReady || !isCandidateCoreEnabled() ||
        (button.id === "submit-call" &&
          (!selectedCandidate || !canRecordCall(selectedCandidate[TABLES.candidate.status]) ||
            callRetryBlockedCandidates.has(selectedCandidate[TABLES.candidate.id].toLowerCase()))) ||
        (button.id === "waiting-status-button" && button.hidden) ||
        (button.id === "schedule-round1-button" &&
          (button.hidden || !selectedCandidate ||
            selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
            Boolean(selectedSchedule) ||
            scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id])) ||
        (button.id === "record-interview-result-button" &&
          (button.hidden || !canRecordInterviewResult())) ||
        (button.id === "save-schedule" &&
          ((requiresTrustedScheduleAvailability() && !isManualRound1Scheduling() && !selectedVerifiedRound1Slot()) || !selectedCandidate ||
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
    updateCandidatePagination();
    updateRound1AvailabilityControls();
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

  async function sendCandidateCoreRequest(action, values, correlationId, onDispatch) {
    if (referenceMode === "NORMAL" &&
        (environmentPolicy.syntheticDataOnly || Object.hasOwn(values, "SyntheticScopeId") ||
          !CORE_API_ACTIONS.has(action))) {
      throw new Error("NORMAL_CANDIDATE_OPERATION_NOT_AUTHORIZED");
    }
    if (CORE_API_ACTIONS.has(action) && (!workspaceReady || !referencesReady)) {
      throw new Error("CANDIDATE_WORKSPACE_NOT_READY");
    }
    const scopedRead = environmentPolicy.candidateOperationMode === "SingleUserDev" &&
      Object.values(SINGLE_USER_DEV_READ_ACTIONS).includes(action);
    if (environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly && !scopedRead) {
      await verifyServerIsolation();
    }
    if (!isCandidateCoreEnabled()) throw new Error("CANDIDATE_CORE_ENVIRONMENT_REJECTED");
    if (!CORE_API_ACTIONS.has(action) &&
        !(environmentPolicy.candidateOperationMode === "SingleUserDev" &&
          Object.values(SINGLE_USER_DEV_READ_ACTIONS).includes(action))) {
      throw new Error("CANDIDATE_CORE_ACTION_INVALID");
    }
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
    const body = JSON.stringify(request);
    if (onDispatch) onDispatch();
    const response = await fetch("/api/data/v9.2/os_sr_cact", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json; charset=utf-8",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0"
      },
      body
    });
    const responseText = await response.text();
    let result;
    try {
      result = responseText ? JSON.parse(responseText) : null;
    } catch {
      const error = new Error("CANDIDATE_CORE_RESPONSE_INVALID");
      error.httpStatus = response.status;
      throw error;
    }
    if (!response.ok) {
      const error = new Error("CANDIDATE_CORE_REQUEST_REJECTED");
      error.httpStatus = response.status;
      const errorCode = result && result.error && result.error.code;
      if (typeof errorCode === "string" && /^0x[0-9a-f]{8}$/i.test(errorCode)) {
        error.errorCode = Number.parseInt(errorCode.slice(2), 16);
      }
      const errorMessage = result && result.error && result.error.message;
      const operationFailure = typeof errorMessage === "string"
        ? errorMessage.match(/CANDIDATE_CORE_OPERATION_REJECTED:(?:CREATE_CANDIDATE:)?(INPUT_VALIDATION|AUTHORIZATION|REFERENCE_VALIDATION|RECEIPT_READ|CANDIDATE_CREATE|CANDIDATE_READBACK|RECEIPT_CREATE|RESPONSE):(0x[0-9a-f]{8}|TIMEOUT|PLUGIN_EXECUTION|INVALID_OPERATION|SERVICE_FAULT|OTHER|REFERENCE_NOT_AVAILABLE|NORMAL_CREATE_DISABLED|NORMAL_CREATE_ORGANIZATION_REJECTED|NORMAL_CREATE_CONFIGURATION_REJECTED|NORMAL_CREATE_PRIVILEGE_METADATA_REJECTED|NORMAL_CREATE_PRIVILEGE_REQUIRED|CANDIDATE_NUMBER_UNAVAILABLE|CANDIDATE_CREATE_READBACK_INVALID|CALLER_READ_ACCESS_REQUIRED)/i)
        : null;
      if (operationFailure) {
        const safeCode = operationFailure[2].startsWith("0x")
          ? `0x${operationFailure[2].slice(2).toUpperCase()}`
          : operationFailure[2];
        error.operationFailure = `${operationFailure[1]}:${safeCode}`;
      }
      if (action === "RecordManualRound1Schedule" || action === "MarkRound1Scheduled") {
        const safeSchedulingFailure = typeof errorMessage === "string" &&
          (/^(?:DATAVERSE_OPERATION_REJECTED|CANDIDATE_CORE_FAILURE):CC_(?:READ_RECEIPT|READ_CANDIDATE|CHECK_PROTECTED_READ_ACCESS|READ_INTERVIEW_SCHEDULE_IDS|READ_INTERVIEW_SCHEDULE|CREATE_INTERVIEW_SCHEDULE|UPDATE_INTERVIEW_SCHEDULE|VERIFY_INTERVIEW_SCHEDULE|UPDATE_CANDIDATE|CREATE_STATUS_HISTORY|CREATE_RECEIPT):(?:0x[0-9a-f]{8}|TIMEOUT|PLUGIN_EXECUTION|INVALID_OPERATION|SERVICE_FAULT|OTHER)$/i.test(errorMessage) ||
            /^(?:NORMAL_CREATE_DISABLED|NORMAL_CREATE_ORGANIZATION_REJECTED|NORMAL_CREATE_CONFIGURATION_REJECTED|NORMAL_SCHEDULE_WRITE_ACCESS_REQUIRED|CALLER_READ_ACCESS_REQUIRED|STALE_EXPECTED_STATUS|INVALID_TRANSITION|INVALID_SCHEDULE_REFERENCE|INVALID_SCHEDULE_TIME|MANUAL_SCHEDULE_NORMAL_CONTEXT_REQUIRED|ACTIVE_SCHEDULE_CONFLICT|SCHEDULE_STATE_AMBIGUOUS|SCHEDULE_INTEGRITY_FAILURE|SCHEDULE_PERSISTENCE_NOT_CONFIRMED|CORRELATION_CONFLICT|CORRELATION_OR_KEY_CONFLICT|RECEIPT_INTEGRITY_FAILURE|ROW_VERSION_CONFLICT|ROW_VERSION_UNAVAILABLE|AVAILABILITY_PROVIDER_UNAVAILABLE|DATAVERSE_OPERATION_REJECTED|REFERENCE_NOT_AVAILABLE:(?:InterviewerId|LocationId))$/.test(errorMessage));
        if (safeSchedulingFailure) error.operationFailure = errorMessage;
      }
      throw error;
    }
    return { correlationId, result };
  }

  async function invokeCandidateCore(action, values = {}, correlationId = newCorrelationId(), onDispatch) {
    if (!CORE_API_ACTIONS.has(action)) throw new Error("CANDIDATE_CORE_ACTION_INVALID");
    const { result } = await sendCandidateCoreRequest(action, values, correlationId, onDispatch);
    if (!result || !["Applied", "DuplicateReplay"].includes(result.ResultCode)) {
      throw new Error("CANDIDATE_CORE_RESULT_INVALID");
    }
    return { correlationId, result };
  }

  async function readSingleUserDevRecords(tableLogicalName) {
    if (environmentPolicy.candidateOperationMode !== "SingleUserDev") {
      throw new Error("SINGLE_USER_DEV_READ_UNAVAILABLE");
    }
    const action = SINGLE_USER_DEV_READ_ACTIONS[tableLogicalName];
    if (!action) throw new Error("SINGLE_USER_DEV_READ_TABLE_INVALID");
    const { result } = await sendCandidateCoreRequest(action, {}, newCorrelationId());
    if (!result || result.ResultCode !== "ScopedRead" || typeof result.ScopedData !== "string") {
      throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
    }
    return parseSingleUserDevRows(tableLogicalName, result.ScopedData);
  }

  function parseSingleUserDevRows(tableLogicalName, scopedData) {
    let rows;
    try {
      rows = JSON.parse(scopedData);
    } catch {
      throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
    }
    if (!Array.isArray(rows)) throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
    return rows.map((row) => {
      if (!row || typeof row !== "object" || Array.isArray(row) ||
          row.__logicalName !== tableLogicalName) {
        throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
      }
      const parsed = { ...row };
      delete parsed.__logicalName;
      for (const [name, value] of Object.entries(parsed)) {
        if (SINGLE_USER_DEV_CHOICE_ATTRIBUTES.has(name) && value !== null) {
          const number = Number(value);
          if (!Number.isSafeInteger(number)) throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
          parsed[name] = number;
        }
      }
      return parsed;
    });
  }

  async function readSingleUserDevCandidatePage(searchText, statusFilter, pageNumber) {
    const action = SINGLE_USER_DEV_READ_ACTIONS[TABLES.candidate.logicalName];
    if (!action || environmentPolicy.candidateOperationMode !== "SingleUserDev") {
      throw new Error("SINGLE_USER_DEV_READ_UNAVAILABLE");
    }
    const { result } = await sendCandidateCoreRequest(action, {
      CandidateSearchText: searchText,
      CandidateStatusFilter: statusFilter,
      CandidatePageNumber: pageNumber
    }, newCorrelationId());
    if (!result || result.ResultCode !== "ScopedRead" ||
        typeof result.ScopedData !== "string" ||
        typeof result.ScopedHasNextPage !== "boolean" ||
        !Number.isSafeInteger(result.ScopedTotalCount)) {
      throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
    }
    const rows = parseSingleUserDevRows(TABLES.candidate.logicalName, result.ScopedData);
    if (rows.length > CANDIDATE_PAGE_SIZE) {
      throw new Error("SINGLE_USER_DEV_READ_RESPONSE_INVALID");
    }
    return {
      rows,
      hasNextPage: result.ScopedHasNextPage,
      totalCount: result.ScopedTotalCount >= 0 ? result.ScopedTotalCount : null,
      nextRequest: null
    };
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

  async function reportCandidateCoreFailure(action, candidateId, error, partialFailureMessage = "", correlationId = "") {
    logSafeFailure(`CANDIDATE_CORE_${action}_FAILED`, error);
    const details = [];
    if (error && Number.isInteger(error.httpStatus) && error.httpStatus >= 100 && error.httpStatus <= 599) {
      details.push(`HTTP ${error.httpStatus}`);
    }
    if (error && Number.isInteger(error.errorCode)) {
      details.push(`0x${(error.errorCode >>> 0).toString(16).padStart(8, "0").toUpperCase()}`);
    }
    if (error && typeof error.operationFailure === "string") details.push(error.operationFailure);
    if (/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(correlationId)) {
      details.push(`Correlation ${correlationId}`);
    }
    const diagnostic = details.length ? ` (${details.join("; ")})` : "";
    try {
      await refreshCandidates();
      if (candidateId) await openCandidate(candidateId);
    } catch (reconcileError) {
      logSafeFailure("CANDIDATE_CORE_RECONCILIATION_FAILED", reconcileError);
      showNotice(`${action} failed or its outcome is uncertain. Current server state could not be fully refreshed; do not retry until it is reconciled.${diagnostic}`, true);
      return;
    }
    if (action === "CreateCandidate" && error &&
        typeof error.operationFailure === "string" &&
        error.operationFailure.startsWith("AUTHORIZATION:")) {
      showNotice("Candidate creation was rejected by server authorization. Contact an administrator; no Candidate was created.", true);
      return;
    }
    const message = partialFailureMessage ||
      `${action} failed or its outcome is uncertain. Current server state was refreshed; verify it before retrying.`;
    showNotice(`${message}${diagnostic}`, true);
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
      if (!isCandidateCoreEnabled()) throw new Error("CONSOLE_DATA_ACCESS_BLOCKED");
      if (environmentPolicy.candidateOperationMode === "SingleUserDev") {
        const rows = await readSingleUserDevRecords(tableLogicalName);
        if (!isCandidateCoreEnabled()) throw new Error("CONSOLE_DATA_ACCESS_BLOCKED");
        return rows;
      }
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
    if (referenceMode === "NORMAL") return filter;
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
    const body = $("candidate-rows");
    body.replaceChildren();
    if (!rows.length) {
      const row = document.createElement("tr");
      const hasCriteria = Boolean($("candidate-search").value.trim() ||
        $("candidate-status-filter").value);
      const cell = appendCell(row, hasCriteria
        ? "No candidates match the current search and filter."
        : "No candidates found. Create one to get started.");
      cell.colSpan = 11;
      cell.className = "empty";
      body.appendChild(row);
      return;
    }
    for (const candidate of rows) {
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

  function candidateServerFilter(searchText, statusFilter) {
    const c = TABLES.candidate;
    const filters = [];
    if (searchText) {
      const term = searchText.replace(/'/g, "''");
      filters.push(`(contains(${filterAttribute(c.number)},'${term}') or ` +
        `contains(${filterAttribute(c.name)},'${term}') or ` +
        `contains(${filterAttribute(c.email)},'${term}'))`);
    }
    if (statusFilter === "active") {
      filters.push(`${filterAttribute(c.status)} ne ${STATUS.offerExtended} and ` +
        `${filterAttribute(c.status)} ne ${STATUS.candidateFailed}`);
    } else if (statusFilter) {
      if (!Object.hasOwn(STATUS_LABELS, statusFilter)) {
        throw new Error("CANDIDATE_STATUS_FILTER_INVALID");
      }
      filters.push(`${filterAttribute(c.status)} eq ${Number(statusFilter)}`);
    }
    return filters.join(" and ");
  }

  function candidateApiUrl(candidateUrl) {
    const clientUrl = globalContext().getClientUrl();
    const url = new URL(candidateUrl, clientUrl);
    const expectedPath = new RegExp(
      `^/api/data/v9\\.[012]/${filterAttribute(TABLES.candidate.entitySetName)}$`
    );
    if (url.origin !== new URL(clientUrl).origin || !expectedPath.test(url.pathname) ||
        url.username || url.password || url.hash) {
      throw new Error("CANDIDATE_LIST_PAGING_RESPONSE_INVALID");
    }
    return url;
  }

  function initialCandidateApiUrl(searchText, statusFilter) {
    const c = TABLES.candidate;
    const url = candidateApiUrl(
      `/api/data/v9.2/${filterAttribute(c.entitySetName)}`
    );
    const query = new URLSearchParams();
    query.set("$select", candidateColumns().join(","));
    query.set("$orderby", `createdon desc,${filterAttribute(c.id)} asc`);
    query.set("$count", "true");
    const filter = candidateServerFilter(searchText, statusFilter);
    if (filter) query.set("$filter", filter);
    url.search = query.toString();
    return url;
  }

  async function readNormalCandidatePage(searchText, statusFilter, requestUrl) {
    const url = requestUrl
      ? candidateApiUrl(requestUrl)
      : initialCandidateApiUrl(searchText, statusFilter);
    const response = await fetch(url.toString(), {
      method: "GET",
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
        Prefer: `odata.maxpagesize=${CANDIDATE_PAGE_SIZE}`
      }
    });
    let data;
    try {
      data = await response.json();
    } catch {
      throw new Error("CANDIDATE_LIST_RESPONSE_INVALID");
    }
    if (!response.ok || !data || !Array.isArray(data.value) ||
        data.value.length > CANDIDATE_PAGE_SIZE ||
        (data["@odata.nextLink"] != null && typeof data["@odata.nextLink"] !== "string")) {
      throw new Error("CANDIDATE_LIST_REQUEST_REJECTED");
    }
    const total = data["@odata.count"] == null ? null : Number(data["@odata.count"]);
    if (total !== null && (!Number.isSafeInteger(total) || total < 0)) {
      throw new Error("CANDIDATE_LIST_RESPONSE_INVALID");
    }
    return {
      rows: data.value,
      totalCount: total,
      hasNextPage: Boolean(data["@odata.nextLink"]),
      nextRequest: data["@odata.nextLink"] || null
    };
  }

  function updateCandidatePagination() {
    const total = candidateTotalCount;
    const pageCount = total == null ? null : Math.ceil(total / CANDIDATE_PAGE_SIZE);
    $("candidate-page-info").textContent = total === 0
      ? "0 candidates"
      : pageCount == null
        ? `Page ${candidatePageNumber}`
        : `Page ${candidatePageNumber} of ${pageCount} (${total} candidates)`;
    $("candidate-previous-page").disabled =
      busy || candidatePageNumber <= 1 || !isCandidateCoreEnabled();
    $("candidate-next-page").disabled =
      busy || !candidateHasNextPage || !isCandidateCoreEnabled();
  }

  async function refreshCandidates({ resetPage = false } = {}) {
    if (!isCandidateCoreEnabled()) throw new Error("CONSOLE_DATA_ACCESS_BLOCKED");
    if (resetPage) {
      candidatePageNumber = 1;
      candidatePageRequests = [null];
      candidateTotalCount = null;
      candidateHasNextPage = false;
    }
    const requestId = ++candidateListRequestId;
    const searchText = $("candidate-search").value.trim();
    const statusFilter = $("candidate-status-filter").value;
    const pageRequest = candidatePageRequests[candidatePageNumber - 1] || null;
    updateCandidatePagination();
    let page;
    try {
      page = environmentPolicy.candidateOperationMode === "SingleUserDev"
        ? await readSingleUserDevCandidatePage(searchText, statusFilter, candidatePageNumber)
        : await readNormalCandidatePage(searchText, statusFilter, pageRequest);
    } catch (error) {
      if (environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly) {
        blockSyntheticQuery();
      }
      throw error;
    }
    if (requestId !== candidateListRequestId) return;
    requireSyntheticCandidates(page.rows);
    candidateHasNextPage = page.hasNextPage;
    if (page.totalCount !== null) candidateTotalCount = page.totalCount;
    if (environmentPolicy.candidateOperationMode !== "SingleUserDev") {
      if (page.nextRequest) candidatePageRequests[candidatePageNumber] = page.nextRequest;
      else candidatePageRequests.length = candidatePageNumber;
    }
    renderCandidateRows(page.rows.filter(isCandidateAllowedByDataMode));
    updateCandidatePagination();
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
      appendCell(row, call[c.notes]).style.whiteSpace = "pre-wrap";
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
    invalidateRound1Availability(true);
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

  function setLookupPlaceholder(select, label) {
    select.replaceChildren();
    addOption(select, "", label);
  }

  function referenceXrm() {
    if (referenceMode !== "NORMAL") return xrm();
    // Native Dataverse reads enforce the signed-in caller's table and row permissions.
    if (resolveEnvironmentPolicy().allowed !== true) throw new Error("REFERENCE_CONTEXT_REJECTED");
    currentUserId();
    const service = window.parent && window.parent.Xrm || window.Xrm;
    if (!service || !service.WebApi || !service.Utility) {
      throw new Error("REFERENCE_DATA_SERVICES_UNAVAILABLE");
    }
    return service;
  }

  async function readNormalReferenceRecords(tableName, query, entitySetName) {
    if (referenceMode !== "NORMAL" || !SINGLE_USER_DEV_REFERENCE_SCOPE_KEYS[tableName]) {
      throw new Error("NORMAL_REFERENCE_TABLE_REJECTED");
    }
    const rows = [];
    const generation = referenceGeneration;
    const visited = new Set();
    let next = query;
    while (next) {
      if (visited.has(next)) throw new Error("REFERENCE_PAGING_RESPONSE_INVALID");
      visited.add(next);
      const response = await referenceXrm().WebApi.retrieveMultipleRecords(tableName, next);
      if (generation !== referenceGeneration || referenceMode !== "NORMAL") {
        throw new Error("REFERENCE_REQUEST_SUPERSEDED");
      }
      if (!response || !Array.isArray(response.entities)) throw new Error("REFERENCE_RESPONSE_INVALID");
      rows.push(...response.entities);
      if (response.nextLink && typeof response.nextLink !== "string") {
        throw new Error("REFERENCE_PAGING_RESPONSE_INVALID");
      }
      next = response.nextLink || "";
      if (next && !next.startsWith("?")) {
        const url = new URL(next, globalContext().getClientUrl());
        const expected = new URL(globalContext().getClientUrl());
        if (url.origin !== expected.origin ||
            !new RegExp(`^/api/data/v9\\.[012]/${filterAttribute(entitySetName)}$`).test(url.pathname)) {
          throw new Error("REFERENCE_PAGING_RESPONSE_INVALID");
        }
        next = url.search;
        if (!next) throw new Error("REFERENCE_PAGING_RESPONSE_INVALID");
      }
    }
    return rows;
  }

  function getSingleUserDevReferenceId(tableName) {
    const key = SINGLE_USER_DEV_REFERENCE_SCOPE_KEYS[tableName];
    const policy = window.BsoRsCandidateConsolePolicy;
    const scope = policy && typeof policy.getSyntheticScope === "function"
      ? policy.getSyntheticScope()
      : null;
    if (!key || !scope || !scope[key]) {
      throw new Error("SINGLE_USER_DEV_REFERENCE_SCOPE_UNAVAILABLE");
    }
    return normalizeGuid(scope[key]);
  }

  async function loadLookupOptions(tableName, selectIds, emptyLabels) {
    const ids = Array.isArray(selectIds) ? selectIds : [selectIds];
    const labels = Array.isArray(emptyLabels) ? emptyLabels : ids.map(() => emptyLabels);
    if (ids.length !== labels.length) throw new Error("REFERENCE_SELECTOR_CONFIGURATION_INVALID");
    const selects = ids.map((id) => $(id));
    const generation = referenceGeneration;
    const mode = referenceMode;
    const request = {};
    selects.forEach((select) => referenceRequests.set(select, request));
    const isCurrent = () => generation === referenceGeneration && mode === referenceMode &&
      selects.every((select) => referenceRequests.get(select) === request && $(select.id) === select);
    const previousValues = selects.map((select) => select.value);
    selects.forEach((select) => {
      select.disabled = true;
      select.setAttribute("aria-busy", "true");
      setLookupPlaceholder(select, "Loading options...");
    });
    try {
      const metadata = await referenceXrm().Utility.getEntityMetadata(tableName);
      if (!isCurrent()) return;
      const primaryId = metadata.PrimaryIdAttribute;
      const primaryName = metadata.PrimaryNameAttribute;
      if (!primaryId || !primaryName || !metadata.EntitySetName) {
        throw new Error("CANDIDATE_REFERENCE_METADATA_INVALID");
      }
      const roomFilter = requiresTrustedScheduleAvailability() && tableName === "os_sr_loc"
        ? " and os_sr_loc_rmeml ne null" : "";
      const filter = referenceScope(`statecode eq 0${roomFilter}`, primaryName);
      filterAttribute(primaryId);
      filterAttribute(primaryName);
      const query = `?$select=${primaryId},${primaryName},statecode` +
        `&$filter=${encodeURIComponent(filter)}&$orderby=${primaryName} asc,${primaryId} asc`;
      const rows = referenceMode === "NORMAL"
        ? await readNormalReferenceRecords(tableName, query, metadata.EntitySetName)
        : await retrieveAll(tableName, query);
      if (!isCurrent()) return;
      const expectedId = referenceMode !== "NORMAL" && environmentPolicy.candidateOperationMode === "SingleUserDev"
        ? getSingleUserDevReferenceId(tableName).toLowerCase()
        : null;
      const normalizedRows = rows.map((row) => {
        const id = normalizeGuid(row && row[primaryId]).toLowerCase();
        const label = row && row[primaryName];
        if (row.statecode !== 0 || typeof label !== "string" || !label.trim() ||
            !isReferenceAllowedByDataMode(label) || (expectedId && id !== expectedId)) {
          throw new Error("CANDIDATE_REFERENCE_OPTION_INVALID");
        }
        return { id, label };
      });
      if (new Set(normalizedRows.map((row) => row.id)).size !== normalizedRows.length) {
        throw new Error("CANDIDATE_REFERENCE_OPTION_DUPLICATED");
      }
      if (referenceMode !== "NORMAL" && environmentPolicy.candidateOperationMode === "SingleUserDev" &&
          (normalizedRows.length !== 1 || normalizedRows[0].id !== expectedId)) {
        throw new Error("SINGLE_USER_DEV_REFERENCE_RESPONSE_INVALID");
      }
      selects.forEach((select, index) => {
        setLookupPlaceholder(select, normalizedRows.length
          ? labels[index]
          : `No active ${REFERENCE_OPTION_LABELS[tableName] || "reference"} records found`);
        for (const row of normalizedRows) addOption(select, row.id, row.label);
        if (expectedId) select.value = expectedId;
        else if (normalizedRows.some((row) => row.id === previousValues[index])) {
          select.value = previousValues[index];
        }
        select.disabled = normalizedRows.length === 0;
        select.removeAttribute("aria-busy");
      });
    } catch (error) {
      if (!isCurrent()) return;
      selects.forEach((select) => {
        setLookupPlaceholder(select, "Options unavailable; use Refresh reference options to retry");
        select.removeAttribute("aria-busy");
      });
      throw error;
    }
  }

  async function refreshReferenceOptions() {
    const generation = ++referenceGeneration;
    referencesReady = false;
    const results = await Promise.allSettled([
      loadLookupOptions("os_sr_pos", ["candidate-position", "edit-candidate-position"],
        ["No position selected", "No position selected"]),
      loadLookupOptions("os_sr_csrc", ["candidate-source", "edit-candidate-source"],
        ["No source selected", "No source selected"]),
      loadLookupOptions("os_sr_ta",
        ["candidate-assigned-ta", "edit-candidate-assigned-ta", "scheduling-ta"],
        ["No TA assigned", "No TA assigned", "Select interviewer"]),
      referenceMode === "NORMAL" && environmentPolicy.syntheticDataOnly
        ? Promise.resolve()
        : loadLookupOptions("os_sr_loc", "scheduling-location",
          requiresTrustedScheduleAvailability() ? "Select meeting room" : "Select location")
    ]);
    if (generation !== referenceGeneration) return;
    const failures = results.filter((result) => result.status === "rejected");
    failures.forEach((result) => logSafeFailure("REFERENCE_OPTIONS_LOAD_FAILED", result.reason));
    if (failures.length) throw new Error("REFERENCE_OPTIONS_LOAD_FAILED");
    referencesReady = true;
  }

  function requiresTrustedScheduleAvailability() {
    return referenceMode === "NORMAL" || environmentPolicy.syntheticDataOnly === false;
  }

  function isManualRound1Scheduling() {
    return requiresTrustedScheduleAvailability() && $("scheduling-method").value === "manual";
  }

  function manualRound1Selection() {
    const selection = {};
    const messages = [];
    for (const [key, value, label] of [
      ["candidateId", selectedCandidate && selectedCandidate[TABLES.candidate.id], "Candidate"],
      ["roomId", $("scheduling-location").value, "Meeting Room"],
      ["taId", $("scheduling-ta").value, "Interviewer / TA"]
    ]) {
      try {
        const id = normalizeGuid(value).toLowerCase();
        if (id === "00000000-0000-0000-0000-000000000000") messages.push(`Select a valid ${label}.`);
        else selection[key] = id;
      } catch (error) {
        if (error.message !== "DEV_DIRECT_WRITE_INVALID_RECORD_REFERENCE") throw error;
        messages.push(`Select a valid ${label}.`);
      }
    }
    const date = $("scheduling-date").value;
    const midnight = new Date(`${date}T00:00:00+07:00`);
    const validDate = /^\d{4}-\d{2}-\d{2}$/.test(date) && Number.isFinite(midnight.getTime()) &&
      new Date(midnight.getTime() + 7 * 3600000).toISOString().slice(0, 10) === date;
    if (!validDate) messages.push("Enter a valid Interview Date.");
    const times = ["scheduling-time", "scheduling-end-time"].map((id, index) => {
      const time = $(id).value;
      if (!/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(time)) {
        messages.push(`Enter a valid ${index === 0 ? "Start" : "End"} Time.`);
        return null;
      }
      return validDate ? new Date(`${date}T${time}:00+07:00`) : null;
    });
    if (times[0] && times[0].getTime() <= Date.now()) {
      messages.push("Start Time must be in the future in SE Asia Standard Time (UTC+07:00).");
    }
    if (times[0] && times[1] && times[1] <= times[0]) messages.push("End Time must be later than Start Time.");
    if (messages.length) {
      const error = new Error("MANUAL_SCHEDULE_INPUT_INVALID");
      error.validationMessages = messages;
      throw error;
    }
    return { ...selection, actorId: currentUserId().toLowerCase(), date,
      startUtc: times[0].toISOString(), endUtc: times[1].toISOString() };
  }

  function round1SchedulingMethodChanged() {
    if (!requiresTrustedScheduleAvailability()) return;
    invalidateRound1Availability();
    const manual = isManualRound1Scheduling();
    for (const id of ["scheduling-time", "scheduling-end-time"]) {
      $(`${id}-field`).hidden = !manual;
      $(id).required = manual;
      $(id).disabled = busy || !manual;
    }
    $("scheduling-manual-warning").hidden = !manual;
    $("scheduling-availability").hidden = manual;
    $("scheduling-slot-field").hidden = manual;
    $("scheduling-slot").required = !manual;
    updateRound1AvailabilityControls();
  }

  function invalidateRound1Availability(resetCapabilities = false, preserveManualTimes = false) {
    round1Availability.generation++;
    round1Availability.checking = false;
    round1Availability.evidence = null;
    if (resetCapabilities) {
      round1Availability.capabilityGeneration++;
      round1Availability.providerOperational = false;
      round1Availability.manualSchedulingOperational = false;
    }
    window.clearTimeout(round1Availability.expiryTimer);
    round1Availability.expiryTimer = null;
    if (!preserveManualTimes) {
      for (const id of ["scheduling-time", "scheduling-end-time"]) $(id).value = "";
    }
    setLookupPlaceholder($("scheduling-slot"), "Check availability to load verified slots");
    $("scheduling-slot").disabled = true;
    $("save-schedule").disabled = true;
  }

  function round1Selection() {
    if (!selectedCandidate || scheduleMode === "reschedule") throw new Error("AVAILABILITY_CANDIDATE_INVALID");
    const date = $("scheduling-date").value;
    const start = new Date(`${date}T09:00:00+07:00`);
    const end = new Date(`${date}T17:00:00+07:00`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(start.getTime()) ||
        new Date(start.getTime() + 7 * 3600000).toISOString().slice(0, 10) !== date) {
      throw new Error("AVAILABILITY_DATE_INVALID");
    }
    return {
      candidateId: normalizeGuid(selectedCandidate[TABLES.candidate.id]).toLowerCase(),
      actorId: currentUserId().toLowerCase(),
      roomId: normalizeGuid($("scheduling-location").value).toLowerCase(),
      taId: normalizeGuid($("scheduling-ta").value).toLowerCase(), date,
      startUtc: start.toISOString(), endUtc: end.toISOString()
    };
  }

  function selectedVerifiedRound1Slot() {
    const evidence = round1Availability.evidence;
    if (!round1Availability.providerOperational || round1Availability.checking || !evidence ||
        Date.parse(evidence.expiresAtUtc) <= Date.now()) return null;
    try {
      const current = round1Selection();
      if (["candidateId", "actorId", "roomId", "taId", "date"].some((key) => current[key] !== evidence[key])) return null;
      return evidence.slots.find((slot) => slot.startUtc === $("scheduling-slot").value &&
        Date.parse(slot.startUtc) > Date.now()) || null;
    } catch (error) {
      if (error.message !== "DEV_DIRECT_WRITE_INVALID_RECORD_REFERENCE" && !error.message.startsWith("AVAILABILITY_")) throw error;
      return null;
    }
  }

  function updateRound1AvailabilityControls() {
    if (!requiresTrustedScheduleAvailability()) return;
    const manual = isManualRound1Scheduling();
    let valid = false;
    let manualMessages = [];
    if (manual || selectedCandidate && selectedCandidate[TABLES.candidate.status] === STATUS.waitingManualScheduling) {
      try { if (manual) manualRound1Selection(); else round1Selection(); valid = true; }
      catch (error) {
        if (manual && error.message === "MANUAL_SCHEDULE_INPUT_INVALID") manualMessages = error.validationMessages;
        else if (error.message === "DEV_DIRECT_WRITE_INVALID_RECORD_REFERENCE") {
          if (manual) manualMessages = ["Authenticated user identity is unavailable. Reload Candidate details."];
        } else if (manual || !error.message.startsWith("AVAILABILITY_")) throw error;
      }
    }
    for (const id of ["scheduling-location", "scheduling-date", "scheduling-ta", "scheduling-method", "scheduling-notes"]) {
      $(id).disabled = busy;
    }
    for (const id of ["scheduling-time", "scheduling-end-time"]) $(id).disabled = busy || !manual;
    $("scheduling-manual-option").disabled = !round1Availability.manualSchedulingOperational;
    $("scheduling-check-availability").disabled = busy || !workspaceReady || !referencesReady ||
      manual || !round1Availability.providerOperational || round1Availability.checking || !valid;
    $("scheduling-slot").disabled = busy || manual || round1Availability.checking ||
      !round1Availability.evidence || round1Availability.evidence.slots.length === 0;
    const blockers = [];
    if (busy) blockers.push("A request is in progress. Wait for it to finish.");
    if (!workspaceReady) blockers.push("Candidate workspace is not ready.");
    if (!referencesReady) blockers.push("Room and TA references are not ready. Refresh references.");
    if (!isCandidateCoreEnabled()) blockers.push("Candidate Core is unavailable for this environment.");
    if (!selectedCandidate) blockers.push("Select a valid Candidate.");
    else {
      if (!isCandidateAllowedByDataMode(selectedCandidate)) blockers.push("Candidate is not authorized for the current data mode.");
      if (selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling) {
        blockers.push("Candidate must be in Waiting Manual Scheduling.");
      }
      if (scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id]) {
        blockers.push("A previous Schedule request needs reconciliation before another save.");
      }
    }
    if (scheduleMode === "reschedule") blockers.push("Reschedule is not supported by this scheduling confirmation form.");
    if (selectedSchedule) blockers.push("An active Round 1 Schedule already exists. Refresh Candidate details.");
    if (manual && !round1Availability.manualSchedulingOperational) {
      blockers.push("Server authorization for manual scheduling has not been confirmed. Reload Candidate details.");
    }
    $("save-schedule").disabled = blockers.length > 0 ||
      (manual ? !valid : !selectedVerifiedRound1Slot());
    const feedback = $("scheduling-validation-status");
    feedback.hidden = !manual;
    feedback.textContent = manual
      ? [...new Set(blockers.concat(manualMessages))].join(" ") ||
        "Ready to save Manual Scheduling - availability not checked."
      : "";
  }

  async function readRound1Availability(action, inputs, correlationId) {
    const { result } = await sendCandidateCoreRequest(action, inputs, correlationId);
    if (!result || result.ResultCode !== "AvailabilityRead" || typeof result.ScopedData !== "string") {
      throw new Error("AVAILABILITY_RESPONSE_INVALID");
    }
    const data = JSON.parse(result.ScopedData);
    if (!data || data.schemaVersion !== 1) throw new Error("AVAILABILITY_RESPONSE_INVALID");
    return data;
  }

  async function loadRound1SchedulingCapabilities() {
    const generation = round1Availability.capabilityGeneration;
    $("scheduling-availability-status").textContent = "Checking scheduling service capability...";
    try {
      const data = await readRound1Availability("GetRound1SchedulingCapabilities", {
        CandidateId: selectedCandidate[TABLES.candidate.id],
        ExpectedStatus: selectedCandidate[TABLES.candidate.status]
      }, newCorrelationId());
      if (generation !== round1Availability.capabilityGeneration) return;
      if (typeof data.providerOperational !== "boolean" ||
          typeof data.manualSchedulingOperational !== "boolean") throw new Error("AVAILABILITY_RESPONSE_INVALID");
      round1Availability.providerOperational = data.providerOperational;
      round1Availability.manualSchedulingOperational = data.manualSchedulingOperational;
      $("scheduling-availability-status").textContent = data.providerOperational
        ? "Select Meeting Room, Interview Date and TA, then check availability."
        : "Authenticated Outlook transport is unavailable. Automatic availability and saving remain disabled. " +
          (data.manualSchedulingOperational ? "Choose Manual Scheduling to record an explicit schedule without checking availability."
            : "Manual scheduling is not enabled.");
      updateRound1AvailabilityControls();
    } catch (error) {
      if (generation !== round1Availability.capabilityGeneration) return;
      logSafeFailure("ROUND1_CAPABILITY_READ_FAILED", error);
      round1Availability.providerOperational = false;
      round1Availability.manualSchedulingOperational = false;
      $("scheduling-availability-status").textContent =
        "Scheduling service capability could not be verified. No availability or saving is enabled. Reopen Schedule Round 1 to retry.";
      updateRound1AvailabilityControls();
    }
  }

  function validateRound1Availability(data, selection, correlationId) {
    const utc = (value) => typeof value === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value) &&
      Number.isFinite(Date.parse(value)) && new Date(value).toISOString() === value;
    const now = Date.now();
    if (data.state !== "Ready" || data.queryId !== correlationId ||
        ["candidateId", "actorId", "roomId", "taId", "date"].some((key) => data[key] !== selection[key]) ||
        data.correlationId !== correlationId || normalizeGuid(data.evidenceId) !== data.evidenceId ||
        data.evidenceId === "00000000-0000-0000-0000-000000000000" ||
        !utc(data.observedAtUtc) || !utc(data.expiresAtUtc) ||
        Date.parse(data.observedAtUtc) > now || now - Date.parse(data.observedAtUtc) > 120000 ||
        Date.parse(data.expiresAtUtc) <= now || Date.parse(data.expiresAtUtc) <= Date.parse(data.observedAtUtc) ||
        Date.parse(data.expiresAtUtc) - Date.parse(data.observedAtUtc) > 120000 ||
        !Array.isArray(data.slots) || data.slots.length > 16) throw new Error("AVAILABILITY_EVIDENCE_INVALID");
    let previousEnd = 0;
    for (const slot of data.slots) {
      if (!slot || !utc(slot.startUtc) || !utc(slot.endUtc) ||
          slot.evidenceCorrelationId !== correlationId ||
          Date.parse(slot.endUtc) - Date.parse(slot.startUtc) !== 1800000 ||
          Date.parse(slot.startUtc) <= now || Date.parse(slot.startUtc) < previousEnd ||
          Date.parse(slot.startUtc) < Date.parse(selection.startUtc) ||
          Date.parse(slot.endUtc) > Date.parse(selection.endUtc) ||
          Date.parse(slot.startUtc) % 1800000 !== 0 ||
          [0, 6].includes(new Date(`${selection.date}T12:00:00+07:00`).getUTCDay())) {
        throw new Error("AVAILABILITY_SLOT_INVALID");
      }
      previousEnd = Date.parse(slot.endUtc);
    }
    return data;
  }

  async function pollRound1Availability(selection, correlationId, generation) {
    for (let attempt = 0; attempt < AVAILABILITY_POLL_ATTEMPTS; attempt++) {
      if (generation !== round1Availability.generation) return null;
      const data = await readRound1Availability("GetRound1Availability", {
        CandidateId: selection.candidateId, ExpectedStatus: STATUS.waitingManualScheduling,
        InterviewerId: selection.taId, LocationId: selection.roomId,
        StartAt: selection.startUtc, EndAt: selection.endUtc
      }, correlationId);
      if (generation !== round1Availability.generation) return null;
      if (data.state === "Ready") return validateRound1Availability(data, selection, correlationId);
      if (data.state === "Failed") {
        const code = typeof data.errorCode === "string" &&
          /^[A-Z][A-Z0-9_]{0,39}$/.test(data.errorCode) ? data.errorCode : "AVAILABILITY_PROVIDER_UNAVAILABLE";
        throw new Error(`AVAILABILITY_PROVIDER_FAILED:${code}`);
      }
      if (data.state === "Expired") throw new Error("AVAILABILITY_EVIDENCE_STALE");
      if (data.state !== "Pending") throw new Error("AVAILABILITY_RESPONSE_INVALID");
      $("scheduling-availability-status").textContent = "Checking availability...";
      await new Promise((resolve) => window.setTimeout(resolve, AVAILABILITY_POLL_INTERVAL_MS));
    }
    throw new Error("AVAILABILITY_TIMEOUT");
  }

  async function checkRound1Availability() {
    if (busy || round1Availability.checking || !round1Availability.providerOperational ||
        !requiresTrustedScheduleAvailability()) return;
    let selection;
    try { selection = round1Selection(); }
    catch (error) {
      logSafeFailure("ROUND1_AVAILABILITY_INPUT_INVALID", error);
      showNotice("Select a valid Meeting Room, Interview Date and TA.", true);
      return;
    }
    invalidateRound1Availability();
    const generation = round1Availability.generation;
    const correlationId = newCorrelationId();
    round1Availability.checking = true;
    $("scheduling-availability-status").textContent = "Checking availability...";
    updateRound1AvailabilityControls();
    try {
      const data = await pollRound1Availability(selection, correlationId, generation);
      if (!data) return null;
      if (generation !== round1Availability.generation) return;
      round1Availability.evidence = data;
      setLookupPlaceholder($("scheduling-slot"), data.slots.length ? "Select a verified 30-minute slot" : "No common free slots");
      for (const slot of data.slots) {
        const label = (value) => new Date(value).toLocaleTimeString("en-GB", {
          timeZone: "Asia/Ho_Chi_Minh", hour: "2-digit", minute: "2-digit", hour12: false
        });
        addOption($("scheduling-slot"), slot.startUtc, `${label(slot.startUtc)} - ${label(slot.endUtc)}`);
      }
      $("scheduling-availability-status").textContent = data.slots.length
        ? `${data.slots.length} common free 30-minute slots. Availability is rechecked by the server before saving.`
        : "No common free 30-minute slots for the selected Room, TA and date.";
      round1Availability.expiryTimer = window.setTimeout(() => {
        if (generation !== round1Availability.generation) return;
        invalidateRound1Availability();
        $("scheduling-availability-status").textContent = "Availability expired. Check Room + TA availability again.";
        updateRound1AvailabilityControls();
      }, Math.min(Date.parse(data.expiresAtUtc), ...data.slots.map((slot) => Date.parse(slot.startUtc))) - Date.now());
      return data;
    } catch (error) {
      if (generation !== round1Availability.generation) return;
      logSafeFailure("ROUND1_AVAILABILITY_FAILED", error);
      const providerFailure = /^AVAILABILITY_PROVIDER_FAILED:([A-Z][A-Z0-9_]{0,39})$/.exec(error.message);
      $("scheduling-availability-status").textContent = providerFailure
        ? `Availability check failed (${providerFailure[1]}). No slots are available to select.`
        : error.message === "AVAILABILITY_EVIDENCE_STALE" || error.message === "AVAILABILITY_TIMEOUT"
          ? "Availability expired or timed out. No slots are available to select; check again."
          : "Outlook provider error or invalid response. No slots are available to select. Check availability again to retry.";
      return null;
    } finally {
      if (generation === round1Availability.generation) {
        round1Availability.checking = false;
        updateRound1AvailabilityControls();
      }
    }
  }

  function round1SelectionChanged() {
    if (!requiresTrustedScheduleAvailability()) return;
    const recalculate = Boolean(round1Availability.evidence) || round1Availability.checking;
    invalidateRound1Availability(false, isManualRound1Scheduling());
    $("scheduling-availability-status").textContent = round1Availability.providerOperational
      ? "Selection changed. Check Room + TA availability for the current selection."
      : "Authenticated Outlook transport is unavailable. Automatic availability and saving remain disabled; manual scheduling does not check availability.";
    updateRound1AvailabilityControls();
    if (recalculate && !$("scheduling-check-availability").disabled) void checkRound1Availability();
  }

  function selectRound1Slot() {
    const slot = selectedVerifiedRound1Slot();
    const localTime = (value) => new Date(Date.parse(value) + 7 * 3600000).toISOString().slice(11, 16);
    $("scheduling-time").value = slot ? localTime(slot.startUtc) : "";
    $("scheduling-end-time").value = slot ? localTime(slot.endUtc) : "";
    updateRound1AvailabilityControls();
  }

  function configureSchedulingAvailability() {
    const required = requiresTrustedScheduleAvailability();
    $("scheduling-method").value = "automatic";
    $("scheduling-method-field").hidden = !required;
    $("scheduling-manual-warning").hidden = true;
    $("scheduling-validation-status").hidden = true;
    invalidateRound1Availability(true);
    $("scheduling-time-field").hidden = required;
    $("scheduling-end-time-field").hidden = required;
    for (const id of ["scheduling-time", "scheduling-end-time"]) {
      $(id).disabled = required;
      $(id).required = !required;
    }
    $("scheduling-location-label").textContent = required ? "Meeting Room" : "Location";
    $("scheduling-availability").hidden = !required;
    $("scheduling-slot-field").hidden = !required;
    $("scheduling-slot").required = required;
    $("scheduling-slot").disabled = true;
    setLookupPlaceholder($("scheduling-slot"), "Availability unavailable - no verified slots");
    $("scheduling-check-availability").disabled = true;
    $("scheduling-availability-status").textContent = "Authenticated Outlook availability has not been verified.";
    $("scheduling-dev-note").hidden = false;
    $("scheduling-dev-note").textContent = required
      ? "Saves the ATSugg schedule only. No Outlook meeting or email invitation is created."
      : "Manual schedule evidence only. No calendar availability check or calendar booking is performed.";
    if (required) {
      const assignedTa = selectedCandidate[TABLES.candidate.assignedTa];
      $("scheduling-ta").value = typeof assignedTa === "string" ? assignedTa.toLowerCase() : "";
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
        : "Schedule Round 1 is available only in Waiting Manual Scheduling with no active schedule.", true);
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
    configureSchedulingAvailability();
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
    $(requiresTrustedScheduleAvailability() ? "scheduling-location" : "scheduling-ta").focus();
    if (requiresTrustedScheduleAvailability() && scheduleMode !== "reschedule") void loadRound1SchedulingCapabilities();
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

  async function saveNormalRound1Schedule() {
    const manual = isManualRound1Scheduling();
    let slot = manual ? null : selectedVerifiedRound1Slot();
    let selection;
    try { selection = manual ? manualRound1Selection() : round1Selection(); }
    catch (error) {
      logSafeFailure("ROUND1_SELECTION_INVALID", error);
      showNotice(error.message === "MANUAL_SCHEDULE_INPUT_INVALID"
        ? `Schedule not saved. ${error.validationMessages.join(" ")}`
        : "Schedule not saved. Select Room, Date and TA, with valid future start/end times for manual scheduling.", true);
      return;
    }
    if ((manual ? !round1Availability.manualSchedulingOperational : !slot) ||
        !isCandidateCoreEnabled() || !workspaceReady || !referencesReady ||
        !selectedCandidate || !isCandidateAllowedByDataMode(selectedCandidate) ||
        selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
        Boolean(selectedSchedule) || scheduleMode === "reschedule" ||
        scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id]) {
      showNotice("Schedule not saved. Select a current verified Room + TA slot, or explicitly choose authorized Manual Scheduling with valid times.", true);
      return;
    }
    const action = manual ? "RecordManualRound1Schedule" : "MarkRound1Scheduled";
    if (!manual) {
      const selectedStart = slot.startUtc;
      const refreshedEvidence = await checkRound1Availability();
      slot = refreshedEvidence?.slots.find((candidate) => candidate.startUtc === selectedStart) || null;
      if (!slot) {
        showNotice("Schedule not saved. The selected slot is no longer available; select a current verified slot.", true);
        return;
      }
      $("scheduling-slot").value = selectedStart;
    }
    const timeWindow = manual ? selection : slot;
    const notes = manual ? $("scheduling-notes").value : $("scheduling-notes").value.trim();
    const correlationId = manual ? newCorrelationId() : round1Availability.evidence.queryId;
    let submitted = false;
    let confirmed = false;
    hideNotice();
    setBusy(true);
    try {
      await Promise.all([
        getActiveReference("os_sr_ta", selection.taId),
        getActiveReference("os_sr_loc", selection.roomId)
      ]);
      if (manual) {
        const current = manualRound1Selection();
        if (!isManualRound1Scheduling() || ["candidateId", "roomId", "taId", "date", "startUtc", "endUtc"]
            .some((key) => current[key] !== selection[key])) throw new Error("MANUAL_SCHEDULE_SELECTION_CHANGED");
      } else if (isManualRound1Scheduling() || selectedVerifiedRound1Slot() !== slot) {
        throw new Error("AVAILABILITY_SELECTION_CHANGED");
      }
      const { result } = await invokeCandidateCore(action, {
        CandidateId: selection.candidateId, ExpectedStatus: STATUS.waitingManualScheduling,
        InterviewerId: selection.taId, LocationId: selection.roomId,
        StartAt: timeWindow.startUtc, EndAt: timeWindow.endUtc, Notes: notes
      }, correlationId, () => { submitted = true; });
      assertCandidateCoreStatus(result, STATUS.round1Scheduled);
      normalizeGuid(result.StatusHistoryId);
      await refreshCoreCandidate(selection.candidateId);
      const interview = TABLES.interview;
      const saved = scheduleRows.filter(isActiveSchedule);
      if (!selectedCandidate || normalizeGuid(selectedCandidate[TABLES.candidate.id]).toLowerCase() !== selection.candidateId ||
          selectedCandidate[TABLES.candidate.status] !== STATUS.round1Scheduled || saved.length !== 1 ||
          !sameOptionalGuid(saved[0][interview.ta], selection.taId) ||
          !sameOptionalGuid(saved[0][interview.location], selection.roomId) ||
          Date.parse(saved[0][interview.start]) !== Date.parse(timeWindow.startUtc) ||
          Date.parse(saved[0][interview.end]) !== Date.parse(timeWindow.endUtc) ||
          (saved[0][interview.notes] || "") !== (notes.trim() ? notes : "")) throw new Error("SCHEDULE_PERSISTENCE_NOT_CONFIRMED");
      confirmed = true;
      invalidateRound1Availability(true);
      $("scheduling-form").reset();
      $("scheduling-panel").hidden = true;
      scheduleMode = "new";
      showNotice(manual
        ? "Manual Scheduling \u2014 availability not checked. Round 1 Scheduled in ATSugg only; no Outlook meeting or invitation was created."
        : "Round 1 Scheduled. ATSugg record saved; no Outlook meeting or invitation was created.");
    } catch (error) {
      if (submitted) scheduleRetryBlockedCandidateId = selection.candidateId;
      await reportCandidateCoreFailure(action, selection.candidateId, error,
        submitted ? "Schedule persistence or refresh could not be confirmed. Reconcile the current Schedule and Status History before retrying."
          : "Schedule was not submitted. Review the selection, active references and application authorization before trying again.",
        correlationId);
    } finally {
      setBusy(false);
    }
    if (confirmed) {
      setBusy(true);
      try {
        await xrm().Navigation.openAlertDialog({ text: "Schedule saved successfully." });
      } catch (error) {
        logSafeFailure("SCHEDULE_SUCCESS_DIALOG_FAILED", error);
        showNotice("Schedule saved successfully, but the success dialog could not be displayed.", true);
      } finally {
        setBusy(false);
      }
    }
  }

  async function createScheduleThroughCore(event) {
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    if (requiresTrustedScheduleAvailability()) {
      return saveNormalRound1Schedule();
    }
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
    if (requiresTrustedScheduleAvailability()) {
      event.preventDefault();
      if (busy || !selectedCandidate) return;
      return saveNormalRound1Schedule();
    }
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
      const { result } = await invokeCandidateCore("CreateCandidate", inputs, correlationId);
      candidateId = normalizeGuid(result.CreatedCandidateId);
      if (typeof result.CandidateNumber !== "string" ||
          !result.CandidateNumber.trim() || result.CandidateNumber.length > 100) {
        throw new Error("CANDIDATE_CORE_CREATE_RESPONSE_INVALID");
      }
      $("candidate-form").reset();
      $("candidate-search").value = "";
      $("candidate-status-filter").value = "";
      await refreshCoreCandidate(candidateId);
      showNotice(`Candidate ${result.CandidateNumber} created successfully through Candidate Core.`);
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
    if (callRetryBlockedCandidates.has(candidateId.toLowerCase())) {
      showNotice("A previous Call submission failed or is uncertain. Reconcile Call history before recording another Call; do not resubmit.", true);
      return;
    }
    const outcome = Number($("call-outcome").value);
    if (![OUTCOME.noAnswer, OUTCOME.answered, OUTCOME.callBackRequested].includes(outcome)) {
      showNotice("Choose a supported call outcome.", true);
      return;
    }
    const notes = $("call-notes").value;
    const currentStatus = selectedCandidate[c.status];
    const expectedStatus = outcome === OUTCOME.answered && currentStatus === STATUS.needCall
      ? STATUS.answered
      : currentStatus;
    let showSchedulingPanelAfterSave = false;
    let confirmedSuccess = false;
    let callConfirmed = false;
    let action = "RecordCall";
    const correlationId = newCorrelationId();
    const schedulingCorrelationId = newCorrelationId();
    setBusy(true);
    callRetryBlockedCandidates.add(candidateId.toLowerCase());
    try {
      const { result } = await invokeCandidateCore("RecordCall", {
        CandidateId: candidateId,
        ExpectedStatus: currentStatus,
        CallOutcome: outcome,
        ContactedAt: new Date().toISOString(),
        Notes: notes.trim() ? notes : undefined
      }, correlationId);
      assertCandidateCoreStatus(result, expectedStatus);
      await verifyRecordedCall(candidateId, correlationId, result, outcome, notes);
      callConfirmed = true;
      if (outcome === OUTCOME.answered && currentStatus === STATUS.needCall) {
        action = "ProceedToScheduling";
        callSchedulingCorrelations.set(candidateId.toLowerCase(), schedulingCorrelationId);
        const schedulingResult = await invokeCandidateCore("ProceedToScheduling", {
          CandidateId: candidateId,
          ExpectedStatus: STATUS.answered
        }, schedulingCorrelationId);
        assertCandidateCoreStatus(schedulingResult.result, STATUS.waitingManualScheduling);
      }
      await refreshCoreCandidate(candidateId);
      if (outcome === OUTCOME.answered &&
          (!selectedCandidate || selectedCandidate[c.status] !== STATUS.waitingManualScheduling))
        throw new Error("CALL_SCHEDULING_STATUS_READBACK_MISMATCH");
      showSchedulingPanelAfterSave = outcome === OUTCOME.answered;
      $("call-form").reset();
      callRetryBlockedCandidates.delete(candidateId.toLowerCase());
      callSchedulingCorrelations.delete(candidateId.toLowerCase());
      confirmedSuccess = true;
      showNotice(showSchedulingPanelAfterSave
        ? "Candidate moved to Waiting Manual Scheduling; Call and comments verified."
        : "Call and comments verified.");
    } catch (error) {
      await reportCandidateCoreFailure(action, candidateId, error, callConfirmed
        ? "The Call and comments were saved, but the workflow refresh or scheduling transition failed or is uncertain. Do not record the Call again. If the refreshed status is Candidate Answered, use Move to Waiting Manual Scheduling."
        : "Call persistence could not be confirmed. Comments remain in the form. Reconcile Call history before retrying; do not submit another Call blindly.");
    } finally {
      setBusy(false);
    }
    if (showSchedulingPanelAfterSave) showSchedulingPanel();
    if (confirmedSuccess) {
      setBusy(true);
      try {
        await xrm().Navigation.openAlertDialog({ text: "Call saved successfully." });
      } catch (error) {
        logSafeFailure("CALL_SUCCESS_DIALOG_FAILED", error);
        showNotice("Call saved successfully, but the success dialog could not be displayed.", true);
      } finally {
        setBusy(false);
      }
    }
  }

  async function verifyRecordedCall(candidateId, correlationId, result, outcome, notes) {
    const call = TABLES.call;
    const callId = normalizeGuid(result.CallLogId);
    const rows = await retrieveAll(call.logicalName,
      `?$select=${[call.id, call.candidate, call.correlation, call.outcome, call.notes].join(",")}` +
      `&$filter=${encodeURIComponent(relatedCandidateFilter(call, candidateId,
        `${call.id} eq ${callId}`))}&$top=2`);
    const matches = rows.filter((row) =>
      String(row[call.id]).toLowerCase() === callId.toLowerCase() &&
      String(row[call.candidate]).toLowerCase() === candidateId.toLowerCase() &&
      (environmentPolicy.candidateOperationMode === "SingleUserDev" ||
        String(row[call.correlation]).toLowerCase() === correlationId.toLowerCase()) &&
      row[call.outcome] === outcome);
    const expectedNotes = notes.trim() ? notes : "";
    if (matches.length !== 1 ||
        String(matches[0][call.notes] ?? "").replace(/\r\n/g, "\n") !==
          expectedNotes.replace(/\r\n/g, "\n"))
      throw new Error("CALL_COMMENTS_READBACK_MISMATCH");
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
      const key = candidateId.toLowerCase();
      const correlationId = callSchedulingCorrelations.get(key) || newCorrelationId();
      callSchedulingCorrelations.set(key, correlationId);
      const { result } = await invokeCandidateCore("ProceedToScheduling", {
        CandidateId: candidateId,
        ExpectedStatus: STATUS.answered
      }, correlationId);
      assertCandidateCoreStatus(result, STATUS.waitingManualScheduling);
      await refreshCoreCandidate(candidateId);
      if (!selectedCandidate || selectedCandidate[c.status] !== STATUS.waitingManualScheduling)
        throw new Error("CALL_SCHEDULING_STATUS_READBACK_MISMATCH");
      callSchedulingCorrelations.delete(key);
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
    $("candidate-data-mode").addEventListener("change", async () => {
      if (busy) return;
      const selectedMode = $("candidate-data-mode").value;
      if (!["CONFIGURED", "NORMAL"].includes(selectedMode)) {
        showNotice("Candidate data mode is invalid. Reload the Console.", true);
        return;
      }
      referenceMode = selectedMode;
      environmentPolicy = resolveEnvironmentPolicy(selectedMode);
      referenceGeneration++;
      referencesReady = false;
      syntheticQueryBlocked = false;
      invalidateRound1Availability(true);
      window.clearTimeout(isolationExpiryTimer);
      selectedCandidate = null;
      selectedSchedule = null;
      proposedSchedule = null;
      scheduleRows = [];
      currentRows = [];
      scheduleRetryBlockedCandidateId = null;
      resultRetryBlockedCandidateId = null;
      $("dev-fallback-toggle").checked = false;
      for (const id of ["candidate-form", "edit-candidate-form", "call-form",
        "scheduling-form", "cancellation-form", "interview-result-form"]) {
        $(id).reset();
      }
      for (const id of ["detail-panel", "call-entry-panel", "edit-candidate-panel",
        "scheduling-panel", "cancellation-panel", "interview-result-panel"]) {
        $(id).hidden = true;
      }
      for (const id of ["candidate-position", "edit-candidate-position", "candidate-source",
        "edit-candidate-source", "candidate-assigned-ta", "edit-candidate-assigned-ta",
        "scheduling-ta", "scheduling-location"]) {
        setLookupPlaceholder($(id), "Select a reference");
        $(id).disabled = true;
      }
      $("candidate-rows").replaceChildren();
      hideNotice();
      await loadWorkspace();
    });
    $("refresh-references").addEventListener("click", async () => {
      if (busy) return;
      setBusy(true);
      hideNotice();
      try {
        if (referenceMode !== "NORMAL" && environmentPolicy.syntheticDataOnly) {
          await verifyServerIsolation();
          syntheticQueryBlocked = false;
          if (!TABLES.candidate.id) throw new Error("CANDIDATE_WORKSPACE_RELOAD_REQUIRED");
        }
        await refreshReferenceOptions();
        showNotice("Active reference options refreshed.");
      } catch (error) {
        logSafeFailure("REFERENCE_REFRESH_FAILED", error);
        showNotice("Reference options could not be refreshed. Check access and use Refresh reference options to retry.", true);
      } finally {
        setBusy(false);
      }
    });
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
    $("scheduling-check-availability").addEventListener("click", checkRound1Availability);
    for (const id of ["scheduling-location", "scheduling-date", "scheduling-ta"]) {
      $(id).addEventListener("input", updateRound1AvailabilityControls);
      $(id).addEventListener("change", round1SelectionChanged);
    }
    $("scheduling-slot").addEventListener("change", selectRound1Slot);
    $("scheduling-method").addEventListener("change", round1SchedulingMethodChanged);
    for (const id of ["scheduling-time", "scheduling-end-time"]) {
      $(id).addEventListener("input", updateRound1AvailabilityControls);
    }
    $("cancellation-form").addEventListener("submit", cancelRound1);
    $("interview-result-form").addEventListener("submit", recordInterviewResult);
    $("candidate-search").addEventListener("input", () => {
      candidateListRequestId++;
      candidatePageNumber = 1;
      candidatePageRequests = [null];
      candidateTotalCount = null;
      candidateHasNextPage = false;
      updateCandidatePagination();
      if (candidateSearchTimer) clearTimeout(candidateSearchTimer);
      candidateSearchTimer = setTimeout(() => {
        candidateSearchTimer = null;
        refreshCandidates({ resetPage: true }).catch((error) => {
          logSafeFailure("CANDIDATE_LIST_SEARCH_FAILED", error);
          showNotice("Candidate list search could not be completed.", true);
        });
      }, 250);
    });
    $("candidate-status-filter").addEventListener("change", () => {
      candidateListRequestId++;
      candidatePageNumber = 1;
      candidatePageRequests = [null];
      candidateTotalCount = null;
      candidateHasNextPage = false;
      updateCandidatePagination();
      refreshCandidates({ resetPage: true }).catch((error) => {
        logSafeFailure("CANDIDATE_LIST_FILTER_FAILED", error);
        showNotice("Candidate list filter could not be completed.", true);
      });
    });
    const changeCandidatePage = async (delta) => {
      if (busy || (delta < 0 && candidatePageNumber <= 1) ||
          (delta > 0 && !candidateHasNextPage)) return;
      const previousPage = candidatePageNumber;
      candidatePageNumber += delta;
      try {
        await refreshCandidates();
      } catch (error) {
        candidatePageNumber = previousPage;
        updateCandidatePagination();
        logSafeFailure("CANDIDATE_LIST_PAGE_FAILED", error);
        showNotice("Candidate list page could not be loaded.", true);
      }
    };
    $("candidate-previous-page").addEventListener("click", () => changeCandidatePage(-1));
    $("candidate-next-page").addEventListener("click", () => changeCandidatePage(1));
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

  function verifyServerIsolation() {
    if (isolationVerificationPromise) return isolationVerificationPromise;
    const verification = verifyServerIsolationOnce();
    isolationVerificationPromise = verification.finally(() => {
      isolationVerificationPromise = null;
    });
    return isolationVerificationPromise;
  }

  async function verifyServerIsolationOnce() {
    const context = globalContext();
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.verifySyntheticIsolation !== "function") {
      throw new Error("SYNTHETIC_VERIFIER_UNAVAILABLE");
    }
    try {
      const proof = await policy.verifySyntheticIsolation(window.BsoRsCandidateConsoleConfiguration, {
        organizationUrl: context.getClientUrl(),
        organizationId: context.organizationSettings.organizationId,
        actorId: context.userSettings && context.userSettings.userId
      });
      if (Number.isFinite(Date.parse(proof.validUntil))) {
        window.clearTimeout(isolationExpiryTimer);
        isolationExpiryTimer = window.setTimeout(blockSyntheticQuery,
          Math.max(0, Date.parse(proof.validUntil) - Date.now()) + 1);
      }
      return proof;
    } catch (error) {
      blockSyntheticQuery();
      throw error;
    }
  }

  async function initialize() {
    $("create-button").disabled = true;
    bindEvents();
    const selectedMode = $("candidate-data-mode").value;
    referenceMode = ["CONFIGURED", "NORMAL"].includes(selectedMode)
      ? selectedMode : "CONFIGURED";
    environmentPolicy = resolveEnvironmentPolicy(referenceMode);
    await loadWorkspace();
  }

  async function loadWorkspace() {
    referenceGeneration++;
    setBusy(true);
    referencesReady = false;
    workspaceReady = false;
    updateWorkflowPathLabel();
    try {
      if (referenceMode === "NORMAL" && environmentPolicy.allowed === true &&
          environmentPolicy.syntheticDataOnly) {
        await refreshReferenceOptions();
        const row = document.createElement("tr");
        const cell = appendCell(row, "Candidate operations are blocked in NORMAL mode in this synthetic environment.");
        cell.colSpan = 11;
        $("candidate-rows").replaceChildren(row);
        showNotice("NORMAL Active references loaded. Candidate reads and writes remain blocked; use the configured synthetic workflow for DEV testing.");
        return;
      }
      await loadCandidateWorkspace();
    } catch (error) {
      logSafeFailure("NORMAL_REFERENCE_INITIALIZATION_FAILED", error);
      showNotice("NORMAL reference options could not be loaded. Check access and use Refresh reference options to retry.", true);
    } finally {
      setBusy(false);
      updateWorkflowPathLabel();
    }
  }

  async function loadCandidateWorkspace() {
    if (environmentPolicy.allowed === true && environmentPolicy.syntheticDataOnly &&
        referenceMode !== "NORMAL") {
      try {
        await verifyServerIsolation();
      } catch (error) {
        $("create-button").disabled = true;
        $("refresh-button").disabled = true;
        document.querySelectorAll("button[data-action]").forEach((button) => { button.disabled = true; });
        const rejection = error && typeof error.message === "string"
          ? error.message.match(/^SYNTHETIC_VERIFIER_REJECTED:([A-Z][A-Z0-9_]{2,100})$/)
          : null;
        const message = rejection
          ? `Candidate Management is blocked: server-side synthetic isolation rejected this scope (${rejection[1]}). No Candidate data was loaded; contact support to reconcile the scoped DEV records.`
          : "Candidate Management is blocked until server-side synthetic data isolation is established: the verifier is unavailable or rejected this scope.";
        showNotice(message, true);
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
      loadStage = "Position, Candidate Source, TA, and Location options";
      await refreshReferenceOptions();
      loadStage = "the Candidate list";
      const statusFilter = $("candidate-status-filter");
      statusFilter.replaceChildren();
      addOption(statusFilter, "", "All statuses");
      addOption(statusFilter, "active", "Active candidates");
      for (const [value, label] of Object.entries(STATUS_LABELS)) {
        addOption(statusFilter, value, label);
      }
      await refreshCandidates({ resetPage: true });
      workspaceReady = true;
    } catch (error) {
      if (environmentPolicy.syntheticDataOnly) blockSyntheticQuery();
      logSafeFailure("CANDIDATE_MANAGEMENT_INITIALIZATION_FAILED", error);
      const message = loadStage === "Position, Candidate Source, TA, and Location options"
        ? "Reference options could not be loaded. Use Refresh reference options to retry, or reload the Console."
        : `Candidate Management could not load ${loadStage}. Confirm app access and try again.`;
      showNotice(message, true);
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
