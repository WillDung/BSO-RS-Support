const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "solutions", "CandidateConsole",
  "WebResources", "os_", "bso", "candidate-console.js"), "utf8");
const html = fs.readFileSync(path.join(__dirname, "..", "solutions", "CandidateConsole",
  "WebResources", "os_", "bso", "candidate-console.html"), "utf8");

function extract(startText, endText = "\n  }") {
  const start = source.indexOf(startText);
  const end = source.indexOf(endText, start) + endText.length;
  assert.ok(start >= 0 && end > start);
  return source.slice(start, end);
}

function harness(singleUserDev = false) {
  const elements = new Map(), notices = [], requests = [], reads = [], dialogs = [], errors = [], timers = [];
  const candidateId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const taId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  function element(id) {
    if (!elements.has(id)) elements.set(id, {
      id, value: "", children: [], hidden: false, disabled: false,
      dataset: {}, replaceChildren(...children) { this.children = children; },
      appendChild(child) { this.children.push(child); },
      listeners: new Map(),
      addEventListener(type, listener) {
        if (!this.listeners.has(type)) this.listeners.set(type, []);
        this.listeners.get(type).push(listener);
      },
      dispatch(type) { for (const listener of this.listeners.get(type) || []) listener({ target: this }); },
      reset() {}, focus() {}, scrollIntoView() {}
    });

    return elements.get(id);
  }
  let correlationSequence = 0;
  const context = {
    busy: false, referencesReady: true, workspaceReady: true,
    referenceMode: singleUserDev ? "CONFIGURED" : "NORMAL",
    environmentPolicy: { allowed: true, syntheticDataOnly: singleUserDev,
      candidateOperationMode: singleUserDev ? "SingleUserDev" : "BsoSynthetic" },
    selectedCandidate: { os_sr_candid: candidateId, os_sr_cand_stat: 100010002,
      _os_sr_cand_ta_value: taId },
    selectedSchedule: null, proposedSchedule: null, scheduleRows: [],
    scheduleMode: "new", scheduleRetryBlockedCandidateId: null,
    round1Availability: { generation: 0, capabilityGeneration: 0, providerOperational: false,
      manualSchedulingOperational: false, checking: false, evidence: null, correlationId: null, state: "Idle" },
    window: { clearTimeout() {}, setTimeout(fn, delay) {
      if (delay === 2000) queueMicrotask(fn);
      else timers.push(fn);
      return timers.length + 1;
    } },
    AVAILABILITY_POLL_INTERVAL_MS: 2000,
    AVAILABILITY_POLL_ATTEMPTS: 60,
    currentUserId: () => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    newCorrelationId: () => `dddddddd-dddd-4ddd-8ddd-${String(++correlationSequence).padStart(12, "0")}`,
    $: element,
    document: { createElement: (tag) => ({
      tagName: tag.toUpperCase(), dataset: {}, listeners: new Map(), disabled: false,
      addEventListener(type, listener) {
        if (!this.listeners.has(type)) this.listeners.set(type, []);
        this.listeners.get(type).push(listener);
      },
      setAttribute(name, value) { this[name] = value; },
      dispatch(type) { for (const listener of this.listeners.get(type) || []) listener({ target: this }); }
    }), querySelectorAll: () => [element("save-schedule")] },
    showNotice: (...args) => notices.push(args), hideNotice() {},
    isCandidateCoreEnabled: () => true, isCandidateAllowedByDataMode: () => true,
    isDevFallbackEnabled: () => true, canManageSchedule: () => false,
    isActiveSchedule: () => true, updateCandidatePagination() {},
    logSafeFailure: (...args) => errors.push(args),
    xrm: () => ({ Navigation: { openAlertDialog: async (value) => dialogs.push(value.text) } }),
    reply: () => ({ schemaVersion: 1, providerOperational: false, manualSchedulingOperational: true }),
    sendCandidateCoreRequest: async (...args) => {
      reads.push(args);
      return { result: { ResultCode: "AvailabilityRead", ScopedData: JSON.stringify(await context.reply(...args)) } };
    },
    getActiveReference: async () => ({}), refreshCoreCandidate: async () => {},
    reportCandidateCoreFailure: async (...args) => errors.push(args),
    invokeCandidateCore: async (...args) => {
      if (args[3]) args[3]();
      requests.push(args);
      throw new Error("UNEXPECTED_WRITE");
    }
  };
  vm.createContext(context);
  vm.runInContext([
    extract("  const STATUS = {", "\n  };"),
    extract("  const TABLES = {", "\n  };"),
    'TABLES.candidate.id = "os_sr_candid";',
    extract("  const ROUND1_AVAILABILITY_STATE = Object.freeze({", "\n  });"),
    extract("  function addOption("),
    extract("  function setLookupPlaceholder("),
    extract("  function normalizeGuid("),
    extract("  function sameOptionalGuid("),
    extract("  function assertCandidateCoreStatus("),
    extract("  function requiresTrustedScheduleAvailability("),
    ...["round1GridIntervals", "renderRound1SlotGrid", "setRound1AvailabilityState",
      "isManualRound1Scheduling", "manualRound1Selection", "round1SchedulingMethodChanged",
      "invalidateRound1Availability", "round1Selection", "selectedVerifiedRound1Slot",
      "updateRound1AvailabilityControls", "validateRound1Availability", "round1SelectionChanged",
      "selectRound1Slot", "round1InterviewTypeChanged"].map((name) => extract(`  function ${name}(`)),
    ...["readRound1Availability", "loadRound1SchedulingCapabilities", "pollRound1Availability",
      "checkRound1Availability",
      "saveNormalRound1Schedule"].map((name) => extract(`  async function ${name}(`)),
    extract("  function configureSchedulingAvailability("),
    extract("  function setBusy("),
    extract("  function showSchedulingPanel("),
    extract("  async function createScheduleThroughCore("),
    extract("  async function createSchedule(")
  ].join("\n"), context);
  return { context, element, notices, requests, reads, dialogs, errors, timers, taId };
}

