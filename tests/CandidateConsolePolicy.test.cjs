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

function createPolicy() {
  const context = vm.createContext({ window: {}, URL });
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
  assert.equal(value.devDirectWriteFallbackEnabled, false);
  assert.equal(value.diagnosticsMode, "OFF");
});

test("a matching DEV configuration enables Candidate Core and only configured fallback", () => {
  const result = createPolicy().resolve(configuration(), runtime());

  assert.equal(result.allowed, true);
  assert.equal(result.mode, "DEV");
  assert.equal(result.syntheticDataOnly, true);
  assert.equal(result.directWriteFallbackAvailable, true);
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
    policy.resolve(configuration({ candidateCoreEnabled: false }), runtime()).reason,
    "CONFIGURATION_INVALID"
  );
  assert.equal(
    policy.resolve(configuration({ organizationUrl: "http://dev.example.invalid" }), runtime()).reason,
    "CONFIGURATION_INVALID"
  );
});
