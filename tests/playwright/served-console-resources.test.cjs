const test = require("node:test");
const assert = require("node:assert/strict");
const { analyzeSource, createResourceEvidence, identifyConsoleResource, safeConsoleUrl } =
  require("./served-console-resources.cjs");
const { loadResourceManifest, verifyResourceHashes, evaluateCreateGate } =
  require("./served-console-resources.cjs");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const origin = "https://orgsynthetic.crm4.dynamics.com";

test("accepts only HTTPS same-origin Candidate Console resources", () => {
  assert.equal(identifyConsoleResource(`${origin}/WebResources/os_/bso/candidate-console.html`, origin)
    ?.name, "candidate-console.html");
  assert.equal(identifyConsoleResource("http://orgsynthetic.crm4.dynamics.com/candidate-console.js", origin), null);
  assert.equal(identifyConsoleResource("https://other.crm4.dynamics.com/candidate-console.js", origin), null);
  assert.equal(identifyConsoleResource(`${origin}/candidate-console-policy.js.evil`, origin), null);
  assert.equal(identifyConsoleResource(`${origin}/candidate-records`, origin), null);
});

test("redacts unrecognized iframe query values while retaining version tokens", () => {
  assert.deepEqual(safeConsoleUrl(
    `${origin}/WebResources/os_/bso/candidate-console.html?v=abc123&data=synthetic-secret`, origin),
  {
    origin,
    path: "/WebResources/os_/bso/candidate-console.html",
    query: [{ key: "data", value: "REDACTED" }, { key: "v", value: "abc123" }]
  });
});

test("records hashes, cache metadata, and safe identity without retaining response content", () => {
  const evidence = createResourceEvidence({
    rawUrl: `${origin}/candidate-console-policy.js?v=abc123`, expectedOrigin: origin,
    status: 200, headers: { "content-type": "application/javascript", "cache-control": "max-age=60",
      etag: '"abc123"', "last-modified": "Mon, 09 Nov 2026 10:00:00 GMT" },
    body: Buffer.from("window.BsoRsCandidateConsolePolicy = {};"), sequence: 2, fromServiceWorker: false
  });
  assert.equal(evidence.status, 200);
  assert.equal(evidence.byteLength, Buffer.byteLength("window.BsoRsCandidateConsolePolicy = {};"));
  assert.match(evidence.sha256, /^[a-f0-9]{64}$/);
  assert.equal(evidence.url.query[0].value, "abc123");
  assert.equal("body" in evidence, false);
  assert.equal("headers" in evidence, false);
});

test("extracts only Candidate Console script references and cache tokens", () => {
  const result = analyzeSource("candidate-console.html", [
    '<button id="create-button">Create</button>',
    '<script defer src="candidate-console-policy.js?v=abc123"></script>',
    '<script defer src="candidate-console.js?data=private"></script>',
    '<script src="unrelated.js"></script>'
  ].join("\n"));
  assert.deepEqual(result.deferredScriptReferences.map(script => script.path), [
    "/candidate-console-policy.js", "/candidate-console.js"
  ]);
  assert.equal(result.deferredScriptReferences[0].query[0].value, "abc123");
  assert.equal(result.deferredScriptReferences[1].query[0].value, "REDACTED");
  assert.equal(result.createButtonInitiallyDisabled, false);
});