test("scheduling controls follow the unified order with one date and disabled booking confirmation", () => {
  const positions = [
    'id="scheduling-interview-type"', 'id="scheduling-date"', 'id="scheduling-location-field"',
    'id="scheduling-ta"', 'id="scheduling-availability-status"', 'id="scheduling-slot-grid"',
    'id="scheduling-booking-confirm"'
  ].map((id) => html.indexOf(id));
  assert.ok(positions.every((position) => position >= 0));
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
  assert.equal((html.match(/type="date"/g) || []).length, 1);
  assert.match(html, /id="scheduling-booking-confirm"[^>]*disabled/);
});

test("NORMAL scheduling defaults assigned TA and disables manual times and unverified slots", () => {
  const ui = harness();
  ui.context.showSchedulingPanel();
  assert.equal(ui.element("scheduling-ta").value, ui.taId);
  assert.equal(ui.element("scheduling-location-label").textContent, "Meeting Room");
  assert.equal(ui.element("scheduling-location-field").hidden, true);
  assert.equal(ui.element("scheduling-location").required, false);
  assert.equal(ui.element("scheduling-availability").hidden, false);
  assert.equal(ui.element("scheduling-slot-field").hidden, false);
  assert.equal(ui.element("scheduling-slot").disabled, true);
  assert.equal(ui.element("scheduling-slot-grid").children.length, 0);
  assert.equal(ui.element("scheduling-check-availability").disabled, true);
  assert.equal(ui.element("scheduling-booking-confirm").disabled, true);
  for (const id of ["scheduling-time", "scheduling-end-time"]) {
    assert.equal(ui.element(id).disabled, true);
    assert.equal(ui.element(id).required, false);
    assert.equal(ui.element(`${id}-field`).hidden, true);
  }
  for (const busy of [true, false, false]) {
    ui.context.setBusy(busy);
    assert.equal(ui.element("save-schedule").disabled, true);
  }
  assert.equal(ui.requests.length, 0);
});

function readySelection(ui) {
  const date = new Date(Date.now() + 2 * 86400000);
  while ([0, 6].includes(date.getUTCDay())) date.setUTCDate(date.getUTCDate() + 1);
  ui.element("scheduling-interview-type").value = "offline";
  ui.element("scheduling-date").value = date.toISOString().slice(0, 10);
  ui.element("scheduling-location").value = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
  ui.element("scheduling-ta").value = ui.taId;
  ui.context.round1Availability.providerOperational = true;
  return ui.context.round1Selection();
}

function envelope(selection, correlationId, slots = true) {
  const now = Date.now();
  return { schemaVersion: 1, state: "Ready", queryId: correlationId, ...selection, correlationId,
    evidenceId: "ffffffff-ffff-4fff-8fff-ffffffffffff",
    observedAtUtc: new Date(now - 1000).toISOString(),
    expiresAtUtc: new Date(now + 60000).toISOString(),
    slots: slots ? [{ startUtc: selection.startUtc,
      endUtc: new Date(Date.parse(selection.startUtc) + 1800000).toISOString(),
      evidenceCorrelationId: correlationId }] : [] };
}

test("provider-backed response enables one slot, derives times and invalidates on reference change or expiry", async () => {
  const ui = harness();
  readySelection(ui);
  ui.context.reply = (_, inputs, correlationId) => envelope(ui.context.round1Selection(), correlationId);
  await ui.context.checkRound1Availability();
  assert.equal(ui.element("scheduling-slot").disabled, false);
  assert.equal(ui.element("save-schedule").disabled, true);
  const availableButton = ui.element("scheduling-slot-grid").children.find((button) => !button.disabled);
  assert.ok(availableButton);
  assert.equal(availableButton.textContent, "09:00 - 09:30 (Available)");
  availableButton.dispatch("click");
  assert.equal(ui.element("scheduling-time").value, "09:00");
  assert.equal(ui.element("scheduling-end-time").value, "09:30");
  assert.equal(ui.element("save-schedule").disabled, false);
  assert.equal(ui.element("scheduling-booking-confirm").disabled, true);
  ui.timers.at(-1)();
  assert.equal(ui.element("save-schedule").disabled, true);
  assert.equal(ui.context.round1Availability.evidence, null);
  assert.match(ui.element("scheduling-availability-status").textContent, /expired/);
});

