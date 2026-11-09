const test = require("node:test");
const assert = require("node:assert/strict");
const { analyzeSource, createResourceEvidence, identifyConsoleResource, safeConsoleUrl } =
  require("./served-console-resources.cjs");

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
