const { isAuthenticationRequest } = require("./authentication-request.cjs");
const { isOptionalMetricsRequest, isOptionalTelemetryRequest } = require("./platform-support-request.cjs");

function classifyRequest(request, url, { origin, callbackOrigin, approvedBusinessOperation = false }) {
  const write = !["GET", "HEAD", "OPTIONS"].includes(request.method());
  const api = url.origin === origin && /^\/api\/data\//i.test(url.pathname);
  const provider = /(^|\.)(graph\.microsoft\.com|outlook\.office365\.com|outlook\.office\.com)$/i.test(url.hostname);
  if (provider) {
    return write ? "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION" : "UNKNOWN_REQUEST_BLOCKED";
  }
  if (isOptionalTelemetryRequest(request, url)) return "OPTIONAL_TELEMETRY_SUPPRESSED";
  const support = api && request.method() === "POST" && !url.search &&
    ["xhr", "fetch"].includes(request.resourceType()) && !request.isNavigationRequest() &&
    /^\/api\/data\/v9\.(?:0|2)\/(msdyn_ReportToMonitoringHub|GetRecentItems|GetCopilotSettingsForEnvironment)$/.test(url.pathname);
  if (support || isOptionalMetricsRequest(request, url, origin)) return "OPTIONAL_SUPPORT_SUPPRESSED";
  if (api && request.method() === "POST" && !url.search &&
      url.pathname === "/api/data/v9.2/os_sr_cact" &&
      ["xhr", "fetch"].includes(request.resourceType()) && !request.isNavigationRequest()) {
    let body;
    try { body = JSON.parse(request.postData()); } catch { body = null; }
    if (body && Object.keys(body).length === 2 && body.ActionType === "VerifySyntheticIsolation" &&
        typeof body.CorrelationId === "string" &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(body.CorrelationId) &&
        body.CorrelationId !== "00000000-0000-0000-0000-000000000000") {
      return "READ_ONLY_VERIFIER_ALLOWED";
    }
  }
  if (api && write) {
    return approvedBusinessOperation && request.method() === "POST" &&
      url.pathname === "/api/data/v9.2/os_sr_cact" && !url.search &&
      ["xhr", "fetch"].includes(request.resourceType()) && !request.isNavigationRequest()
      ? "APPROVED_BUSINESS_OPERATION" : "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION";
  }
  if (isAuthenticationRequest(request, url, callbackOrigin, origin)) return "AUTH_NAVIGATION";
  return write ? "UNKNOWN_REQUEST_BLOCKED" : "READ_REQUEST_ALLOWED";
}

module.exports = { classifyRequest };