test("loading, no-slots, provider-error and late-response states fail closed", async () => {
  const ui = harness();
  const selection = readySelection(ui);
  let release;
  ui.context.reply = (_, inputs, correlationId) => new Promise((resolve) => {
    release = () => resolve(envelope(selection, correlationId));
  });

  const pending = ui.context.checkRound1Availability();
  assert.equal(ui.element("scheduling-slot").disabled, true);
  assert.equal(ui.element("scheduling-check-availability").disabled, true);
  assert.match(ui.element("scheduling-availability-status").textContent, /Checking availability/);
  assert.equal(ui.context.round1Availability.state, "Pending");
  assert.ok(ui.element("scheduling-slot-grid").children.every((button) => button.dataset.state === "pending"));
  ui.element("scheduling-date").value = "";
  ui.context.round1SelectionChanged();
  release();
  await pending;
  assert.equal(ui.context.round1Availability.evidence, null);
  readySelection(ui);
  ui.context.reply = (_, inputs, correlationId) => envelope(ui.context.round1Selection(), correlationId, false);
  await ui.context.checkRound1Availability();
  assert.match(ui.element("scheduling-availability-status").textContent, /No verified free intervals/);
  assert.equal(ui.element("scheduling-slot").disabled, true);
  ui.context.reply = () => { throw new Error("PROVIDER_FAILED"); };
  await ui.context.checkRound1Availability();
  assert.match(ui.element("scheduling-availability-status").textContent, /provider error/);
  assert.equal(ui.context.round1Availability.evidence, null);
  assert.equal(ui.context.round1Availability.state, "Failed");
  assert.ok(ui.element("scheduling-slot-grid").children.every((button) => button.disabled));
});

test("Online hides and clears Room, remains non-bookable, and Offline requires Room", async () => {
  const ui = harness();
  readySelection(ui);
  ui.element("scheduling-location").value = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
  ui.context.round1Availability.providerOperational = true;
  ui.context.round1InterviewTypeChanged();
  ui.element("scheduling-interview-type").value = "online";
  ui.context.round1InterviewTypeChanged();
  assert.equal(ui.element("scheduling-location-field").hidden, true);
  assert.equal(ui.element("scheduling-location").required, false);
  assert.equal(ui.element("scheduling-location").value, "");
  assert.equal(ui.element("scheduling-check-availability").disabled, true);
  assert.equal(ui.element("scheduling-booking-confirm").disabled, true);
  const before = ui.reads.filter(([action]) => action === "GetRound1Availability").length;
  await ui.context.checkRound1Availability();
  assert.equal(ui.reads.filter(([action]) => action === "GetRound1Availability").length, before);
  assert.match(ui.element("scheduling-availability-status").textContent, /Online scheduling is disabled/);
  ui.element("scheduling-interview-type").value = "offline";
  ui.context.round1InterviewTypeChanged();
  assert.equal(ui.element("scheduling-location-field").hidden, false);
  assert.equal(ui.element("scheduling-location").required, true);
  assert.equal(ui.element("scheduling-location").value, "");
  assert.equal(ui.element("scheduling-check-availability").disabled, true);
});

test("Online submission is rejected before either scheduling write path", async () => {
  const ui = harness();
  readySelection(ui);
  ui.element("scheduling-interview-type").value = "online";
  await ui.context.createSchedule({ preventDefault() {} });
  await ui.context.createScheduleThroughCore({ preventDefault() {} });
  assert.equal(ui.requests.length, 0);
  assert.equal(ui.reads.filter(([action]) => action === "GetRound1Availability").length, 0);
  assert.equal(ui.notices.length, 2);
  assert.ok(ui.notices.every(([message]) => /Online scheduling is disabled/.test(message)));
});

test("grid builds exactly sixteen Ho Chi Minh 30-minute weekday intervals", () => {
  const ui = harness();
  const intervals = ui.context.round1GridIntervals("2026-11-23");
  assert.equal(intervals.length, 16);
  assert.equal(JSON.stringify(intervals.slice(0, 2).map(({ startLabel, endLabel }) => [startLabel, endLabel])),
    JSON.stringify([["09:00", "09:30"], ["09:30", "10:00"]]));
  assert.deepEqual([intervals.at(-1).startLabel, intervals.at(-1).endLabel], ["16:30", "17:00"]);
  assert.ok(intervals.every((interval) => Date.parse(interval.endUtc) - Date.parse(interval.startUtc) === 1800000));
  assert.equal(ui.context.round1GridIntervals("2026-11-21").length, 0);
  assert.equal(ui.context.round1GridIntervals("2026-02-31").length, 0);
});

test("only complete provider-verified Room and TA intersections are selectable; other intervals stay Unknown", async () => {
  const ui = harness();
  const selection = readySelection(ui);
  const freeSlot = { startUtc: new Date(Date.parse(selection.startUtc) + 3600000).toISOString(),
    endUtc: new Date(Date.parse(selection.startUtc) + 5400000).toISOString() };
  ui.context.reply = (_, inputs, correlationId) => ({
    ...envelope(selection, correlationId, false), slots: [{ ...freeSlot, evidenceCorrelationId: correlationId }]
  });
  await ui.context.checkRound1Availability();
  const buttons = ui.element("scheduling-slot-grid").children;
  assert.equal(buttons.length, 16);
  assert.equal(buttons.filter((button) => button.dataset.state === "available").length, 1);
  assert.equal(buttons.filter((button) => button.dataset.state === "unknown").length, 15);
  assert.ok(buttons.filter((button) => button.dataset.state === "unknown").every((button) => button.disabled));
  assert.equal(ui.context.round1Availability.state, "Available");
  assert.equal(ui.element("scheduling-booking-confirm").disabled, true);
});

