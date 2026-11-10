"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");
const { createSimulatedIsolatedPolicy } = require(".\\helpers\\AvailabilityConsoleHarness.cjs");
const { createServer, matchesFilter } = require(".\\CandidateConsoleServerFixture.cjs");

const root = path.join(__dirname, "..", "solutions", "CandidateConsole", "WebResources", "os_", "bso");
const policySource = fs.readFileSync(path.join(root, "candidate-console-policy.js"), "utf8");
const consoleSource = fs.readFileSync(path.join(root, "candidate-console.js"), "utf8")
  .replace('  document.addEventListener("DOMContentLoaded", initialize);', `
  window.__testConsole = {
    isCandidateCoreEnabled, refreshCandidates, openCandidate, getLookupName, loadLookupOptions,
    getActiveReference, resolveCreatedCandidate, renderCallHistory, renderStatusHistory,
    renderSchedulingDetails, findRound1Schedules, retrieveCandidateRecord, retrieveInterviewRecord,
    invokeCandidateCore
  };
  document.addEventListener("DOMContentLoaded", initialize);`);

const id = "11111111-1111-4111-8111-111111111111";
const orgId = "22222222-2222-4222-8222-222222222222";
const orgUrl = "https://synthetic-console.invalid";
const guid = (digit) => `${digit.repeat(8)}-${digit.repeat(4)}-4${digit.repeat(3)}-8${digit.repeat(3)}-${digit.repeat(12)}`;
const referenceNames = Object.freeze({
  os_sr_pos: "os_sr_pos_ttl",
  os_sr_csrc: "os_sr_csrc_nm",
  os_sr_ta: "os_sr_ta_nm",
  os_sr_loc: "os_sr_loc_nm"
});

class Element {
  constructor() {
    this.value = "";
    this.textContent = "";
    this.disabled = false;
    this.hidden = false;
    this.checked = false;
    this.dataset = {};
    this.children = [];
    this.listeners = {};
    this.classList = { add() {}, remove() {}, toggle() {} };
  }
  addEventListener(name, handler) { this.listeners[name] = handler; }
  append(...children) { this.children.push(...children); }
  appendChild(child) { this.children.push(child); return child; }
  replaceChildren(...children) { this.children = children; }
  removeAttribute(name) { delete this[name]; }
  reportValidity() { return true; }
  requestSubmit() {}
  scrollIntoView() {}
}

async function createConsole({ mode = "DEV", syntheticDataOnly = true, fixtures = {},
  configuration = {}, serverOptions = {}, simulatedIsolation = false, verifier } = {}) {
  const server = createServer(fixtures, serverOptions);
  const elements = new Map();
  const element = (name) => {
    if (!elements.has(name)) elements.set(name, new Element());
    return elements.get(name);
  };
  const actionButton = new Element();
  const workflowLabel = new Element();
  const document = {
    listeners: {},
    getElementById: element,
    createElement: () => new Element(),
    querySelectorAll: (selector) => selector === "button[data-action]"
      ? [actionButton] : selector === "[data-workflow-label]" ? [workflowLabel] : [],
    addEventListener(name, handler) { this.listeners[name] = handler; }
  };
  const window = {
    BsoRsCandidateConsoleConfiguration: {
      mode, syntheticDataOnly, environmentId: id, organizationId: orgId, organizationUrl: orgUrl,
      candidateCoreEnabled: true, devDirectWriteFallbackEnabled: true, diagnosticsMode: "OFF",
      ...configuration
    },
    Xrm: {
      WebApi: server.api,
      Utility: {
        getGlobalContext: () => ({
          getClientUrl: () => orgUrl,
          organizationSettings: { organizationId: orgId },
          userSettings: { userId: guid("3") }
        }),
        getEntityMetadata: async (name) => ({
          PrimaryIdAttribute: `${name}id`,
          PrimaryNameAttribute: referenceNames[name] || `${name}_nm`,
          EntitySetName: name === "os_sr_pos" ? "os_sr_poses" : `${name}s`
        })
      }
    }
  };
  const fetchCalls = [];
  if (verifier) window.fetch = verifier;
  const context = vm.createContext({
    window, document, URL, URLSearchParams,
    fetch: async (...args) => {
      fetchCalls.push(args);
      return { ok: true, text: async () => JSON.stringify({ ResultCode: "Applied" }) };
    }
  });
  if (simulatedIsolation) window.BsoRsCandidateConsolePolicy = createSimulatedIsolatedPolicy();
  else vm.runInContext(policySource, context);
  vm.runInContext(consoleSource, context);
  await document.listeners.DOMContentLoaded();
  return { server, element, actionButton, workflowLabel, fetchCalls, methods: window.__testConsole };
}

