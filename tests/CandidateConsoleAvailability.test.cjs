"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { createSimulatedIsolatedPolicy, createUi: createRawUi, row } =
  require(".\\helpers\\AvailabilityConsoleHarness.cjs");
const { createServer } = require(".\\CandidateConsoleServerFixture.cjs");
const simulatedIsolatedPolicy = createSimulatedIsolatedPolicy();

// These panel-unit tests simulate a future isolation prerequisite, not its authorization.
function createUi(options = {}) {
  return createRawUi({
    ...options,
    policy: Object.hasOwn(options, "policy") ? options.policy : simulatedIsolatedPolicy
  });
}

test("the actual policy blocks synthetic availability before any row request", async () => {
  const ui = await createRawUi({
    configuration: { syntheticIsolationVerified: true, approvedReferences: ["untrusted"] }
  });
  await ui.submit();
  await ui.refresh();
  assert.equal(ui.calls.references.length, 0);
  assert.equal(ui.calls.metadata.length, 0);
  assert.equal(ui.calls.creates.length, 0);
  assert.equal(ui.calls.reads.length, 0);
  assert.equal(ui.get("availability-submit").disabled, true);
});

test("availability's emitted predicates and simulated server authorization exclude reference rows", async () => {
  const taId = "11111111-1111-4111-8111-111111111111";
  const roomId = "22222222-2222-4222-8222-222222222222";
  const outsideId = "33333333-3333-4333-8333-333333333333";
  const inactiveId = "44444444-4444-4444-8444-444444444444";
  const unapprovedId = "55555555-5555-4555-8555-555555555555";
  const fixtures = {};
  for (const [table, approvedId] of [["os_sr_ta", taId], ["os_sr_loc", roomId]]) {
    fixtures[table] = [
      { [`${table}id`]: approvedId, [`${table}_nm`]: "[DEV] approved fixture", statecode: 0 },
      { [`${table}id`]: outsideId, [`${table}_nm`]: "Outside marker", statecode: 0 },
      { [`${table}id`]: inactiveId, [`${table}_nm`]: "[DEV] inactive fixture", statecode: 1 },
      { [`${table}id`]: unapprovedId, [`${table}_nm`]: "[DEV] unapproved fixture", statecode: 0 }
    ];
  }
  const server = createServer(fixtures, {
    authorized: (table, record) => record[`${table}id`] !== unapprovedId
  });
  const ui = await createUi({
    configuration: { approvedReferences: [unapprovedId] },
    references: (table, query) => server.api.retrieveMultipleRecords(table, query)
  });
  for (const [table, approvedId] of [["os_sr_ta", taId], ["os_sr_loc", roomId]]) {
    const response = server.responses.find((entry) => entry.table === table);
    assert.deepEqual(response.entities.map((entity) => entity[`${table}id`]), [approvedId]);
    assert.equal(new URLSearchParams(response.query.slice(1)).get("$filter"),
      `statecode eq 0 and startswith(${table}_nm,'[[]DEV]')`);
    assert.match(response.query, /%5B%5B%5DDEV%5D/);
  }
  assert.equal(ui.get("availability-submit").disabled, false);
});

test("availability does not retry failed filtered reference queries without the filter", async () => {
  for (const status of [400, 429, "TIMEOUT"]) {
    const server = createServer({}, {
      fail: () => Object.assign(new Error("SYNTHETIC_REFERENCE_FAILURE"), { status })
    });
    const ui = await createUi({ references: (table, query) => server.api.retrieveMultipleRecords(table, query) });
    await ui.submit();
    assert.equal(server.requests.length, 2);
    assert.ok(server.requests.every((request) =>
      new URLSearchParams(request.query.slice(1)).get("$filter").includes("startswith(")));
    assert.equal(ui.calls.creates.length, 0);
    assert.doesNotMatch(ui.get("availability-result").textContent, /SYNTHETIC_REFERENCE_FAILURE/);
  }
});

test("availability fails closed when the synthetic reference predicate is unavailable", async () => {
  const ui = await createUi({
    policy: createSimulatedIsolatedPolicy({ syntheticReferenceFilter: undefined })
  });
  await ui.submit();
  assert.equal(ui.calls.references.length, 0);
  assert.equal(ui.calls.creates.length, 0);
  assert.equal(ui.get("availability-submit").disabled, true);
});

