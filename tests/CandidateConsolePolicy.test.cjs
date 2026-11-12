"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const webRoot = path.join(
  __dirname,
  "..",
  "solutions",
  "CandidateConsole",
  "WebResources",
  "os_",
  "bso"
);
const configurationSource = fs.readFileSync(
  path.join(webRoot, "candidate-console-environment.js"),
  "utf8"
);
const policySource = fs.readFileSync(
  path.join(webRoot, "candidate-console-policy.js"),
  "utf8"
);

function createPolicy(fetch, crypto = require("node:crypto").webcrypto) {
  const context = vm.createContext({ window: { fetch, crypto }, URL });
  vm.runInContext(policySource, context);
  return context.window.BsoRsCandidateConsolePolicy;
}

function configuration(overrides = {}) {
  return {
    mode: "DEV",
    environmentId: "11111111-1111-4111-8111-111111111111",
    organizationId: "22222222-2222-4222-8222-222222222222",
    organizationUrl: "https://dev.example.invalid",
    candidateCoreEnabled: true,
    syntheticDataOnly: true,
    candidateOperationMode: "BsoSynthetic",
    devDirectWriteFallbackEnabled: true,
    diagnosticsMode: "OFF",
    ...overrides
  };
}

function runtime(overrides = {}) {
  return {
    organizationUrl: "https://dev.example.invalid/",
    organizationId: "22222222-2222-4222-8222-222222222222",
    ...overrides
  };
}

test("the checked-in environment template is disabled and unconfigured", () => {
  const context = vm.createContext({ window: {} });
  vm.runInContext(configurationSource, context);
  const value = context.window.BsoRsCandidateConsoleConfiguration;

  assert.equal(value.mode, "UNCONFIGURED");
  assert.equal(value.candidateCoreEnabled, false);
  assert.equal(value.syntheticDataOnly, true);
  assert.equal(value.candidateOperationMode, "BsoSynthetic");
  assert.equal(value.devDirectWriteFallbackEnabled, false);
  assert.equal(value.diagnosticsMode, "OFF");
});

test("a matching DEV configuration resolves without granting synthetic data access", () => {
  const result = createPolicy().resolve(configuration(), runtime());

  assert.equal(result.allowed, true);
  assert.equal(result.mode, "DEV");
  assert.equal(result.syntheticDataOnly, true);
  assert.equal(result.directWriteFallbackAvailable, true);
});

test("synthetic isolation is not granted by browser configuration", () => {
  const policy = createPolicy();
  assert.equal(policy.hasSyntheticIsolation(), false);
  assert.equal(policy.hasSyntheticIsolation({
    syntheticDataOnly: true,
    syntheticIsolationVerified: true,
    approvedReferences: ["11111111-1111-4111-8111-111111111111"]
  }), false);
});

function verifierFixture(overrides = {}) {
  return {
    version: 2, boundary: "ScopedCandidateCoreApi", nativeWritesDenied: true, readback: "CallerOwnedScope",
    organizationId: runtime().organizationId, environmentId: configuration().environmentId,
    actorId: "33333333-3333-4333-8333-333333333333",
    scopeId: "44444444-4444-4444-8444-444444444444",
    candidateId: "44444444-4444-4444-8444-444444444444",
    positionId: "55555555-5555-4555-8555-555555555555",
    sourceId: "66666666-6666-4666-8666-666666666666",
    taId: "77777777-7777-4777-8777-777777777777",
    locationId: "88888888-8888-4888-8888-888888888888",
    validUntil: new Date(Date.now() + 60000).toISOString(), calendarEnabled: false, ...overrides
  };
}

