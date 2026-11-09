const assert = require("node:assert/strict");
const { test } = require("node:test");
const { isOptionalMetricsRequest } = require("./platform-support-request.cjs");

test("Only the exact optional CRM metrics XHR is suppressed", () => {
  const origin = "https://orgsynthetic.crm4.dynamics.com";
  const path = "/AppWebServices/MetricsReportingService.asmx/Report";
  const request = { method: () => "POST", resourceType: () => "xhr", isNavigationRequest: () => false };
  const matches = (url, overrides = {}) =>
    isOptionalMetricsRequest({ ...request, ...overrides }, new URL(url), origin);
  assert.equal(matches(`${origin}${path}`), true);
  for (const suffix of ["/api/data/v9.2/os_sr_cact", "/api/data/v9.2/os_sr_cands",
    "/api/data/v9.2/os_sr_calls", "/api/data/v9.2/os_sr_intvs", "/api/data/v9.2/SendEmail",
    "/api/data/v9.2/organizations", `${path}/Other`, `${path}?operation=write`]) {
    assert.equal(matches(`${origin}${suffix}`), false);
  }
  assert.equal(matches(`http://orgsynthetic.crm4.dynamics.com${path}`), false);
  assert.equal(matches(`https://other.crm4.dynamics.com${path}`), false);
  assert.equal(matches(`https://graph.microsoft.com${path}`), false);
  assert.equal(matches(`${origin}${path}`, { method: () => "GET" }), false);
  assert.equal(matches(`${origin}${path}`, { resourceType: () => "fetch" }), false);
  assert.equal(matches(`${origin}${path}`, { isNavigationRequest: () => true }), false);
});
