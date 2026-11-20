(() => {
  "use strict";

  const TIME_ZONE = "Asia/Ho_Chi_Minh";
  const VIETNAM_OFFSET_MS = 7 * 60 * 60 * 1000;
  const QUEUE_PAGE_SIZE = 50;
  const MAX_RESULT_ROWS = 50000;
  const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const STATUS = Object.freeze({
    100010000: "Need Call Candidate",
    100010001: "Candidate Answered",
    100010002: "Waiting Manual Scheduling",
    100010003: "Round 1 Scheduled",
    100010004: "Offer Extended",
    100010005: "Candidate Failed"
  });
  const STATUS_ORDER = Object.freeze(Object.keys(STATUS).map(Number));
  const PENDING_STATUSES = new Set([100010000, 100010001, 100010002]);
  const TABLE = Object.freeze({
    candidate: {
      logicalName: "os_sr_cand",
      id: "os_sr_candid",
      number: "os_sr_cand_cnum",
      name: "os_sr_cand_nm",
      status: "os_sr_cand_stat",
      position: "_os_sr_cand_pos_value",
      source: "_os_sr_cand_csrc_value",
      ta: "_os_sr_cand_ta_value"
    },
    interview: {
      logicalName: "os_sr_intv",
      id: "os_sr_intvid",
      candidate: "_os_sr_intv_cand_value",
      candidateNavigation: "os_sr_intv_cand",
      ta: "_os_sr_intv_ta_value",
      round: "os_sr_intv_rnd",
      start: "os_sr_intv_strt",
      status: "os_sr_intv_stat"
    },
    position: { logicalName: "os_sr_pos", id: "os_sr_posid", name: "os_sr_pos_ttl" },
    source: { logicalName: "os_sr_csrc", id: "os_sr_csrcid", name: "os_sr_csrc_nm" },
    ta: { logicalName: "os_sr_ta", id: "os_sr_taid", name: "os_sr_ta_nm" }
  });
  const state = {
    xrm: null,
    generation: 0,
    queueNextLink: null,
    queueRows: [],
    pendingTotal: 0,
    queueLoading: false
  };

  function getVietnamParts(date) {
    const values = new Intl.DateTimeFormat("en-US", {
      timeZone: TIME_ZONE,
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric",
      second: "numeric",
      hourCycle: "h23"
    }).formatToParts(date);
    const parts = Object.fromEntries(values.map((part) => [part.type, Number(part.value)]));
    return {
      year: parts.year,
      month: parts.month,
      day: parts.day,
      hour: parts.hour,
      minute: parts.minute,
      second: parts.second,
      millisecond: date.getUTCMilliseconds()
    };
  }

  function localVietnamToUtc(parts) {
    return new Date(Date.UTC(
      parts.year, parts.month - 1, parts.day,
      parts.hour || 0, parts.minute || 0, parts.second || 0, parts.millisecond || 0
    ) - VIETNAM_OFFSET_MS);
  }

  function getYtdRange(yearValue, nowValue = new Date()) {
    const year = Number(yearValue);
    const now = new Date(nowValue);
    if (!Number.isInteger(year) || Number.isNaN(now.getTime())) throw new Error("INVALID_PERIOD");
    const nowParts = getVietnamParts(now);
    if (year < 1900 || year > nowParts.year) throw new Error("INVALID_PERIOD");

    const startUtc = localVietnamToUtc({ year, month: 1, day: 1 }).toISOString();
    let asOf;
    if (year === nowParts.year) {
      asOf = now;
    } else {
      const lastDay = new Date(Date.UTC(year, nowParts.month, 0)).getUTCDate();
      asOf = localVietnamToUtc({ ...nowParts, year, day: Math.min(nowParts.day, lastDay) });
    }
    return {
      year,
      startUtc,
      endExclusiveUtc: new Date(asOf.getTime() + 1).toISOString(),
      startMs: Date.parse(startUtc),
      endExclusiveMs: asOf.getTime() + 1
    };
  }

  function normalizeGuid(value, allowEmpty = false) {
    if (allowEmpty && value === "") return "";
    if (typeof value !== "string") throw new Error("INVALID_FILTER");
    const normalized = value.replace(/[{}]/g, "").toLowerCase();
    if (!GUID.test(normalized)) throw new Error("INVALID_FILTER");
    return normalized;
  }

  function normalizeFilters(filters) {
    return {
      year: Number(filters.year),
      positionId: normalizeGuid(filters.positionId || "", true),
      sourceId: normalizeGuid(filters.sourceId || "", true),
      taId: normalizeGuid(filters.taId || "", true)
    };
  }

  function candidateFilterXml(filters, range, statusValues) {
    const conditions = [
      '<condition attribute="statecode" operator="eq" value="0" />',
      `<condition attribute="createdon" operator="ge" value="${range.startUtc}" />`,
      `<condition attribute="createdon" operator="lt" value="${range.endExclusiveUtc}" />`
    ];
    if (filters.positionId) conditions.push(
      `<condition attribute="os_sr_cand_pos" operator="eq" value="${filters.positionId}" />`
    );
    if (filters.sourceId) conditions.push(
      `<condition attribute="os_sr_cand_csrc" operator="eq" value="${filters.sourceId}" />`
    );
    if (filters.taId) conditions.push(
      `<condition attribute="os_sr_cand_ta" operator="eq" value="${filters.taId}" />`
    );
    if (statusValues && statusValues.length) {
      conditions.push(`<condition attribute="${TABLE.candidate.status}" operator="in">${statusValues
        .map((value) => `<value>${value}</value>`).join("")}</condition>`);
    }
    return `<filter type="and">${conditions.join("")}</filter>`;
  }

  function buildPipelineFetchXml(filters, range) {
    const normalized = normalizeFilters(filters);
    const filter = candidateFilterXml(normalized, range);
    return `<fetch aggregate="true"><entity name="${TABLE.candidate.logicalName}">` +
      `<attribute name="${TABLE.candidate.id}" alias="candidateCount" aggregate="count" />` +
      `<attribute name="${TABLE.candidate.status}" alias="status" groupby="true" />` +
      `${filter}</entity></fetch>`;
  }

  function buildCandidateODataFilter(filters, range, pendingOnly = false) {
    const normalized = normalizeFilters(filters);
    const clauses = [
      "statecode eq 0",
      `createdon ge ${range.startUtc}`,
      `createdon lt ${range.endExclusiveUtc}`
    ];
    if (normalized.positionId) clauses.push(
      `${TABLE.candidate.position} eq ${normalized.positionId}`
    );
    if (normalized.sourceId) clauses.push(
      `${TABLE.candidate.source} eq ${normalized.sourceId}`
    );
    if (normalized.taId) clauses.push(
      `${TABLE.candidate.ta} eq ${normalized.taId}`
    );
    if (pendingOnly) {
      clauses.push(`(${Array.from(PENDING_STATUSES, (value) =>
        `${TABLE.candidate.status} eq ${value}`).join(" or ")})`);
    }
    return clauses.join(" and ");
  }

  function buildQueueOptions(filters, range) {
    const select = [
      TABLE.candidate.id,
      TABLE.candidate.number,
      TABLE.candidate.name,
      TABLE.candidate.status,
      TABLE.candidate.position,
      TABLE.candidate.source,
      TABLE.candidate.ta,
      "createdon"
    ].join(",");
    const filter = encodeURIComponent(buildCandidateODataFilter(filters, range, true));
    return `?$select=${select}&$filter=${filter}` +
      `&$orderby=createdon asc,${TABLE.candidate.id} asc`;
  }

  function buildScheduleOptions(filters) {
    const normalized = normalizeFilters(filters);
    const clauses = [
      "statecode eq 0",
      `${TABLE.interview.round} eq 100000000`,
      `(${TABLE.interview.status} eq 100000001 or ${TABLE.interview.status} eq null)`
    ];
    if (normalized.taId) clauses.push(`${TABLE.interview.ta} eq ${normalized.taId}`);
    const candidateSelect = [
      "os_sr_candid",
      TABLE.candidate.status,
      TABLE.candidate.position,
      TABLE.candidate.source,
      TABLE.candidate.ta,
      "statecode",
      "createdon"
    ].join(",");
    const select = [
      TABLE.interview.id,
      TABLE.interview.candidate,
      TABLE.interview.ta,
      TABLE.interview.round,
      TABLE.interview.start,
      TABLE.interview.status,
      "statecode",
      "createdon"
    ].join(",");
    return `?$select=${select}&$filter=${encodeURIComponent(clauses.join(" and "))}` +
      `&$expand=${encodeURIComponent(`${TABLE.interview.candidateNavigation}($select=${candidateSelect})`)}` +
      `&$orderby=createdon desc,${TABLE.interview.id} asc`;
  }

  function parseCount(value) {
    if (typeof value !== "number" && (typeof value !== "string" || !/^\d+$/.test(value))) {
      throw new Error("INVALID_AGGREGATE");
    }
    const count = typeof value === "number" ? value : Number(value);
    if (!Number.isSafeInteger(count) || count < 0) throw new Error("INVALID_AGGREGATE");
    return count;
  }

  function summarizePipeline(rows) {
    const counts = Object.fromEntries(STATUS_ORDER.map((status) => [status, 0]));
    let otherCount = 0;
    for (const row of rows) {
      const count = parseCount(row.candidateCount);
      const status = row.status == null ? null : Number(row.status);
      if (Number.isInteger(status) && Object.hasOwn(counts, status)) counts[status] += count;
      else otherCount += count;
    }
    const total = Object.values(counts).reduce((sum, count) => sum + count, otherCount);
    const pending = Array.from(PENDING_STATUSES).reduce((sum, status) => sum + counts[status], 0);
    return { counts, otherCount, total, pending };
  }

  function normalizedLookupId(value) {
    if (value == null || value === "") return "";
    if (typeof value !== "string") throw new Error("INVALID_RECORD");
    const normalized = value.replace(/[{}]/g, "").toLowerCase();
    if (!GUID.test(normalized)) throw new Error("INVALID_RECORD");
    return normalized;
  }

  function getScheduleMetrics(rows, filters, range) {
    const normalized = normalizeFilters(filters);
    const latestByCandidate = new Map();
    for (const row of rows) {
      if (!row || row.statecode !== 0 || row[TABLE.interview.round] !== 100000000 ||
          (row[TABLE.interview.status] != null && row[TABLE.interview.status] !== 100000001)) continue;
      const candidate = row[TABLE.interview.candidateNavigation];
      if (!candidate || candidate.statecode !== 0 || candidate[TABLE.candidate.status] !== 100010003) continue;

      const candidateCreated = Date.parse(candidate.createdon);
      const scheduleStart = Date.parse(row[TABLE.interview.start]);
      const scheduleCreated = Date.parse(row.createdon);
      if (![candidateCreated, scheduleStart, scheduleCreated].every(Number.isFinite)) {
        throw new Error("INVALID_RECORD");
      }
      if (candidateCreated < range.startMs || candidateCreated >= range.endExclusiveMs) continue;

      const positionId = normalizedLookupId(candidate[TABLE.candidate.position]);
      const sourceId = normalizedLookupId(candidate[TABLE.candidate.source]);
      const candidateTaId = normalizedLookupId(candidate[TABLE.candidate.ta]);
      const scheduleTaId = normalizedLookupId(row[TABLE.interview.ta]);
      if (normalized.positionId && positionId !== normalized.positionId) continue;
      if (normalized.sourceId && sourceId !== normalized.sourceId) continue;
      if (normalized.taId &&
          (candidateTaId !== normalized.taId || scheduleTaId !== normalized.taId)) continue;

      const candidateId = normalizedLookupId(row[TABLE.interview.candidate]);
      if (!candidateId) throw new Error("INVALID_RECORD");
      const current = latestByCandidate.get(candidateId);
      if (!current || scheduleCreated > current.scheduleCreated ||
          (scheduleCreated === current.scheduleCreated && scheduleStart > current.scheduleStart)) {
        latestByCandidate.set(candidateId, { candidateCreated, scheduleCreated, scheduleStart });
      }
    }

    const leadTimes = Array.from(latestByCandidate.values())
      .map((row) => (row.scheduleStart - row.candidateCreated) / 86400000)
      .filter((days) => Number.isFinite(days) && days > 0);
    const averageLeadDays = leadTimes.length
      ? leadTimes.reduce((sum, days) => sum + days, 0) / leadTimes.length
      : null;
    return {
      scheduled: latestByCandidate.size,
      averageLeadDays,
      averageLeadDenominator: leadTimes.length
    };
  }

  function getXrm() {
    if (window.Xrm?.WebApi) return window.Xrm;
    if (window.parent.Xrm?.WebApi) return window.parent.Xrm;
    throw new Error("CONTEXT_UNAVAILABLE");
  }

  function continuationOptions(nextLink) {
    const queryStart = typeof nextLink === "string" ? nextLink.indexOf("?") : -1;
    if (queryStart < 0 || !nextLink.slice(queryStart + 1)) throw new Error("INVALID_RESPONSE");
    return nextLink.slice(queryStart);
  }

  async function retrieveAll(api, tableName, options, generation) {
    const records = [];
    let response = await api.retrieveMultipleRecords(tableName, options, 5000);
    while (true) {
      if (generation !== state.generation) return null;
      if (!response || !Array.isArray(response.entities)) throw new Error("INVALID_RESPONSE");
      records.push(...response.entities);
      if (records.length > MAX_RESULT_ROWS) throw new Error("RESULT_LIMIT_EXCEEDED");
      if (!response.nextLink) return records;
      response = await api.retrieveMultipleRecords(tableName, continuationOptions(response.nextLink), 5000);
    }
  }

  async function loadReference(api, reference, generation) {
    const options = `?$select=${reference.id},${reference.name}` +
      `&$filter=${encodeURIComponent("statecode eq 0")}&$orderby=${reference.name} asc,${reference.id} asc`;
    const rows = await retrieveAll(api, reference.logicalName, options, generation);
    if (rows === null) return null;
    return rows.map((row) => {
      const id = normalizedLookupId(row[reference.id]);
      if (!id || typeof row[reference.name] !== "string") throw new Error("INVALID_RESPONSE");
      return { id, name: row[reference.name] };
    });
  }

  async function loadReferences(api, generation) {
    const [positions, sources, tas] = await Promise.all([
      loadReference(api, TABLE.position, generation),
      loadReference(api, TABLE.source, generation),
      loadReference(api, TABLE.ta, generation)
    ]);
    if (positions === null || sources === null || tas === null) return null;
    return { positions, sources, tas };
  }

  async function loadPipeline(api, filters, range, generation) {
    const xml = buildPipelineFetchXml(filters, range);
    const result = await api.retrieveMultipleRecords(
      TABLE.candidate.logicalName, `?fetchXml=${xml}`
    );
    if (generation !== state.generation) return null;
    if (!result || !Array.isArray(result.entities) || result.nextLink || result.fetchXmlPagingCookie) {
      throw new Error("INVALID_RESPONSE");
    }
    return summarizePipeline(result.entities);
  }

  function readQueueRow(row) {
    const id = normalizedLookupId(row[TABLE.candidate.id]);
    if (!id || typeof row[TABLE.candidate.name] !== "string" ||
        typeof row[TABLE.candidate.number] !== "string") throw new Error("INVALID_RESPONSE");
    const status = Number(row[TABLE.candidate.status]);
    if (!Number.isInteger(status) || !Object.hasOwn(STATUS, status)) throw new Error("INVALID_RESPONSE");
    return {
      id,
      number: row[TABLE.candidate.number],
      name: row[TABLE.candidate.name],
      status,
      position: row[`${TABLE.candidate.position}@OData.Community.Display.V1.FormattedValue`] || "—",
      source: row[`${TABLE.candidate.source}@OData.Community.Display.V1.FormattedValue`] || "—",
      ta: row[`${TABLE.candidate.ta}@OData.Community.Display.V1.FormattedValue`] || "—",
      createdOn: row.createdon
    };
  }

  async function loadQueuePage(api, filters, range, nextLink, generation) {
    const options = nextLink ? continuationOptions(nextLink) : buildQueueOptions(filters, range);
    const response = await api.retrieveMultipleRecords(TABLE.candidate.logicalName, options, QUEUE_PAGE_SIZE);
    if (generation !== state.generation) return null;
    if (!response || !Array.isArray(response.entities) ||
        (response.nextLink != null && typeof response.nextLink !== "string")) {
      throw new Error("INVALID_RESPONSE");
    }
    return {
      rows: response.entities.map(readQueueRow),
      nextLink: response.nextLink || null
    };
  }

  async function loadScheduleMetrics(api, filters, generation) {
    const rows = await retrieveAll(
      api, TABLE.interview.logicalName, buildScheduleOptions(filters), generation
    );
    if (rows === null) return null;
    return rows;
  }

  function selectedFilters() {
    return {
      year: $("filter-year").value,
      positionId: $("filter-position").value,
      sourceId: $("filter-source").value,
      taId: $("filter-ta").value
    };
  }

  function $(id) {
    return document.getElementById(id);
  }

  function setStatus(message, kind = "") {
    const status = $("status");
    status.textContent = message;
    status.className = `status ${kind}`.trim();
  }

  function formatCount(value) {
    return new Intl.NumberFormat("en-US").format(value);
  }

  function formatDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "—";
    return new Intl.DateTimeFormat("en-GB", {
      timeZone: TIME_ZONE,
      year: "numeric",
      month: "short",
      day: "2-digit"
    }).format(date);
  }

  function fillYearFilter() {
    const nowParts = getVietnamParts(new Date());
    const select = $("filter-year");
    select.replaceChildren();
    for (let year = nowParts.year; year >= nowParts.year - 10; year--) {
      select.add(new Option(String(year), String(year)));
    }
  }

  function fillReferenceFilter(id, rows, emptyLabel) {
    const select = $(id);
    select.replaceChildren(new Option(emptyLabel, ""));
    for (const row of rows) select.add(new Option(row.name, row.id));
  }

  function clearDashboard() {
    $("metric-candidates").textContent = "—";
    $("detail-candidates").textContent = "";
    $("metric-pending").textContent = "—";
    $("metric-lead-time").textContent = "—";
    $("detail-lead-time").textContent = "";
    $("metric-scheduled").textContent = "—";
    $("pipeline").replaceChildren();
    $("queue").replaceChildren();
    $("queue-summary").textContent = "";
    $("load-more").hidden = true;
    state.queueRows = [];
    state.queueNextLink = null;
    state.pendingTotal = 0;
  }

  function renderPipeline(pipeline) {
    const container = $("pipeline");
    container.replaceChildren();
    const entries = STATUS_ORDER.map((status) => ({
      label: STATUS[status],
      count: pipeline.counts[status]
    }));
    if (pipeline.otherCount) entries.push({ label: "Unmapped status", count: pipeline.otherCount });
    const maximum = Math.max(0, ...entries.map((entry) => entry.count));
    for (const entry of entries) {
      const row = document.createElement("div");
      row.className = "pipeline-row";
      const label = document.createElement("span");
      label.textContent = entry.label;
      const count = document.createElement("strong");
      count.textContent = formatCount(entry.count);
      const bar = document.createElement("div");
      bar.className = "pipeline-bar";
      const fill = document.createElement("div");
      fill.className = "pipeline-fill";
      fill.style.width = maximum ? `${(entry.count / maximum) * 100}%` : "0%";
      bar.append(fill);
      row.append(label, count, bar);
      container.append(row);
    }
    if (!pipeline.total) {
      const empty = document.createElement("p");
      empty.className = "muted";
      empty.textContent = "No active Candidates match these filters.";
      container.append(empty);
    }
  }

  function makeQueueRow(candidate) {
    const row = document.createElement("article");
    row.className = "queue-row";
    const main = document.createElement("div");
    main.className = "queue-main";
    const name = document.createElement("strong");
    name.textContent = candidate.name;
    const number = document.createElement("span");
    number.textContent = candidate.number;
    main.append(name, number);

    const status = document.createElement("span");
    status.className = "queue-meta";
    status.textContent = STATUS[candidate.status];
    const position = document.createElement("span");
    position.className = "queue-meta";
    position.textContent = candidate.position;
    const ta = document.createElement("span");
    ta.className = "queue-meta";
    ta.textContent = candidate.ta;
    const open = document.createElement("button");
    open.type = "button";
    open.textContent = "Open";
    open.addEventListener("click", async () => {
      try {
        await state.xrm.Navigation.openForm({ entityName: TABLE.candidate.logicalName, entityId: candidate.id });
      } catch {
        setStatus("The selected Candidate record could not be opened.", "error");
      }
    });
    row.append(main, status, position, ta, open);
    return row;
  }

  function renderQueue() {
    const container = $("queue");
    container.replaceChildren(...state.queueRows.map(makeQueueRow));
    $("queue-summary").textContent = state.pendingTotal
      ? `Showing ${formatCount(state.queueRows.length)} of ${formatCount(state.pendingTotal)} pending actions.`
      : "No pending actions match these filters.";
    $("load-more").hidden = !state.queueNextLink;
    $("load-more").disabled = state.queueLoading;
  }

  function renderDashboard(pipeline, scheduleMetrics, queuePage, range) {
    $("metric-candidates").textContent = formatCount(pipeline.total);
    $("detail-candidates").textContent =
      `Active Candidate records created ${formatDate(range.startUtc)} through ${formatDate(range.endExclusiveUtc)} (Vietnam time).`;
    $("metric-pending").textContent = formatCount(pipeline.pending);
    $("metric-scheduled").textContent = formatCount(scheduleMetrics.scheduled);
    if (scheduleMetrics.averageLeadDays == null) {
      $("metric-lead-time").textContent = "—";
      $("detail-lead-time").textContent = "No qualifying Round 1 schedules (denominator: 0).";
    } else {
      $("metric-lead-time").textContent = `${scheduleMetrics.averageLeadDays.toFixed(1)} days`;
      $("detail-lead-time").textContent =
        `Candidate created to scheduled start; denominator: ${formatCount(scheduleMetrics.averageLeadDenominator)} Candidates.`;
    }
    renderPipeline(pipeline);
    state.queueRows = queuePage.rows;
    state.queueNextLink = queuePage.nextLink;
    state.pendingTotal = pipeline.pending;
    renderQueue();
  }

  function readErrorMessage(error) {
    if (error && error.message === "CONTEXT_UNAVAILABLE") {
      return "Dataverse application context is unavailable. Open this page from the Recruitment Support app.";
    }
    if (error && error.message === "RESULT_LIMIT_EXCEEDED") {
      return "The result set exceeds the supported dashboard limit. Narrow the filters and try again.";
    }
    return "Dashboard data could not be verified. Check your Dataverse read access and retry.";
  }

  async function refreshDashboard(event) {
    if (event) event.preventDefault();
    const generation = ++state.generation;
    state.queueLoading = false;
    clearDashboard();
    $("refresh").disabled = true;
    $("load-more").disabled = true;
    setStatus("Loading dashboard data…");
    try {
      state.xrm = getXrm();
      const filters = normalizeFilters(selectedFilters());
      const range = getYtdRange(filters.year);
      const api = state.xrm.WebApi;
      const [pipeline, scheduleRows, queuePage] = await Promise.all([
        loadPipeline(api, filters, range, generation),
        loadScheduleMetrics(api, filters, generation),
        loadQueuePage(api, filters, range, null, generation)
      ]);
      if (generation !== state.generation ||
          pipeline === null || scheduleRows === null || queuePage === null) return;
      const scheduleMetrics = getScheduleMetrics(scheduleRows, filters, range);
      renderDashboard(pipeline, scheduleMetrics, queuePage, range);
      setStatus(`Updated ${new Intl.DateTimeFormat("en-GB", {
        timeZone: TIME_ZONE, hour: "2-digit", minute: "2-digit"
      }).format(new Date())} Vietnam time.`, "success");
    } catch (error) {
      if (generation !== state.generation) return;
      clearDashboard();
      setStatus(readErrorMessage(error), "error");
    } finally {
      if (generation === state.generation) $("refresh").disabled = false;
    }
  }

  async function loadMoreQueue() {
    if (!state.queueNextLink || state.queueLoading) return;
    const generation = state.generation;
    state.queueLoading = true;
    $("load-more").disabled = true;
    try {
      const page = await loadQueuePage(state.xrm.WebApi, selectedFilters(), null, state.queueNextLink, generation);
      if (generation !== state.generation || page === null) return;
      state.queueRows.push(...page.rows);
      state.queueNextLink = page.nextLink;
      renderQueue();
    } catch (error) {
      if (generation === state.generation) setStatus(readErrorMessage(error), "error");
    } finally {
      if (generation === state.generation) {
        state.queueLoading = false;
        $("load-more").disabled = !state.queueNextLink;
      }
    }
  }

  async function initialize() {
    state.xrm = getXrm();
    fillYearFilter();
    $("refresh").disabled = true;
    const generation = ++state.generation;
    setStatus("Loading filters…");
    const references = await loadReferences(state.xrm.WebApi, generation);
    if (generation !== state.generation || references === null) return;
    fillReferenceFilter("filter-position", references.positions, "All positions");
    fillReferenceFilter("filter-source", references.sources, "All sources");
    fillReferenceFilter("filter-ta", references.tas, "All TAs");
    $("filters").addEventListener("submit", refreshDashboard);
    for (const id of ["filter-year", "filter-position", "filter-source", "filter-ta"]) {
      $(id).addEventListener("change", refreshDashboard);
    }
    $("load-more").addEventListener("click", loadMoreQueue);
    await refreshDashboard();
  }

  const api = Object.freeze({
    STATUS,
    PENDING_STATUSES: Array.from(PENDING_STATUSES),
    getYtdRange,
    normalizeFilters,
    buildPipelineFetchXml,
    buildCandidateODataFilter,
    buildQueueOptions,
    buildScheduleOptions,
    summarizePipeline,
    getScheduleMetrics
  });

  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (typeof document !== "undefined") {
    document.addEventListener("DOMContentLoaded", () => {
      initialize().catch((error) => setStatus(`${readErrorMessage(error)} Reload the page to retry initialization.`, "error"));
    });
  }
})();