test("type, date, Room and TA changes invalidate evidence and clear selected slots", async () => {
  const mutations = [
    (ui) => {
      ui.element("scheduling-interview-type").value = "online";
      ui.context.round1InterviewTypeChanged();
    },
    (ui) => {
      const nextDate = new Date(`${ui.element("scheduling-date").value}T12:00:00+07:00`);
      nextDate.setUTCDate(nextDate.getUTCDate() + 1);
      ui.element("scheduling-date").value = nextDate.toISOString().slice(0, 10);
      ui.context.round1SelectionChanged();
    },
    (ui) => {
      ui.element("scheduling-location").value = "ffffffff-ffff-4fff-8fff-ffffffffffff";
      ui.context.round1SelectionChanged();
    },
    (ui) => {
      ui.element("scheduling-ta").value = "99999999-9999-4999-8999-999999999999";
      ui.context.round1SelectionChanged();
    }
  ];
  for (const mutate of mutations) {
    const ui = harness();
    readySelection(ui);
    ui.context.reply = (_, inputs, correlationId) => envelope(ui.context.round1Selection(), correlationId);
    await ui.context.checkRound1Availability();
    ui.element("scheduling-slot").value = ui.context.round1Availability.evidence.slots[0].startUtc;
    const generation = ui.context.round1Availability.generation;
    mutate(ui);
    assert.ok(ui.context.round1Availability.generation > generation);
    assert.equal(ui.context.round1Availability.evidence, null);
    assert.equal(ui.context.round1Availability.correlationId, null);
    assert.equal(ui.element("scheduling-slot").value, "");
    assert.equal(ui.element("scheduling-slot-grid").children.every((button) => button.disabled), true);
    assert.equal(ui.element("scheduling-booking-confirm").disabled, true);
  }
});

test("async availability polls one correlated request until Ready", async () => {
  const ui = harness();
  const selection = readySelection(ui);
  const requests = [];
  ui.context.reply = (action, inputs, correlationId) => {
    requests.push({ action, inputs, correlationId });
    return requests.length === 1
      ? { schemaVersion: 1, state: "Pending", queryId: correlationId, slots: [] }
      : envelope(selection, correlationId);
  };
  await ui.context.checkRound1Availability();
  assert.equal(requests.length, 2);
  assert.ok(requests.every((request) => request.action === "GetRound1Availability"));
  assert.equal(requests[0].correlationId, requests[1].correlationId);
  assert.equal(ui.context.round1Availability.evidence.queryId, requests[0].correlationId);
  assert.equal(ui.element("scheduling-slot").disabled, false);
});

test("async availability displays provider failures and bounds Pending polling", async () => {
  for (const state of ["Failed", "Expired"]) {
    const ui = harness();
    readySelection(ui);
    ui.context.reply = (_, inputs, correlationId) => ({
      schemaVersion: 1, state, queryId: correlationId,
      errorCode: "AVAILABILITY_RESULT_UNTRUSTED", slots: []
    });
    await ui.context.checkRound1Availability();
    assert.equal(ui.context.round1Availability.evidence, null);
    assert.match(ui.element("scheduling-availability-status").textContent,
      state === "Failed" ? /AVAILABILITY_RESULT_UNTRUSTED/ : /expired/);
  }

  const pending = harness();
  readySelection(pending);
  const requests = [];
  pending.context.reply = (_, inputs, correlationId) => {
    requests.push(correlationId);
    return { schemaVersion: 1, state: "Pending", queryId: correlationId, slots: [] };
  };
  await pending.context.checkRound1Availability();
  assert.equal(requests.length, 60);
  assert.ok(requests.every((correlationId) => correlationId === requests[0]));
  assert.match(pending.element("scheduling-availability-status").textContent, /timed out/);
  assert.equal(pending.context.round1Availability.evidence, null);
});

test("Room/Date/TA changes do not discard an in-flight capability response for the same Candidate", async () => {
  const ui = harness();
  let release;
  ui.context.reply = () => new Promise((resolve) => { release = resolve; });
  const pending = ui.context.loadRound1SchedulingCapabilities();
  ui.context.round1SelectionChanged();
  release({ schemaVersion: 1, providerOperational: true, manualSchedulingOperational: true });
  await pending;
  readySelection(ui);
  ui.context.updateRound1AvailabilityControls();
  assert.equal(ui.element("scheduling-check-availability").disabled, false);
});

test("strict envelope rejects stale, mismatched, overlapping and partial slots", () => {
  const ui = harness();
  const selection = readySelection(ui), correlationId = ui.context.newCorrelationId();
  const invalid = [
    { ...envelope(selection, correlationId), roomId: ui.taId },
    { ...envelope(selection, correlationId), expiresAtUtc: new Date(Date.now() - 1).toISOString() },
    { ...envelope(selection, correlationId), correlationId: ui.taId },
    { ...envelope(selection, correlationId), slots: [{ ...envelope(selection, correlationId).slots[0],
      endUtc: new Date(Date.parse(selection.startUtc) + 900000).toISOString() }] }
  ];
  const overlapping = envelope(selection, correlationId);
  overlapping.slots.push(overlapping.slots[0]);
  invalid.push(overlapping);
  for (const data of invalid) {
    assert.throws(() => ui.context.validateRound1Availability(data, selection, correlationId), /AVAILABILITY_/);
  }
});

