"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname,
  "..", "solutions", "CandidateConsole", "WebResources", "os_", "bso", "candidate-console.js"), "utf8");
const elements = new Map();
function makeElement() {
  return {
    value: "", children: [], attributes: {}, disabled: false,
    classList: { toggle() {} },
    replaceChildren(...children) { this.children = children; this.value = ""; },
    appendChild(child) { this.children.push(child); },
    setAttribute(name, value) { this.attributes[name] = value; },
    removeAttribute(name) { delete this.attributes[name]; }
  };
}
function element(id) {
  if (!elements.has(id)) {
    const value = makeElement();
    value.id = id;
    if (id === "candidate-data-mode") value.options = [{ textContent: "" }];
    elements.set(id, value);
  }
  return elements.get(id);
}
const ids = ["11111111-1111-4111-8111-111111111111",
  "22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333"];
const metadata = {
  PrimaryIdAttribute: "os_sr_posid", PrimaryNameAttribute: "os_sr_pos_ttl", EntitySetName: "os_sr_poses"
};
const metadataByTable = {
  os_sr_pos: metadata,
  os_sr_csrc: { PrimaryIdAttribute: "os_sr_csrcid", PrimaryNameAttribute: "os_sr_csrc_nm", EntitySetName: "os_sr_csrcs" },
  os_sr_ta: { PrimaryIdAttribute: "os_sr_taid", PrimaryNameAttribute: "os_sr_ta_nm", EntitySetName: "os_sr_tas" }
};
const calls = [];
const requests = [];
let retrieve;
let fetchResult = { ResultCode: "Applied" };
const policy = {
  resolve: () => ({ allowed: true }),
  hasSyntheticIsolation: () => true,
  getSyntheticScope: () => ({ scopeId: ids[0], positionId: ids[0] }),
  allowsReference: (label, synthetic) => !synthetic || label.startsWith("[DEV]"),
  syntheticReferenceFilter: () => "startswith(os_sr_pos_ttl,'[[]DEV]')"
};
const context = vm.createContext({
  URL, Set, Map, Object, Number, Date, RegExp, Error, Promise,
  console, crypto: { randomUUID: () => ids[2] },
  document: {
    getElementById: element, createElement: makeElement,
    addEventListener() {},
    querySelectorAll: (selector) => selector === "button[data-action]" ? [element("create-button")] : []
  },
  window: {
    BsoRsCandidateConsolePolicy: policy,
    BsoRsCandidateConsoleConfiguration: {},
    parent: { Xrm: {
      Utility: {
        getGlobalContext: () => ({
          getClientUrl: () => "https://test.invalid",
          organizationSettings: { organizationId: ids[1] },
          userSettings: { userId: ids[0] }
        }),
        getEntityMetadata: async (table) => metadataByTable[table]
      },
      WebApi: { retrieveMultipleRecords: async (table, query) => {
        calls.push({ table, query }); return retrieve(table, query);
      } }
    } }
  },
  fetch: async (url, request) => {
    requests.push(JSON.parse(request.body));
    return { ok: true, text: async () => JSON.stringify(fetchResult) };
  }
});
const marker = 'document.addEventListener("DOMContentLoaded", initialize);';
assert.equal(source.split(marker).length, 2);
vm.runInContext(source.replace(marker, `globalThis.testConsole = {
  loadLookupOptions, readNormalReferenceRecords, sendCandidateCoreRequest, isCandidateCoreEnabled, loadWorkspace,
  setMode(mode, synthetic) {
    referenceMode = mode;
    workspaceReady = true;
    referencesReady = true;
    environmentPolicy = { allowed: true, mode: synthetic ? "DEV" : "PROD",
      syntheticDataOnly: synthetic, candidateOperationMode: synthetic ? "SingleUserDev" : "BsoSynthetic", diagnosticsMode: "OFF" };
  },
  setReady(ready) { workspaceReady = ready; referencesReady = ready; },
  supersede(mode) { referenceMode = mode; referenceGeneration++; }
};`), context);
const api = context.testConsole;
const row = (id, name) => ({ os_sr_posid: id, os_sr_pos_ttl: name, statecode: 0 });
let passed = 0;
function check(condition) { assert.ok(condition); passed++; }

