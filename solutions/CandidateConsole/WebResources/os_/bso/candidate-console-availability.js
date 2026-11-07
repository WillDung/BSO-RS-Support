(() => {
  "use strict";

  const TABLE = {
    query: {
      logicalName: "os_sr_avq",
      id: "os_sr_avqid",
      entitySetName: "os_sr_avqs",
      ta: "os_sr_avq_ta",
      location: "os_sr_avq_loc",
      mode: "os_sr_avq_mod",
      start: "os_sr_avq_strt",
      end: "os_sr_avq_end",
      duration: "os_sr_avq_dur",
      state: "os_sr_avq_stat",
      reason: "os_sr_avq_rsn",
      error: "os_sr_avq_err",
      slots: "os_sr_avq_slts",
      expiresAt: "os_sr_avq_exp"
    },
    ta: { logicalName: "os_sr_ta", id: "os_sr_taid", name: "os_sr_ta_nm" },
    location: { logicalName: "os_sr_loc", id: "os_sr_locid", name: "os_sr_loc_nm" }
  };
  const MODE = { online: 100000000, onsite: 100000001 };
  const STATE = { pending: 100000000, available: 100000001, noSlots: 100000002, failed: 100000003 };
  const POLL_INTERVAL_MS = 2000;
  const MAX_POLL_MS = 120000;
  const VIETNAM_OFFSET = "+07:00";
  const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  let lastQueryId = null;
  let lastRequest = null;
  let activeSubmission = 0;
  let busy = false;
  let ready = false;
  let pollTimer = null;
  let initialized = false;
  const referenceIds = { ta: new Set(), location: new Set() };
  const SAFE_ERRORS = {
    TA_INACTIVE: "The selected TA is inactive.",
    TA_EMAIL_MISSING: "The selected TA has no calendar email.",
    TA_EMAIL_INVALID: "The selected TA email is invalid.",
    TA_EMAIL_DOMAIN_NOT_ALLOWED: "The selected TA email domain is not allowed.",
    LOCATION_REQUIRED: "Select an active location for an onsite interview.",
    LOCATION_INACTIVE: "The selected location is inactive.",
    ROOM_EMAIL_MISSING: "The selected location has no room calendar.",
    ROOM_EMAIL_INVALID: "The selected room calendar address is invalid.",
    ROOM_EMAIL_DOMAIN_NOT_ALLOWED: "The selected room email domain is not allowed.",
    PROVIDER_RESPONSE_INVALID: "Availability data could not be verified.",
    PROVIDER_TIMEZONE_UNSUPPORTED: "Availability timezone could not be verified. Contact support.",
    PROVIDER_AUTH: "Calendar integration authentication is unavailable.",
    PROVIDER_PERMISSION: "Calendar integration does not have permission.",
    MAILBOX_NOT_FOUND: "A calendar mailbox could not be found.",
    PROVIDER_THROTTLED: "Calendar service is busy. Start a new availability check later.",
    PROVIDER_TIMEOUT: "Calendar availability timed out. Start a new availability check.",
    PROVIDER_UNAVAILABLE: "Calendar availability is unavailable.",
    RESULT_TOO_LARGE: "Too many slots were returned. Narrow the requested window.",
    INVALID_REQUEST: "The requested availability window or duration is invalid.",
    REFERENCE_READ_FAILED: "A selected reference could not be verified.",
    REFERENCE_CHANGED: "The selected TA or room changed during this query. Start a new availability check."
  };

  const $ = (id) => document.getElementById(id);
  const getXrm = () => {
    if (window.parent && window.parent.Xrm && window.parent.Xrm.WebApi) return window.parent.Xrm;
    if (window.Xrm && window.Xrm.WebApi) return window.Xrm;
    throw new Error("CONTEXT_UNAVAILABLE");
  };

  function availabilityAllowed() {
    try {
      const config = window.BsoRsCandidateConsoleConfiguration;
      const policy = window.BsoRsCandidateConsolePolicy;
      if (!config || config.availabilityEnabled !== true || !policy ||
          typeof policy.resolve !== "function") return false;
      const context = typeof GetGlobalContext === "function"
        ? GetGlobalContext() : getXrm().Utility.getGlobalContext();
      const resolved = policy.resolve(config, {
        organizationUrl: context.getClientUrl(),
        organizationId: context.organizationSettings.organizationId
      });
      return resolved.allowed === true && resolved.mode === "DEV" && resolved.syntheticDataOnly === true &&
        typeof policy.hasSyntheticIsolation === "function" && policy.hasSyntheticIsolation() === true;
    } catch {
      return false;
    }
  }

  function blockAvailability() {
    ready = false;
    stopPolling();
    formControls().forEach((control) => { control.disabled = true; });
    showResult("Availability checking is not configured, its environment identity could not be verified, " +
      "or approved synthetic data isolation is unavailable.", true);
  }

  function formControls() {
    return $("availability-form").querySelectorAll("input, select, button");
  }

  function showResult(message, isError = false) {
    const output = $("availability-result");
    output.textContent = message;
    output.classList.toggle("error", isError);
    output.hidden = false;
  }

  function localVietnamToUtc(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(value || "");
    if (!match) return null;
    const date = new Date(`${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:00${VIETNAM_OFFSET}`);
    if (Number.isNaN(date.getTime())) return null;
    const roundTrip = new Date(date.getTime() + 7 * 60 * 60000).toISOString().slice(0, 16);
    return roundTrip === value ? date : null;
  }

  async function getEntitySetName(logicalName) {
    const metadata = await getXrm().Utility.getEntityMetadata(logicalName);
    if (!metadata || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(metadata.EntitySetName || ""))
      throw new Error("REFERENCE_METADATA_UNAVAILABLE");
    return metadata.EntitySetName;
  }

  async function loadReferences(table, select) {
    if (!availabilityAllowed()) throw new Error("SYNTHETIC_ISOLATION_REQUIRED");
    const api = getXrm().WebApi;
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.syntheticReferenceFilter !== "function") {
      throw new Error("SYNTHETIC_QUERY_POLICY_UNAVAILABLE");
    }
    const filter = `statecode eq 0 and ${policy.syntheticReferenceFilter(table.name)}`;
    const query = `?$select=${[table.id, table.name].concat(select || []).join(",")}` +
      `&$filter=${encodeURIComponent(filter)}&$orderby=${table.name} asc`;
    const records = [];
    let response = await api.retrieveMultipleRecords(table.logicalName, query);
    records.push(...(response.entities || []));
    while (response.nextLink) {
      if (!availabilityAllowed()) throw new Error("SYNTHETIC_ISOLATION_REQUIRED");
      response = await api.retrieveMultipleRecords(table.logicalName, response.nextLink);
      records.push(...(response.entities || []));
    }
    const config = window.BsoRsCandidateConsoleConfiguration || {};
    if (!policy || typeof policy.allowsReference !== "function" ||
        typeof config.syntheticDataOnly !== "boolean") throw new Error("SYNTHETIC_QUERY_POLICY_UNAVAILABLE");
    const invalid = records.some((record) => !(typeof record[table.name] === "string" &&
      typeof record[table.id] === "string" && GUID.test(record[table.id].replace(/[{}]/g, "")) &&
      policy.allowsReference(record[table.name], config.syntheticDataOnly)));
    if (invalid) throw new Error("SYNTHETIC_REFERENCE_RESPONSE_INVALID");
    return records;
  }

  function fillSelect(select, records, emptyLabel) {
    select.replaceChildren(new Option(emptyLabel, ""));
    for (const record of records) {
      const id = (record[TABLE[select.id === "availability-ta" ? "ta" : "location"].id] || "")
        .replace(/[{}]/g, "");
      const option = new Option(record[select.dataset.nameField] || "Unnamed reference", id);
      select.add(option);
    }
  }

  function modeChanged() {
    const onsite = $("availability-mode").value === String(MODE.onsite);
    $("availability-location-field").hidden = !onsite;
    $("availability-location").required = onsite;
    $("availability-location").disabled = !onsite;
    if (!ready || busy) return;
    $("availability-submit").disabled = !referenceIds.ta.size || (onsite && !referenceIds.location.size);
    if (!referenceIds.ta.size) showResult("No active TAs are available for this environment.");
    else if (onsite && !referenceIds.location.size)
      showResult("No active rooms / locations are available. Onsite availability cannot be checked.");
    else showResult("Select a TA and a future Vietnam-time window to check availability.");
  }

  function setBusy(value) {
    busy = value;
    $("availability-submit").disabled = value || !ready || !referenceIds.ta.size ||
      ($("availability-mode").value === String(MODE.onsite) && !referenceIds.location.size);
    $("availability-refresh").disabled = value;
  }

  function stopPolling() {
    if (pollTimer !== null) window.clearTimeout(pollTimer);
    pollTimer = null;
  }

  function readFailed(queryId) {
    if (queryId !== lastQueryId) return;
    setBusy(false);
    showResult("Availability status could not be read. Use Refresh status to try again.", true);
    $("availability-refresh").hidden = false;
  }

  function utcTimestamp(value) {
    if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value))
      return NaN;
    const time = Date.parse(value);
    return Number.isFinite(time) && new Date(time).toISOString().replace(".000Z", "Z") === value
      ? time : NaN;
  }

  function resultExpiration(value) {
    if (typeof value !== "string" ||
        !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$/.test(value)) return NaN;
    const time = Date.parse(value);
    return Number.isFinite(time) && new Date(time).toISOString().slice(0, 19) === value.slice(0, 19)
      ? time : NaN;
  }

  function appendSlotList(json) {
    let slots;
    try {
      if (typeof json !== "string" || json.length > 32768) throw new Error("RESULT_INVALID");
      slots = JSON.parse(json);
    } catch {
      throw new Error("RESULT_INVALID");
    }
    if (!Array.isArray(slots) || !slots.length || slots.length > 200) throw new Error("RESULT_INVALID");
    let previousStart = -Infinity;
    const list = document.createElement("ol");
    for (const slot of slots) {
      if (!slot || Object.keys(slot).sort().join(",") !== "endUtc,startUtc")
        throw new Error("RESULT_INVALID");
      const startTime = utcTimestamp(slot.startUtc);
      const endTime = utcTimestamp(slot.endUtc);
      if (!lastRequest || !Number.isFinite(startTime) || !Number.isFinite(endTime) ||
          startTime <= previousStart || startTime < lastRequest.start || endTime > lastRequest.end ||
          startTime <= Date.now() || endTime - startTime !== lastRequest.duration * 60000 ||
          startTime % 900000 !== 0 || endTime % 900000 !== 0)
        throw new Error("RESULT_INVALID");
      previousStart = startTime;
      const item = document.createElement("li");
      const start = new Date(slot.startUtc);
      const end = new Date(slot.endUtc);
      if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) throw new Error("RESULT_INVALID");
      const formatter = new Intl.DateTimeFormat("en-GB", {
        timeZone: "Asia/Ho_Chi_Minh", dateStyle: "medium", timeStyle: "short"
      });
      item.textContent = `${formatter.format(start)} – ${formatter.format(end)} (Vietnam time)`;
      list.append(item);
    }
    showResult("");
    $("availability-result").replaceChildren(document.createTextNode("Available slots:"), list);
  }

  async function readQuery(queryId, startedAt) {
    if (queryId !== lastQueryId) return true;
    if (!availabilityAllowed()) {
      blockAvailability();
      return true;
    }
    const api = getXrm().WebApi;
    const query = TABLE.query;
    const row = await api.retrieveRecord(query.logicalName, queryId,
      `?$select=${[query.state, query.reason, query.error, query.slots, query.expiresAt].join(",")}`);
    if (queryId !== lastQueryId) return true;
    if (!availabilityAllowed()) {
      blockAvailability();
      return true;
    }
    const state = row[query.state];
    if (state === STATE.pending) {
      if (Date.now() - startedAt >= MAX_POLL_MS) {
        setBusy(false);
        showResult("Availability is still pending. Use Refresh status to check again.");
        $("availability-refresh").hidden = false;
        return false;
      }
      showResult("Availability query pending…");
      pollTimer = window.setTimeout(() => {
        pollTimer = null;
        return readQuery(queryId, startedAt).catch(() => readFailed(queryId));
      }, POLL_INTERVAL_MS);
      return false;
    }

    setBusy(false);
    $("availability-refresh").hidden = false;
    const expiration = resultExpiration(row[query.expiresAt]);
    if (!Number.isFinite(expiration) || expiration <= Date.now()) {
      showResult("Availability result expired. Start a new query.");
      return true;
    }
    if (state === STATE.available) {
      try {
        appendSlotList(row[query.slots]);
      } catch {
        showResult("Availability result could not be verified.", true);
      }
    } else if (state === STATE.noSlots) {
      const reason = row[query.reason] === "NO_COMMON_SLOT"
        ? "No common slots were found in the requested window."
        : "No slots are available.";
      showResult(reason);
    } else if (state === STATE.failed) {
      const error = row[query.error];
      showResult(Object.prototype.hasOwnProperty.call(SAFE_ERRORS, error)
        ? SAFE_ERRORS[error] : "Availability could not be verified. Contact support.", true);
    } else {
      showResult("Availability result has an unknown state.", true);
    }
    return true;
  }

  async function submitQuery(event) {
    event.preventDefault();
    if (busy) return;
    const form = $("availability-form");
    if (!form.reportValidity()) return;
    if (!availabilityAllowed()) {
      blockAvailability();
      return;
    }
    if (!ready) return;
    const start = localVietnamToUtc($("availability-start").value);
    const end = localVietnamToUtc($("availability-end").value);
    const duration = Number($("availability-duration").value);
    if (!start || !end || start <= new Date() || end <= start ||
        start.getTime() % 900000 !== 0 || end.getTime() % 900000 !== 0 ||
        !Number.isInteger(duration) || duration <= 0 || duration > 480 || duration % 15 !== 0 ||
        end - start < duration * 60000) {
      showResult("Enter a future Vietnam-time window and a duration in 15-minute increments.", true);
      return;
    }
    const mode = Number($("availability-mode").value);
    const ta = $("availability-ta").value;
    const location = $("availability-location").value;
    if (!Object.values(MODE).includes(mode) || !referenceIds.ta.has(ta) ||
        (mode === MODE.onsite && !referenceIds.location.has(location))) {
      showResult("Select an active TA, a valid interview mode, and an active location for onsite interviews.", true);
      return;
    }
    const submission = ++activeSubmission;
    setBusy(true);
    stopPolling();
    lastQueryId = null;
    lastRequest = { start: start.getTime(), end: end.getTime(), duration };
    $("availability-refresh").hidden = true;
    showResult("Submitting availability query…");
    try {
      const xrm = getXrm();
      const payload = {
        [`${TABLE.query.ta}@odata.bind`]: `/${await getEntitySetName(TABLE.ta.logicalName)}(${ta})`,
        [TABLE.query.mode]: mode,
        [TABLE.query.start]: start.toISOString(),
        [TABLE.query.end]: end.toISOString(),
        [TABLE.query.duration]: duration
      };
      if (mode === MODE.onsite) {
        payload[`${TABLE.query.location}@odata.bind`] =
          `/${await getEntitySetName(TABLE.location.logicalName)}(${location})`;
      }
      if (submission !== activeSubmission) return;
      if (!availabilityAllowed()) {
        blockAvailability();
        return;
      }
      const created = await xrm.WebApi.createRecord(TABLE.query.logicalName, payload);
      if (submission !== activeSubmission) return;
      const id = created && typeof created.id === "string" ? created.id.replace(/[{}]/g, "") : "";
      if (!GUID.test(id)) throw new Error("QUERY_ID_MISSING");
      lastQueryId = id;
      showResult("Availability query pending…");
      await readQuery(id, Date.now());
    } catch {
      if (submission === activeSubmission) {
        if (lastQueryId) readFailed(lastQueryId);
        else {
          setBusy(false);
          showResult("Availability query could not be started or read. Contact support if this continues.", true);
        }
      }
    }
  }

  async function refreshQuery() {
    if (!availabilityAllowed()) {
      blockAvailability();
      return;
    }
    const id = lastQueryId;
    if (!id || busy) return;
    stopPolling();
    setBusy(true);
    $("availability-refresh").hidden = true;
    try {
      await readQuery(id, Date.now());
    } catch {
      readFailed(id);
    }
  }

  async function initialize() {
    const form = $("availability-form");
    if (!form || initialized) return;
    initialized = true;
    setBusy(true);
    $("availability-mode").addEventListener("change", modeChanged);
    form.addEventListener("submit", (event) => submitQuery(event).catch(() =>
      showResult("Availability query could not be started. Contact support if this continues.", true)));
    $("availability-refresh").addEventListener("click", () => refreshQuery().catch(() =>
      showResult("Availability status could not be read.", true)));
    if (!availabilityAllowed()) {
      blockAvailability();
      return;
    }

    try {
      const [tas, locations] = await Promise.all([
        loadReferences(TABLE.ta),
        loadReferences(TABLE.location)
      ]);
      if (!availabilityAllowed()) {
        blockAvailability();
        return;
      }
      $("availability-ta").dataset.nameField = TABLE.ta.name;
      $("availability-location").dataset.nameField = TABLE.location.name;
      fillSelect($("availability-ta"), tas, "Select a TA");
      fillSelect($("availability-location"), locations, "Select a room / location");
      for (const record of tas) referenceIds.ta.add(record[TABLE.ta.id].replace(/[{}]/g, ""));
      for (const record of locations) referenceIds.location.add(record[TABLE.location.id].replace(/[{}]/g, ""));
      ready = true;
      setBusy(false);
      modeChanged();
    } catch {
      showResult("TA or Location references could not be loaded.", true);
      formControls().forEach((control) => { control.disabled = true; });
    }
  }

  window.BsoRsAvailabilityQuery = Object.freeze({ initialize });
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => initialize().catch(() =>
      showResult("Availability panel could not be initialized.", true)), { once: true });
  } else {
    initialize().catch(() => showResult("Availability panel could not be initialized.", true));
  }
})();
