const assert = require("node:assert/strict");
const { test } = require("node:test");
const { isOptionalMetricsRequest, isOptionalTelemetryRequest } = require("./platform-support-request.cjs");

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

test("Exact optional telemetry stays suppressed; other traffic fails closed", () => {
  const request = { method: () => "POST", resourceType: () => "xhr", isNavigationRequest: () => false };
  const matches = (url, overrides = {}) =>
    isOptionalTelemetryRequest({ ...request, ...overrides }, new URL(url));
  assert.equal(matches("https://browser.events.data.microsoft.com/OneCollector/1.0/"), true);
  assert.equal(matches("https://eu-mobile.events.data.microsoft.com/OneCollector/1.0/"), true);
  assert.equal(matches("https://browser.pipe.aria.microsoft.com/Collector/3.0/",
    { resourceType: () => "ping" }), true);
  for (const url of ["https://browser.events.data.microsoft.com/other",
    "https://browser.events.data.microsoft.com.evil.invalid/OneCollector/1.0/",
    "http://browser.events.data.microsoft.com/OneCollector/1.0/",
    "https://orgsynthetic.crm4.dynamics.com/api/data/v9.2/os_sr_cact",
    "https://graph.microsoft.com/v1.0/me/events", "https://outlook.office.com/api/sendmail"]) {
    assert.equal(matches(url), false);
  }
  assert.equal(matches("https://browser.events.data.microsoft.com/OneCollector/1.0/",
    { isNavigationRequest: () => true }), false);
  assert.equal(matches("https://browser.events.data.microsoft.com/OneCollector/1.0/",
    { method: () => "PATCH" }), false);
  assert.equal(matches("https://browser.events.data.microsoft.com/OneCollector/1.0/",
    { resourceType: () => "document" }), false);
});