(async () => {
  api.setMode("NORMAL", true);
  check(!api.isCandidateCoreEnabled());
  retrieve = async (table) => {
    const m = metadataByTable[table];
    return { entities: [{ [m.PrimaryIdAttribute]: ids[0], [m.PrimaryNameAttribute]: "Accessible active reference", statecode: 0 }] };
  };
  await api.loadWorkspace();
  assert.equal(element("candidate-rows").children.length, 1, JSON.stringify({
    calls, notice: element("notice").textContent, options: element("candidate-position").children
  }));
  check(calls.length === 3 && calls.every((call) => Object.hasOwn(metadataByTable, call.table)) &&
    requests.length === 0 && element("create-button").disabled &&
    element("candidate-rows").children.length === 1);
  check(["candidate-position", "candidate-source", "candidate-assigned-ta"].every((id) =>
    element(id).children.length === 2 && element(id).children[1].value === ids[0]));
  calls.length = 0;
  retrieve = async () => ({
    entities: [row(ids[0], "[DEV] Synthetic reference"), row(ids[1], "<Active position>")],
    nextLink: "https://test.invalid/api/data/v9.2/os_sr_poses?$skiptoken=page2"
  });
  let page = 0;
  retrieve = async () => ++page === 1
    ? { entities: [row(ids[0], "[DEV] Synthetic reference")],
      nextLink: "https://test.invalid/api/data/v9.2/os_sr_poses?$skiptoken=page2" }
    : { entities: [row(ids[1], "<Active position>")] };
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  const select = element("position");
  check(select.children.length === 3 && select.children[1].value === ids[0] &&
    select.children[2].value === ids[1] && select.children[2].textContent === "<Active position>");
  check(calls.length === 2 && calls[0].query.includes("statecode%20eq%200") &&
    !calls[0].query.includes("startswith") && calls[1].query === "?$skiptoken=page2");
  check(requests.length === 0 && !select.disabled && !select.attributes["aria-busy"]);

  select.value = ids[1];
  retrieve = async () => ({ entities: [row(ids[1], "Renamed"), row(ids[2], "Added")] });
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  check(select.value === ids[1] && select.children[1].textContent === "Renamed" &&
    select.children[2].value === ids[2]);
  retrieve = async () => ({ entities: [row(ids[2], "Added")] });
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  check(select.value === "" && select.children.length === 2);
  retrieve = async () => ({ entities: [] });
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  check(select.children.length === 1 && select.children[0].textContent.includes("No active") && select.disabled);

  let complete;
  retrieve = () => new Promise((resolve) => { complete = resolve; });
  const loading = api.loadLookupOptions("os_sr_pos", "position", "Select position");
  await new Promise((resolve) => setImmediate(resolve));
  check(select.disabled && select.attributes["aria-busy"] === "true" &&
    select.children[0].textContent === "Loading options...");
  complete({ entities: [row(ids[0], "Available")] });
  await loading;
  check(!select.disabled);

  retrieve = async () => { throw new Error("permission denied"); };
  await assert.rejects(api.loadLookupOptions("os_sr_pos", "position", "Select position"), /permission denied/);
  check(select.disabled && select.children.length === 1 &&
    select.children[0].textContent.includes("Refresh reference options") && !select.attributes["aria-busy"]);
  retrieve = async () => ({ entities: [row(ids[0], "One"), row(ids[0], "Duplicate")] });
  await assert.rejects(api.loadLookupOptions("os_sr_pos", "position", "Select position"), /DUPLICATED/);
  passed++;
  retrieve = async () => ({ entities: [{ ...row(ids[0], "Inactive"), statecode: 1 }] });
  await assert.rejects(api.loadLookupOptions("os_sr_pos", "position", "Select position"), /OPTION_INVALID/);
  passed++;
  retrieve = async () => ({ entities: [row("invalid", "Invalid ID")] });
  await assert.rejects(api.loadLookupOptions("os_sr_pos", "position", "Select position"));
  passed++;
  retrieve = async () => ({ entities: [], nextLink: "https://other.invalid/api/data/v9.2/os_sr_poses?$skiptoken=x" });
  await assert.rejects(api.readNormalReferenceRecords("os_sr_pos", "?query", "os_sr_poses"), /PAGING_RESPONSE_INVALID/);
  passed++;
  retrieve = async () => ({ entities: [], nextLink: "https://test.invalid/api/data/v9.2/os_sr_cands?$skiptoken=x" });
  await assert.rejects(api.readNormalReferenceRecords("os_sr_pos", "?query", "os_sr_poses"), /PAGING_RESPONSE_INVALID/);
  passed++;
  retrieve = async () => ({ entities: [], nextLink: "?query" });
  await assert.rejects(api.readNormalReferenceRecords("os_sr_pos", "?query", "os_sr_poses"), /PAGING_RESPONSE_INVALID/);
  passed++;
  await assert.rejects(api.readNormalReferenceRecords("os_sr_cand", "?query", "os_sr_cands"), /TABLE_REJECTED/);
  passed++;
  await assert.rejects(api.sendCandidateCoreRequest("CreateCandidate", {}, ids[2]), /NOT_AUTHORIZED/);
  check(requests.length === 0);

  api.setMode("NORMAL", false);
  check(api.isCandidateCoreEnabled());
  api.setReady(false);
  await assert.rejects(api.sendCandidateCoreRequest("CreateCandidate", {}, ids[2]), /WORKSPACE_NOT_READY/);
  check(requests.length === 0);
  api.setReady(true);
  await api.sendCandidateCoreRequest("CreateCandidate", { CandidateName: "Synthetic test" }, ids[2]);
  check(requests.length === 1 && !Object.hasOwn(requests[0], "SyntheticScopeId") &&
    requests[0].ActionType === "CreateCandidate");
  await assert.rejects(api.sendCandidateCoreRequest("CreateCandidate", { SyntheticScopeId: ids[0] }, ids[2]), /NOT_AUTHORIZED/);
  await assert.rejects(api.sendCandidateCoreRequest("ReadScopedPositions", {}, ids[2]), /NOT_AUTHORIZED/);
  check(requests.length === 1);

  api.setMode("CONFIGURED", false);
  check(!api.isCandidateCoreEnabled());
  api.setMode("CONFIGURED", true);
  calls.length = 0;
  fetchResult = {
    ResultCode: "ScopedRead",
    ScopedData: JSON.stringify([{ ...row(ids[0], "[DEV] Bound reference"),
      statecode: "0", __logicalName: "os_sr_pos" }])
  };
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  check(select.children.length === 2 && select.value === ids[0] && calls.length === 0 &&
    requests.at(-1).SyntheticScopeId === ids[0] && requests.at(-1).ActionType === "ReadScopedPositions");
  fetchResult.ScopedData = JSON.stringify([{ ...row(ids[1], "[DEV] Wrong scope"), __logicalName: "os_sr_pos" }]);
  await assert.rejects(api.loadLookupOptions("os_sr_pos", "position", "Select position"), /OPTION_INVALID/);
  passed++;
  api.setMode("NORMAL", true);
  let finishOld;
  retrieve = () => new Promise((resolve) => { finishOld = resolve; });
  const oldLoad = api.loadLookupOptions("os_sr_pos", "position", "Select position");
  await new Promise((resolve) => setImmediate(resolve));
  api.supersede("CONFIGURED");
  fetchResult.ScopedData = JSON.stringify([{ ...row(ids[0], "[DEV] Bound reference"), __logicalName: "os_sr_pos" }]);
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  finishOld({ entities: [row(ids[1], "Old normal response")] });
  await oldLoad;
  check(select.children.length === 2 && select.value === ids[0] &&
    select.children[1].textContent === "[DEV] Bound reference");
  api.setMode("NORMAL", true);
  let rejectOld;
  retrieve = () => new Promise((resolve, reject) => { rejectOld = reject; });
  const oldFailure = api.loadLookupOptions("os_sr_pos", "position", "Select position");
  await new Promise((resolve) => setImmediate(resolve));
  retrieve = async () => ({ entities: [row(ids[1], "New normal response")] });
  await api.loadLookupOptions("os_sr_pos", "position", "Select position");
  rejectOld(new Error("stale request failed"));
  await oldFailure;
  check(select.children.length === 2 && select.children[1].textContent === "New normal response" &&
    !select.disabled);
  console.log(`Candidate Console reference runtime checks passed: ${passed}`);
})().catch((error) => { console.error(error); process.exitCode = 1; });
