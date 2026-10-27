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
  const DEV_FAILURE_PATTERN = /\b(DEV_SLICE_INPUT_REJECTED(?::(?:CONTEXT|ACTION|PARAMETER_SHAPE|SYNTHETIC_PROFILE|CALL_PARAMETERS|REQUIRED_VALUE|OPTIONAL_TEXT|OPTIONAL_LOOKUP|CONTACTED_AT))?|DEV_SLICE_(?:ENVIRONMENT_REJECTED|CANDIDATE_CREATE_FAILED|CANDIDATE_READBACK_FAILED|CALL_CREATE_FAILED|STATUS_UPDATE_FAILED|HISTORY_CREATE_FAILED|RESPONSE_FAILED)|DEV_SLICE_REQUEST_REJECTED_HTTP_[1-5]\d\d)(?::(0x[0-9a-f]{8}))?\b/i;
  const TABLES = {
    candidate: {
      logicalName: "os_sr_cand",
      id: "",
      number: "os_sr_cand_cnum",
      name: "os_sr_cand_nm",
      email: "os_sr_cand_eml",
      phone: "os_sr_cand_phn",
      status: "os_sr_cand_stat",
      correlation: "os_sr_cand_corid",
      position: "_os_sr_cand_pos_value",
      source: "_os_sr_cand_csrc_value"
    },
    call: {
      logicalName: "os_sr_call",
      id: "",
      candidate: "_os_sr_call_cand_value",
      outcome: "os_sr_call_out",
      contactedAt: "os_sr_call_ctat",
      notes: "os_sr_call_nts",
      reference: "os_sr_call_ref"
    },
    history: {
      logicalName: "os_sr_csh",
      id: "",
      candidate: "_os_sr_csh_cand_value",
      previous: "os_sr_csh_prevstat",
      current: "os_sr_csh_newstat",
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

  function safeDevFailure(error, action) {
    const message = error && typeof error.message === "string" ? error.message : "";
    const match = DEV_FAILURE_PATTERN.exec(message);
    if (!match) return `The DEV Candidate Slice could not ${action}.`;
    const code = match[2] ? `, ${match[2].toUpperCase()}` : "";
    return `The DEV Candidate Slice could not ${action} (${match[1].toUpperCase()}${code}).`;
  }

  function hideNotice() {
    $("notice").hidden = true;
    $("notice").textContent = "";
    $("notice").classList.remove("error");
  }

  function setBusy(value) {
    busy = value;
    document.querySelectorAll("button").forEach((button) => {
      button.disabled = value;
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

  const API_PARAMETER_TYPES = {
    ActionType: { typeName: "Edm.String", structuralProperty: 1 },
    CorrelationId: { typeName: "Edm.String", structuralProperty: 1 },
    CandidateId: { typeName: "Edm.String", structuralProperty: 1 },
    ExpectedStatus: { typeName: "Edm.Int32", structuralProperty: 1 },
    CandidateName: { typeName: "Edm.String", structuralProperty: 1 },
    CandidateEmail: { typeName: "Edm.String", structuralProperty: 1 },
    CandidatePhone: { typeName: "Edm.String", structuralProperty: 1 },
    PositionId: { typeName: "Edm.String", structuralProperty: 1 },
    CandidateSourceId: { typeName: "Edm.String", structuralProperty: 1 },
    CallOutcome: { typeName: "Edm.Int32", structuralProperty: 1 },
    ContactedAt: { typeName: "Edm.String", structuralProperty: 1 },
    Notes: { typeName: "Edm.String", structuralProperty: 1 }
  };

  function CandidateActionRequest(parameters) {
    Object.assign(this, parameters);
  }

  CandidateActionRequest.prototype.getMetadata = function () {
    return {
      boundParameter: null,
      parameterTypes: API_PARAMETER_TYPES,
      operationType: 0,
      operationName: "os_sr_devcs"
    };
  };

  async function executeCandidateAction(parameters) {
    const request = new CandidateActionRequest(parameters);
    const response = await xrm().WebApi.online.execute(request);
    if (!response.ok) {
      let safeCategory = "";
      try {
        const body = await response.text();
        const match = DEV_FAILURE_PATTERN.exec(body);
        if (match) {
          safeCategory = `${match[1].toUpperCase()}${match[2] ? `:${match[2].toUpperCase()}` : ""}`;
        }
      } catch {
        safeCategory = "";
      }
      throw new Error(safeCategory || `DEV_SLICE_REQUEST_REJECTED_HTTP_${response.status}`);
    }
    return response.json();
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
    const body = $("candidate-rows");
    body.replaceChildren();
    if (!rows.length) {
      const row = document.createElement("tr");
      const cell = appendCell(row, "No candidates found.");
      cell.colSpan = 8;
      cell.className = "empty";
      body.appendChild(row);
      return;
    }
    for (const candidate of rows) {
      const row = document.createElement("tr");
      appendCell(row, candidate[TABLES.candidate.number]);
      appendCell(row, candidate[TABLES.candidate.name]);
      appendCell(row, candidate[TABLES.candidate.email]);
      appendCell(row, candidate[TABLES.candidate.phone]);
      appendCell(row, choiceLabel(candidate, TABLES.candidate.status, STATUS_LABELS));
      appendCell(row, formatted(candidate, "_ownerid_value"));
      appendCell(row, formatDate(candidate.createdon));
      const actions = document.createElement("td");
      actions.className = "actions";
      const open = document.createElement("button");
      open.type = "button";
      open.className = "button button-secondary button-small";
      open.textContent = "Open";
      open.addEventListener("click", () => openCandidate(candidate[TABLES.candidate.id]));
      const call = document.createElement("button");
      call.type = "button";
      call.className = "button button-primary button-small";
      call.textContent = "Record Call";
      call.addEventListener("click", () => showCallDialog(candidate));
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
      `startswith(${c.name},'[SYNTHETIC-E2E]') and endswith(${c.email},'.invalid')`
    )}&$orderby=createdon desc&$top=100`;
    const rows = await retrieveAll(c.logicalName, query);
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
  }

  async function renderCallHistory(candidateId) {
    const c = TABLES.call;
    const rows = await retrieveAll(c.logicalName,
      `?$select=${[c.id, c.outcome, c.contactedAt, c.notes, c.reference].join(",")}` +
      `&$filter=${c.candidate} eq ${candidateId}&$orderby=${c.contactedAt} desc&$top=100`);
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
      `?$select=${[h.id, h.previous, h.current, h.changedAt, h.reason].join(",")}` +
      `&$filter=${h.candidate} eq ${candidateId}&$orderby=${h.changedAt} desc&$top=100`);
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
      $("detail-heading").textContent = candidate[TABLES.candidate.name] || "Candidate";
      $("detail-panel").hidden = false;
      await Promise.all([
        renderCandidateDetails(candidate),
        renderCallHistory(candidateId),
        renderStatusHistory(candidateId)
      ]);
      $("detail-panel").scrollIntoView({ behavior: "smooth", block: "start" });
    } catch {
      showNotice("Candidate details could not be loaded. Refresh and try again.", true);
    }
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
      `?$select=${metadata.PrimaryIdAttribute},${primaryName}&$orderby=${primaryName} asc&$top=250`);
    select.replaceChildren();
    addOption(select, "", emptyLabel);
    for (const row of rows) {
      const id = row[metadata.PrimaryIdAttribute];
      const label = row[primaryName];
      if (!id || !label) continue;
      addOption(select, id, label);
    }
  }

  async function loadTableMetadata(table) {
    const metadata = await xrm().Utility.getEntityMetadata(table.logicalName);
    table.id = metadata.PrimaryIdAttribute;
    if (!table.id) throw new Error("Table metadata is incomplete.");
  }

  function showCallDialog(candidate) {
    selectedCandidate = candidate;
    $("call-candidate-label").textContent =
      `${candidate[TABLES.candidate.number] || ""} ${candidate[TABLES.candidate.name] || ""}`.trim();
    $("call-notes").value = "";
    $("call-outcome").value = "100010001";
    $("call-dialog").showModal();
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
    setBusy(true);
    try {
      const correlationId = newCorrelationId();
      const parameters = {
        ActionType: "CreateCandidate",
        CorrelationId: correlationId,
        CandidateName: candidateName,
        CandidateEmail: candidateEmail
      };
      if (candidatePhone) parameters.CandidatePhone = candidatePhone;
      if ($("candidate-position").value) parameters.PositionId = $("candidate-position").value;
      if ($("candidate-source").value) parameters.CandidateSourceId = $("candidate-source").value;
      const result = await executeCandidateAction(parameters);
      if (result.ResultCode !== "Applied" && result.ResultCode !== "DuplicateReplay") {
        throw new Error("The DEV Candidate Slice did not confirm candidate creation.");
      }
      const c = TABLES.candidate;
      if (typeof result.CandidateId !== "string" ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(result.CandidateId)) {
        throw new Error("The DEV Candidate Slice returned no valid candidate reference.");
      }
      const candidate = await xrm().WebApi.retrieveRecord(c.logicalName, result.CandidateId);
      $("candidate-form").reset();
      await refreshCandidates();
      await openCandidate(candidate[c.id]);
      showNotice("Candidate created successfully.");
    } catch (error) {
      showNotice(safeDevFailure(error, "create the candidate"), true);
    } finally {
      setBusy(false);
    }
  }

  async function recordCall(event) {
    event.preventDefault();
    if (busy || !selectedCandidate) return;
    hideNotice();
    const candidateId = selectedCandidate[TABLES.candidate.id];
    const expectedStatus = selectedCandidate[TABLES.candidate.status];
    if (expectedStatus == null) {
      showNotice("The current Candidate status is unavailable; refresh before recording a call.", true);
      return;
    }
    setBusy(true);
    try {
      const result = await executeCandidateAction({
        ActionType: "RecordCall",
        CorrelationId: newCorrelationId(),
        CandidateId: candidateId,
        ExpectedStatus: expectedStatus,
        CallOutcome: Number($("call-outcome").value),
        ContactedAt: new Date().toISOString(),
        ...( $("call-notes").value.trim() ? { Notes: $("call-notes").value.trim() } : {})
      });
      if (result.ResultCode !== "Applied" && result.ResultCode !== "DuplicateReplay") {
        throw new Error("The DEV Candidate Slice did not confirm the call.");
      }
      $("call-dialog").close();
      await refreshCandidates();
      await openCandidate(candidateId);
      showNotice("Call recorded successfully.");
    } catch (error) {
      showNotice(safeDevFailure(error, "record the call"), true);
    } finally {
      setBusy(false);
    }
  }

  function bindEvents() {
    $("candidate-form").addEventListener("submit", createCandidate);
    $("call-form").addEventListener("submit", recordCall);
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
      selectedCandidate = null;
    });
    $("cancel-call").addEventListener("click", () => $("call-dialog").close());
  }

  async function initialize() {
    bindEvents();
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
        loadLookupOptions("os_sr_csrc", "candidate-source", "No source selected")
      ]);
      loadStage = "the Candidate list";
      await refreshCandidates();
    } catch {
      showNotice(`Candidate Management could not load ${loadStage}. Confirm app access and try again.`, true);
      const row = document.createElement("tr");
      const cell = appendCell(row, "Candidate data is unavailable.");
      cell.colSpan = 8;
      cell.className = "empty";
      $("candidate-rows").replaceChildren(row);
    }
  }

  document.addEventListener("DOMContentLoaded", initialize);
})();