test("reference paging stops if the simulated isolation prerequisite ceases to hold", async () => {
  let isolated = true;
  const ui = await createUi({
    policy: { ...simulatedIsolatedPolicy, hasSyntheticIsolation: () => isolated },
    references: async () => {
      isolated = false;
      return { entities: [], nextLink: "https://synthetic-console.invalid/next-page" };
    }
  });
  assert.equal(ui.calls.references.length, 1);
  assert.equal(ui.get("availability-submit").disabled, true);
  await ui.submit();
  assert.equal(ui.calls.creates.length, 0);
});

test("disabled availability does not read or create anything", async () => {
  const ui = await createUi({ enabled: false });
  assert.equal(ui.calls.references.length, 0);
  assert.equal(ui.get("availability-submit").disabled, true);
  await ui.submit();
  await ui.refresh();
  assert.equal(ui.calls.creates.length, 0);
  assert.match(ui.get("availability-result").textContent, /not configured/);
});

test("the strict feature flag cannot bypass the actual environment identity and DEV synthetic policy", async () => {
  for (const options of [
    { enabled: "true" },
    { runtime: { organizationUrl: "https://different-console.invalid" } },
    { runtime: { organizationId: "55555555-5555-4555-8555-555555555555" } },
    { runtime: { organizationId: null } },
    { runtime: { organizationUrl: "http://synthetic-console.invalid" } },
    { configuration: { candidateCoreEnabled: false } },
    { configuration: { mode: "TEST" } },
    { configuration: { mode: "PROD", syntheticDataOnly: false } },
    { syntheticDataOnly: false },
    { policy: null },
    { policy: { allowsReference: () => true } },
    { policy: { resolve: () => { throw new Error("SYNTHETIC_POLICY_DETAIL"); } } }
  ]) {
    const ui = await createUi(options);
    await ui.submit();
    await ui.refresh();
    assert.equal(ui.calls.references.length, 0);
    assert.equal(ui.calls.creates.length, 0);
    assert.equal(ui.calls.reads.length, 0);
    assert.equal(ui.get("availability-submit").disabled, true);
    assert.match(ui.get("availability-result").textContent, /not configured|identity/);
    assert.doesNotMatch(ui.get("availability-result").textContent, /SYNTHETIC_POLICY_DETAIL/);
  }
});

test("context identity drift fails closed before dispatch, refresh and queued polling", async () => {
  const submit = await createUi();
  submit.runtime.organizationId = "55555555-5555-4555-8555-555555555555";
  await submit.submit();
  assert.equal(submit.calls.creates.length, 0);

  const pending = await createUi({ read: async () => row(100000000) });
  await pending.submit();
  pending.runtime.organizationUrl = "https://different-console.invalid";
  await pending.calls.timers.shift()();
  await pending.refresh();
  assert.equal(pending.calls.reads.length, 1);
  assert.equal(pending.calls.creates.length, 1);
  assert.equal(pending.calls.timers.length, 0);
  assert.match(pending.get("availability-result").textContent, /identity/);

  let metadataReady;
  const preparing = await createUi({
    metadata: () => new Promise((resolve) => { metadataReady = resolve; })
  });
  const submitting = preparing.submit();
  await waitFor(() => metadataReady);
  preparing.runtime.organizationUrl = "https://different-console.invalid";
  metadataReady({ EntitySetName: "os_sr_tas" });
  await submitting;
  assert.equal(preparing.calls.creates.length, 0);
});

test("reference, mode, and onsite location validation does not trust native form validation", async () => {
  for (const values of [
    { "availability-ta": "" },
    { "availability-ta": "33333333-3333-4333-8333-333333333333" },
    { "availability-ta": "invalid-guid" },
    { "availability-mode": "100000002" },
    { "availability-mode": "100000001", "availability-location": "" },
    { "availability-mode": "100000001", "availability-location": "invalid-guid" }
  ]) {
    const ui = await createUi({ values });
    await ui.submit();
    assert.equal(ui.calls.creates.length, 0);
    assert.equal(ui.calls.metadata.length, 0);
    assert.match(ui.get("availability-result").textContent, /Select an active TA/);
  }
});