test("the actual policy enables synthetic scope only after a same-origin server response", async () => {
  const proof = verifierFixture();
  const calls = [];
  const policy = createPolicy(async (url, request) => {
    calls.push({ url, request });
    return { ok: true, json: async () => ({
      ResultCode: "SyntheticIsolationVerified", IsolationContract: JSON.stringify(proof)
    }) };
  });
  assert.equal(policy.hasSyntheticIsolation(), false);
  await policy.verifySyntheticIsolation(configuration(), runtime({ actorId: proof.actorId }));
  assert.equal(policy.hasSyntheticIsolation(), true);
  assert.equal(policy.getSyntheticScope().scopeId, proof.scopeId);
  assert.equal(policy.getSyntheticScope().calendarEnabled, false);
  assert.match(policy.syntheticCandidateFilter(), new RegExp(`os_sr_candid eq ${proof.candidateId}`));
  assert.match(policy.syntheticReferenceFilter("os_sr_ta_nm"), new RegExp(`os_sr_taid eq ${proof.taId}`));
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "/api/data/v9.2/os_sr_cact");
  const body = JSON.parse(calls[0].request.body);
  assert.deepEqual(Object.keys(body).sort(), ["ActionType", "CorrelationId"]);
  assert.equal(body.ActionType, "VerifySyntheticIsolation");
  assert.match(body.CorrelationId, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  await policy.verifySyntheticIsolation(configuration(), runtime({ actorId: proof.actorId }));
  assert.notEqual(JSON.parse(calls[1].request.body).CorrelationId, body.CorrelationId);
});

test("SingleUserDev requires its distinct server proof and cannot enable direct-write fallback", async () => {
  const proof = verifierFixture({
    version: 4,
    boundary: "SingleUserDevCandidateCoreApi",
    mode: "SingleUserDev",
    nativeWritesDenied: false,
    scopedReads: true,
    globalGuardsRequired: false
  });
  const calls = [];
  const config = configuration({
    candidateOperationMode: "SingleUserDev",
    devDirectWriteFallbackEnabled: false
  });
  const policy = createPolicy(async (url, request) => {
    calls.push({ url, request });
    return { ok: true, json: async () => ({
      ResultCode: "SingleUserDevVerified", IsolationContract: JSON.stringify(proof)
    }) };
  });
  const resolved = policy.resolve(config, runtime({ actorId: proof.actorId }));
  assert.equal(resolved.allowed, true);
  assert.equal(resolved.directWriteFallbackAvailable, false);
  await policy.verifySyntheticIsolation(config, runtime({ actorId: proof.actorId }));
  assert.equal(policy.getSyntheticScope().mode, "SingleUserDev");
  assert.equal(calls.length, 1);
  assert.equal(JSON.parse(calls[0].request.body).ActionType, "VerifySingleUserDev");
});

test("SingleUserDev rejects the guard-dependent v3 proof and incomplete scoped-read proofs", async () => {
  const config = configuration({
    candidateOperationMode: "SingleUserDev",
    devDirectWriteFallbackEnabled: false
  });
  for (const proof of [
    verifierFixture({ version: 3, boundary: "SingleUserDevCandidateCoreApi", mode: "SingleUserDev",
      nativeWritesDenied: false }),
    verifierFixture({ version: 4, boundary: "SingleUserDevCandidateCoreApi", mode: "SingleUserDev",
      nativeWritesDenied: false, scopedReads: true, globalGuardsRequired: true }),
    verifierFixture({ version: 4, boundary: "SingleUserDevCandidateCoreApi", mode: "SingleUserDev",
      nativeWritesDenied: false, scopedReads: false, globalGuardsRequired: false })
  ]) {
    const policy = createPolicy(async () => ({
      ok: true, json: async () => ({
        ResultCode: "SingleUserDevVerified", IsolationContract: JSON.stringify(proof)
      })
    }));
    await assert.rejects(policy.verifySyntheticIsolation(config,
      runtime({ actorId: proof.actorId })), /SYNTHETIC_VERIFIER_RESPONSE_INVALID/);
    assert.equal(policy.hasSyntheticIsolation(), false);
  }
});