test("confirmed save sends exact refs, derived times and Notes, then verifies readback before one dialog", async () => {
  const ui = harness();
  const selection = readySelection(ui);
  const availabilityRequests = [];
  ui.context.reply = (action, inputs, correlationId) => {
    availabilityRequests.push({ action, inputs, correlationId });
    return envelope(selection, correlationId);
  };
  await ui.context.checkRound1Availability();
  const slot = ui.context.round1Availability.evidence.slots[0];
  ui.element("scheduling-slot").value = slot.startUtc;
  ui.element("scheduling-notes").value = "Synthetic <safe> notes";
  ui.context.invokeCandidateCore = async (action, inputs, correlationId) => {
    ui.requests.push({ action, inputs, correlationId });
    return { result: { ResultCode: "Applied", CurrentStatus: 100010003, StatusHistoryId: ui.taId } };
  };
  ui.context.refreshCoreCandidate = async () => {
    ui.context.selectedCandidate.os_sr_cand_stat = 100010003;
    ui.context.scheduleRows = [{
      _os_sr_intv_ta_value: selection.taId, _os_sr_intv_loc_value: selection.roomId,
      os_sr_intv_strt: slot.startUtc, os_sr_intv_end: slot.endUtc, os_sr_intv_nts: "Synthetic <safe> notes"
    }];
  };
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
  assert.equal(availabilityRequests.length, 2);
  assert.notEqual(availabilityRequests[0].correlationId, availabilityRequests[1].correlationId);
  assert.equal(ui.requests[0].correlationId, availabilityRequests[1].correlationId);
  assert.equal(ui.requests[0].inputs.Notes, "Synthetic <safe> notes");
  assert.equal(ui.requests[0].inputs.StartAt, slot.startUtc);
  assert.equal(ui.requests[0].inputs.InterviewerId, selection.taId);
  assert.equal(ui.requests[0].inputs.LocationId, selection.roomId);
  assert.deepEqual(ui.dialogs, ["Schedule saved successfully."]);
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
  assert.equal(ui.dialogs.length, 1);
});

test("HTTP failure or mismatched persisted schedule never shows success and blocks blind resubmission", async () => {
  for (const failedResponse of [true, false]) {
    const ui = harness();
    const selection = readySelection(ui);
    ui.context.reply = (_, inputs, correlationId) => envelope(selection, correlationId);
    await ui.context.checkRound1Availability();
    ui.element("scheduling-slot").value = ui.context.round1Availability.evidence.slots[0].startUtc;
    ui.context.invokeCandidateCore = async (_action, _inputs, _correlationId, onDispatch) => {
      onDispatch();
      if (failedResponse) throw new Error("HTTP_ERROR");
      return { result: { CurrentStatus: 100010003, StatusHistoryId: ui.taId } };
    };
    await ui.context.createSchedule({ preventDefault() {} });
    assert.equal(ui.dialogs.length, 0);
    assert.equal(ui.context.scheduleRetryBlockedCandidateId, selection.candidateId);
    assert.equal(ui.element("save-schedule").disabled, true);
  }
});