test("empty, restricted and failed reference loads have explicit states and cannot submit", async () => {
  const noTa = await createUi({ references: async () => ({ entities: [] }) });
  assert.match(noTa.get("availability-result").textContent, /No active TAs/);
  assert.equal(noTa.get("availability-submit").disabled, true);
  await noTa.submit();
  assert.equal(noTa.calls.creates.length, 0);

  const roomsMissing = await createUi({
    references: async (table) => ({ entities: table === "os_sr_ta"
      ? [{ os_sr_taid: "11111111-1111-4111-8111-111111111111", os_sr_ta_nm: "[DEV] Synthetic TA" }]
      : [] })
  });
  assert.equal(roomsMissing.get("availability-submit").disabled, false);
  roomsMissing.get("availability-mode").value = "100000001";
  roomsMissing.get("availability-mode").listeners.change();
  assert.match(roomsMissing.get("availability-result").textContent, /No active rooms/);
  assert.equal(roomsMissing.get("availability-location").required, true);
  assert.equal(roomsMissing.get("availability-location-field").hidden, false);
  assert.equal(roomsMissing.get("availability-submit").disabled, true);
  roomsMissing.get("availability-mode").value = "100000000";
  roomsMissing.get("availability-mode").listeners.change();
  assert.equal(roomsMissing.get("availability-location").disabled, true);
  await roomsMissing.submit();
  assert.equal(roomsMissing.calls.creates.length, 1);
  assert.equal("os_sr_avq_loc@odata.bind" in roomsMissing.calls.creates[0].payload, false);

  const restricted = await createUi({
    references: async () => ({ entities: [
      { os_sr_taid: "11111111-1111-4111-8111-111111111111", os_sr_ta_nm: "Unapproved reference" },
      { os_sr_taid: "invalid-guid", os_sr_ta_nm: "[DEV] Invalid reference" }
    ] })
  });
  assert.match(restricted.get("availability-result").textContent, /could not be loaded/);
  const failed = await createUi({ references: async () => { throw new Error("SYNTHETIC_REFERENCE_ERROR"); } });
  assert.match(failed.get("availability-result").textContent, /could not be loaded/);
  await failed.submit();
  assert.equal(failed.calls.creates.length, 0);
  assert.equal(failed.get("availability-submit").disabled, true);
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
  assert.equal(ui.calls.creates[0].payload.os_sr_avq_mod, 100000000);
  assert.equal(ui.calls.creates[0].payload.os_sr_avq_dur, 60);
  assert.equal(ui.calls.creates[0].payload.os_sr_avq_strt, "2099-01-05T02:00:00.000Z");
  assert.equal(ui.calls.creates[0].payload.os_sr_avq_end, "2099-01-05T10:00:00.000Z");
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
  assert.equal(payload.os_sr_avq_mod, 100000001);
  assert.equal(Object.keys(payload).some((key) => /cand|intv|cact/i.test(key)), false);
});

test("invalid local inputs stop before creating or polling a query", async () => {
  for (const [field, value] of [
    ["availability-start", "2099-01-05T09:00+07:00"],
    ["availability-start", "2099-02-30T09:00"],
    ["availability-start", "2099-01-05T09:01"],
    ["availability-start", "2000-01-05T09:00"],
    ["availability-end", "2099-01-05T09:30"],
    ["availability-end", "2099-01-05T09:00"],
    ["availability-duration", "50"],
    ["availability-duration", "495"],
    ["availability-duration", "0"],
    ["availability-duration", "15.5"]
  ]) {
    const ui = await createUi();
    ui.get(field).value = value;
    await ui.submit();
    assert.equal(ui.calls.creates.length, 0);
    assert.equal(ui.calls.reads.length, 0);
    assert.equal(ui.calls.timers.length, 0);
    assert.match(ui.get("availability-result").textContent, /future Vietnam-time window/);
  }
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

  const noSlots = await createUi({
    read: async () => row(100000002, { os_sr_avq_rsn: "SYNTHETIC_PROVIDER_REASON" })
  });
  await noSlots.submit();
  assert.equal(noSlots.get("availability-result").textContent, "No slots are available.");
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
    read: async () => row(100000001, {
      os_sr_avq_exp: "2000-01-01T00:00:00Z",
      os_sr_avq_slts: '[{"startUtc":"2099-01-05T02:00:00Z","endUtc":"2099-01-05T03:00:00Z"}]'
    })
  });
  await expired.submit();
  assert.match(expired.get("availability-result").textContent, /expired/i);
  assert.equal(expired.get("availability-result").children.length, 0);

  const invalid = await createUi({
    read: async () => row(100000001, {
      os_sr_avq_slts: '[{"startUtc":"2099-01-05T02:00:00Z","endUtc":"2099-01-05T03:00:00Z",' +
        '"providerPayload":"SYNTHETIC_PROVIDER_BODY"}]'
    })
  });
  await invalid.submit();
  assert.equal(invalid.get("availability-result").textContent, "Availability result could not be verified.");
});