test("identifies fail-closed policy and initialization signatures", () => {
  const policy = analyzeSource("candidate-console-policy.js", [
    "function hasSyntheticIsolation() { return false; }",
    'Object.defineProperty(global, "BsoRsCandidateConsolePolicy", {});'
  ].join("\n"));
  assert.deepEqual(policy, {
    definesPolicyGlobal: true, definesIsolationCheck: true, isolationReturnsLiteralFalse: true
  });

  const main = analyzeSource("candidate-console.js", [
    "function isCandidateCoreEnabled() {",
    "  const policy = window.BsoRsCandidateConsolePolicy;",
    "  return Boolean(policy && policy.hasSyntheticIsolation() === true);",
    "}",
    "async function initialize() {",
    "  if (!isCandidateCoreEnabled()) {",
    '  $("create-button").disabled = true;',
    "    return;",
    "  }",
    "}"
  ].join("\n"));
  assert.equal(main.referencesPolicyGlobal, true);
  assert.equal(main.requiresTrueIsolationResult, true);
  assert.equal(main.hasInitializationEarlyExit, true);
  assert.deepEqual(main.createButtonAssignments, [{ line: 7, disabled: "true" }]);
  assert.ok(main.enablementDecisionStatements.some(statement => statement.statement.includes("hasSyntheticIsolation")));
  assert.ok(main.initializationDecisionStatements.some(statement => statement.statement.includes("return;")));
});

test("expected resource manifests require the exact target and five-resource scope", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "console-manifest-"));
  const file = path.join(directory, "manifest.json");
  const approval = { origin, organizationId: "22222222-2222-4222-8222-222222222222" };
  const names = ["candidate-console.html", "candidate-console-environment.js", "candidate-console-policy.js",
    "candidate-console.js", "candidate-console-availability.js"];
  const manifest = {
    schemaVersion: 1,
    target: { organizationUrl: origin, organizationId: approval.organizationId,
      environmentId: "11111111-1111-4111-8111-111111111111", solutionUniqueName: "os_sr_bso_rs_support" },
    resources: names.map(name => ({ name: `os_/bso/${name}`, expectedSha256: "a".repeat(64) }))
  };
  try {
    fs.writeFileSync(file, JSON.stringify(manifest));
    assert.equal(loadResourceManifest(file, approval).resources.length, 5);
    assert.throws(() => loadResourceManifest(file, { ...approval, origin: "https://other.invalid" }),
      /UAT_RESOURCE_MANIFEST_INVALID/);
    assert.throws(() => loadResourceManifest("relative.json", approval), /UAT_ABSOLUTE_RESOURCE_MANIFEST_REQUIRED/);
    manifest.resources[4] = manifest.resources[0];
    fs.writeFileSync(file, JSON.stringify(manifest));
    assert.throws(() => loadResourceManifest(file, approval), /UAT_RESOURCE_MANIFEST_INVALID/);
  } finally {
    fs.rmSync(file);
    fs.rmdirSync(directory);
  }
});

test("read-only verification rejects missing, stale and unsuccessful served resources", () => {
  const manifest = { resources: [{ name: "os_/bso/candidate-console.js", expectedSha256: "a".repeat(64) }] };
  const good = { name: "candidate-console.js", status: 200, sha256: "a".repeat(64) };
  assert.equal(verifyResourceHashes([good], manifest)[0].result, "MATCH");
  for (const observed of [[], [{ ...good, status: 404 }], [{ ...good, sha256: "b".repeat(64) }],
    [good, { ...good, sha256: "b".repeat(64) }]]) {
    assert.equal(verifyResourceHashes(observed, manifest)[0].result, "MISMATCH");
  }
});

test("a correct fail-closed Create gate is not synthetic-isolation acceptance", () => {
  const result = evaluateCreateGate({
    policyAvailable: true, isolation: false, createEnabled: false, knownIsolationBlock: true
  });
  assert.equal(result.passed, true);
  assert.equal(result.syntheticIsolation, "BLOCKED");
  assert.equal(result.reason, "SERVER_SIDE_SYNTHETIC_ISOLATION_UNAVAILABLE");
  for (const gate of [
    { policyAvailable: false, isolation: false, createEnabled: true, knownIsolationBlock: false },
    { policyAvailable: true, isolation: false, createEnabled: true, knownIsolationBlock: false },
    { policyAvailable: true, isolation: false, createEnabled: false, knownIsolationBlock: false },
    { policyAvailable: true, isolation: true, createEnabled: false, knownIsolationBlock: false }
  ]) {
    assert.equal(evaluateCreateGate(gate).passed, false);
  }
});