test("forced NORMAL Core or DEV-fallback form submission cannot bypass unavailable evidence", async () => {
  const ui = harness();
  ui.element("scheduling-time").value = "09:00";
  ui.element("scheduling-end-time").value = "09:30";
  ui.element("scheduling-slot").value = "fabricated-slot";
  for (const handler of ["createSchedule", "createScheduleThroughCore"]) {
    let prevented = false;
    await ui.context[handler]({ preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
  }
  assert.equal(ui.requests.length, 0);
  assert.equal(ui.notices.length, 2);
  assert.ok(ui.notices.every(([message, error]) => error && message.startsWith("Schedule not saved.")));
});

test("SingleUserDev retains the existing manual scheduling controls", () => {
  const ui = harness(true);
  ui.context.showSchedulingPanel();
  assert.equal(ui.element("save-schedule").disabled, true);
  ui.element("scheduling-interview-type").value = "offline";
  ui.context.round1InterviewTypeChanged();
  assert.equal(ui.element("scheduling-availability").hidden, true);
  assert.equal(ui.element("scheduling-slot-field").hidden, true);
  assert.equal(ui.element("scheduling-dev-note").hidden, false);
  assert.equal(ui.element("scheduling-location-label").textContent, "Meeting Room");
  assert.equal(ui.element("scheduling-location-field").hidden, false);
  assert.equal(ui.element("scheduling-location").required, true);
  assert.equal(ui.element("save-schedule").disabled, false);
  for (const id of ["scheduling-time", "scheduling-end-time"]) {
    assert.equal(ui.element(id).disabled, false);
    assert.equal(ui.element(id).required, true);
    assert.equal(ui.element(`${id}-field`).hidden, false);
  }
  assert.equal(ui.element("save-schedule").disabled, false);
  assert.equal(ui.requests.length, 0);
});

test("non-synthetic configured mode cannot bypass the NORMAL availability gate", async () => {
  const ui = harness();
  ui.context.referenceMode = "CONFIGURED";
  await ui.context.createSchedule({ preventDefault() {} });
  ui.context.setBusy(false);
  assert.equal(ui.element("save-schedule").disabled, true);
  assert.equal(ui.requests.length, 0);
  assert.equal(ui.notices.length, 1);
});

test("manual fallback requires verified capability, explicit method and future SE Asia inputs", async () => {
  const ui = harness();
  readySelection(ui);
  ui.context.round1Availability.providerOperational = false;
  ui.element("scheduling-method").value = "manual";
  ui.context.round1SchedulingMethodChanged();
  ui.element("scheduling-time").value = "09:00";
  ui.element("scheduling-end-time").value = "10:00";
  ui.context.updateRound1AvailabilityControls();
  assert.equal(ui.element("save-schedule").disabled, true);
  await ui.context.loadRound1SchedulingCapabilities();
  assert.equal(ui.element("scheduling-manual-warning").hidden, false);
  assert.equal(ui.element("scheduling-availability").hidden, true);
  assert.equal(ui.element("scheduling-slot-field").hidden, true);
  assert.equal(ui.element("scheduling-time").required, true);
  assert.equal(ui.element("save-schedule").disabled, false);
  assert.equal(ui.element("scheduling-check-availability").disabled, true);
  assert.equal(ui.context.round1Availability.evidence, null);
  assert.equal(ui.context.manualRound1Selection().startUtc,
    `${ui.element("scheduling-date").value}T02:00:00.000Z`);
  ui.element("scheduling-end-time").value = "08:30";
  ui.context.updateRound1AvailabilityControls();
  assert.equal(ui.element("save-schedule").disabled, true);
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 0);
  ui.element("scheduling-method").value = "automatic";
  ui.context.round1SchedulingMethodChanged();
  assert.equal(ui.element("scheduling-time").value, "");
  assert.equal(ui.element("scheduling-time").disabled, true);
  assert.equal(ui.element("save-schedule").disabled, true);
});

test("manual Save uses a distinct action, preserves Notes and confirms persistence before success", async () => {
  const ui = harness();
  const selection = readySelection(ui);
  ui.context.round1Availability.providerOperational = false;
  await ui.context.loadRound1SchedulingCapabilities();
  ui.element("scheduling-method").value = "manual";
  ui.context.round1SchedulingMethodChanged();
  ui.element("scheduling-time").value = "09:00";
  ui.element("scheduling-end-time").value = "10:00";
  const notes = "  Synthetic manual notes\r\n<literal text>  ";
  ui.element("scheduling-notes").value = notes;
  let release;
  ui.context.invokeCandidateCore = async (action, inputs, correlationId) => {
    ui.requests.push({ action, inputs, correlationId });
    await new Promise((resolve) => { release = resolve; });
    return { result: { ResultCode: "Applied", CurrentStatus: 100010003, StatusHistoryId: ui.taId } };
  };
  ui.context.refreshCoreCandidate = async () => {
    const inputs = ui.requests[0].inputs;
    ui.context.selectedCandidate.os_sr_cand_stat = 100010003;
    ui.context.scheduleRows = [{
      _os_sr_intv_ta_value: selection.taId, _os_sr_intv_loc_value: selection.roomId,
      os_sr_intv_strt: inputs.StartAt, os_sr_intv_end: inputs.EndAt, os_sr_intv_nts: notes
    }];
  };
  const pending = ui.context.createSchedule({ preventDefault() {} });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(ui.element("scheduling-time").disabled, true);
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
  assert.equal(ui.dialogs.length, 0);
  assert.equal(ui.requests[0].action, "RecordManualRound1Schedule");
  assert.equal(ui.requests[0].inputs.Notes, notes);
  assert.equal(ui.requests[0].inputs.StartAt, `${selection.date}T02:00:00.000Z`);
  assert.equal(ui.requests[0].inputs.EndAt, `${selection.date}T03:00:00.000Z`);
  release();
  await pending;
  assert.deepEqual(ui.dialogs, ["Schedule saved successfully."]);
  assert.ok(ui.notices.some(([text]) => text.includes("Manual Scheduling \u2014 availability not checked")));
  assert.equal(ui.reads.filter(([action]) => action === "GetRound1Availability").length, 0);
});

test("uncertain manual persistence never reports success or retries through the automatic path", async () => {
  const ui = harness();
  readySelection(ui);
  ui.context.round1Availability.providerOperational = false;
  await ui.context.loadRound1SchedulingCapabilities();
  ui.element("scheduling-method").value = "manual";
  ui.context.round1SchedulingMethodChanged();
  ui.element("scheduling-time").value = "09:00";
  ui.element("scheduling-end-time").value = "10:00";
  await ui.context.createSchedule({ preventDefault() {} });
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
  assert.equal(ui.requests[0][0], "RecordManualRound1Schedule");
  assert.equal(ui.dialogs.length, 0);
  assert.equal(ui.element("save-schedule").disabled, true);
});

async function manualTransportHarness(response) {
  const ui = harness();
  const selection = readySelection(ui);
  await ui.context.loadRound1SchedulingCapabilities();
  ui.element("scheduling-method").value = "manual";
  ui.context.round1SchedulingMethodChanged();
  ui.element("scheduling-time").value = "09:00";
  ui.element("scheduling-end-time").value = "10:00";
  ui.context.environmentPolicy.candidateOperationMode = "NORMAL";
  ui.context.refreshCandidates = async () => {};
  ui.context.openCandidate = async () => true;
  ui.context.fetch = async (url, options) => {
    assert.equal(url, "/api/data/v9.2/os_sr_cact");
    ui.requests.push(JSON.parse(options.body));
    if (response instanceof Error) throw response;
    return response;
  };
  vm.runInContext([
    extract("  const CORE_API_ACTIONS = new Set([", "\n  ]);"),
    extract("  const CORE_API_PARAMETER_NAMES = new Set([", "\n  ]);"),
    extract("  async function sendCandidateCoreRequest("),
    extract("  async function invokeCandidateCore("),
    extract("  async function reportCandidateCoreFailure(")
  ].join("\n"), ui.context);
  return { ...ui, selection };
}

test("real manual transport retains HTTP, safe schedule stage and correlation without retrying", async () => {
  const ui = await manualTransportHarness({
    ok: false, status: 400,
    text: async () => JSON.stringify({ error: {
      code: "0x80040265",
      message: "DATAVERSE_OPERATION_REJECTED:CC_CREATE_INTERVIEW_SCHEDULE:0x80040265"
    } })
  });
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
  assert.equal(ui.requests[0].ActionType, "RecordManualRound1Schedule");
  assert.equal(ui.requests[0].CandidateId, ui.selection.candidateId);
  assert.equal(ui.requests[0].LocationId, ui.selection.roomId);
  assert.equal(ui.requests[0].InterviewerId, ui.selection.taId);
  assert.equal(ui.requests[0].StartAt, `${ui.selection.date}T02:00:00.000Z`);
  assert.equal(ui.requests[0].EndAt, `${ui.selection.date}T03:00:00.000Z`);
  const message = ui.notices.at(-1)[0];
  assert.match(message, /HTTP 400/);
  assert.match(message, /CC_CREATE_INTERVIEW_SCHEDULE:0x80040265/);
  assert.ok(message.includes(ui.requests[0].CorrelationId));
  assert.equal(ui.dialogs.length, 0);
  assert.equal(ui.context.scheduleRetryBlockedCandidateId, ui.selection.candidateId);
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
});

test("real transport preflight rejection does not falsely mark a manual mutation as dispatched", async () => {
  const ui = await manualTransportHarness();
  ui.context.environmentPolicy.syntheticDataOnly = true;
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 0);
  assert.equal(ui.context.scheduleRetryBlockedCandidateId, null);
  assert.match(ui.notices.at(-1)[0], /Schedule was not submitted/);
  assert.equal(ui.dialogs.length, 0);
});