test("canonical slots must be UTC, chronological, aligned, in the submitted window and exact duration", async () => {
  const slot = { startUtc: "2099-01-05T02:00:00Z", endUtc: "2099-01-05T03:00:00Z" };
  for (const slots of [
    [],
    [null],
    [slot, slot],
    [{ ...slot, startUtc: "2099-01-05T02:00:00+00:00" }],
    [{ ...slot, startUtc: "2099-02-30T02:00:00Z", endUtc: "2099-02-30T03:00:00Z" }],
    [{ startUtc: "2099-01-05T01:00:00Z", endUtc: "2099-01-05T02:00:00Z" }],
    [{ startUtc: "2099-01-05T10:00:00Z", endUtc: "2099-01-05T11:00:00Z" }],
    [{ ...slot, endUtc: "2099-01-05T02:30:00Z" }],
    [{ startUtc: "2099-01-05T02:01:00Z", endUtc: "2099-01-05T03:01:00Z" }],
    Array(201).fill(slot)
  ]) {
    const ui = await createUi({
      read: async () => row(100000001, { os_sr_avq_slts: JSON.stringify(slots) })
    });
    await ui.submit();
    assert.equal(ui.get("availability-result").textContent, "Availability result could not be verified.");
    assert.equal(ui.get("availability-result").classes.has("error"), true);
    assert.equal(ui.get("availability-result").children.length, 0);
  }
});

test("a refreshed result clears old error styling and stale slots when it expires", async () => {
  let state = 0;
  const ui = await createUi({
    read: async () => ++state === 1
      ? row(100000003, { os_sr_avq_err: "REFERENCE_CHANGED" })
      : state === 2 ? row(100000001, {
        os_sr_avq_slts: '[{"startUtc":"2099-01-05T02:00:00Z","endUtc":"2099-01-05T03:00:00Z"}]'
      }) : row(100000001, { os_sr_avq_exp: "2000-01-01T00:00:00Z" })
  });
  await ui.submit();
  assert.equal(ui.get("availability-result").classes.has("error"), true);
  await ui.refresh();
  assert.equal(ui.get("availability-result").classes.has("error"), false);
  assert.equal(ui.get("availability-result").children[1].children.length, 1);
  await ui.refresh();
  assert.match(ui.get("availability-result").textContent, /expired/);
  assert.equal(ui.get("availability-result").children.length, 0);
  assert.equal(ui.calls.creates.length, 1);
});

test("unknown states and invalid expiry never display available slots", async () => {
  for (const extra of [
    { os_sr_avq_stat: 100000099 },
    { os_sr_avq_stat: "100000001" },
    { os_sr_avq_exp: null },
    { os_sr_avq_exp: "invalid-date" },
    { os_sr_avq_exp: "2099-02-30T02:00:00Z" },
    { os_sr_avq_exp: "2099-01-05T02:00:00" }
  ]) {
    const ui = await createUi({
      read: async () => row(100000001, {
        os_sr_avq_slts: '[{"startUtc":"2099-01-05T02:00:00Z","endUtc":"2099-01-05T03:00:00Z"}]',
        ...extra
      })
    });
    await ui.submit();
    assert.equal(ui.get("availability-result").children.length, 0);
    assert.match(ui.get("availability-result").textContent, /unknown|expired/);
  }
});

