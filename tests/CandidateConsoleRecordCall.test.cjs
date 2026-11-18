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

function harness(options = {}) {
  const candidateId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const callId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const requests = [], dialogs = [], errors = [], notices = [];
  let resets = 0, schedulingPanels = 0, counter = 0, persistedStatus = 100010000;
  const notes = options.notes ?? "  Synthetic comments\n<script>literal text</script>  ";
  const context = {
    busy: false,
    selectedCandidate: { os_sr_candid: candidateId, os_sr_cand_stat: 100010000 },
    environmentPolicy: { candidateOperationMode: options.singleUserDev ? "SingleUserDev" : "NORMAL" },
    callRetryBlockedCandidates: new Set(),
    callSchedulingCorrelations: new Map(),
    $: (id) => ({
      value: id === "call-notes" ? notes : String(options.outcome ?? 100010000),
      reset: () => { resets++; }
    }),
    normalizeGuid: (value) => {
      assert.match(value, /^[a-f0-9-]{36}$/i);
      return value.toLowerCase();
    },
    hideNotice: () => {},
    showNotice: (...args) => notices.push(args),
    logSafeFailure: (...args) => errors.push(args),
    setBusy: (value) => { context.busy = value; },
    isCandidateCoreEnabled: () => true,
    isCandidateAllowedByDataMode: () => true,
    canRecordCall: (status) => status === 100010000,
    newCorrelationId: () => `cccccccc-cccc-4ccc-8ccc-${String(++counter).padStart(12, "0")}`,
    relatedCandidateFilter: (table, id, extra) => `${table.candidate} eq ${id} and ${extra}`,
    assertCandidateCoreStatus: (result, expected) => assert.equal(result.CurrentStatus, expected),
    refreshCoreCandidate: async () => { context.selectedCandidate.os_sr_cand_stat = persistedStatus; },
    showSchedulingPanel: () => { schedulingPanels++; },
    reportCandidateCoreFailure: async (...args) => {
      errors.push(args);
      context.selectedCandidate.os_sr_cand_stat = persistedStatus;
    },
    xrm: () => ({ Navigation: { openAlertDialog: async (dialog) => dialogs.push(dialog.text) } })
  };
  context.invokeCandidateCore = async (action, values, correlationId) => {
    requests.push({ action, values, correlationId });
    if (options.httpFailure && action === "RecordCall") throw new Error("HTTP_403");
    if (action === "RecordCall") {
      persistedStatus = values.CallOutcome === 100010000 ? 100010001 : 100010000;
      return { result: { CurrentStatus: persistedStatus, CallLogId: callId } };
    }
    if (options.transitionFailure && requests.filter((r) => r.action === action).length === 1)
      throw new Error("TRANSITION_RESPONSE_UNCERTAIN");
    persistedStatus = 100010002;
    return { result: { CurrentStatus: persistedStatus } };
  };
  context.retrieveAll = async (table, query) => {
    assert.match(query, /\$top=2/);
    const request = requests.find((r) => r.action === "RecordCall");
    return [{
      os_sr_callid: callId,
      _os_sr_call_cand_value: candidateId,
      os_sr_call_corid: options.singleUserDev ? undefined : request.correlationId,
      os_sr_call_out: request.values.CallOutcome,
      os_sr_call_nts: options.commentsMismatch ? "Different text" : request.values.Notes ?? null
    }];
  };
  vm.createContext(context);
  vm.runInContext([
    extract("  const STATUS = {", "\n  };"),
    extract("  const OUTCOME = {", "\n  };"),
    extract("  const TABLES = {", "\n  };"),
    'TABLES.candidate.id = "os_sr_candid"; TABLES.call.id = "os_sr_callid";',
    extract("  async function recordCallThroughCore("),
    extract("  async function verifyRecordedCall("),
    extract("  async function moveToWaitingManualSchedulingThroughCore(")
  ].join("\n"), context);
  return {
    submit: () => context.recordCallThroughCore({ preventDefault() {} }),
    recover: () => context.moveToWaitingManualSchedulingThroughCore(),
    requests, dialogs, errors, notices,
    get resets() { return resets; },
    get schedulingPanels() { return schedulingPanels; }
  };
}

test("Record Call preserves comments, confirms persisted data, transitions and notifies once", async () => {
  const ui = harness();
  await Promise.all([ui.submit(), ui.submit()]);
  assert.deepEqual(ui.requests.map((r) => r.action), ["RecordCall", "ProceedToScheduling"]);
  assert.equal(ui.requests[0].values.Notes, "  Synthetic comments\n<script>literal text</script>  ");
  assert.deepEqual(ui.dialogs, ["Call saved successfully."]);
  assert.equal(ui.resets, 1);
  assert.equal(ui.schedulingPanels, 1);
  assert.equal(ui.errors.length, 0);
});

test("Record Call does not report success or advance after HTTP or comment readback failure", async () => {
  for (const options of [{ httpFailure: true }, { commentsMismatch: true }]) {
    const ui = harness(options);
    await ui.submit();
    await ui.submit();
    assert.equal(ui.requests.length, 1);
    assert.equal(ui.dialogs.length, 0);
    assert.equal(ui.resets, 0);
    assert.equal(ui.schedulingPanels, 0);
    assert.equal(ui.errors.length, 1);
  }
});

test("Record Call scheduling recovery reuses correlation without creating another Call", async () => {
  const ui = harness({ transitionFailure: true });
  await ui.submit();
  assert.equal(ui.dialogs.length, 0);
  assert.equal(ui.resets, 0);
  await ui.recover();
  assert.deepEqual(ui.requests.map((r) => r.action),
    ["RecordCall", "ProceedToScheduling", "ProceedToScheduling"]);
  assert.equal(ui.requests[1].correlationId, ui.requests[2].correlationId);
  assert.equal(ui.requests[1].values.ExpectedStatus, 100010001);
});

test("Record Call handles blank comments and preserves scoped SingleUserDev readback", async () => {
  for (const singleUserDev of [false, true]) {
    const ui = harness({ notes: " \r\n ", outcome: 100010001, singleUserDev });
    await ui.submit();
    assert.equal(ui.requests.length, 1);
    assert.equal(ui.requests[0].values.Notes, undefined);
    assert.deepEqual(ui.dialogs, ["Call saved successfully."]);
    assert.equal(ui.schedulingPanels, 0);
    assert.equal(ui.errors.length, 0);
  }
});
