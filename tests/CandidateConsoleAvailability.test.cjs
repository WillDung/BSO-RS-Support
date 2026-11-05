"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(
  __dirname, "..", "solutions", "CandidateConsole", "WebResources", "os_", "bso",
  "candidate-console-availability.js"
), "utf8");

class Element {
  constructor(id) {
    this.id = id;
    this.value = "";
    this.textContent = "";
    this.hidden = false;
    this.disabled = false;
    this.dataset = {};
    this.listeners = {};
    this.children = [];
    this.classList = { toggle() {} };
  }

  addEventListener(name, handler) { this.listeners[name] = handler; }
  replaceChildren(...children) { this.children = children; }
  append(child) { this.children.push(child); }
  add(option) { this.children.push(option); }
  reportValidity() { return true; }
  querySelectorAll() { return []; }
}

function row(state, extra = {}) {
  return {
    os_sr_avq_stat: state,
    os_sr_avq_exp: new Date(Date.now() + 600000).toISOString(),
    ...extra
  };
}

async function createUi({ enabled = true, create, read } = {}) {
  const elements = new Map();
  const get = (id) => {
    if (!elements.has(id)) elements.set(id, new Element(id));
    return elements.get(id);
  };
  const calls = { references: [], creates: [], reads: [], timers: [] };
  const ids = [
    "11111111-1111-4111-8111-111111111111",
    "22222222-2222-4222-8222-222222222222"
  ];
  const api = {
    async retrieveMultipleRecords(table, query) {
      calls.references.push({ table, query });
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
      return create ? create(id) : { id };
    },
    async retrieveRecord(table, id, query) {
      calls.reads.push({ table, id, query });
      return read ? read(id) : row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" });
    }
  };
  const window = {
    BsoRsCandidateConsoleConfiguration: { availabilityEnabled: enabled, syntheticDataOnly: true },
    BsoRsCandidateConsolePolicy: {
      allowsReference: (name, syntheticOnly) => syntheticOnly && name.startsWith("[DEV]")
    },
    Xrm: {
      WebApi: api,
      Utility: { async getEntityMetadata(name) { return { EntitySetName: name + "s" }; } }
    },
    setTimeout(callback) { calls.timers.push(callback); }
  };
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
  const context = vm.createContext({ window, document, Option, Intl });
  vm.runInContext(source, context);
  get("availability-mode").value = "100000000";
  get("availability-ta").value = ids[0];
  get("availability-location").value = ids[1];
  get("availability-start").value = "2099-01-05T09:00";
  get("availability-end").value = "2099-01-05T17:00";
  get("availability-duration").value = "60";
  await window.BsoRsAvailabilityQuery.initialize();
  return {
    calls,
    get,
    ids,
    submit: () => get("availability-form").listeners.submit({ preventDefault() {} })
  };
}

test("disabled availability does not read or create anything", async () => {
  const ui = await createUi({ enabled: false });
  assert.equal(ui.calls.references.length, 0);
  assert.match(ui.get("availability-result").textContent, /not configured/);
});

test("the panel creates and polls only its query without requesting mailbox addresses", async () => {
  const ui = await createUi();
  await ui.submit();
  assert.equal(ui.calls.references.length, 2);
  for (const reference of ui.calls.references) {
    assert.doesNotMatch(reference.query, /os_sr_ta_eml|os_sr_loc_rmeml/);
  }
  assert.equal(ui.calls.creates.length, 1);
  assert.equal(ui.calls.creates[0].table, "os_sr_avq");
  assert.deepEqual(Object.keys(ui.calls.creates[0].payload).sort(), [
    "os_sr_avq_dur", "os_sr_avq_end", "os_sr_avq_mod", "os_sr_avq_strt", "os_sr_avq_ta@odata.bind"
  ]);
  assert.equal(ui.calls.reads.length, 1);
  assert.equal(ui.calls.reads[0].table, "os_sr_avq");
  assert.equal(ui.calls.reads[0].id, ui.ids[0]);
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
});