test("lost or missing create acknowledgments never cause an automatic replacement query", async () => {
  for (const create of [
    async () => { throw new Error("SYNTHETIC_CREATE_FAILURE"); },
    async () => ({}),
    async () => ({ id: "invalid-guid" })
  ]) {
    const ui = await createUi({ create });
    await ui.submit();
    assert.equal(ui.calls.creates.length, 1);
    assert.equal(ui.calls.reads.length, 0);
    assert.equal(ui.calls.timers.length, 0);
    assert.equal(ui.get("availability-result").textContent,
      "Availability query could not be started or read. Contact support if this continues.");
    await ui.get("availability-refresh").listeners.click();
    assert.equal(ui.calls.creates.length, 1);
    assert.equal(ui.calls.reads.length, 0);
  }
});

test("metadata failures stop before create and do not expose raw integration details", async () => {
  for (const metadata of [
    async () => { throw new Error("SYNTHETIC_METADATA_DETAIL"); },
    async () => ({}),
    async () => ({ EntitySetName: "invalid/collection" })
  ]) {
    const ui = await createUi({ metadata });
    await ui.submit();
    assert.equal(ui.calls.creates.length, 0);
    assert.equal(ui.calls.reads.length, 0);
    assert.equal(ui.get("availability-submit").disabled, false);
    assert.doesNotMatch(ui.get("availability-result").textContent, /SYNTHETIC|collection/);
  }
});

