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
    waitingManualScheduling: 100010002
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
    }
  };

  let selectedCandidate = null;
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
        button.id === "save-schedule" ||
        (button.id === "submit-call" && !selectedCandidate) ||
        (button.id === "waiting-status-button" && button.hidden) ||
        (button.id === "schedule-round1-button" &&
          (button.hidden || !selectedCandidate ||
            selectedCandidate[TABLES.candidate.status] !== STATUS.waitingManualScheduling));
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

  async function openCandidate(candidateId) {
    hideNotice();
    try {
      const candidate = currentRows.find((row) => row[TABLES.candidate.id] === candidateId) ||
        await xrm().WebApi.retrieveRecord(TABLES.candidate.logicalName, candidateId);
      selectedCandidate = candidate;
      $("scheduling-panel").hidden = true;
      $("detail-heading").textContent = candidate[TABLES.candidate.name] || "Candidate";
      $("detail-panel").hidden = false;
      $("call-entry-panel").hidden = false;
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
      renderCandidateRows(currentRows);
      await Promise.all([
        renderCandidateDetails(candidate),
        renderCallHistory(candidateId),
        renderStatusHistory(candidateId)
      ]);
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
    $("scheduling-form").reset();
    $("scheduling-candidate").value =
      `${selectedCandidate[TABLES.candidate.number] || ""} ${selectedCandidate[TABLES.candidate.name] || ""}`.trim();
    $("scheduling-panel").hidden = false;
    $("scheduling-panel").scrollIntoView({ behavior: "smooth", block: "center" });
    $("scheduling-ta").focus();
  }

  function rejectScheduleWithoutStorage(event) {
    event.preventDefault();
    showNotice(
      "SCHEDULING_STORAGE_NOT_PROVISIONED. No schedule was saved and Candidate status remains Waiting Manual Scheduling.",
      true
    );
  }

  async function loadTableMetadata(table) {
    const metadata = await xrm().Utility.getEntityMetadata(table.logicalName);
    table.id = metadata.PrimaryIdAttribute;
    if (!table.id) throw new Error("Table metadata is incomplete.");
  }

  async function showCallPanel(candidate) {
    if (!isSyntheticCandidate(candidate)) {
      showNotice("DEV direct write is limited to [SYNTHETIC-E2E] candidates with .invalid email addresses.", true);
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
    $("scheduling-form").addEventListener("submit", rejectScheduleWithoutStorage);
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
      $("scheduling-panel").hidden = true;
      selectedCandidate = null;
      renderCandidateRows(currentRows);
    });
    $("waiting-status-button").addEventListener("click", moveToWaitingManualScheduling);
    $("schedule-round1-button").addEventListener("click", showSchedulingPanel);
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
        loadTableMetadata(TABLES.history)
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