test("real Console policy consumes a verifier before references/list reads and scopes subsequent writes", async () => {
  let verified = false;
  const ui = await createConsole({
    verifier: async (_url, request) => {
      assert.deepEqual(JSON.parse(request.body), { ActionType: "VerifySyntheticIsolation" });
      verified = true;
      return {
        ok: true, json: async () => ({
          ResultCode: "SyntheticIsolationVerified", IsolationContract: JSON.stringify({
            version: 1, organizationId: orgId, environmentId: id, actorId: guid("3"),
            scopeId: guid("4"), candidateId: guid("4"), positionId: guid("5"), sourceId: guid("6"),
            taId: guid("7"), locationId: guid("8"), validUntil: new Date(Date.now() + 60000).toISOString(),
            calendarEnabled: false
          })
        })
      };
    }
  });
  assert.equal(verified, true);
  assert.equal(ui.methods.isCandidateCoreEnabled(), true);
  assert.equal(ui.element("create-button").disabled, false);
  await ui.methods.invokeCandidateCore("RecordCall", { CandidateId: guid("4") }, guid("9"));
  const mutation = JSON.parse(ui.fetchCalls.at(-1)[1].body);
  assert.equal(mutation.SyntheticScopeId, guid("4"));
  assert.equal(mutation.CorrelationId, guid("9"));
});

test("verifier denial closes actual Console initialization without business queries or dispatch", async () => {
  const ui = await createConsole({ verifier: async () => ({ ok: false }) });
  assert.equal(ui.methods.isCandidateCoreEnabled(), false);
  assert.equal(ui.element("create-button").disabled, true);
  assert.deepEqual(ui.server.requests, []);
  assert.deepEqual(ui.fetchCalls, []);
});

test("the SQL-style fixture models literal brackets, case-insensitivity, and URI decoding", () => {
  const name = "[SYNTHETIC-E2E] sample";
  const escaped = "startswith(os_sr_cand_nm,'[[]SYNTHETIC-E2E]')";
  const query = `?$filter=${encodeURIComponent(escaped)}`;
  const decoded = new URLSearchParams(query.slice(1)).get("$filter");
  assert.equal(decoded, escaped);
  assert.equal(matchesFilter({ os_sr_cand_nm: name }, decoded), true);
  assert.equal(matchesFilter({ os_sr_cand_nm: name }, "startswith(os_sr_cand_nm,'[SYNTHETIC-E2E]')"), false);
  assert.equal(matchesFilter({ os_sr_cand_nm: "[synthetic-e2e] sample" }, decoded), true);
  assert.equal(matchesFilter({ os_sr_cand_nm: "[SYNTHETIC-E2E sample" }, decoded), false);
  assert.equal(matchesFilter({ os_sr_cand_eml: "not-an-address.invalid" },
    "endswith(os_sr_cand_eml,'.invalid')"), true);
});

test("a case-insensitive server predicate cannot preserve the existing non-synthetic reference policy", () => {
  const policy = createSimulatedIsolatedPolicy();
  const label = "[dev] synthetic reference";
  assert.equal(policy.allowsReference(label, false), true);
  assert.equal(matchesFilter({ os_sr_ta_nm: label }, policy.syntheticReferenceFilter("os_sr_ta_nm")), true);
});