test("manual failure feedback excludes raw provider text and preserves non-JSON HTTP status", async () => {
  for (const rawMessage of ["Synthetic private name synthetic@example.invalid", null]) {
    const ui = await manualTransportHarness({
      ok: false, status: 503,
      text: async () => rawMessage === null ? "<html>private upstream failure</html>"
        : JSON.stringify({ error: { code: "0x80040265", message: rawMessage } })
    });
    await ui.context.createSchedule({ preventDefault() {} });
    const message = ui.notices.at(-1)[0];
    assert.match(message, /HTTP 503/);
    assert.doesNotMatch(message, /synthetic@example|private|<html>/);
    assert.equal(ui.dialogs.length, 0);
    assert.equal(ui.context.scheduleRetryBlockedCandidateId, ui.selection.candidateId);
  }
});

test("real manual transport network failure remains ambiguous and never resubmits automatically", async () => {
  const ui = await manualTransportHarness(new Error("Synthetic private upstream connection detail"));
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.context.scheduleRetryBlockedCandidateId, ui.selection.candidateId);
  assert.match(ui.notices.at(-1)[0], /Reconcile/);
  assert.doesNotMatch(ui.notices.at(-1)[0], /private upstream/);
  assert.equal(ui.dialogs.length, 0);
  await ui.context.createSchedule({ preventDefault() {} });
  assert.equal(ui.requests.length, 1);
});

test("manual disabled feedback identifies missing Room and past Start without automatic validation", async () => {
  const ui = await manualTransportHarness();
  ui.context.Date = class extends Date {
    static now() { return Date.parse("2026-11-18T05:36:36.815Z"); }
  };
  ui.element("scheduling-date").value = "2026-11-18";
  ui.element("scheduling-time").value = "12:33";
  ui.element("scheduling-end-time").value = "13:33";
  ui.element("scheduling-location").value = "";
  ui.context.updateRound1AvailabilityControls();
  assert.equal(ui.element("save-schedule").disabled, true);
  assert.match(ui.element("scheduling-validation-status").textContent, /Meeting Room/);
  assert.match(ui.element("scheduling-validation-status").textContent, /Start Time.*future/);
  ui.element("scheduling-location").value = ui.selection.roomId;
  ui.element("scheduling-time").value = "13:03";
  ui.element("scheduling-end-time").value = "13:20";
  ui.context.round1Selection = () => { throw new Error("AUTOMATIC_VALIDATION_MUST_NOT_RUN"); };
  ui.context.updateRound1AvailabilityControls();
  assert.equal(ui.element("save-schedule").disabled, false);
  assert.match(ui.element("scheduling-validation-status").textContent, /Ready.*availability not checked/);
  assert.equal(ui.context.round1Availability.providerOperational, false);
  assert.equal(ui.context.round1Availability.evidence, null);
  assert.equal(ui.requests.length, 0);
});

