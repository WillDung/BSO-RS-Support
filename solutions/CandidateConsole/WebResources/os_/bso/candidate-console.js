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
  const DEV_ORIGIN = "https://org14938ec2.crm4.dynamics.com";
  const STATUS = {
    needCall: 100010000,
    answered: 100010001,
    waitingManualScheduling: 100010002,
    round1Scheduled: 100010003,
    offerExtended: 100010004,
    candidateFailed: 100010005
  };
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
      number: "os_sr_cand_cnum",
      name: "os_sr_cand_nm",
      email: "os_sr_cand_eml",
      phone: "os_sr_cand_phn",
      status: "os_sr_cand_stat",
      position: "_os_sr_cand_pos_value",
      positionNavigation: "os_sr_cand_pos",
      positionEntitySet: "os_sr_poses",
      source: "_os_sr_cand_csrc_value",
      sourceNavigation: "os_sr_cand_csrc",
      sourceEntitySet: "os_sr_csrcs"
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
      resultNotes: "os_sr_intv_rnts"
    }
  };

  let selectedCandidate = null;
  let selectedSchedule = null;
  let scheduleRetryBlockedCandidateId = null;
  let resultRetryBlockedCandidateId = null;
  let currentRows = [];
  let busy = false;

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

  function isTargetDevEnvironment() {
    try {
      return new URL(globalContext().getClientUrl()).origin.toLowerCase() === DEV_ORIGIN;
    } catch {
      return false;
    }
  }

  function currentUserId() {
    const userId = globalContext().userSettings.userId;
    if (typeof userId !== "string" ||
        !/^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$/i.test(userId)) {
      throw new Error("DEV_DIRECT_WRITE_USER_CONTEXT_INVALID");
    }
    return userId.replace(/[{}]/g, "");
  }

  function isSyntheticCandidate(candidate) {
    return Boolean(candidate &&
      typeof candidate[TABLES.candidate.name] === "string" &&
      candidate[TABLES.candidate.name].startsWith("[SYNTHETIC-E2E]") &&
      typeof candidate[TABLES.candidate.email] === "string" &&
      /^[^@\s]+@[^@\s]+\.invalid$/i.test(candidate[TABLES.candidate.email]));
  }

  function logSafeFailure(category, error) {
    const numericCode = Number(error && error.errorCode);
    const code = Number.isFinite(numericCode) && numericCode !== 0
      ? `:0x${(numericCode >>> 0).toString(16).padStart(8, "0").toUpperCase()}`
      : "";
    console.error(`${category}${code}`);
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
    document.querySelectorAll("button[data-action]").forEach((button) => {
      button.disabled = value ||
        (button.id === "submit-call" && !selectedCandidate) ||
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
            selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
            Boolean(selectedSchedule) ||
            scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id])) ||
        (button.id === "save-interview-result" &&
          (!selectedCandidate || !canRecordInterviewResult()));
    });
  }

  function formatDate(value) {
    if (!value) return "";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "" : date.toLocaleString();
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

  function normalizeGuid(value) {
    if (typeof value !== "string" ||
        !/^\{?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}?$/i.test(value)) {
      throw new Error("DEV_DIRECT_WRITE_INVALID_RECORD_REFERENCE");
    }
    return value.replace(/[{}]/g, "");
  }

  async function retrieveAll(tableLogicalName, query) {
    const api = xrm().WebApi;
    let response = await api.retrieveMultipleRecords(tableLogicalName, query);
    const results = [...response.entities];
    while (response.nextLink) {
      response = await api.retrieveMultipleRecords(tableLogicalName, response.nextLink);
      results.push(...response.entities);
    }
    return results;
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
      cell.colSpan = 10;
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
      call.hidden = [STATUS.offerExtended, STATUS.candidateFailed].includes(candidate[TABLES.candidate.status]);
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
    const query = `?$select=${[
      c.id, c.number, c.name, c.email, c.phone, c.status, c.position, c.source,
      "createdon", "_ownerid_value"
    ].join(",")}&$filter=${encodeURIComponent(
      `endswith(${c.email},'.invalid')`
    )}&$orderby=createdon desc`;
    const rows = (await retrieveAll(c.logicalName, query)).filter(isSyntheticCandidate);
    renderCandidateRows(rows);
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

  async function getLookupName(tableLogicalName, id) {
    if (!id) return "";
    const entityMetadata = await xrm().Utility.getEntityMetadata(tableLogicalName);
    const primaryName = entityMetadata.PrimaryNameAttribute;
    const record = await xrm().WebApi.retrieveRecord(
      tableLogicalName,
      id.replace(/[{}]/g, ""),
      `?$select=${primaryName}`
    );
    return record[primaryName] || "";
  }

  async function renderCandidateDetails(candidate) {
    const details = $("candidate-details");
    details.replaceChildren();
    const lookups = await Promise.all([
      getLookupName("os_sr_pos", candidate[TABLES.candidate.position]),
      getLookupName("os_sr_csrc", candidate[TABLES.candidate.source])
    ]);
    addDetailItem(details, "Candidate Number", candidate[TABLES.candidate.number]);
    addDetailItem(details, "Candidate Name", candidate[TABLES.candidate.name]);
    addDetailItem(details, "Email", candidate[TABLES.candidate.email]);
    addDetailItem(details, "Phone", candidate[TABLES.candidate.phone]);
    addDetailItem(details, "Status", choiceLabel(candidate, TABLES.candidate.status, STATUS_LABELS));
    addDetailItem(details, "Position", lookups[0]);
    addDetailItem(details, "Candidate Source", lookups[1]);
    addDetailItem(details, "Owner", formatted(candidate, "_ownerid_value"));
    addDetailItem(details, "Created On", formatDate(candidate.createdon));
  }

  async function renderCallHistory(candidateId) {
    const c = TABLES.call;
    const rows = await retrieveAll(c.logicalName,
      `?$select=${[c.id, c.outcome, c.contactedAt, c.notes, c.reference].join(",")}` +
      `&$filter=${c.candidate} eq ${candidateId}&$orderby=${c.contactedAt} desc`);
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
      `&$filter=${h.candidate} eq ${candidateId}&$orderby=${h.changedAt} desc`);
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
      `?$select=${[interview.id, interview.round, interview.start, interview.end, interview.notes, interview.ta, interview.location, interview.result, interview.resultRecordedAt, interview.resultNotes].join(",")}` +
      `&$filter=${interview.candidate} eq ${candidateId} and ${interview.round} eq ${interview.round1}` +
      `&$orderby=${interview.start} desc&$top=2`);
    const body = $("schedule-history-rows");
    body.replaceChildren();
    selectedSchedule = rows[0] || null;
    if (!selectedSchedule) {
      const row = document.createElement("tr");
      const cell = appendCell(row, "No Round 1 schedule.");
      cell.colSpan = 8;
      cell.className = "empty";
      body.appendChild(row);
    } else {
      const names = await Promise.all([
        getLookupName("os_sr_ta", selectedSchedule[interview.ta]),
        getLookupName("os_sr_loc", selectedSchedule[interview.location])
      ]);
      const row = document.createElement("tr");
      appendCell(row, choiceLabel(selectedSchedule, interview.round, { [interview.round1]: "Round 1" }));
      appendCell(row, names[0]);
      appendCell(row, `${formatDate(selectedSchedule[interview.start])} – ${formatDate(selectedSchedule[interview.end])}`);
      appendCell(row, names[1]);
      appendCell(row, selectedSchedule[interview.notes]);
      appendCell(row, choiceLabel(selectedSchedule, interview.result, INTERVIEW_RESULT_LABELS) || "Pending");
      appendCell(row, formatDate(selectedSchedule[interview.resultRecordedAt]));
      appendCell(row, selectedSchedule[interview.resultNotes]);
      body.appendChild(row);
      if (rows.length > 1) {
        const warning = document.createElement("tr");
        const cell = appendCell(warning, "Multiple Round 1 schedule rows exist; showing the newest. Reconcile before creating another.");
        cell.colSpan = 8;
        cell.className = "empty";
        body.appendChild(warning);
      }
    }
    const canSchedule = selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.waitingManualScheduling &&
      isSyntheticCandidate(selectedCandidate);
    $("schedule-round1-button").disabled = busy || !canSchedule || Boolean(selectedSchedule) ||
      scheduleRetryBlockedCandidateId === candidateId;
    const canRecord = selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled &&
      isSyntheticCandidate(selectedCandidate) &&
      rows.length === 1 &&
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
      $("schedule-round1-button").title = "A Round 1 schedule already exists. Reconcile the Candidate state before scheduling again.";
    } else if (scheduleRetryBlockedCandidateId === candidateId) {
      $("schedule-round1-button").title = "A previous submission needs reconciliation. Reload before trying again.";
    } else {
      $("schedule-round1-button").removeAttribute("title");
    }
  }

  async function openCandidate(candidateId) {
    hideNotice();
    try {
      const candidate = currentRows.find((row) => row[TABLES.candidate.id] === candidateId) ||
        await xrm().WebApi.retrieveRecord(TABLES.candidate.logicalName, candidateId);
      selectedCandidate = candidate;
      selectedSchedule = null;
      $("scheduling-panel").hidden = true;
      $("interview-result-panel").hidden = true;
      $("schedule-round1-button").hidden = true;
      $("record-interview-result-button").hidden = true;
      $("detail-heading").textContent = candidate[TABLES.candidate.name] || "Candidate";
      $("detail-panel").hidden = false;
      const terminal = [STATUS.offerExtended, STATUS.candidateFailed].includes(candidate[TABLES.candidate.status]);
      $("call-entry-panel").hidden = terminal;
      $("call-candidate-label").textContent =
        `${candidate[TABLES.candidate.number] || ""} ${candidate[TABLES.candidate.name] || ""}`.trim();
      $("submit-call").disabled = busy;
      const canMoveToWaiting = candidate[TABLES.candidate.status] === STATUS.answered;
      const canSchedule = candidate[TABLES.candidate.status] === STATUS.waitingManualScheduling &&
        isSyntheticCandidate(candidate);
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
      $("schedule-round1-button").hidden = !canSchedule;
      $("schedule-round1-button").disabled = busy || !canSchedule || Boolean(selectedSchedule) ||
        scheduleRetryBlockedCandidateId === candidateId;
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

  async function loadLookupOptions(tableName, selectId, emptyLabel) {
    const select = $(selectId);
    const metadata = await xrm().Utility.getEntityMetadata(tableName);
    const primaryName = metadata.PrimaryNameAttribute;
    const rows = await retrieveAll(tableName,
      `?$select=${metadata.PrimaryIdAttribute},${primaryName},statecode&$filter=statecode eq 0&$orderby=${primaryName} asc`);
    select.replaceChildren();
    addOption(select, "", emptyLabel);
    for (const row of rows) {
      const id = row[metadata.PrimaryIdAttribute];
      const label = row[primaryName];
      if (!id || typeof label !== "string" || !label.startsWith("[DEV]")) continue;
      addOption(select, id, label);
    }
  }

  function showSchedulingPanel() {
    if (busy || !selectedCandidate) return;
    if (selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling ||
        !isSyntheticCandidate(selectedCandidate)) {
      showNotice("Schedule Round 1 is available only for synthetic candidates in Waiting Manual Scheduling.", true);
      return;
    }
    if (selectedSchedule || scheduleRetryBlockedCandidateId === selectedCandidate[TABLES.candidate.id]) {
      showNotice("A previous Round 1 schedule submission needs reconciliation. Refresh or reload before trying again.", true);
      return;
    }
    $("scheduling-form").reset();
    $("scheduling-candidate").value =
      `${selectedCandidate[TABLES.candidate.number] || ""} ${selectedCandidate[TABLES.candidate.name] || ""}`.trim();
    $("scheduling-panel").hidden = false;
    $("scheduling-panel").scrollIntoView({ behavior: "smooth", block: "center" });
    $("scheduling-ta").focus();
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

  async function getActiveSyntheticReference(tableName, value) {
    const id = normalizeGuid(value);
    const metadata = await xrm().Utility.getEntityMetadata(tableName);
    if (!metadata.PrimaryIdAttribute || !metadata.PrimaryNameAttribute || !metadata.EntitySetName) {
      throw new Error("DEV_DIRECT_WRITE_REFERENCE_METADATA_INVALID");
    }
    const reference = await xrm().WebApi.retrieveRecord(
      tableName,
      id,
      `?$select=${[metadata.PrimaryIdAttribute, metadata.PrimaryNameAttribute, "statecode"].join(",")}`
    );
    if (reference.statecode !== 0 ||
        typeof reference[metadata.PrimaryNameAttribute] !== "string" ||
        !reference[metadata.PrimaryNameAttribute].startsWith("[DEV]")) {
      throw new Error("DEV_DIRECT_WRITE_REFERENCE_NOT_SYNTHETIC_ACTIVE");
    }
    return { id, entitySetName: metadata.EntitySetName };
  }

  async function findRound1Schedules(candidateId) {
    const interview = TABLES.interview;
    return retrieveAll(interview.logicalName,
      `?$select=${[interview.id, interview.round, interview.start, interview.result].join(",")}` +
      `&$filter=${interview.candidate} eq ${candidateId} and ${interview.round} eq ${interview.round1}` +
      `&$orderby=${interview.start} desc&$top=2`);
  }

  function isPendingInterviewResult(schedule) {
    return Boolean(schedule &&
      (schedule[TABLES.interview.result] == null ||
        schedule[TABLES.interview.result] === INTERVIEW_RESULT.pending));
  }

  function canRecordInterviewResult() {
    return Boolean(selectedCandidate &&
      selectedCandidate[TABLES.candidate.status] === STATUS.round1Scheduled &&
      isSyntheticCandidate(selectedCandidate) &&
      selectedSchedule &&
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

  async function recordInterviewResult(event) {
    event.preventDefault();
    if (busy || !selectedCandidate || !canRecordInterviewResult()) return;
    hideNotice();
    const c = TABLES.candidate;
    const interview = TABLES.interview;
    const history = TABLES.history;
    const candidateId = normalizeGuid(selectedCandidate[c.id]);
    const scheduleId = normalizeGuid(selectedSchedule[interview.id]);
    if (!isTargetDevEnvironment() || !isSyntheticCandidate(selectedCandidate)) {
      showNotice("Interview results are limited to synthetic candidates in VN LMV IT.", true);
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
      const current = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isSyntheticCandidate(current) || current[c.status] !== STATUS.round1Scheduled) {
        await reconcileAfterFailure(candidateId);
        showNotice("Candidate is no longer Round 1 Scheduled. No interview result was written.", true);
        return;
      }

      category = "INTERVIEW_RESULT_SCHEDULE_READ_FAILED";
      const schedules = await findRound1Schedules(candidateId);
      if (schedules.length !== 1 || normalizeGuid(schedules[0][interview.id]) !== scheduleId ||
          !isPendingInterviewResult(schedules[0])) {
        await reconcileAfterFailure(candidateId);
        showNotice("Exactly one pending Round 1 schedule could not be verified. No interview result was written.", true);
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
      const saved = await xrm().WebApi.retrieveRecord(
        interview.logicalName,
        scheduleId,
        `?$select=${[interview.id, interview.candidate, interview.round, interview.result, interview.resultRecordedAt, interview.resultNotes].join(",")}`
      );
      if (normalizeGuid(saved[interview.candidate]) !== candidateId ||
          saved[interview.round] !== interview.round1 ||
          saved[interview.result] !== result ||
          Date.parse(saved[interview.resultRecordedAt]) !== Date.parse(recordedAt) ||
          (notes && saved[interview.resultNotes] !== notes)) {
        throw new Error("DEV_DIRECT_WRITE_INTERVIEW_RESULT_READBACK_MISMATCH");
      }
      resultReadbackConfirmed = true;

      category = "INTERVIEW_RESULT_CANDIDATE_STATUS_READ_FAILED";
      const beforeStatusUpdate = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isSyntheticCandidate(beforeStatusUpdate) ||
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

  async function createSchedule(event) {
    event.preventDefault();
    if (busy || !selectedCandidate) return;
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
    if (!isTargetDevEnvironment() || !isSyntheticCandidate(selectedCandidate)) {
      showNotice("Scheduling is limited to synthetic candidates in VN LMV IT.", true);
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
      const current = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isSyntheticCandidate(current)) {
        showNotice("Scheduling is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
        return;
      }
      if (current[c.status] !== STATUS.waitingManualScheduling) {
        await reconcileAfterFailure(candidateId);
        showNotice("Candidate status changed. No schedule was created; refresh and verify the current state.", true);
        return;
      }
      const existingSchedules = await findRound1Schedules(candidateId);
      if (existingSchedules.length) {
        await reconcileAfterFailure(candidateId);
        showNotice("A Round 1 schedule already exists. No duplicate was created; reconcile the Candidate state.", true);
        return;
      }
      const ta = await getActiveSyntheticReference("os_sr_ta", $("scheduling-ta").value);
      const location = await getActiveSyntheticReference("os_sr_loc", $("scheduling-location").value);
      const userId = currentUserId();
      const payload = {
        [`${interview.candidateNavigation}@odata.bind`]: `/${c.entitySetName}(${candidateId})`,
        [`${interview.taNavigation}@odata.bind`]: `/${ta.entitySetName}(${ta.id})`,
        [`${interview.locationNavigation}@odata.bind`]: `/${location.entitySetName}(${location.id})`,
        [interview.round]: interview.round1,
        [interview.result]: INTERVIEW_RESULT.pending,
        [interview.start]: start.toISOString(),
        [interview.end]: end.toISOString()
      };
      const notes = $("scheduling-notes").value.trim();
      if (notes) payload[interview.notes] = notes;

      category = "SCHEDULE_CREATE_FAILED";
      scheduleCreateAttempted = true;
      const result = await xrm().WebApi.createRecord(interview.logicalName, payload);
      const scheduleId = result && typeof result.id === "string" ? normalizeGuid(result.id) : null;
      if (!scheduleId) throw new Error("DEV_DIRECT_WRITE_SCHEDULE_ID_MISSING");

      category = "SCHEDULE_READBACK_FAILED";
      const saved = await xrm().WebApi.retrieveRecord(
        interview.logicalName,
        scheduleId,
        `?$select=${[interview.id, interview.round, interview.result, interview.candidate, interview.ta, interview.location, interview.start, interview.end, interview.notes].join(",")}`
      );
      if (normalizeGuid(saved[interview.candidate]) !== candidateId ||
          normalizeGuid(saved[interview.ta]) !== ta.id ||
          normalizeGuid(saved[interview.location]) !== location.id ||
          saved[interview.round] !== interview.round1 ||
          saved[interview.result] !== INTERVIEW_RESULT.pending ||
          Date.parse(saved[interview.start]) !== start.getTime() ||
          Date.parse(saved[interview.end]) !== end.getTime()) {
        throw new Error("DEV_DIRECT_WRITE_SCHEDULE_READBACK_MISMATCH");
      }
      scheduleReadbackConfirmed = true;

      category = "SCHEDULE_CANDIDATE_STATUS_UPDATE_FAILED";
      const beforeStatusUpdate = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isSyntheticCandidate(beforeStatusUpdate) ||
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
      showNotice("Round 1 schedule saved and Candidate moved to Round 1 Scheduled.");
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

  async function loadTableMetadata(table) {
    const metadata = await xrm().Utility.getEntityMetadata(table.logicalName);
    table.id = metadata.PrimaryIdAttribute;
    if (!table.id || !metadata.EntitySetName) throw new Error("Table metadata is incomplete.");
    table.entitySetName = metadata.EntitySetName;
  }

  async function showCallPanel(candidate) {
    if (!isSyntheticCandidate(candidate)) {
      showNotice("DEV direct write is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
      return;
    }
    if ([STATUS.offerExtended, STATUS.candidateFailed].includes(candidate[TABLES.candidate.status])) {
      showNotice("No further workflow actions are available for this Candidate in the current DEV scope.", true);
      return;
    }
    if (await openCandidate(candidate[TABLES.candidate.id])) {
      $("call-entry-panel").scrollIntoView({ behavior: "smooth", block: "center" });
      $("call-outcome").focus();
    }
  }

  async function createCandidate(event) {
    event.preventDefault();
    if (busy) return;
    hideNotice();
    const candidateName = $("candidate-name").value.trim();
    const candidateEmail = $("candidate-email").value.trim();
    const candidatePhone = $("candidate-phone").value.trim();
    if (!candidateName || !candidateEmail) {
      showNotice("Candidate Name and Email are required.", true);
      return;
    }
    if (!candidateName.startsWith("[SYNTHETIC-E2E]") ||
        !/^[^@\s]+@[^@\s]+\.invalid$/i.test(candidateEmail)) {
      showNotice("This DEV console accepts only [SYNTHETIC-E2E] names and reserved .invalid email addresses.", true);
      return;
    }
    if (!isTargetDevEnvironment()) {
      showNotice("DEV direct writes are available only in VN LMV IT.", true);
      return;
    }
    setBusy(true);
    const c = TABLES.candidate;
    let category = "CANDIDATE_CREATE_FAILED";
    let candidateId = null;
    let candidateCreated = false;
    try {
      const payload = {
        [c.name]: candidateName,
        [c.email]: candidateEmail,
        [c.status]: STATUS.needCall
      };
      if (candidatePhone) payload[c.phone] = candidatePhone;
      const positionId = $("candidate-position").value;
      if (positionId) {
        payload[`${c.positionNavigation}@odata.bind`] =
          `/${c.positionEntitySet}(${normalizeGuid(positionId)})`;
      }
      const sourceId = $("candidate-source").value;
      if (sourceId) {
        payload[`${c.sourceNavigation}@odata.bind`] =
          `/${c.sourceEntitySet}(${normalizeGuid(sourceId)})`;
      }
      const result = await xrm().WebApi.createRecord(c.logicalName, payload);
      candidateId = result && typeof result.id === "string" ? normalizeGuid(result.id) : null;
      candidateCreated = Boolean(candidateId);
      if (!candidateId) {
        category = "CANDIDATE_READBACK_FAILED";
        throw new Error("DEV_DIRECT_WRITE_CANDIDATE_ID_MISSING");
      }

      category = "CANDIDATE_READBACK_FAILED";
      const candidate = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.number, c.name, c.email, c.phone, c.status, c.position, c.source, "createdon", "_ownerid_value"].join(",")}`
      );
      if (!isSyntheticCandidate(candidate) || candidate[c.status] !== STATUS.needCall ||
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

  async function recordCall(event) {
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
    if (!isTargetDevEnvironment()) {
      showNotice("DEV direct writes are available only in VN LMV IT.", true);
      return;
    }
    if (!isSyntheticCandidate(selectedCandidate)) {
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
      const current = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isSyntheticCandidate(current)) {
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

  async function moveToWaitingManualScheduling() {
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
    if (!isTargetDevEnvironment() || !isSyntheticCandidate(selectedCandidate)) {
      showNotice("This transition is available only for synthetic candidates in VN LMV IT.", true);
      return;
    }

    setBusy(true);
    let category = "CANDIDATE_READ_FAILED";
    let statusUpdated = false;
    try {
      const current = await xrm().WebApi.retrieveRecord(
        c.logicalName,
        candidateId,
        `?$select=${[c.id, c.name, c.email, c.status].join(",")}`
      );
      if (!isSyntheticCandidate(current)) {
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
    $("candidate-form").addEventListener("submit", createCandidate);
    $("call-form").addEventListener("submit", recordCall);
    $("scheduling-form").addEventListener("submit", createSchedule);
    $("interview-result-form").addEventListener("submit", recordInterviewResult);
    $("candidate-search").addEventListener("input", () => renderCandidateRows(currentRows));
    $("candidate-status-filter").addEventListener("change", () => renderCandidateRows(currentRows));
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
      $("waiting-status-button").hidden = true;
      $("schedule-round1-button").hidden = true;
      $("record-interview-result-button").hidden = true;
      $("scheduling-panel").hidden = true;
      $("interview-result-panel").hidden = true;
      selectedCandidate = null;
      selectedSchedule = null;
      renderCandidateRows(currentRows);
    });
    $("waiting-status-button").addEventListener("click", moveToWaitingManualScheduling);
    $("schedule-round1-button").addEventListener("click", showSchedulingPanel);
    $("record-interview-result-button").addEventListener("click", showInterviewResultPanel);
  }

  async function initialize() {
    bindEvents();
    if (!isTargetDevEnvironment()) {
      $("create-button").disabled = true;
      $("refresh-button").disabled = true;
      showNotice("This DEV direct-write console is available only in VN LMV IT.", true);
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
        loadLookupOptions("os_sr_pos", "candidate-position", "No position selected"),
        loadLookupOptions("os_sr_csrc", "candidate-source", "No source selected"),
        loadLookupOptions("os_sr_ta", "scheduling-ta", "Select interviewer"),
        loadLookupOptions("os_sr_loc", "scheduling-location", "Select location")
      ]);
      loadStage = "the Candidate list";
      const statusFilter = $("candidate-status-filter");
      for (const [value, label] of Object.entries(STATUS_LABELS)) {
        addOption(statusFilter, value, label);
      }
      await refreshCandidates();
    } catch {
      showNotice(`Candidate Management could not load ${loadStage}. Confirm app access and try again.`, true);
      document.querySelectorAll("button[data-action]").forEach((button) => {
        button.disabled = true;
      });
      const row = document.createElement("tr");
      const cell = appendCell(row, "Candidate data is unavailable.");
      cell.colSpan = 10;
      cell.className = "empty";
      $("candidate-rows").replaceChildren(row);
    }
  }

  document.addEventListener("DOMContentLoaded", initialize);
})();