test("SingleUserDev rejects fallback-enabled or non-DEV configuration", () => {
  assert.equal(createPolicy().resolve(configuration({
    candidateOperationMode: "SingleUserDev",
    devDirectWriteFallbackEnabled: true
  }), runtime()).allowed, false);
  assert.equal(createPolicy().resolve(configuration({
    mode: "TEST",
    candidateOperationMode: "SingleUserDev",
    devDirectWriteFallbackEnabled: false
  }), runtime()).allowed, false);
});

test("unavailable or invalid verifier UUID generation fails closed before dispatch", async () => {
  for (const crypto of [null, {}, { randomUUID: () => "" }, { randomUUID: () => "not-a-guid" },
    { randomUUID: () => "00000000-0000-0000-0000-000000000000" }]) {
    let dispatched = false;
    const policy = createPolicy(async () => { dispatched = true; }, crypto);
    await assert.rejects(policy.verifySyntheticIsolation(configuration(),
      runtime({ actorId: verifierFixture().actorId })), /SYNTHETIC_VERIFIER_CORRELATION_UNAVAILABLE/);
    assert.equal(dispatched, false);
    assert.equal(policy.hasSyntheticIsolation(), false);
  }
});

test("browser emits the exact wire fixture exercised by the SDK handler", async () => {
  const wire = require("./fixtures/synthetic-verifier-request.json");
  let emitted;
  const policy = createPolicy(async (_url, request) => {
    emitted = JSON.parse(request.body);
    return { ok: true, json: async () => ({
      ResultCode: "SyntheticIsolationVerified", IsolationContract: JSON.stringify(verifierFixture())
    }) };
  }, { randomUUID: () => wire.CorrelationId });
  await policy.verifySyntheticIsolation(configuration(), runtime({ actorId: verifierFixture().actorId }));
  assert.deepEqual(emitted, wire);
});

for (const [label, invalid] of Object.entries({
  "wrong organization": { organizationId: "99999999-9999-4999-8999-999999999999" },
  "wrong environment": { environmentId: "99999999-9999-4999-8999-999999999999" },
  "wrong actor": { actorId: "99999999-9999-4999-8999-999999999999" },
  "unbound Candidate": { candidateId: "99999999-9999-4999-8999-999999999999" },
  "missing TA": { taId: null }, "unapproved reference response": { locationId: "forged" },
  "expired response": { validUntil: new Date(0).toISOString() },
  "unbounded response": { validUntil: new Date(Date.now() + 600000).toISOString() },
  "Calendar enabled": { calendarEnabled: true },
  "old full-isolation contract": { version: 1 },
  "wrong boundary": { boundary: "Unrestricted" },
  "native writes allowed": { nativeWritesDenied: false },
  "unbounded readback": { readback: "AllCandidates" }
})) {
  test(`server proof fails closed: ${label}`, async () => {
    const policy = createPolicy(async () => ({ ok: true, json: async () => ({
      ResultCode: "SyntheticIsolationVerified", IsolationContract: JSON.stringify(verifierFixture(invalid))
    }) }));
    await assert.rejects(policy.verifySyntheticIsolation(configuration(),
      runtime({ actorId: verifierFixture().actorId })), /SYNTHETIC_VERIFIER_RESPONSE_INVALID/);
    assert.equal(policy.hasSyntheticIsolation(), false);
    assert.equal(policy.getSyntheticScope(), null);
  });
}

test("a failed refresh clears a previous proof; errors never synthesize success", async () => {
  let unavailable = false;
  const proof = verifierFixture();
  const policy = createPolicy(async () => unavailable ? { ok: false } : {
    ok: true, json: async () => ({ ResultCode: "SyntheticIsolationVerified", IsolationContract: JSON.stringify(proof) })
  });
  const context = runtime({ actorId: proof.actorId });
  await policy.verifySyntheticIsolation(configuration(), context);
  unavailable = true;
  await assert.rejects(policy.verifySyntheticIsolation(configuration(), context), /SYNTHETIC_VERIFIER_UNAVAILABLE/);
  assert.equal(policy.hasSyntheticIsolation(), false);
  const missing = createPolicy();
  await assert.rejects(missing.verifySyntheticIsolation(configuration(), context));
  assert.equal(missing.hasSyntheticIsolation(), false);
});