function scopedFixtures() {
  const correlation = guid("c");
  const candidate = {
    os_sr_candid: id, os_sr_cand_cnum: "SYN-001", os_sr_cand_nm: "[SYNTHETIC-E2E] sample",
    os_sr_cand_eml: "sample@example.invalid", os_sr_cand_corid: correlation, os_sr_cand_stat: 100010000,
    _os_sr_cand_pos_value: guid("6"), _os_sr_cand_csrc_value: guid("6"), _os_sr_cand_ta_value: guid("6")
  };
  const nonMarkerCandidate = { ...candidate, os_sr_candid: orgId, os_sr_cand_nm: "Outside marker" };
  const fixtures = {
    os_sr_cand: [
      candidate,
      nonMarkerCandidate,
      { ...candidate, os_sr_candid: guid("3"), os_sr_cand_eml: "sample@example.test" },
      { ...candidate, os_sr_candid: guid("4") },
      { ...candidate, os_sr_candid: guid("5"), os_sr_cand_nm: "[synthetic-e2e] outside",
        os_sr_cand_eml: "not-an-address.invalid" }
    ]
  };
  for (const table of ["os_sr_pos", "os_sr_csrc", "os_sr_ta", "os_sr_loc"]) {
    const name = referenceNames[table];
    fixtures[table] = [
      { [`${table}id`]: guid("6"), [name]: "[DEV] approved fixture", statecode: 0 },
      { [`${table}id`]: guid("7"), [name]: "Outside marker", statecode: 0 },
      { [`${table}id`]: guid("8"), [name]: "[DEV] inactive fixture", statecode: 1 },
      { [`${table}id`]: guid("9"), [name]: "[DEV] unapproved fixture", statecode: 0 }
    ];
  }
  for (const row of fixtures.os_sr_cand) {
    row.os_sr_cand_pos = fixtures.os_sr_pos[0];
    row.os_sr_cand_csrc = fixtures.os_sr_csrc[0];
    row.os_sr_cand_ta = fixtures.os_sr_ta[0];
    row["_os_sr_cand_pos_value@OData.Community.Display.V1.FormattedValue"] = "[DEV] approved fixture";
  }
  fixtures.os_sr_cand.push({
    ...candidate, os_sr_candid: guid("e"), _os_sr_cand_pos_value: guid("7"),
    os_sr_cand_pos: fixtures.os_sr_pos[1],
    "_os_sr_cand_pos_value@OData.Community.Display.V1.FormattedValue": "Outside marker"
  }, {
    ...candidate, os_sr_candid: guid("f"), _os_sr_cand_pos_value: guid("9"),
    os_sr_cand_pos: fixtures.os_sr_pos[3],
    "_os_sr_cand_pos_value@OData.Community.Display.V1.FormattedValue": "[DEV] unapproved fixture"
  });
  for (const [table, lookup, navigation] of [
    ["os_sr_call", "_os_sr_call_cand_value", "os_sr_call_cand"],
    ["os_sr_csh", "_os_sr_csh_cand_value", "os_sr_csh_cand"],
    ["os_sr_intv", "_os_sr_intv_cand_value", "os_sr_intv_cand"]
  ]) {
    fixtures[table] = [
      { [`${table}id`]: guid("a"), [lookup]: id, [navigation]: candidate, os_sr_intv_rnd: 100000000 },
      { [`${table}id`]: guid("b"), [lookup]: orgId, [navigation]: nonMarkerCandidate, os_sr_intv_rnd: 100000000 }
    ];
  }
  for (const schedule of fixtures.os_sr_intv) {
    schedule._os_sr_intv_ta_value = guid("6");
    schedule._os_sr_intv_loc_value = guid("6");
  }
  const authorized = (table, row) => {
    const recordId = row[`${table}id`];
    if (table === "os_sr_cand") return [id, orgId, guid("3"), guid("e")].includes(recordId);
    if (["os_sr_pos", "os_sr_csrc", "os_sr_ta", "os_sr_loc"].includes(table)) {
      return [guid("6"), guid("7"), guid("8")].includes(recordId);
    }
    return [guid("a"), guid("b")].includes(recordId);
  };
  return { fixtures, authorized, candidate, correlation };
}

function lastResponse(server, table) {
  return server.responses.filter((response) => response.table === table).at(-1);
}

