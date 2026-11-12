const assert = require("node:assert/strict");
const { test } = require("node:test");
const { classifyRequest, matchesCandidateActionResponse } = require("./request-classification.cjs");

const origin = "https://orgsynthetic.crm4.dynamics.com";
const callbackOrigin = "https://callback.crm4.dynamics.com";
const options = { origin, callbackOrigin };
const request = (overrides = {}) => ({
  method: () => "POST", resourceType: () => "xhr", isNavigationRequest: () => false,
  headers: () => { throw new Error("Headers must not be read for this category"); },
  postData: () => { throw new Error("Body must not be read for this category"); },
  ...overrides
});
const classify = (url, overrides = {}, settings = options) =>
  classifyRequest(request(overrides), new URL(url), settings);

test("only exact correlated isolation verifiers are read-only; business dispatch remains forbidden", () => {
  const url = `${origin}/api/data/v9.2/os_sr_cact`;
  const verifier = require("../fixtures/synthetic-verifier-request.json");
  assert.equal(classify(url, { postData: () => JSON.stringify(verifier) }), "READ_ONLY_VERIFIER_ALLOWED");
  for (const body of [
    { ...verifier, CandidateId: "11111111-1111-4111-8111-111111111111" },
    { ActionType: "VerifySyntheticIsolation" },
    { ...verifier, CorrelationId: "" },
    { ...verifier, CorrelationId: "00000000-0000-0000-0000-000000000000" },
    { ...verifier, CorrelationId: "malformed" },
    { ...verifier, CorrelationId: 42 },
    { ...verifier, SyntheticScopeId: "11111111-1111-4111-8111-111111111111" },
    { ActionType: "CreateCandidate" }, {}, null
  ]) {
    assert.equal(classify(url, { postData: () => JSON.stringify(body) }),
      "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  }
  assert.equal(classify(`${url}?extra=1`, { postData: () => JSON.stringify(verifier) }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(url, { method: () => "PATCH", postData: () => JSON.stringify(verifier) }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  const singleUserVerifier = {
    ActionType: "VerifySingleUserDev",
    CorrelationId: "22222222-2222-4222-8222-222222222222"
  };
  assert.equal(classify(url, { postData: () => JSON.stringify(singleUserVerifier) }),
    "READ_ONLY_VERIFIER_ALLOWED");
});

test("only the fixed SingleUserDev read actions with exact correlation and scope are read-only", () => {
  const url = `${origin}/api/data/v9.2/os_sr_cact`;
  const requestBody = {
    ActionType: "ReadScopedCandidates",
    CorrelationId: "11111111-1111-4111-8111-111111111111",
    SyntheticScopeId: "22222222-2222-4222-8222-222222222222"
  };
  assert.equal(classify(url, { postData: () => JSON.stringify(requestBody) }),
    "SCOPED_READ_OPERATION_ALLOWED");
  for (const body of [
    { ...requestBody, CandidateId: "33333333-3333-4333-8333-333333333333" },
    { ...requestBody, SyntheticScopeId: "" },
    { ...requestBody, CorrelationId: "malformed" },
    { ...requestBody, ActionType: "ReadAnyTable" },
    { ...requestBody, ActionType: "CreateCandidate" },
    { ...requestBody, Table: "os_sr_cand" },
    null
  ]) {
    assert.equal(classify(url, { postData: () => JSON.stringify(body) }),
      "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  }
  assert.equal(classify(`${url}?extra=1`, { postData: () => JSON.stringify(requestBody) }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(url, { method: () => "PATCH", postData: () => JSON.stringify(requestBody) }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
});

test("lifecycle response waits ignore proof refresh and match only the intended correlated business action", () => {
  const url = `${origin}/api/data/v9.2/os_sr_cact`;
  const correlation = "11111111-1111-4111-8111-111111111111";
  const response = (body, target = url, overrides = {}) => ({
    url: () => target,
    request: () => request({ postData: () => JSON.stringify(body), ...overrides })
  });
  const verifier = require("../fixtures/synthetic-verifier-request.json");
  for (const action of ["CreateCandidate", "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled"]) {
    assert.equal(matchesCandidateActionResponse(response(verifier), origin, action, correlation), false);
    assert.equal(matchesCandidateActionResponse(response({
      ActionType: action, CorrelationId: correlation
    }), origin, action, correlation), true);
    assert.equal(matchesCandidateActionResponse(response({
      ActionType: action, CorrelationId: "22222222-2222-4222-8222-222222222222"
    }), origin, action, correlation), false);
    assert.equal(matchesCandidateActionResponse(response({
      ActionType: action, CorrelationId: correlation
    }), origin, action), false, "No response is admitted before durable correlation reservation");
    for (const invalid of ["", "invalid", "00000000-0000-0000-0000-000000000000", null]) {
      assert.equal(matchesCandidateActionResponse(response({
        ActionType: action, CorrelationId: invalid
      }), origin, action, correlation), false);
    }
    assert.equal(matchesCandidateActionResponse(response({
      ActionType: "OtherAction", CorrelationId: correlation
    }), origin, action, correlation), false);
    assert.equal(matchesCandidateActionResponse(response({
      ActionType: action, CorrelationId: correlation
    }, `${url}?extra=1`), origin, action, correlation), false);
    assert.equal(matchesCandidateActionResponse(response({
      ActionType: action, CorrelationId: correlation
    }, url, { method: () => "PATCH" }), origin, action, correlation), false);
    assert.equal(matchesCandidateActionResponse(response(null), origin, action, correlation), false);
  }
  assert.equal(matchesCandidateActionResponse(response(verifier), origin, "VerifySyntheticIsolation", correlation), false);
});

test("Recorded collector destination is suppressed across documented transports; missing metadata stays unknown", () => {
  // Historical blocked events retained only POST and this destination, not their transport or initiator.
  const url = "https://eu-mobile.events.data.microsoft.com/OneCollector/1.0/";
  for (const resourceType of ["xhr", "fetch", "ping"]) {
    assert.equal(classify(url, { resourceType: () => resourceType }), "OPTIONAL_TELEMETRY_SUPPRESSED");
  }
  assert.equal(classify(url, { resourceType: () => undefined }), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify(url, { resourceType: () => "other" }), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify(url, { isNavigationRequest: () => true }), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify(url, { method: () => "PUT" }), "UNKNOWN_REQUEST_BLOCKED");
});

test("Other pinned collectors are suppressed, not arbitrary Microsoft POSTs", () => {
  assert.equal(classify("https://browser.events.data.microsoft.com/OneCollector/1.0/",
    { resourceType: () => "fetch" }), "OPTIONAL_TELEMETRY_SUPPRESSED");
  assert.equal(classify("https://browser.pipe.aria.microsoft.com/Collector/3.0/",
    { resourceType: () => "ping" }), "OPTIONAL_TELEMETRY_SUPPRESSED");
  for (const url of ["https://eu-mobile.events.data.microsoft.com/other",
    "https://eu-mobile.events.data.microsoft.com.evil.invalid/OneCollector/1.0/",
    "http://eu-mobile.events.data.microsoft.com/OneCollector/1.0/",
    "https://unknown.microsoft.com/OneCollector/1.0/",
    "https://example.invalid/write"]) {
    assert.equal(classify(url), "UNKNOWN_REQUEST_BLOCKED");
  }
});

test("Legitimate synthetic Microsoft callback and regional federation handoff remain authentication", () => {
  const auth = {
    resourceType: () => "document", isNavigationRequest: () => true,
    headers: () => ({ "content-type": "application/x-www-form-urlencoded" }),
    frame: () => ({ url: () => "https://login.microsoftonline.com/authorize" }),
    postData: () => "code=SYNTHETIC&state=SYNTHETIC"
  };
  assert.equal(classify(`${callbackOrigin}/`, auth), "AUTH_NAVIGATION");
  assert.equal(classify(`${origin}/`, {
    ...auth, frame: () => ({ url: () => `${callbackOrigin}/` }),
    postData: () => "wa=wsignin1.0&wresult=SYNTHETIC&wctx=SYNTHETIC"
  }), "AUTH_NAVIGATION");
  assert.equal(classify(`${origin}/`, {
    ...auth, frame: () => ({ url: () => "https://untrusted.invalid/" })
  }), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify("https://login.microsoft.com/bridge", auth), "AUTH_NAVIGATION");
});

test("Only a separately validated one-shot operation can receive approved classification", () => {
  const url = `${origin}/api/data/v9.2/os_sr_cact`;
  // The runner sets this flag only after sequence, arm, payload and expiry checks.
  for (const action of ["CreateCandidate", "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled"]) {
    assert.equal(classify(url, { postData: () => JSON.stringify({ ActionType: action }) },
      { ...options, approvedBusinessOperation: true }), "APPROVED_BUSINESS_OPERATION");
    assert.equal(classify(url), "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  }
  assert.equal(classify(`${url}?extra=1`, {}, { ...options, approvedBusinessOperation: true }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(url, { method: () => "DELETE" }, { ...options, approvedBusinessOperation: true }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(url, { isNavigationRequest: () => true }, { ...options, approvedBusinessOperation: true }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
});

test("Direct/extra Candidate, call, schedule, email, configuration and provider operations remain forbidden", () => {
  for (const operation of ["os_sr_cands", "os_sr_calls", "os_sr_intvs", "SendEmail",
    "organizations", "environmentvariablevalues", "PublishXml", "$batch"]) {
    assert.equal(classify(`${origin}/api/data/v9.2/${operation}`, {},
      { ...options, approvedBusinessOperation: true }), "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  }
  for (const url of ["https://graph.microsoft.com/v1.0/me/events",
    "https://outlook.office.com/api/sendmail", "https://outlook.office365.com/api/events"]) {
    assert.equal(classify(url), "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  }
});

test("Optional CRM support is kept separate from telemetry and ordinary reads", () => {
  assert.equal(classify(`${origin}/AppWebServices/MetricsReportingService.asmx/Report`),
    "OPTIONAL_SUPPORT_SUPPRESSED");
  assert.equal(classify(`${origin}/api/data/v9.2/GetRecentItems`), "OPTIONAL_SUPPORT_SUPPRESSED");
  for (const version of ["v9.0", "v9.2"]) {
    for (const operation of ["msdyn_ReportToMonitoringHub", "GetRecentItems", "GetCopilotSettingsForEnvironment"]) {
      assert.equal(classify(`${origin}/api/data/${version}/${operation}`, {
        resourceType: () => "fetch"
      }), "OPTIONAL_SUPPORT_SUPPRESSED");
    }
  }
  assert.equal(classify(`${origin}/api/data/v9.2/GetRecentItems/extra`),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(`${origin}/api/data/v9.0/GetRecentItems`, {
    resourceType: () => "document", isNavigationRequest: () => true
  }), "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(`${origin}/api/data/v9.2/os_sr_cands`, { method: () => "GET" }),
    "READ_REQUEST_ALLOWED");
  assert.equal(classify(`${origin}/api/data/v9.0/os_sr_tas`, { method: () => "GET" }),
    "READ_REQUEST_ALLOWED");
  assert.equal(classify(`${origin}/main.aspx`, { method: () => "GET" }), "READ_REQUEST_ALLOWED");
  assert.equal(classify(`${origin}/api/data/v9.2/os_sr_cact`, { method: () => "POST" }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(`${origin}/api/data/v9.2/UnknownAction`, { method: () => "POST" }),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
  assert.equal(classify(`${origin}/AppWebServices/MetadataService.asmx/GetResourceStrings`, {
    resourceType: () => "xhr"
  }), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify("https://graph.microsoft.com/v1.0/me/photos/120x120/$value", {
    method: () => "GET"
  }), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify("https://graph.microsoft.com/v1.0/me/events", {
    method: () => "POST"
  }), "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
});
