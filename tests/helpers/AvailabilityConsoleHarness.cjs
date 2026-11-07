"use strict";

const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "..", "solutions",
  "CandidateConsole", "WebResources", "os_", "bso", "candidate-console-availability.js"), "utf8");
const policySource = fs.readFileSync(path.join(__dirname, "..", "..", "solutions",
  "CandidateConsole", "WebResources", "os_", "bso", "candidate-console-policy.js"), "utf8");

class Element {
  constructor(id) {
    this.id = id;
    this.value = "";
    this._text = "";
    this.hidden = id === "availability-refresh";
    this.disabled = false;
    this.required = false;
    this.dataset = {};
    this.listeners = {};
    this.children = [];
    this.classes = new Set();
    this.classList = {
      toggle: (name, enabled) => enabled ? this.classes.add(name) : this.classes.delete(name),
      contains: (name) => this.classes.has(name)
    };
  }

  set textContent(value) { this._text = value; this.children = []; }
  get textContent() { return this._text + this.children.map((child) => child.textContent).join(""); }
  addEventListener(name, handler) { this.listeners[name] = handler; }
  replaceChildren(...children) { this._text = ""; this.children = children; }
  append(child) { this.children.push(child); }
  add(option) { this.children.push(option); }
  reportValidity() { return this.valid !== false; }
  setAttribute(name, value) { this[name] = value; }
}

function row(state, extra = {}, now = Date.now()) {
  return {
    os_sr_avq_stat: state,
    os_sr_avq_exp: new Date(now + 600000).toISOString(),
    ...extra
  };
}

function createSimulatedIsolatedPolicy(overrides = {}) {
  const context = vm.createContext({ window: {}, URL });
  vm.runInContext(policySource, context);
  // Test-only stub; it does not establish a server authorization boundary.
  return {
    ...context.window.BsoRsCandidateConsolePolicy,
    hasSyntheticIsolation: () => true,
    ...overrides
  };
}

async function createUi({ enabled = true, create, read, clock, values = {}, references,
  metadata, syntheticDataOnly = true, configuration = {}, runtime = {}, policy } = {}) {
  const elements = new Map();
  const get = (id) => {
    if (!elements.has(id)) elements.set(id, new Element(id));
    return elements.get(id);
  };
  const calls = { references: [], metadata: [], creates: [], reads: [], timers: [] };
  const ids = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222"
  ];
  const api = {
    async retrieveMultipleRecords(table, query) {
      calls.references.push({ table, query });
      if (references) return references(table, query);
      if (table === "os_sr_ta") {
        return { entities: [{ os_sr_taid: ids[0], os_sr_ta_nm: "[DEV] Synthetic TA" }] };
      }
      if (table === "os_sr_loc") {
        return { entities: [{ os_sr_locid: ids[1], os_sr_loc_nm: "[DEV] Synthetic room" }] };
      }
      throw new Error("Unexpected reference table");
    },
    async createRecord(table, payload) {
      calls.creates.push({ table, payload });
      const id = ids[(calls.creates.length - 1) % ids.length];
      return create ? create(table, payload, id) : { id };
    },
    async retrieveRecord(table, id, query) {
      calls.reads.push({ table, id, query });
      return read ? read(id, table, query)
        : row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" }, clock ? clock() : Date.now());
    }
  };
  const runtimeIdentity = {
    organizationUrl: "https://synthetic-console.invalid",
    organizationId: "33333333-3333-4333-8333-333333333333",
    ...runtime
  };
  const window = {
    BsoRsCandidateConsoleConfiguration: {
      mode: "DEV", availabilityEnabled: enabled, syntheticDataOnly,
      environmentId: "44444444-4444-4444-8444-444444444444",
      organizationId: "33333333-3333-4333-8333-333333333333",
      organizationUrl: "https://synthetic-console.invalid",
      candidateCoreEnabled: true, devDirectWriteFallbackEnabled: false, diagnosticsMode: "OFF",
      ...configuration
    },
    Xrm: {
      WebApi: api,
      Utility: {
        getGlobalContext() {
          return {
            getClientUrl: () => runtimeIdentity.organizationUrl,
            organizationSettings: { organizationId: runtimeIdentity.organizationId }
          };
        },
        async getEntityMetadata(name) {
          calls.metadata.push(name);
          return metadata ? metadata(name) : { EntitySetName: name + "s" };
        }
      }
    },
    setTimeout(callback) { calls.timers.push(callback); return callback; },
    clearTimeout(callback) {
      const index = calls.timers.indexOf(callback);
      if (index >= 0) calls.timers.splice(index, 1);
    }
  };
  const controlIds = ["availability-ta", "availability-mode", "availability-location",
    "availability-start", "availability-end", "availability-duration",
    "availability-submit", "availability-refresh"];
  get("availability-form").querySelectorAll = () => controlIds.map(get);
  const document = {
    readyState: "loading",
    addEventListener() {},
    getElementById: get,
    createElement: (name) => new Element(name),
    createTextNode: (text) => ({ textContent: text })
  };
  class Option {
    constructor(label, value) { this.textContent = label; this.value = value; }
  }
  const TestDate = clock ? class extends Date {
    constructor(...args) { super(...(args.length ? args : [clock()])); }
    static now() { return clock(); }
  } : Date;
  const context = vm.createContext({ window, document, Option, Intl, URL, Date: TestDate });
  if (policy === undefined) vm.runInContext(policySource, context);
  else window.BsoRsCandidateConsolePolicy = policy;
  vm.runInContext(source, context);
  get("availability-mode").value = values["availability-mode"] || "100000000";
  await window.BsoRsAvailabilityQuery.initialize();
  const defaults = {
    "availability-ta": ids[0], "availability-location": ids[1],
    "availability-start": "2099-01-05T09:00", "availability-end": "2099-01-05T17:00",
    "availability-duration": "60", ...values
  };
  for (const [id, value] of Object.entries(defaults)) get(id).value = value;
  return {
    calls, get, ids, window, api, runtime: runtimeIdentity,
    submit: () => get("availability-form").listeners.submit({ preventDefault() {} }),
    refresh: () => get("availability-refresh").listeners.click()
  };
}

module.exports = { createSimulatedIsolatedPolicy, createUi, row };