test("synthetic Create stays disabled before reads when server isolation is unavailable", () => {
  const source = fs.readFileSync(path.join(webRoot, "candidate-console.js"), "utf8");
  const coreGate = source.match(/function isCandidateCoreEnabled\(\) \{[\s\S]*?\n  \}/);
  const initialization = source.match(/async function initialize\(\) \{([\s\S]*?)\n  \}/);
  assert.ok(coreGate && initialization);
  assert.match(coreGate[0], /environmentPolicy\.syntheticDataOnly[\s\S]*?policy\.hasSyntheticIsolation\(\) === true/);
  const blockedBranch = initialization[1].match(/if \(!isCandidateCoreEnabled\(\)\) \{([\s\S]*?)\n    \}/);
  assert.ok(blockedBranch);
  assert.match(blockedBranch[1], /\$\("create-button"\)\.disabled = true/);
  assert.match(blockedBranch[1], /server-side synthetic data isolation/);
  assert.match(blockedBranch[1], /\breturn;/);
  assert.ok(initialization[1].indexOf(blockedBranch[0]) <
    initialization[1].indexOf('loadLookupOptions("os_sr_pos"'));
});

test("synthetic query helpers escape literal brackets and reject invalid attribute paths", () => {
  const policy = createPolicy();
  assert.equal(policy.syntheticCandidateFilter(),
    "startswith(os_sr_cand_nm,'[[]SYNTHETIC-E2E]') and endswith(os_sr_cand_eml,'.invalid')");
  assert.equal(policy.syntheticCandidateFilter("os_sr_call_cand"),
    "startswith(os_sr_call_cand/os_sr_cand_nm,'[[]SYNTHETIC-E2E]') and " +
    "endswith(os_sr_call_cand/os_sr_cand_eml,'.invalid')");
  assert.equal(policy.syntheticReferenceFilter("os_sr_ta_nm", "os_sr_cand_ta"),
    "startswith(os_sr_cand_ta/os_sr_ta_nm,'[[]DEV]')");
  assert.throws(() => policy.syntheticReferenceFilter("os_sr_ta_nm or statecode eq 0"));
  assert.throws(() => policy.syntheticCandidateFilter("os_sr_call_cand/extra"));
  assert.equal(policy.hasSyntheticIsolation(), false);
});

test("TEST never enables the direct-write fallback", () => {
  const result = createPolicy().resolve(
    configuration({ mode: "TEST", devDirectWriteFallbackEnabled: true }),
    runtime()
  );

  assert.equal(result.allowed, true);
  assert.equal(result.directWriteFallbackAvailable, false);
});

test("PROD fallback stays unavailable even when requested in configuration", () => {
  const result = createPolicy().resolve(
    configuration({
      mode: "PROD",
      syntheticDataOnly: false,
      devDirectWriteFallbackEnabled: true
    }),
    runtime()
  );

  assert.equal(result.allowed, true);
  assert.equal(result.syntheticDataOnly, false);
  assert.equal(result.directWriteFallbackAvailable, false);
});

