"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const { createUi } = require("./helpers/AvailabilityConsoleHarness.cjs");
const { runFlow } = require("./helpers/AvailabilityFlowHarness.cjs");
const { invokeGuard } = require("./helpers/AvailabilityGuardBridge.cjs");
const { IDS, buildFixture, providerResult } = require("./helpers/CheckCalendarFixtures.cjs");

const schema = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "solutions", "Entities",
  "os_sr_avq", "AvailabilityQuery.schema.json"), "utf8")).table;
const flow = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "solutions", "AvailabilityQuery",
  "os_sr_avchk.clientdata.json"), "utf8")).properties.definition;
const TERMINAL_FIELDS = [
  "os_sr_avq_err", "os_sr_avq_exp", "os_sr_avq_qat",
  "os_sr_avq_rsn", "os_sr_avq_slts", "os_sr_avq_stat"
];

async function exercise({ onsite = false, roomBusy = false, empty = false, fault,
  drift = false, timezone, duplicate = false } = {}) {
  const fixture = buildFixture();
  const references = structuredClone(fixture.references);
  let persisted;
  let original;
  let providerAttempts = 0;
  const terminalWrites = [];
  const connectorCalls = [];
  const guard = (operation, payload) => invokeGuard({
    operation, payload, query: persisted, references,
    settings: fixture.settings, caller: operation === "Create" ? "requester" : "writer"
  });
  const ui = await createUi({
    clock: () => Date.parse(fixture.now),
    values: {
      "availability-mode": onsite ? "100000001" : "100000000",
      "availability-start": fixture.localStart,
      "availability-end": fixture.localEnd,
      "availability-duration": "60"
    },
    create(table, payload) {
      assert.equal(table, schema.logicalName);
      assert.equal(payload.os_sr_avq_mod, onsite ? 100000001 : 100000000);
      assert.equal(payload.os_sr_avq_strt, fixture.start.toISOString());
      assert.equal(payload.os_sr_avq_end, fixture.end.toISOString());
      const admitted = guard("Create", payload);
      assert.equal(admitted.accepted, true, admitted.error);
      persisted = { ...admitted.row, os_sr_avqid: IDS.query };
      assert.equal(persisted.os_sr_avq_stat, 100000000);
      original = structuredClone(persisted);
      return { id: IDS.query };
    },
    read(id, table) {
      assert.equal(table, schema.logicalName);
      assert.equal(id, IDS.query);
      return structuredClone(persisted);
    }
  });

  await ui.submit();
  assert.equal(ui.calls.creates.length, 1);
  assert.match(ui.get("availability-result").textContent, /pending/i);
  assert.equal(ui.calls.timers.length, 1);
  if (duplicate) {
    await ui.submit();
    assert.equal(ui.calls.creates.length, 1, "Pending submissions must not create another request.");
  }

  await runFlow({
    query: persisted,
    parameters: fixture.parameters,
    now: fixture.now,
    async getItem(parameters, actionName) {
      connectorCalls.push({ operation: "GetItem", actionName, entity: parameters.entityName });
      if (parameters.entityName === "os_sr_avqs") {
        assert.equal(parameters.recordId, IDS.query);
        return structuredClone(persisted);
      }
      if (parameters.entityName === "os_sr_tas") {
        assert.equal(parameters.recordId, references.ta.id);
        return {
          os_sr_taid: references.ta.id, statecode: references.ta.statecode,
          os_sr_ta_eml: references.ta.email
        };
      }
      assert.equal(parameters.entityName, "os_sr_locs");
      assert.equal(parameters.recordId, references.location.id);
      return {
        os_sr_locid: references.location.id, statecode: references.location.statecode,
        os_sr_loc_rmeml: references.location.roomEmail
      };
    },
    async outlook(parameters) {
      providerAttempts++;
      assert.equal(parameters["body/RequiredAttendees"], fixture.references.ta.email);
      assert.equal(parameters["body/ResourceAttendees"],
        onsite ? fixture.references.location.roomEmail : "");
      assert.equal(parameters["body/MeetingDuration"], 60);
      assert.equal(parameters["body/MinimumAttendeePercentage"], "100");
      assert.equal(parameters["body/IsOrganizerOptional"], true);
      assert.equal(parameters["body/ActivityDomain"], "Work");
      assert.deepEqual(Object.keys(parameters).sort(), [
        "body/RequiredAttendees", "body/ResourceAttendees", "body/MeetingDuration",
        "body/Start", "body/End", "body/MaxCandidates", "body/MinimumAttendeePercentage",
        "body/IsOrganizerOptional", "body/ActivityDomain"
      ].sort());
      if (drift) references.ta.email = "changed@example.invalid";
      if (fault) {
        const error = new Error("SYNTHETIC_PROVIDER_BODY_NOT_FOR_PERSISTENCE");
        error.statusCode = fault;
        throw error;
      }
      const response = providerResult(fixture, { onsite, roomBusy, empty });
      if (timezone) response.meetingTimeSuggestions[0].meetingTimeSlot.start.timeZone = timezone;
      return response;
    },
    async updateItem(parameters, actionName) {
      connectorCalls.push({ operation: "UpdateOnlyRecord", actionName, entity: parameters.entityName });
      assert.equal(parameters.entityName, schema.logicalName + "s");
      assert.equal(parameters.recordId, IDS.query);
      const patch = Object.fromEntries(Object.entries(parameters)
        .filter(([key]) => key.startsWith("item/")).map(([key, value]) => [key.slice(5), value]));
      assert.deepEqual(Object.keys(patch).sort(), TERMINAL_FIELDS);
      assert.equal(Object.keys(parameters).length, TERMINAL_FIELDS.length + 2);
      const admitted = guard("Update", patch);
      assert.equal(admitted.accepted, true, admitted.error);
      terminalWrites.push(patch);
      persisted = { ...persisted, ...patch };
      return structuredClone(persisted);
    }
  });

  assert.equal(providerAttempts, 1);
  assert.equal(terminalWrites.length, 1, "The Flow must persist exactly one acknowledged terminal result.");
  const terminal = terminalWrites[0];
  const validStates = schema.choices.os_sr_avq_stat.map((choice) => choice.value);
  assert.equal(validStates.includes(terminal.os_sr_avq_stat), true);
  for (const [key, value] of Object.entries(original)) {
    if (!TERMINAL_FIELDS.includes(key)) assert.deepEqual(persisted[key], value);
  }
  assert.equal(Date.parse(terminal.os_sr_avq_exp) - Date.parse(terminal.os_sr_avq_qat), 600000);
  assert.doesNotMatch(JSON.stringify(persisted), /@|SYNTHETIC_PROVIDER/);
  await ui.calls.timers.shift()();
  assert.equal(ui.calls.timers.length, 0);
  assert.equal(ui.calls.creates.length, 1);
  assert.equal(connectorCalls.every((call) =>
    ["os_sr_avqs", "os_sr_tas", "os_sr_locs"].includes(call.entity)), true);
  return { ui, terminal, fixture, connectorCalls };
}

