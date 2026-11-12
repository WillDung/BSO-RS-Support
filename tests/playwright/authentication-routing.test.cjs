const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  resolveAuthenticationRouting, inspectAuthenticationHandoff
} = require("./authentication-routing.cjs");
const { classifyRequest } = require("./request-classification.cjs");

const organizationOrigin = "https://orgsynthetic.crm4.dynamics.com";
const callbackOrigin = "https://callback.crm4.dynamics.com";
const routing = resolveAuthenticationRouting({
  organizationOrigin, pinnedCallbackOrigin: callbackOrigin
});

const request = (overrides = {}) => ({
  url: () => `${organizationOrigin}/`,
  method: () => "POST",
  resourceType: () => "document",
  isNavigationRequest: () => true,
  headers: () => ({ "content-type": "application/x-www-form-urlencoded; charset=UTF-8" }),
  frame: () => ({ url: () => `${callbackOrigin}/` }),
  postData: () => "code=REDACTED&state=REDACTED",
  redirectedFrom: () => null,
  ...overrides
});

const classify = (url, req = request(), options = routing) =>
  classifyRequest(req, new URL(url), options);

test("read-only and lifecycle runners resolve the same pinned callback policy", () => {
  const readOnlyRouting = resolveAuthenticationRouting({
    organizationOrigin, pinnedCallbackOrigin: callbackOrigin
  });
  const lifecycleRouting = resolveAuthenticationRouting({
    organizationOrigin, scopedCallbackOrigin: undefined, pinnedCallbackOrigin: callbackOrigin
  });
  assert.deepEqual(readOnlyRouting, lifecycleRouting);
  assert.equal(classify(`${organizationOrigin}/`, request(), readOnlyRouting), "AUTH_NAVIGATION");
  assert.equal(classify(`${organizationOrigin}/`, request(), lifecycleRouting), "AUTH_NAVIGATION");
});

test("scope callback cannot override the locally pinned callback origin", () => {
  assert.throws(() => resolveAuthenticationRouting({
    organizationOrigin,
    scopedCallbackOrigin: "https://other.crm4.dynamics.com",
    pinnedCallbackOrigin: callbackOrigin
  }), /UAT_AUTHENTICATION_CALLBACK_PIN_MISMATCH/);
  assert.throws(() => resolveAuthenticationRouting({
    organizationOrigin,
    scopedCallbackOrigin: organizationOrigin,
    pinnedCallbackOrigin: callbackOrigin
  }), /UAT_AUTHENTICATION_CALLBACK_PIN_MISMATCH/);
});

test("the pinned OpenID handoff is allowed and unknown root POSTs stay blocked", () => {
  assert.equal(classify(`${organizationOrigin}/`, request()), "AUTH_NAVIGATION");
  assert.equal(classify(`${organizationOrigin}/`, request({
    postData: () => "candidate=REDACTED&state=REDACTED"
  })), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify(`${organizationOrigin}/`, request({
    postData: () => "code=REDACTED&state=REDACTED&extra=REDACTED"
  })), "UNKNOWN_REQUEST_BLOCKED");
});

test("callback target and initiator must match pinned origins", () => {
  assert.equal(classify("https://other.crm4.dynamics.com/", request()),
    "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify(`${organizationOrigin}/`, request({
    frame: () => ({ url: () => "https://untrusted.invalid/" })
  })), "UNKNOWN_REQUEST_BLOCKED");
  assert.equal(classify(`${organizationOrigin}/`, request({
    resourceType: () => "fetch", isNavigationRequest: () => false
  })), "UNKNOWN_REQUEST_BLOCKED");
});

test("authentication diagnostics retain structure but never parameter values", () => {
  const evidence = inspectAuthenticationHandoff(request({
    postData: () => "code=SECRET_CODE&state=SECRET_STATE&session_state=SECRET_SESSION"
  }), organizationOrigin);
  assert.equal(evidence.method, "POST");
  assert.equal(evidence.resourceType, "document");
  assert.equal(evidence.navigation, true);
  assert.equal(evidence.contentType, "application/x-www-form-urlencoded; charset=utf-8");
  assert.deepEqual(evidence.payloadSchema.parameterNames, ["code", "session_state", "state"]);
  assert.equal(evidence.payloadSchema.authenticationShape, "OPENID");
  assert.equal(evidence.payloadSchema.unexpectedParameterCount, 0);
  assert.equal(JSON.stringify(evidence).includes("SECRET_"), false);
  assert.equal(inspectAuthenticationHandoff(request({
    url: () => `${organizationOrigin}/api/data/v9.2/os_sr_cact`
  }), organizationOrigin), null);
});

test("Dataverse business mutations remain forbidden without the one-shot arm", () => {
  const mutation = request({
    url: () => `${organizationOrigin}/api/data/v9.2/os_sr_cact`,
    resourceType: () => "xhr",
    isNavigationRequest: () => false,
    postData: () => JSON.stringify({
      ActionType: "CreateCandidate",
      CorrelationId: "11111111-1111-4111-8111-111111111111"
    })
  });
  assert.equal(classify(`${organizationOrigin}/api/data/v9.2/os_sr_cact`, mutation),
    "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION");
});