test("reference selection follows syntheticDataOnly rather than environment mode", () => {
  const policy = createPolicy();
  const dev = policy.resolve(configuration(), runtime());
  const test = policy.resolve(
    configuration({ mode: "TEST", devDirectWriteFallbackEnabled: false }),
    runtime()
  );
  const prod = policy.resolve(
    configuration({ mode: "PROD", syntheticDataOnly: false }),
    runtime()
  );

  assert.equal(policy.allowsReference("[DEV] Software Engineer", dev.syntheticDataOnly), true);
  assert.equal(policy.allowsReference("Software Engineer", test.syntheticDataOnly), false);
  assert.equal(policy.allowsReference("Production Software Engineer", prod.syntheticDataOnly), true);
  assert.equal(policy.allowsReference("[DEV] Software Engineer", prod.syntheticDataOnly), false);
  assert.equal(policy.allowsReference("", false), false);
  assert.equal(policy.allowsReference(null, false), false);
  assert.equal(policy.allowsReference("Software Engineer", undefined), false);
});

test("unapproved real-data mode is rejected outside PROD", () => {
  const result = createPolicy().resolve(
    configuration({ syntheticDataOnly: false }),
    runtime()
  );

  assert.equal(result.allowed, false);
  assert.equal(result.reason, "CONFIGURATION_INVALID");
});

test("the browser organization URL and ID must match the configured target", () => {
  const policy = createPolicy();

  assert.equal(
    policy.resolve(configuration(), runtime({ organizationUrl: "https://other.example.invalid" })).reason,
    "ENVIRONMENT_IDENTITY_MISMATCH"
  );
  assert.equal(
    policy.resolve(configuration(), runtime({ organizationId: "33333333-3333-4333-8333-333333333333" })).reason,
    "ENVIRONMENT_IDENTITY_MISMATCH"
  );
});

test("runtime organization IDs with braces are normalized before comparison", () => {
  const result = createPolicy().resolve(
    configuration(),
    runtime({ organizationId: "{22222222-2222-4222-8222-222222222222}" })
  );

  assert.equal(result.allowed, true);
});

test("invalid or unconfigured policies fail closed", () => {
  const policy = createPolicy();

  assert.equal(policy.resolve(null, runtime()).allowed, false);
  assert.equal(
    policy.resolve(configuration({ mode: "UNCONFIGURED" }), runtime()).reason,
    "BLOCK_UNRECOGNIZED_ENVIRONMENT"
  );
  assert.equal(
    policy.resolve(configuration({ mode: "STAGING" }), runtime()).reason,
    "BLOCK_UNRECOGNIZED_ENVIRONMENT"
  );
  assert.equal(
    policy.resolve(configuration({ candidateCoreEnabled: false }), runtime()).reason,
    "CONFIGURATION_INVALID"
  );
  assert.equal(
    policy.resolve(configuration({ organizationId: "" }), runtime()).reason,
    "CONFIGURATION_INVALID"
  );
  assert.equal(
    policy.resolve(configuration({ organizationUrl: "http://dev.example.invalid" }), runtime()).reason,
    "CONFIGURATION_INVALID"
  );
});

test("Record Call availability mirrors the Candidate Core RecordCall transition", () => {
  const consoleSource = fs.readFileSync(path.join(webRoot, "candidate-console.js"), "utf8");
  const statusBlock = consoleSource.match(/const STATUS = \{[\s\S]*?\n  \};/);
  const gateBlock = consoleSource.match(/function canRecordCall\(status\) \{[\s\S]*?\n  \}/);
  assert.ok(statusBlock && gateBlock);
  const context = vm.createContext({});
  vm.runInContext(
    `${statusBlock[0]}\n${gateBlock[0]}\nthis.STATUS = STATUS;\nthis.canRecordCall = canRecordCall;`,
    context
  );
  const { STATUS, canRecordCall } = context;
  assert.equal(canRecordCall(STATUS.needCall), true);
  for (const status of [
    STATUS.answered,
    STATUS.waitingManualScheduling,
    STATUS.round1Scheduled,
    STATUS.offerExtended,
    STATUS.candidateFailed
  ]) {
    assert.equal(canRecordCall(status), false, `status ${status}`);
  }
  assert.equal(canRecordCall(undefined), false);
  assert.equal(canRecordCall(String(STATUS.needCall)), false);
});