test("concurrent Refresh and submit cannot create duplicate reads or requests", async () => {
  let resolveRead;
  let refreshing = false;
  const ui = await createUi({
    read: async () => refreshing ? new Promise((resolve) => { resolveRead = resolve; })
      : row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" })
  });
  await ui.submit();
  refreshing = true;
  const first = ui.refresh();
  await waitFor(() => resolveRead);
  await ui.refresh();
  await ui.submit();
  assert.equal(ui.calls.reads.length, 2);
  assert.equal(ui.calls.creates.length, 1);
  resolveRead(row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" }));
  await first;
  assert.equal(ui.get("availability-refresh").disabled, false);
});

test("a failed query read exposes read-only recovery, not raw errors or replacement queries", async () => {
  let failing = true;
  const ui = await createUi({
    read: async () => {
      if (failing) throw new Error("SYNTHETIC_READ_FAILURE");
      return row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" });
    }
  });
  await ui.submit();
  assert.equal(ui.calls.creates.length, 1);
  assert.equal(ui.calls.reads.length, 1);
  assert.equal(ui.calls.timers.length, 0);
  assert.equal(ui.get("availability-result").textContent,
    "Availability status could not be read. Use Refresh status to try again.");
  assert.equal(ui.get("availability-refresh").hidden, false);
  failing = false;
  await ui.refresh();
  assert.equal(ui.calls.creates.length, 1);
  assert.equal(ui.calls.reads.length, 2);
  assert.equal(ui.get("availability-result").classes.has("error"), false);
  assert.match(ui.get("availability-result").textContent, /No common slots/);
});

test("refreshing an acknowledged Pending query is read-only", async () => {
  let reads = 0;
  let now = Date.now();
  const ui = await createUi({
    clock: () => now,
    read: async () => ++reads < 3
      ? row(100000000)
      : row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" })
  });
  await ui.submit();
  now += 120000;
  await ui.calls.timers.shift()();
  assert.equal(ui.get("availability-refresh").hidden, false);
  assert.match(ui.get("availability-result").textContent, /still pending/i);
  await ui.get("availability-refresh").listeners.click();
  assert.equal(ui.calls.creates.length, 1);
  assert.deepEqual(ui.calls.reads.map((call) => call.id), [ui.ids[0], ui.ids[0], ui.ids[0]]);
  assert.equal(ui.calls.timers.length, 0);
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
});

test("new query after bounded polling timeout invalidates an old queued callback", async () => {
  let now = Date.now();
  let complete = false;
  const ui = await createUi({
    clock: () => now,
    read: async () => complete ? row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" }, now) : row(100000000)
  });
  await ui.submit();
  const oldPoll = ui.calls.timers.shift();
  now += 120000;
  await oldPoll();
  assert.equal(ui.get("availability-submit").disabled, false);
  complete = true;
  await ui.submit();
  const before = ui.calls.reads.length;
  await oldPoll();
  assert.equal(ui.calls.reads.length, before);
  assert.equal(ui.calls.creates.length, 2);
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
});

test("reference paging and entity metadata are respected without reading mailbox fields", async () => {
  const ui = await createUi({
    references: async (table, query) => table === "os_sr_loc" ? { entities: [] }
      : query === "synthetic-next-page" ? { entities: [{
        os_sr_taid: "11111111-1111-4111-8111-111111111111", os_sr_ta_nm: "[DEV] Paged TA"
      }] } : { entities: [], nextLink: "synthetic-next-page" },
    metadata: async () => ({ EntitySetName: "os_sr_ta_directory" })
  });
  await ui.submit();
  assert.equal(ui.calls.references.length, 3);
  assert.equal(ui.calls.creates[0].payload["os_sr_avq_ta@odata.bind"],
    `/os_sr_ta_directory(${ui.ids[0]})`);
  assert.equal(ui.get("availability-ta").children[1].textContent, "[DEV] Paged TA");
});

test("duplicate submission is ignored while the query read is in flight", async () => {
  const responses = new Map();
  const ui = await createUi({
    read: (id) => new Promise((resolve) => responses.set(id, resolve))
  });
  const first = ui.submit();
  await waitFor(() => responses.has(ui.ids[0]));
  await ui.submit();
  await ui.refresh();
  assert.equal(ui.calls.creates.length, 1);
  assert.equal(ui.calls.reads.length, 1);
  assert.equal(ui.get("availability-submit").disabled, true);
  responses.get(ui.ids[0])(row(100000002, { os_sr_avq_rsn: "NO_COMMON_SLOT" }));
  await first;
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");
  assert.equal(ui.get("availability-submit").disabled, false);
});

test("duplicate submission is ignored while Pending and a failed poll allows refresh", async () => {
  let failing = false;
  const ui = await createUi({
    read: async () => {
      if (failing) throw new Error("SYNTHETIC_POLL_FAILURE");
      return row(100000000);
    }
  });
  await ui.submit();
  await ui.submit();
  assert.equal(ui.calls.creates.length, 1);
  failing = true;
  await ui.calls.timers.shift()();
  assert.equal(ui.calls.timers.length, 0);
  assert.equal(ui.get("availability-refresh").hidden, false);
  assert.equal(ui.get("availability-submit").disabled, false);
  assert.doesNotMatch(ui.get("availability-result").textContent, /SYNTHETIC/);
});

test("duplicate submission is ignored during create and input snapshot cannot drift during metadata reads", async () => {
  const pending = new Map();
  const ui = await createUi({
    create: (table, payload, id) => new Promise((resolve) => pending.set(id, resolve))
  });
  const first = ui.submit();
  await waitFor(() => pending.has(ui.ids[0]));
  await ui.submit();
  assert.equal(ui.calls.creates.length, 1);
  pending.get(ui.ids[0])({ id: ui.ids[0] });
  await first;
  assert.deepEqual(ui.calls.reads.map((call) => call.id), [ui.ids[0]]);
  assert.equal(ui.get("availability-result").textContent, "No common slots were found in the requested window.");

  let metadataReady;
  const snapshot = await createUi({
    metadata: () => new Promise((resolve) => { metadataReady = resolve; })
  });
  const submission = snapshot.submit();
  await waitFor(() => metadataReady);
  snapshot.get("availability-ta").value = "";
  snapshot.get("availability-mode").value = "100000001";
  metadataReady({ EntitySetName: "os_sr_tas" });
  await submission;
  assert.equal(snapshot.calls.creates[0].payload.os_sr_avq_mod, 100000000);
  assert.equal(snapshot.calls.creates[0].payload["os_sr_avq_ta@odata.bind"],
    `/os_sr_tas(${snapshot.ids[0]})`);
});

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 20; attempt++) {
    if (predicate()) return;
    await new Promise((resolve) => setImmediate(resolve));
  }
  assert.fail("Expected synthetic poll was not reached.");
}
