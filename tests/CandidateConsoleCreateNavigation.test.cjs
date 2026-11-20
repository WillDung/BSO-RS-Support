const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "..", "solutions", "CandidateConsole", "WebResources", "os_", "bso");
const html = fs.readFileSync(path.join(root, "candidate-console.html"), "utf8");
const source = fs.readFileSync(path.join(root, "candidate-console.js"), "utf8");
const actions = source.slice(source.indexOf("  function showCandidateCreateForm()"),
  source.indexOf("  async function createCandidate(event)"));
const wiring = source.slice(source.indexOf('    $("open-create-candidate").addEventListener'),
  source.indexOf('    $("edit-candidate-button").addEventListener'));

function harness({ rejectCreate = false, rejectRefresh = false } = {}) {
  const elements = new Map();
  const events = [];
  const requests = [];
  const $ = (id) => {
    if (!elements.has(id)) elements.set(id, {
      value: "", hidden: new RegExp(`<[^>]+id="${id}"[^>]+\\bhidden\\b`).test(html),
      disabled: false,
      listeners: {},
      addEventListener(name, callback) { this.listeners[name] = callback; },
      focus() { events.push(`focus:${id}`); },
      reset() { $("candidate-name").value = ""; }
    });
    return elements.get(id);
  };
  const context = vm.createContext({
    $, busy: false, referenceMode: "NORMAL", TABLES: { candidate: {} },
    environmentPolicy: { syntheticDataOnly: false },
    isCandidateCoreEnabled: () => true,
    isValidCandidateCvUrl: () => true,
    newCorrelationId: () => "synthetic-correlation",
    normalizeGuid: (id) => id,
    getSelectedActiveReference: async (_, id) => ({ id }),
    invokeCandidateCore: async (action, inputs, correlation) => {
      requests.push([action, inputs, correlation]);
      if (rejectCreate) throw new Error("Synthetic rejection");
      return { result: { CreatedCandidateId: "synthetic-id", CandidateNumber: "TEST-001" } };
    },
    refreshCandidates: async ({ resetPage }) => {
      assert.equal(resetPage, true);
      assert.equal($("candidate-browse-view").hidden, false);
      events.push("page-one-refresh");
      if (rejectRefresh) throw new Error("Synthetic list error");
    },
    reportCandidateCoreFailure: async () => events.push("create-failure"),
    logSafeFailure: (code) => events.push(code),
    setBusy: (value) => { context.busy = value; $("open-create-candidate").disabled = value; },
    hideNotice: () => {},
    showNotice: (message) => events.push(message)
  });
  vm.runInContext(`${actions}\nconst createCandidate = createCandidateThroughCore;\n${wiring}`, context);
  return {
    $, requests, events, context,
    open: () => $("open-create-candidate").listeners.click(),
    close: () => $("close-create-candidate").listeners.click(),
    submit: () => $("candidate-form").listeners.submit({ preventDefault() {} })
  };
}

test("Candidate List starts visible and the single form opens from the header and cancels without writing", async () => {
  const ui = harness();
  assert.match(html, /<header\b[\s\S]*id="open-create-candidate"[\s\S]*?<\/header>/);
  assert.equal((html.match(/id="candidate-form"/g) || []).length, 1);
  assert.equal(ui.$("candidate-create-panel").hidden, true);
  assert.equal(ui.$("candidate-browse-view").hidden, false);
  await ui.submit();
  ui.$("open-create-candidate").disabled = true;
  ui.open();
  assert.equal(ui.$("candidate-create-panel").hidden, true);
  ui.$("open-create-candidate").disabled = false;
  ui.open();
  assert.equal(ui.$("candidate-create-panel").hidden, false);
  assert.equal(ui.$("candidate-browse-view").hidden, true);
  assert.equal(ui.events.at(-1), "focus:candidate-name");
  ui.$("candidate-name").value = "Discard me";
  ui.$("candidate-search").value = "list filter";
  ui.context.busy = true;
  ui.close();
  assert.equal(ui.$("candidate-create-panel").hidden, false);
  ui.context.busy = false;
  ui.close();
  assert.equal(ui.$("candidate-create-panel").hidden, true);
  assert.equal(ui.$("candidate-browse-view").hidden, false);
  assert.equal(ui.$("candidate-name").value, "");
  assert.equal(ui.$("candidate-search").value, "list filter");
  assert.equal(ui.events.at(-1), "focus:open-create-candidate");
  assert.equal(ui.requests.length, 0);
});

test("existing Create action refreshes page one only after confirmation and preserves failure feedback", async () => {
  for (const options of [{}, { rejectRefresh: true }, { rejectCreate: true }]) {
    const ui = harness(options);
    ui.open();
    ui.$("candidate-name").value = "Synthetic candidate";
    ui.$("candidate-email").value = "candidate@example.invalid";
    await ui.submit();
    assert.equal(ui.requests.length, 1);
    const [[action, inputs, correlation]] = ui.requests;
    assert.equal(action, "CreateCandidate");
    assert.equal(inputs.PositionId, "candidate-position");
    assert.equal(inputs.CandidateSourceId, "candidate-source");
    assert.equal(inputs.AssignedTaId, "candidate-assigned-ta");
    assert.equal(correlation, "synthetic-correlation");
    assert.equal(ui.$("candidate-browse-view").hidden, Boolean(options.rejectCreate));
    if (options.rejectCreate) {
      assert.equal(ui.events.includes("page-one-refresh"), false);
      assert.equal(ui.events.at(-1), "create-failure");
      assert.equal(ui.$("candidate-name").value, "Synthetic candidate");
    } else {
      assert.equal(ui.events.includes("page-one-refresh"), true);
      assert.match(ui.events.at(-1), options.rejectRefresh ? /was created, but the list could not be refreshed/ : /created successfully/);
    }
  }
});
