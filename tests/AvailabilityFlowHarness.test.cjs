"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { runFlow, parseExpression, validateSchema, EvaluationError, Unsupported } =
  require("./helpers/AvailabilityFlowHarness.cjs");

const run = (actions, options = {}) => runFlow({
  definition: { actions }, query: {}, parameters: {}, now: "2035-02-05T00:00:00Z", ...options
});
const compose = (inputs, runAfter = {}) => ({ type: "Compose", inputs, runAfter });

test("fixture expressions preserve optional paths and select only the chosen if branch", async () => {
  const result = await run({
    Optional: compose("@triggerOutputs()?['body/missing']"),
    Chosen: compose("@if(equals(1,1), 'chosen', int('invalid'))")
  });
  assert.equal(result.outputs.Optional, null);
  assert.equal(result.outputs.Chosen, "chosen");
});

test("fixture URI encoding preserves literal percent escapes and encodes control characters", async () => {
  const result = await run({
    Encoded: compose("@uriComponent(parameters('text'))"),
    Invalid: compose("@uriComponent(parameters('notText'))")
  }, { parameters: { text: "literal%01\u0001\u007f", notText: 1 } });
  assert.equal(result.outputs.Encoded, "literal%2501%01%7F");
  assert.equal(result.statuses.Invalid, "Failed");
});

test("fixture and/or evaluate arguments and failed actions drive runAfter handling", async () => {
  const result = await run({
    Failed: compose("@and(false, equals(int('invalid'), 1))"),
    Skipped: compose("must not run", { Failed: ["Succeeded"] }),
    Handled: compose("@actions('Failed')?['status']", { Failed: ["Failed"] })
  });
  assert.equal(result.statuses.Failed, "Failed");
  assert.equal(result.statuses.Skipped, "Skipped");
  assert.equal(result.outputs.Handled, "Failed");
  assert.match(result.errors.Failed.message, /integer/);
});

test("fixture ticks preserve a single 100-nanosecond difference and date formatting", async () => {
  const result = await run({
    Ticks: compose("@sub(ticks('2035-02-05T03:00:00.0000001Z'), ticks('2035-02-05T03:00:00Z'))"),
    Time: compose("@formatDateTime('2035-02-05T03:00:00.1234567Z', 'yyyy-MM-ddTHH:mm:ss.fffffffZ')"),
    Local: compose("@convertFromUtc('2035-02-05T03:00:00Z', 'SE Asia Standard Time', 'HH:mm')"),
    Invalid: compose("@ticks('2035-02-31T03:00:00Z')")
  });
  assert.equal(result.outputs.Ticks, 1n);
  assert.equal(result.outputs.Time, "2035-02-05T03:00:00.1234567Z");
  assert.equal(result.outputs.Local, "10:00");
  assert.equal(result.statuses.Invalid, "Failed");
});

test("fixture nested scope failure skips downstream work and reaches its failure handler", async () => {
  const result = await run({
    Scope: {
      type: "Scope", actions: {
        Invalid: compose("@int('invalid')"),
        Skipped: compose("not run", { Invalid: ["Succeeded"] })
      }, runAfter: {}
    },
    Recovery: compose("safe", { Scope: ["Failed"] })
  });
  assert.equal(result.statuses.Scope, "Failed");
  assert.equal(result.statuses.Skipped, "Skipped");
  assert.equal(result.outputs.Recovery, "safe");
});

test("fixture connector failure retains only the status contract and never retries", async () => {
  let attempts = 0;
  const result = await run({
    Provider: {
      type: "OpenApiConnection",
      inputs: { host: { operationId: "FindMeetingTimes_V2" }, parameters: {}, retryPolicy: { type: "none" } },
      runAfter: {}
    },
    Code: compose("@outputs('Provider')?['statusCode']", { Provider: ["Failed"] })
  }, {
    outlook: async () => {
      attempts++;
      const error = new Error("SYNTHETIC_PRIVATE_ERROR");
      error.statusCode = 429;
      throw error;
    }
  });
  assert.equal(attempts, 1);
  assert.equal(result.outputs.Code, 429);
  assert.doesNotMatch(JSON.stringify(result.outputs), /SYNTHETIC_PRIVATE_ERROR/);
});

test("fixture termination stops later connector operations", async () => {
  const result = await run({
    Stop: { type: "Terminate", inputs: { runStatus: "Cancelled" }, runAfter: {} },
    Later: compose("not run", { Stop: ["Succeeded"] })
  });
  assert.equal(result.status, "Cancelled");
  assert.equal(result.statuses.Later, "Skipped");
});

test("fixture JSON Schema rejects malformed shapes, duplicates and extra members", () => {
  const schema = {
    type: "object", required: ["values"], additionalProperties: false,
    properties: {
      values: { type: "array", minItems: 1, uniqueItems: true,
        items: { type: "integer", minimum: 15, maximum: 480, multipleOf: 15 } },
      optional: { type: ["string", "null"], not: { enum: ["forbidden"] } }
    }
  };
  validateSchema({ values: [30, 60], optional: null }, schema);
  for (const value of [
    { values: [] }, { values: [30, 30] }, { values: [31] }, { values: [30.5] },
    { values: [30], extra: true }, { values: [30], optional: "forbidden" }
  ]) assert.throws(() => validateSchema(value, schema), EvaluationError);
});

test("unsupported fixture semantics fail the test rather than produce a successful Flow fallback", async () => {
  assert.throws(() => parseExpression("unknown + syntax"), Unsupported);
  assert.throws(() => validateSchema({}, { unsupportedKeyword: true }), Unsupported);
  assert.throws(() => validateSchema({}, { additionalProperties: { type: "string" } }), Unsupported);
  assert.throws(() => validateSchema([], { items: [{ type: "string" }] }), Unsupported);
  await assert.rejects(run({ Unknown: compose("@unknownFunction()") }), Unsupported);
  await assert.rejects(run({ Unknown: { type: "Unknown", runAfter: {} } }), Unsupported);
});
