const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "solutions", "CandidateConsole",
  "WebResources", "os_", "bso", "candidate-console.js"), "utf8");

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
      replaceChildren() { this.children = []; this.value = ""; },
      appendChild(child) { this.children.push(child); },
      reset() {}, focus() {}, scrollIntoView() {}
    });
    return elements.get(id);
  }
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
      manualSchedulingOperational: false, checking: false, evidence: null },
    window: { clearTimeout() {}, setTimeout(fn) { timers.push(fn); return timers.length; } },
    currentUserId: () => "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    newCorrelationId: () => "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
    $: element,
    document: { createElement: () => ({}), querySelectorAll: () => [element("save-schedule")] },
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
    invokeCandidateCore: async (...args) => { requests.push(args); throw new Error("UNEXPECTED_WRITE"); }
  };
  vm.createContext(context);
  vm.runInContext([
    extract("  const STATUS = {", "\n  };"),
    extract("  const TABLES = {", "\n  };"),
    'TABLES.candidate.id = "os_sr_candid";',
    extract("  function addOption("),
    extract("  function setLookupPlaceholder("),
    extract("  function normalizeGuid("),
    extract("  function sameOptionalGuid("),
    extract("  function assertCandidateCoreStatus("),
    extract("  function requiresTrustedScheduleAvailability("),
    ...["isManualRound1Scheduling", "manualRound1Selection", "round1SchedulingMethodChanged",
      "invalidateRound1Availability", "round1Selection", "selectedVerifiedRound1Slot",
      "updateRound1AvailabilityControls", "validateRound1Availability", "round1SelectionChanged",
      "selectRound1Slot"].map((name) => extract(`  function ${name}(`)),
    ...["readRound1Availability", "loadRound1SchedulingCapabilities", "checkRound1Availability",
      "saveNormalRound1Schedule"].map((name) => extract(`  async function ${name}(`)),
    extract("  function configureSchedulingAvailability("),
    extract("  function setBusy("),
    extract("  function showSchedulingPanel("),
    extract("  async function createScheduleThroughCore("),
    extract("  async function createSchedule(")
  ].join("\n"), context);
  return { context, element, notices, requests, reads, dialogs, errors, timers, taId };
}

test("NORMAL scheduling defaults assigned TA and disables manual times and unverified slots", () => {
  const ui = harness();
  ui.context.showSchedulingPanel();
  assert.equal(ui.element("scheduling-ta").value, ui.taId);
  assert.equal(ui.element("scheduling-location-label").textContent, "Meeting Room");
  assert.equal(ui.element("scheduling-availability").hidden, false);
  assert.equal(ui.element("scheduling-slot-field").hidden, false);
  assert.equal(ui.element("scheduling-slot").disabled, true);
  assert.deepEqual(ui.element("scheduling-slot").children.map((option) => option.value), [""]);
  assert.equal(ui.element("scheduling-check-availability").disabled, true);
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
  ui.element("scheduling-date").value = date.toISOString().slice(0, 10);
  ui.element("scheduling-location").value = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
  ui.element("scheduling-ta").value = ui.taId;
  ui.context.round1Availability.providerOperational = true;
  return ui.context.round1Selection();
}

function envelope(selection, correlationId, slots = true) {
  const now = Date.now();
  return { schemaVersion: 1, ...selection, correlationId,
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
  ui.element("scheduling-slot").value = ui.context.round1Availability.evidence.slots[0].startUtc;
  ui.context.selectRound1Slot();
  assert.equal(ui.element("scheduling-time").value, "09:00");
  assert.equal(ui.element("scheduling-end-time").value, "09:30");
  assert.equal(ui.element("save-schedule").disabled, false);
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
  assert.match(ui.element("scheduling-availability-status").textContent, /Loading/);
  ui.element("scheduling-date").value = "";
  ui.context.round1SelectionChanged();
  release();
  await pending;
  assert.equal(ui.context.round1Availability.evidence, null);
  readySelection(ui);
  ui.context.reply = (_, inputs, correlationId) => envelope(ui.context.round1Selection(), correlationId, false);
  await ui.context.checkRound1Availability();
  assert.match(ui.element("scheduling-availability-status").textContent, /No common free/);
  assert.equal(ui.element("scheduling-slot").disabled, true);
  ui.context.reply = () => { throw new Error("PROVIDER_FAILED"); };
  await ui.context.checkRound1Availability();
  assert.match(ui.element("scheduling-availability-status").textContent, /provider error/);
  assert.equal(ui.context.round1Availability.evidence, null);
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
  ui.context.reply = (_, inputs, correlationId) => envelope(selection, correlationId);
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
    ui.context.invokeCandidateCore = async () => {
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
  assert.equal(ui.element("scheduling-availability").hidden, true);
  assert.equal(ui.element("scheduling-slot-field").hidden, true);
  assert.equal(ui.element("scheduling-dev-note").hidden, false);
  assert.equal(ui.element("scheduling-location-label").textContent, "Location");
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
