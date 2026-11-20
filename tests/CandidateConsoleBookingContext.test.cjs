const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const root = path.join(__dirname, "..", "solutions", "CandidateConsole", "WebResources", "os_", "bso");
const source = fs.readFileSync(path.join(root, "candidate-console.js"), "utf8");
const html = fs.readFileSync(path.join(root, "candidate-console.html"), "utf8");
const code = source.slice(source.indexOf("  function updateBookingContextControls()"),
  source.indexOf("  function showCandidateCreateForm()"));
const candidateId = "11111111-1111-4111-8111-111111111111";
const scheduleId = "22222222-2222-4222-8222-222222222222";

function harness({ manage = false, foreign = false, denyTA = false } = {}) {
  const elements = new Map();
  const reads = [];
  const notices = [];
  const node = () => ({
    value: "", children: [], options: [], open: false,
    append(...children) { this.children.push(...children); },
    replaceChildren(...children) { this.children = children; this.value = ""; },
    showModal() { this.open = true; }
  });
  const $ = (id) => {
    if (!elements.has(id)) elements.set(id, node());
    return elements.get(id);
  };
  const candidate = { id: candidateId, number: "T-100", name: "Synthetic", email: "test@example.invalid",
    ta: "ta-id", status: manage ? 2 : 1, statecode: 0 };
  const schedules = manage ? [{ id: scheduleId, candidate: foreign ? scheduleId : candidateId,
    status: 1, start: "start", end: "end", location: "room-id" }] : [];
  const context = vm.createContext({
    $, document: { createElement: node }, selectedCandidate: candidate, busy: false,
    workspaceReady: true, referencesReady: true, referenceMode: "NORMAL",
    environmentPolicy: { syntheticDataOnly: false }, isCandidateCoreEnabled: () => true,
    TABLES: {
      candidate: { id: "id", number: "number", name: "name", email: "email", assignedTa: "ta", status: "status" },
      interview: { logicalName: "interviews", id: "id", candidate: "candidate", location: "location",
        start: "start", end: "end", status: "status", round: "round", round1: 1, result: "result" }
    },
    STATUS: { waitingManualScheduling: 1, round1Scheduled: 2 },
    SCHEDULE_STATUS: { proposed: 0 },
    normalizeGuid: (id) => { if (!id) throw new Error("Missing ID"); return id; },
    retrieveCandidateRecord: async (id, query) => { reads.push([id, query]); return candidate; },
    retrieveAll: async (table, query) => { reads.push([table, decodeURIComponent(query)]); return schedules; },
    relatedCandidateFilter: (_, id, tail) => `candidate eq ${id} and ${tail}`,
    isCandidateAllowedByDataMode: () => true, isKnownScheduleState: () => true,
    isActiveSchedule: (s) => s.status === 1, isPendingInterviewResult: () => true,
    getActiveReference: async () => { if (denyTA) throw new Error("Denied"); },
    getLookupName: async (table) => table === "os_sr_ta" ? "Assigned TA label" : "Existing Room label",
    scheduleStatusLabel: () => "Scheduled", formatDate: (date) => date,
    addOption: (select, value) => { if (!select.children.length) select.value = value; select.append(value); },
    showNotice: (message) => notices.push(message), hideNotice() {}, logSafeFailure() {},
    setBusy: (busy) => { context.busy = busy; }
  });
  vm.runInContext(code, context);
  return { $, reads, notices, context };
}

test("booking opens against exact authorized Candidate and applies Online/Offline requirements without enabling a write", async () => {
  const { $, reads, context } = harness();
  await context.showBookingContext();
  assert.equal($("booking-context").open, true);
  assert.deepEqual($("booking-operation").children, ["create"]);
  const shown = $("booking-context-details").children.map((term) => term.children[1].textContent);
  for (const value of [candidateId, "T-100", "Synthetic", "test@example.invalid", "Assigned TA label"]) {
    assert.ok(shown.includes(value));
  }
  assert.equal(reads[0][0], candidateId);
  assert.match(reads[1][1], new RegExp(`candidate eq ${candidateId} and round eq 1 and statecode eq 0`));
  $("booking-interview-type").value = "offline";
  context.updateBookingContextControls();
  assert.equal($("booking-room").required, true);
  assert.equal($("booking-room-field").hidden, false);
  $("booking-room").value = "room-id";
  $("booking-interview-type").value = "online";
  context.updateBookingContextControls();
  assert.equal($("booking-room-field").hidden, true);
  assert.equal($("booking-room").value, "");
  assert.match(html, /id="booking-check"[^>]+ disabled>/);
  assert.match(html, /id="booking-confirm"[^>]+ disabled>/);
});

test("existing schedule identifies Reschedule/Cancel context and denies foreign or inaccessible records", async () => {
  const { $, context } = harness({ manage: true });
  await context.showBookingContext();
  assert.deepEqual($("booking-operation").children, ["reschedule", "cancel"]);
  assert.ok($("booking-context-details").children.some((term) => term.children[1].textContent === scheduleId));
  $("booking-operation").value = "cancel";
  context.updateBookingContextControls();
  assert.equal($("booking-reason").required, true);
  assert.equal($("booking-check").hidden, true);
  for (const options of [{ manage: true, foreign: true }, { denyTA: true }]) {
    const denied = harness(options);
    await denied.context.showBookingContext();
    assert.equal(denied.$("booking-context").open, false);
    assert.match(denied.notices[0], /could not be verified/);
  }
});
