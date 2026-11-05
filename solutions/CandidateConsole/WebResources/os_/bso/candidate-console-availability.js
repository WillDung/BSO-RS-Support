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
  let lastQueryId = null;
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
    SOURCE_UNKNOWN_TA: "TA availability could not be verified.",
    SOURCE_UNKNOWN_ROOM: "Room availability could not be verified.",
    AVAILABILITY_VIEW_INVALID: "Availability data could not be verified.",
    GRAPH_AUTH: "Calendar integration authentication is unavailable.",
    GRAPH_PERMISSION: "Calendar integration does not have permission.",
    MAILBOX_NOT_FOUND: "A calendar mailbox could not be found.",
    GRAPH_THROTTLED: "Calendar service is busy. Start a new availability check later.",
    GRAPH_TIMEOUT: "Calendar availability timed out. Start a new availability check.",
    GRAPH_UNAVAILABLE: "Calendar availability is unavailable.",
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
    return Number.isNaN(date.getTime()) ? null : date;
  }

  async function getEntitySetName(logicalName) {
    const metadata = await getXrm().Utility.getEntityMetadata(logicalName);
    if (!metadata || !metadata.EntitySetName) throw new Error("REFERENCE_METADATA_UNAVAILABLE");
    return metadata.EntitySetName;
  }

  async function loadReferences(table, select) {
    const api = getXrm().WebApi;
    const query = `?$select=${[table.id, table.name].concat(select || []).join(",")}` +
      `&$filter=statecode eq 0&$orderby=${table.name} asc`;
    const records = [];
    let response = await api.retrieveMultipleRecords(table.logicalName, query);
    records.push(...(response.entities || []));
    while (response.nextLink) {
      response = await api.retrieveMultipleRecords(table.logicalName, response.nextLink);
      records.push(...(response.entities || []));
    }
    const config = window.BsoRsCandidateConsoleConfiguration || {};
    const policy = window.BsoRsCandidateConsolePolicy;
    if (!policy || typeof policy.allowsReference !== "function" ||
        typeof config.syntheticDataOnly !== "boolean") return [];
    return records.filter((record) =>
      policy.allowsReference(record[table.name], config.syntheticDataOnly));
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
  }

  function appendSlotList(json) {
    let slots;
    try {
      slots = JSON.parse(json || "");
    } catch {
      throw new Error("RESULT_INVALID");
    }
    if (!Array.isArray(slots) || !slots.length || slots.length > 200) throw new Error("RESULT_INVALID");
    let previousStart = "";
    const list = document.createElement("ol");
    for (const slot of slots) {
      if (!slot || Object.keys(slot).sort().join(",") !== "endUtc,startUtc" ||
          typeof slot.startUtc !== "string" || typeof slot.endUtc !== "string" ||
          slot.startUtc <= previousStart || Date.parse(slot.endUtc) <= Date.parse(slot.startUtc))
        throw new Error("RESULT_INVALID");
      previousStart = slot.startUtc;
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
    $("availability-result").replaceChildren(document.createTextNode("Available slots:"), list);
  }

  async function readQuery(queryId, startedAt) {
    if (queryId !== lastQueryId) return true;
    const api = getXrm().WebApi;
    const query = TABLE.query;
    const row = await api.retrieveRecord(query.logicalName, queryId,
      `?$select=${[query.state, query.reason, query.error, query.slots, query.expiresAt].join(",")}`);
    const state = row[query.state];
    if (state === STATE.pending) {
      if (Date.now() - startedAt >= MAX_POLL_MS) {
        showResult("Availability is still pending. Use Refresh status to check again.");
        $("availability-refresh").hidden = false;
        return false;
      }
      showResult("Availability query pending…");
      window.setTimeout(() => readQuery(queryId, startedAt).catch(() =>
        showResult("Availability status could not be read. Use Refresh status to try again.", true)),
      POLL_INTERVAL_MS);
      return false;
    }

    const expiration = Date.parse(row[query.expiresAt] || "");
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
      showResult(SAFE_ERRORS[row[query.error]] || "Availability could not be verified. Contact support.", true);
    } else {
      showResult("Availability result has an unknown state.", true);
    }
    return true;
  }

  async function submitQuery(event) {
    event.preventDefault();
    const form = $("availability-form");
    if (!form.reportValidity()) return;
    const config = window.BsoRsCandidateConsoleConfiguration || {};
    if (config.availabilityEnabled !== true) {
      showResult("Availability checking is not configured in this environment.", true);
      return;
    }
    const start = localVietnamToUtc($("availability-start").value);
    const end = localVietnamToUtc($("availability-end").value);
    const duration = Number($("availability-duration").value);
    if (!start || !end || start <= new Date() || end <= start ||
        !Number.isInteger(duration) || duration <= 0 || duration % 15 !== 0) {
      showResult("Enter a future Vietnam-time window and a duration in 15-minute increments.", true);
      return;
    }

    const button = $("availability-submit");
    button.disabled = true;
    lastQueryId = null;
    $("availability-refresh").hidden = true;
    showResult("Submitting availability query…");
    try {
      const xrm = getXrm();
      const payload = {
        [`${TABLE.query.ta}@odata.bind`]: `/${await getEntitySetName(TABLE.ta.logicalName)}(${$("availability-ta").value})`,
        [TABLE.query.mode]: Number($("availability-mode").value),
        [TABLE.query.start]: start.toISOString(),
        [TABLE.query.end]: end.toISOString(),
        [TABLE.query.duration]: duration
      };
      if (Number($("availability-mode").value) === MODE.onsite) {
        payload[`${TABLE.query.location}@odata.bind`] =
          `/${await getEntitySetName(TABLE.location.logicalName)}(${$("availability-location").value})`;
      }
      const created = await xrm.WebApi.createRecord(TABLE.query.logicalName, payload);
      const id = created && typeof created.id === "string" ? created.id.replace(/[{}]/g, "") : "";
      if (!id) throw new Error("QUERY_ID_MISSING");
      lastQueryId = id;
      showResult("Availability query pending…");
      await readQuery(id, Date.now());
    } catch {
      showResult("Availability query could not be started or read. Contact support if this continues.", true);
    } finally {
      button.disabled = false;
    }
  }

  async function refreshQuery() {
    const id = lastQueryId;
    if (!id) return;
    $("availability-refresh").hidden = true;
    try {
      await readQuery(id, Date.now());
    } catch {
      showResult("Availability status could not be read. Contact support if this continues.", true);
      $("availability-refresh").hidden = false;
    }
  }

  async function initialize() {
    const form = $("availability-form");
    if (!form) return;
    $("availability-mode").addEventListener("change", modeChanged);
    form.addEventListener("submit", (event) => submitQuery(event).catch(() =>
      showResult("Availability query could not be started. Contact support if this continues.", true)));
    $("availability-refresh").addEventListener("click", () => refreshQuery().catch(() =>
      showResult("Availability status could not be read.", true)));
    const config = window.BsoRsCandidateConsoleConfiguration || {};
    if (config.availabilityEnabled !== true) {
      form.querySelectorAll("input, select, button").forEach((control) => { control.disabled = true; });
      showResult("Availability checking is not configured in this environment.");
      return;
    }

    try {
      const [tas, locations] = await Promise.all([
        loadReferences(TABLE.ta, ["os_sr_ta_eml"]),
        loadReferences(TABLE.location, ["os_sr_loc_rmeml"])
      ]);
      $("availability-ta").dataset.nameField = TABLE.ta.name;
      $("availability-location").dataset.nameField = TABLE.location.name;
      fillSelect($("availability-ta"), tas, "Select a TA");
      fillSelect($("availability-location"), locations, "Select a room / location");
    } catch {
      showResult("TA or Location references could not be loaded.", true);
      form.querySelectorAll("input, select, button").forEach((control) => { control.disabled = true; });
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