test("Console payload and existing Pending trigger agree with the schema", () => {
  const trigger = Object.values(flow.triggers);
  assert.equal(trigger.length, 1);
  assert.equal(trigger[0].inputs.parameters["subscriptionRequest/entityname"], schema.logicalName);
  assert.equal(trigger[0].inputs.parameters["subscriptionRequest/message"], 1);
  assert.equal(trigger[0].inputs.parameters["subscriptionRequest/filterexpression"],
    "os_sr_avq_stat eq 100000000");
  assert.equal(schema.ownership, "UserOwned");
  assert.deepEqual(schema.choices.os_sr_avq_stat.map((choice) => choice.label),
    ["Pending", "Available", "NoSlots", "Failed"]);
});

for (const onsite of [false, true]) {
  test(`${onsite ? "Onsite" : "Online"} Console -> real guard -> actual Flow -> real guard -> visible slots`,
    async () => {
      const result = await exercise({ onsite, duplicate: true });
      assert.equal(result.terminal.os_sr_avq_stat, 100000001);
      assert.equal(result.terminal.os_sr_avq_rsn, null);
      assert.equal(result.terminal.os_sr_avq_err, null);
      assert.equal(result.terminal.os_sr_avq_slts, result.fixture.canonicalSlots);
      const children = result.ui.get("availability-result").children;
      assert.equal(children[0].textContent, "Available slots:");
      assert.equal(children[1].children.length, 1);
      assert.match(children[1].children[0].textContent, /09:00.*10:00.*Vietnam time/);
    });
}

for (const scenario of [{ onsite: true, roomBusy: true }, { empty: true }]) {
  test(scenario.roomBusy ? "A busy room is excluded from the complete path" :
    "Empty Outlook suggestions produce safe NoSlots in Console", async () => {
    const { terminal, ui } = await exercise(scenario);
    assert.equal(terminal.os_sr_avq_stat, 100000002);
    assert.equal(terminal.os_sr_avq_rsn, "NO_COMMON_SLOT");
    assert.equal(terminal.os_sr_avq_err, null);
    assert.equal(terminal.os_sr_avq_slts, "[]");
    assert.match(ui.get("availability-result").textContent, /No common slots/);
  });
}

for (const scenario of [
  { options: { fault: 429 }, error: "PROVIDER_THROTTLED", display: /Calendar service is busy/ },
  { options: { drift: true }, error: "REFERENCE_CHANGED", display: /changed during this query/ },
  { options: { timezone: "Pacific Standard Time" }, error: "PROVIDER_TIMEZONE_UNSUPPORTED",
    display: /timezone could not be verified/ }
]) {
  test(`Complete path fails closed with ${scenario.error}`, async () => {
    const { terminal, ui } = await exercise(scenario.options);
    assert.equal(terminal.os_sr_avq_stat, 100000003);
    assert.equal(terminal.os_sr_avq_rsn, null);
    assert.equal(terminal.os_sr_avq_err, scenario.error);
    assert.equal(terminal.os_sr_avq_slts, "[]");
    assert.match(ui.get("availability-result").textContent, scenario.display);
    assert.doesNotMatch(ui.get("availability-result").textContent, /@|SYNTHETIC_PROVIDER/);
  });
}

test("An invalid Console window never reaches Dataverse or Outlook", async () => {
  const ui = await createUi({ values: { "availability-start": "2099-01-05T09:00+07:00" } });
  await ui.submit();
  assert.equal(ui.calls.creates.length, 0);
  assert.equal(ui.calls.reads.length, 0);
});