test("simulated server scope plus emitted Candidate and reference predicates exclude rows in responses", async () => {
  const fixture = scopedFixtures();
  const ui = await createConsole({
    simulatedIsolation: true, fixtures: fixture.fixtures, configuration: { approvedReferences: [guid("9")] },
    serverOptions: { authorized: fixture.authorized }
  });
  assert.equal(ui.methods.isCandidateCoreEnabled(), true);
  const candidateResponse = lastResponse(ui.server, "os_sr_cand");
  assert.deepEqual(candidateResponse.entities.map((row) => row.os_sr_candid), [id]);
  const candidateFilter = new URLSearchParams(candidateResponse.query.slice(1)).get("$filter");
  assert.match(candidateFilter,
    /^startswith\(os_sr_cand_nm,'\[\[\]SYNTHETIC-E2E\]'\) and endswith\(os_sr_cand_eml,'.invalid'\)/);
  assert.match(candidateFilter, /_os_sr_cand_pos_value eq null or startswith\(os_sr_cand_pos\/os_sr_pos_ttl/);
  assert.doesNotMatch(candidateFilter, /os_sr_pos_nm/);
  assert.match(candidateFilter, /_os_sr_cand_csrc_value eq null or startswith\(os_sr_cand_csrc\/os_sr_csrc_nm/);
  assert.match(candidateFilter, /_os_sr_cand_ta_value eq null or startswith\(os_sr_cand_ta\/os_sr_ta_nm/);
  const candidateSelect = new URLSearchParams(candidateResponse.query.slice(1)).get("$select");
  assert.equal(candidateSelect.includes("_ownerid_value"), false);
  assert.equal(candidateResponse.entities.some((row) =>
    row["_os_sr_cand_pos_value@OData.Community.Display.V1.FormattedValue"] === "Outside marker"), false);
  assert.match(candidateResponse.query, /%5B%5B%5DSYNTHETIC-E2E%5D/);
  for (const table of ["os_sr_pos", "os_sr_csrc", "os_sr_ta", "os_sr_loc"]) {
    const response = lastResponse(ui.server, table);
    assert.deepEqual(response.entities.map((row) => row[`${table}id`]), [guid("6")]);
    const filter = new URLSearchParams(response.query.slice(1)).get("$filter");
    assert.equal(filter, `statecode eq 0 and startswith(${referenceNames[table]},'[[]DEV]')`);
    assert.ok(response.entities.every((row) => row[`${table}id`] !== guid("9")));
  }
  const position = await ui.methods.getActiveReference("os_sr_pos", guid("6"));
  assert.equal(position.id, guid("6"));
  assert.equal(position.entitySetName, "os_sr_poses");
  assert.equal(await ui.methods.openCandidate(id), true);
  assert.equal(ui.server.requests.some((request) => request.operation === "retrieveRecord"), false);

  const direct = await ui.methods.retrieveCandidateRecord(id, "?$select=os_sr_candid,os_sr_cand_nm");
  assert.equal(direct.os_sr_candid, id);
  const readback = await ui.methods.resolveCreatedCandidate(
    fixture.correlation, fixture.candidate.os_sr_cand_nm, fixture.candidate.os_sr_cand_eml);
  assert.equal(readback.os_sr_candid, id);
  assert.deepEqual(lastResponse(ui.server, "os_sr_cand").entities.map((row) => row.os_sr_candid), [id]);

  const cases = [
    ...["os_sr_pos", "os_sr_csrc", "os_sr_ta", "os_sr_loc"].flatMap((table) => [
      { table, invoke: (methods) => methods.getLookupName(table, guid("9")) },
      ...[guid("7"), guid("8")].map((recordId) => ({
        table, active: true, recordId, invoke: (methods) => methods.getActiveReference(table, recordId)
      }))
    ]),
    ...[orgId, guid("3"), guid("4"), guid("5"), guid("e"), guid("f")].map((recordId) => ({
      table: "os_sr_cand", invoke: (methods) => methods.retrieveCandidateRecord(recordId, "?$select=os_sr_candid")
    }))
  ];
  for (const item of cases) {
    const isolated = await createConsole({
      simulatedIsolation: true, fixtures: fixture.fixtures,
      serverOptions: { authorized: fixture.authorized }
    });
    const before = isolated.server.requests.length;
    await assert.rejects(() => item.invoke(isolated.methods));
    assert.equal(isolated.server.requests.length, before + 1);
    const response = lastResponse(isolated.server, item.table);
    assert.deepEqual(response.entities, []);
    assert.equal(isolated.methods.isCandidateCoreEnabled(), false);
    if (item.active) {
      const filter = new URLSearchParams(response.query.slice(1)).get("$filter");
      assert.equal(filter, `${item.table}id eq ${item.recordId} and statecode eq 0 and ` +
        `startswith(${referenceNames[item.table]},'[[]DEV]')`);
    }
  }
  const detail = await createConsole({
    simulatedIsolation: true, fixtures: fixture.fixtures,
    serverOptions: { authorized: fixture.authorized }
  });
  assert.equal(await detail.methods.openCandidate(guid("4")), false);
  assert.deepEqual(lastResponse(detail.server, "os_sr_cand").entities, []);
});

test("related lists and direct schedule reads apply the selected Candidate's server predicate", async () => {
  const fixture = scopedFixtures();
  const ui = await createConsole({
    simulatedIsolation: true, fixtures: fixture.fixtures,
    serverOptions: { authorized: fixture.authorized }
  });
  await ui.methods.renderCallHistory(id);
  assert.deepEqual(lastResponse(ui.server, "os_sr_call").entities.map((row) => row.os_sr_callid), [guid("a")]);
  await ui.methods.renderCallHistory(orgId);
  assert.deepEqual(lastResponse(ui.server, "os_sr_call").entities, []);
  const callFilter = new URLSearchParams(lastResponse(ui.server, "os_sr_call").query.slice(1)).get("$filter");
  assert.match(callFilter, /startswith\(os_sr_call_cand\/os_sr_cand_nm,'\[\[\]SYNTHETIC-E2E\]'\)/);

  await ui.methods.renderStatusHistory(orgId);
  assert.deepEqual(lastResponse(ui.server, "os_sr_csh").entities, []);
  await ui.methods.renderSchedulingDetails(orgId);
  assert.deepEqual(lastResponse(ui.server, "os_sr_intv").entities, []);
  assert.equal((await ui.methods.findRound1Schedules(orgId)).length, 0);
  assert.deepEqual(lastResponse(ui.server, "os_sr_intv").entities, []);
  const good = await ui.methods.retrieveInterviewRecord(guid("a"), id,
    "?$select=os_sr_intvid,_os_sr_intv_cand_value,_os_sr_intv_ta_value,_os_sr_intv_loc_value",
    { ta: guid("6"), location: guid("6") });
  assert.equal(good.os_sr_intvid, guid("a"));
  const scheduleFilter = new URLSearchParams(lastResponse(ui.server, "os_sr_intv").query.slice(1)).get("$filter");
  assert.ok(scheduleFilter.includes(`_os_sr_intv_ta_value eq ${guid("6")}`));
  assert.ok(scheduleFilter.includes(`_os_sr_intv_loc_value eq ${guid("6")}`));
  fixture.fixtures.os_sr_intv[0]._os_sr_intv_ta_value = guid("9");
  await assert.rejects(() => ui.methods.retrieveInterviewRecord(guid("a"), id,
    "?$select=os_sr_intvid,_os_sr_intv_ta_value", { ta: guid("6"), location: guid("6") }));
  assert.deepEqual(lastResponse(ui.server, "os_sr_intv").entities, []);
  for (const [scheduleId, candidateId] of [[guid("b"), orgId], [guid("a"), orgId]]) {
    const isolated = await createConsole({
      simulatedIsolation: true, fixtures: fixture.fixtures,
      serverOptions: { authorized: fixture.authorized }
    });
    const before = isolated.server.requests.length;
    await assert.rejects(() => isolated.methods.retrieveInterviewRecord(scheduleId, candidateId, "?$select=os_sr_intvid"));
    assert.equal(isolated.server.requests.length, before + 1);
    assert.deepEqual(lastResponse(isolated.server, "os_sr_intv").entities, []);
  }
});

test("characterization: marker predicates alone can return out-of-scope rows before the Console blocks", async () => {
  const fixture = scopedFixtures();
  const ui = await createConsole({
    simulatedIsolation: true,
    fixtures: fixture.fixtures,
    configuration: { approvedReferences: [guid("6")] }
  });
  const candidates = lastResponse(ui.server, "os_sr_cand").entities;
  assert.ok(candidates.some((row) => row.os_sr_candid === guid("4")),
    "A synthetic-looking but independently unapproved Candidate reaches the response.");
  assert.ok(candidates.some((row) => row.os_sr_candid === guid("5")),
    "Case-insensitive markers and an invalid email can pass the modeled server predicate.");
  assert.ok(lastResponse(ui.server, "os_sr_ta").entities.some((row) => row.os_sr_taid === guid("9")),
    "A browser-provided approved-reference list does not authorize or exclude server rows.");
  assert.equal(ui.methods.isCandidateCoreEnabled(), false);
});

test("characterization: a related lookup annotation may reach a fixture response before scoped readback fails", async () => {
  const fixture = scopedFixtures();
  const schedule = fixture.fixtures.os_sr_intv[0];
  schedule._os_sr_intv_ta_value = guid("9");
  schedule["_os_sr_intv_ta_value@OData.Community.Display.V1.FormattedValue"] = "[DEV] unapproved fixture";
  const ui = await createConsole({
    simulatedIsolation: true,
    fixtures: fixture.fixtures,
    serverOptions: { authorized: fixture.authorized }
  });
  await assert.rejects(() => ui.methods.renderSchedulingDetails(id));
  const response = lastResponse(ui.server, "os_sr_intv");
  assert.equal(response.entities[0]["_os_sr_intv_ta_value@OData.Community.Display.V1.FormattedValue"],
    "[DEV] unapproved fixture");
  assert.equal(ui.methods.isCandidateCoreEnabled(), false);
});

test("filtered Candidate and reference failures never retry with a broader query", async () => {
  for (const status of [400, 429, "TIMEOUT"]) {
    for (const failingTable of ["os_sr_ta", "os_sr_cand"]) {
      const fixture = scopedFixtures();
      const ui = await createConsole({
        simulatedIsolation: true, fixtures: fixture.fixtures,
        serverOptions: {
          authorized: fixture.authorized,
          fail: (table) => table === failingTable ? Object.assign(new Error("SYNTHETIC_FAILURE"), { status }) : null
        }
      });
      const attempts = ui.server.requests.filter((request) => request.table === failingTable);
      assert.equal(attempts.length, 1);
      const filter = new URLSearchParams(attempts[0].query.slice(1)).get("$filter");
      assert.match(filter, /startswith\(/);
      assert.doesNotMatch(ui.element("notice").textContent, /SYNTHETIC_FAILURE/);
      assert.equal(ui.methods.isCandidateCoreEnabled(), false);
      assert.equal(ui.element("create-button").disabled, true);
      assert.equal(ui.element("refresh-button").disabled, true);
      if (failingTable === "os_sr_ta") {
        await assert.rejects(() => ui.methods.getLookupName("os_sr_ta", guid("6")));
      } else {
        await assert.rejects(() => ui.methods.retrieveCandidateRecord(id, "?$select=os_sr_candid"));
      }
      const afterDirect = ui.server.requests.filter((request) => request.table === failingTable);
      assert.equal(afterDirect.length, 1);
      assert.ok(afterDirect.every((request) => request.operation === "retrieveMultipleRecords" &&
        new URLSearchParams(request.query.slice(1)).get("$filter").includes("startswith(")));
      await assert.rejects(() => ui.methods.invokeCandidateCore("RecordCall", { CandidateId: id }, id));
      assert.deepEqual(ui.fetchCalls, []);
    }
  }
});

test("related-read failures do not fall back to an unscoped list or direct schedule read", async () => {
  for (const [table, invoke] of [
    ["os_sr_call", (methods) => methods.renderCallHistory(id)],
    ["os_sr_csh", (methods) => methods.renderStatusHistory(id)],
    ["os_sr_intv", (methods) => methods.renderSchedulingDetails(id)]
  ]) {
    const fixture = scopedFixtures();
    const ui = await createConsole({
      simulatedIsolation: true, fixtures: fixture.fixtures,
      serverOptions: {
        authorized: fixture.authorized,
        fail: (requested) => requested === table ? new Error("SYNTHETIC_RELATED_FAILURE") : null
      }
    });
    await assert.rejects(() => invoke(ui.methods));
    if (table === "os_sr_intv") {
      await assert.rejects(() => ui.methods.retrieveInterviewRecord(guid("a"), id, "?$select=os_sr_intvid"));
    }
    const attempts = ui.server.requests.filter((request) => request.table === table);
    assert.equal(attempts.length, 1);
    assert.equal(ui.methods.isCandidateCoreEnabled(), false);
    assert.ok(attempts.every((request) => request.operation === "retrieveMultipleRecords" &&
      new URLSearchParams(request.query.slice(1)).get("$filter").includes("startswith(")));
  }
});

test("synthetic Candidate filters retain rows with optional reference lookups unset", async () => {
  const fixture = scopedFixtures();
  const withoutReferences = { ...fixture.candidate, os_sr_candid: guid("d") };
  for (const field of ["_os_sr_cand_pos_value", "_os_sr_cand_csrc_value", "_os_sr_cand_ta_value",
    "os_sr_cand_pos", "os_sr_cand_csrc", "os_sr_cand_ta"]) delete withoutReferences[field];
  delete withoutReferences["_os_sr_cand_pos_value@OData.Community.Display.V1.FormattedValue"];
  fixture.fixtures.os_sr_cand.push(withoutReferences);
  const ui = await createConsole({
    simulatedIsolation: true, fixtures: fixture.fixtures,
    serverOptions: {
      authorized: (table, row) => fixture.authorized(table, row) ||
        (table === "os_sr_cand" && row.os_sr_candid === guid("d"))
    }
  });
  assert.deepEqual(lastResponse(ui.server, "os_sr_cand").entities.map((row) => row.os_sr_candid),
    [id, guid("d")]);
});

test("synthetic paging reuses the server continuation link without broadening the original scope", async () => {
  const fixture = scopedFixtures();
  fixture.fixtures.os_sr_cand.push({ ...fixture.candidate, os_sr_candid: guid("d") });
  fixture.fixtures.os_sr_ta.push({
    os_sr_taid: guid("d"), os_sr_ta_nm: "[DEV] another approved fixture", statecode: 0
  });
  const ui = await createConsole({
    simulatedIsolation: true, fixtures: fixture.fixtures,
    serverOptions: {
      pageSize: 1,
      authorized: (table, row) => fixture.authorized(table, row) ||
        (["os_sr_cand", "os_sr_ta"].includes(table) && row[`${table}id`] === guid("d"))
    }
  });
  const paged = ui.server.responses.filter((response) => response.nextLink);
  assert.equal(paged.length, 2);
  for (const response of paged) {
    assert.ok(ui.server.requests.some((request) =>
      request.table === response.table && request.query === response.nextLink));
  }
  const candidateIds = ui.server.responses.filter((response) => response.table === "os_sr_cand")
    .flatMap((response) => response.entities.map((row) => row.os_sr_candid));
  assert.deepEqual(candidateIds, [id, guid("d")]);
  assert.equal(candidateIds.includes(guid("4")), false);
});

test("a failed synthetic continuation closes the Console without replaying a broader query", async () => {
  const fixture = scopedFixtures();
  fixture.fixtures.os_sr_ta.push({
    os_sr_taid: guid("d"), os_sr_ta_nm: "[DEV] another approved fixture", statecode: 0
  });
  const ui = await createConsole({
    simulatedIsolation: true, fixtures: fixture.fixtures,
    serverOptions: {
      pageSize: 1,
      authorized: (table, row) => fixture.authorized(table, row) ||
        (table === "os_sr_ta" && row.os_sr_taid === guid("d")),
      fail: (table, query) => table === "os_sr_ta" && query.startsWith("https:")
        ? Object.assign(new Error("SYNTHETIC_CONTINUATION_FAILURE"), { status: 429 }) : null
    }
  });
  const first = ui.server.responses.find((response) => response.table === "os_sr_ta");
  const attempts = ui.server.requests.filter((request) => request.table === "os_sr_ta");
  assert.equal(attempts.length, 2);
  assert.equal(attempts[1].query, first.nextLink);
  assert.equal(ui.methods.isCandidateCoreEnabled(), false);
  assert.equal(ui.element("create-button").disabled, true);
  assert.doesNotMatch(ui.element("notice").textContent, /SYNTHETIC_CONTINUATION_FAILURE/);
});

for (const mode of ["DEV", "TEST"]) {
  test(`${mode} synthetic Candidate and reference paths fail before emitting any row query`, async () => {
    const ui = await createConsole({
      mode,
      configuration: { syntheticIsolationVerified: true, approvedReferences: [id] },
      fixtures: {
        os_sr_cand: [
          { os_sr_candid: id, os_sr_cand_nm: "[SYNTHETIC-E2E] sample", os_sr_cand_eml: "sample@example.invalid" },
          { os_sr_candid: orgId, os_sr_cand_nm: "Outside sample", os_sr_cand_eml: "other@example.invalid" }
        ],
        os_sr_ta: [
          { os_sr_taid: id, os_sr_ta_nm: "[DEV] approved test", statecode: 0 },
          { os_sr_taid: orgId, os_sr_ta_nm: "[DEV] unapproved test", statecode: 0 }
        ]
      }
    });
    assert.equal(ui.methods.isCandidateCoreEnabled(), false);
    assert.equal(ui.element("create-button").disabled, true);
    assert.equal(ui.element("refresh-button").disabled, true);
    assert.equal(ui.element("dev-fallback-control").hidden, true);
    assert.equal(ui.actionButton.disabled, true);
    assert.match(ui.element("notice").textContent, /server-side synthetic data isolation/);

    ui.element("dev-fallback-toggle").checked = true;
    await ui.element("refresh-button").listeners.click();
    assert.equal(await ui.methods.openCandidate(id), false);
    for (const invoke of [
      () => ui.methods.refreshCandidates(),
      () => ui.methods.getLookupName("os_sr_ta", id),
      () => ui.methods.loadLookupOptions("os_sr_ta", "candidate-assigned-ta", "Select"),
      () => ui.methods.getActiveReference("os_sr_ta", id),
      () => ui.methods.resolveCreatedCandidate(id, "[SYNTHETIC-E2E] sample", "sample@example.invalid"),
      () => ui.methods.renderCallHistory(id),
      () => ui.methods.renderStatusHistory(id),
      () => ui.methods.renderSchedulingDetails(id),
      () => ui.methods.invokeCandidateCore("CreateCandidate", {}, id)
    ]) await assert.rejects(invoke);
    assert.deepEqual(ui.server.requests, []);
    assert.deepEqual(ui.server.responses, []);
    assert.deepEqual(ui.fetchCalls, []);
  });
}

test("non-synthetic Candidate Core still loads, and inactive references are excluded by the emitted query", async () => {
  const active = { os_sr_posid: id, os_sr_pos_ttl: "Synthetic position A", statecode: 0 };
  const inactive = { os_sr_posid: orgId, os_sr_pos_ttl: "Synthetic position B", statecode: 1 };
  const candidate = {
    os_sr_candid: id, os_sr_cand_cnum: "SYN-001", os_sr_cand_nm: "Synthetic candidate",
    os_sr_cand_eml: "sample@example.invalid", os_sr_cand_stat: 100010000
  };
  const ui = await createConsole({
    mode: "PROD", syntheticDataOnly: false,
    fixtures: { os_sr_pos: [active, inactive], os_sr_cand: [candidate] }
  });
  assert.equal(ui.methods.isCandidateCoreEnabled(), true);
  assert.equal(ui.element("workflow-path-badge").textContent, "CANDIDATE CORE PATH");
  const response = ui.server.responses.find((entry) => entry.table === "os_sr_pos");
  assert.ok(response);
  assert.equal(new URLSearchParams(response.query.slice(1)).get("$filter"), "statecode eq 0");
  assert.deepEqual(response.entities, [active]);
  assert.equal(ui.server.requests.filter((request) => request.operation === "retrieveMultipleRecords").length, 5);
  assert.equal(await ui.methods.openCandidate(id), true);
  assert.equal(ui.element("detail-heading").textContent, "Synthetic candidate");
  const result = await ui.methods.invokeCandidateCore("RecordCall", { CandidateId: id }, id);
  assert.equal(result.result.ResultCode, "Applied");
  assert.equal(ui.fetchCalls.length, 1);
  assert.equal(ui.fetchCalls[0][0], "/api/data/v9.2/os_sr_cact");
  assert.equal(JSON.parse(ui.fetchCalls[0][1].body).ActionType, "RecordCall");
});

test("non-synthetic reference selectors retain the existing case-sensitive visible behavior", async () => {
  const lower = { os_sr_taid: id, os_sr_ta_nm: "[dev] synthetic reference", statecode: 0 };
  const upper = { os_sr_taid: orgId, os_sr_ta_nm: "[DEV] synthetic reference", statecode: 0 };
  const ui = await createConsole({
    mode: "PROD", syntheticDataOnly: false, fixtures: { os_sr_ta: [lower, upper] }
  });
  const labels = ui.element("candidate-assigned-ta").children.map((option) => option.textContent);
  assert.ok(labels.includes(lower.os_sr_ta_nm));
  assert.equal(labels.includes(upper.os_sr_ta_nm), false);
  assert.ok(lastResponse(ui.server, "os_sr_ta").entities.some((row) => row.os_sr_taid === id));
});