test("each manual field and workflow gate explains why Save is disabled", async () => {
  const cases = [
    [(ui) => { ui.element("scheduling-location").value = ""; }, /Meeting Room/],
    [(ui) => { ui.element("scheduling-location").value = "invalid"; }, /Meeting Room/],
    [(ui) => { ui.element("scheduling-ta").value = "00000000-0000-0000-0000-000000000000"; }, /TA/],
    [(ui) => { ui.element("scheduling-date").value = "2030-02-31"; }, /Interview Date/],
    [(ui) => { ui.element("scheduling-time").value = ""; }, /Start Time/],
    [(ui) => { ui.element("scheduling-end-time").value = ""; }, /End Time/],
    [(ui) => { ui.element("scheduling-end-time").value = "09:00"; }, /End Time.*later/],
    [(ui) => { ui.context.selectedCandidate.os_sr_candid = "invalid"; }, /Candidate/],
    [(ui) => { ui.context.selectedCandidate.os_sr_cand_stat = 100010003; }, /Waiting Manual Scheduling/],
    [(ui) => { ui.context.isCandidateAllowedByDataMode = () => false; }, /Candidate.*data mode/],
    [(ui) => { ui.context.scheduleMode = "reschedule"; }, /Reschedule/],
    [(ui) => { ui.context.selectedSchedule = {}; }, /active Round 1 Schedule/],
    [(ui) => { ui.context.scheduleRetryBlockedCandidateId = ui.selection.candidateId; }, /reconcil/],
    [(ui) => { ui.context.round1Availability.manualSchedulingOperational = false; }, /server.*manual scheduling/i],
    [(ui) => { ui.context.busy = true; }, /request.*progress/],
    [(ui) => { ui.context.workspaceReady = false; }, /workspace/],
    [(ui) => { ui.context.referencesReady = false; }, /references/],
    [(ui) => { ui.context.isCandidateCoreEnabled = () => false; }, /Candidate Core/]
  ];
  for (const [invalidate, expected] of cases) {
    const ui = await manualTransportHarness();
    invalidate(ui);
    ui.context.updateRound1AvailabilityControls();
    assert.equal(ui.element("save-schedule").disabled, true, String(expected));
    assert.match(ui.element("scheduling-validation-status").textContent, expected);
    assert.equal(ui.requests.length, 0);
  }
});

test("actual required-field events recalculate manual Save without erasing explicit times", async () => {
  const ui = await manualTransportHarness();
  ui.context.Date = class extends Date {
    static now() { return Date.parse("2026-11-18T05:36:36.815Z"); }
  };
  const start = source.indexOf('    $("scheduling-form").addEventListener');
  const end = source.indexOf('    $("cancellation-form").addEventListener', start);
  assert.ok(start >= 0 && end > start);
  vm.runInContext(source.slice(start, end), ui.context);
  ui.element("scheduling-interview-type").value = "online";
  ui.element("scheduling-interview-type").dispatch("change");
  assert.equal(ui.element("scheduling-location-field").hidden, true);
  assert.equal(ui.element("scheduling-location").value, "");
  assert.equal(ui.element("save-schedule").disabled, true);
  ui.element("scheduling-interview-type").value = "offline";
  ui.element("scheduling-interview-type").dispatch("change");
  assert.equal(ui.element("scheduling-location-field").hidden, false);
  assert.equal(ui.element("scheduling-location").required, true);
  ui.element("scheduling-location").value = "";
  ui.context.updateRound1AvailabilityControls();
  assert.equal(ui.element("save-schedule").disabled, true);
  ui.element("scheduling-location").value = ui.selection.roomId;
  ui.element("scheduling-location").dispatch("input");
  assert.equal(ui.element("save-schedule").disabled, false);
  ui.element("scheduling-location").dispatch("change");
  assert.equal(ui.element("scheduling-time").value, "09:00");
  assert.equal(ui.element("scheduling-end-time").value, "10:00");
  ui.element("scheduling-date").value = "";
  ui.element("scheduling-date").dispatch("input");
  assert.equal(ui.element("save-schedule").disabled, true);
  ui.element("scheduling-date").value = "2026-11-21";
  ui.element("scheduling-date").dispatch("change");
  ui.element("scheduling-ta").dispatch("change");
  ui.element("scheduling-time").value = "00:05";
  ui.element("scheduling-time").dispatch("input");
  ui.element("scheduling-end-time").value = "00:22";
  ui.element("scheduling-end-time").dispatch("input");
  assert.equal(ui.element("save-schedule").disabled, false);
  assert.equal(ui.context.manualRound1Selection().startUtc, "2026-11-20T17:05:00.000Z");
  assert.equal(ui.context.manualRound1Selection().endUtc, "2026-11-20T17:22:00.000Z");
  assert.equal(ui.reads.filter(([action]) => action === "GetRound1Availability").length, 0);
  ui.element("scheduling-method").value = "automatic";
  ui.element("scheduling-method").dispatch("change");
  assert.equal(ui.element("scheduling-time").value, "");
  assert.equal(ui.element("save-schedule").disabled, true);
  assert.equal(ui.requests.length, 0);
});