test("onsite adds only the Location lookup to the availability request", async () => {
  const ui = await createUi();
  ui.get("availability-mode").value = "100000001";
  await ui.submit();
  const payload = ui.calls.creates[0].payload;
  assert.equal(payload["os_sr_avq_loc@odata.bind"], `/os_sr_locs(${ui.ids[1]})`);
  assert.equal(Object.keys(payload).some((key) => /cand|intv|cact/i.test(key)), false);
});

test("safe errors are mapped and raw provider text is never shown", async () => {
  const changed = await createUi({
    read: async () => row(100000003, { os_sr_avq_err: "REFERENCE_CHANGED" })
  });
  await changed.submit();
  assert.match(changed.get("availability-result").textContent, /selected TA or room changed/);

  for (const unsafe of ["SYNTHETIC_PROVIDER_BODY", "__proto__", "toString"]) {
    const ui = await createUi({
      read: async () => row(100000003, { os_sr_avq_err: unsafe })
    });
    await ui.submit();
    assert.equal(ui.get("availability-result").textContent,
      "Availability could not be verified. Contact support.");
    assert.doesNotMatch(ui.get("availability-result").textContent, /SYNTHETIC_PROVIDER_BODY/);
  }
});

test("available, pending, and expired states remain display-only", async () => {
  const available = await createUi({
    read: async () => row(100000001, {
      os_sr_avq_slts: '[{"startUtc":"2099-01-05T02:00:00Z","endUtc":"2099-01-05T03:00:00Z"}]'
    })
  });
  await available.submit();
  assert.equal(available.get("availability-result").children[0].textContent, "Available slots:");
  assert.equal(available.get("availability-result").children[1].children.length, 1);

  const pending = await createUi({ read: async () => row(100000000) });
  await pending.submit();
  assert.match(pending.get("availability-result").textContent, /pending/i);
  assert.equal(pending.calls.timers.length, 1);

  const expired = await createUi({
    read: async () => row(100000001, { os_sr_avq_exp: "2000-01-01T00:00:00Z" })
  });
  await expired.submit();
  assert.match(expired.get("availability-result").textContent, /expired/i);
});

test("an older in-flight poll cannot overwrite the newest query result", async () => {
  const responses = new Map();
  const ui = await createUi({
    read: (id) => new Promise((resolve) => responses.set(id, resolve))
  });
  const first = ui.submit();
  await waitFor(() => responses.has(ui.ids[0]));
  const second = ui.submit();
  await waitFor(() => responses.has(ui.ids[1]));
  responses.get(ui.ids[1])(row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" }));
  await second;
  responses.get(ui.ids[0])(row(100000003, { os_sr_avq_err: "REFERENCE_CHANGED" }));
  await first;
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
  assert.deepEqual(ui.calls.reads.map((call) => call.table), ["os_sr_avq", "os_sr_avq"]);
});

test("an older failed poll cannot replace the newest query result with an error", async () => {
  const responses = new Map();
  const ui = await createUi({
    read: (id) => new Promise((resolve, reject) => responses.set(id, { resolve, reject }))
  });
  const first = ui.submit();
  await waitFor(() => responses.has(ui.ids[0]));
  const second = ui.submit();
  await waitFor(() => responses.has(ui.ids[1]));
  responses.get(ui.ids[1]).resolve(row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" }));
  await second;
  responses.get(ui.ids[0]).reject(new Error("SYNTHETIC_OLD_PROVIDER_ERROR"));
  await first;
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
  assert.equal(ui.get("availability-submit").disabled, false);
});

test("an older create completion cannot switch polling away from the newest query", async () => {
  const pending = new Map();
  const ui = await createUi({
    create: (id) => new Promise((resolve) => pending.set(id, resolve))
  });
  const first = ui.submit();
  await waitFor(() => pending.has(ui.ids[0]));
  const second = ui.submit();
  await waitFor(() => pending.has(ui.ids[1]));
  pending.get(ui.ids[1])({ id: ui.ids[1] });
  await second;
  pending.get(ui.ids[0])({ id: ui.ids[0] });
  await first;
  assert.deepEqual(ui.calls.reads.map((call) => call.id), [ui.ids[1]]);
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
});

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (predicate()) return;
    await new Promise((resolve) => setImmediate(resolve));
  }
  assert.fail("Expected synthetic poll was not reached.");
}
