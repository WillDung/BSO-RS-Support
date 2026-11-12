const { isAuthenticationRequest } = require("./authentication-request.cjs");
const { isOptionalMetricsRequest, isOptionalTelemetryRequest } = require("./platform-support-request.cjs");

const isCorrelation = value => typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value) &&
  value !== "00000000-0000-0000-0000-000000000000";
const scopedReadActions = new Set([
  "ReadScopedCandidates", "ReadScopedPositions", "ReadScopedSources", "ReadScopedTas",
  "ReadScopedLocations", "ReadScopedCalls", "ReadScopedHistory", "ReadScopedSchedules"
]);
const localizationPath = "/AppWebServices/MetadataService.asmx/GetResourceStrings";

function isLocalizationRequest(request, url, origin) {
  if (url.protocol !== "https:" || url.origin !== origin || url.pathname !== localizationPath ||
      url.search || request.method() !== "POST" || request.resourceType() !== "xhr" ||
      request.isNavigationRequest()) return false;
  const contentType = (request.headers()["content-type"] || "").trim();
  if (!/^application\/json\s*;\s*charset=utf-8$/i.test(contentType)) return false;
  const rawBody = request.postData() || "";
  if (Buffer.byteLength(rawBody) > 32768) return false;
  let body;
  try { body = JSON.parse(rawBody); } catch { return false; }
  return Boolean(body && typeof body === "object" && !Array.isArray(body) &&
    Object.keys(body).length === 1 && Array.isArray(body.resourceIds) &&
    body.resourceIds.length > 0 && body.resourceIds.length <= 128 &&
    body.resourceIds.every(value => typeof value === "string" && value.length > 0 &&
      value.length <= 256 && !/[\u0000-\u001f\u007f]/.test(value)));
}

function isUntrustedLocalizationRedirect(request, origin) {
  const url = new URL(request.url());
  for (let previous = request.redirectedFrom(); previous; previous = previous.redirectedFrom()) {
    const previousUrl = new URL(previous.url());
    if (previousUrl.origin === origin && previousUrl.pathname === localizationPath &&
        url.origin !== origin) return true;
  }
  return false;
}

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
  if (isLocalizationRequest(request, url, origin)) return "LOCALIZATION_READ_ALLOWED";
  if (api && request.method() === "POST" && !url.search &&
      url.pathname === "/api/data/v9.2/os_sr_cact" &&
      ["xhr", "fetch"].includes(request.resourceType()) && !request.isNavigationRequest()) {
    let body;
    try { body = JSON.parse(request.postData()); } catch { body = null; }
    if (body && Object.keys(body).length === 2 &&
        ["VerifySyntheticIsolation", "VerifySingleUserDev"].includes(body.ActionType) &&
        isCorrelation(body.CorrelationId)) {
      return "READ_ONLY_VERIFIER_ALLOWED";
    }
    if (body && Object.keys(body).length === 3 && scopedReadActions.has(body.ActionType) &&
        isCorrelation(body.CorrelationId) && isCorrelation(body.SyntheticScopeId)) {
      return "SCOPED_READ_OPERATION_ALLOWED";
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

function matchesCandidateActionResponse(response, origin, action, correlation) {
  if (!["CreateCandidate", "RecordCall", "ProceedToScheduling", "MarkRound1Scheduled"].includes(action) ||
      !isCorrelation(correlation) ||
      response.url() !== `${origin}/api/data/v9.2/os_sr_cact`) return false;
  const request = response.request();
  if (classifyRequest(request, new URL(response.url()), {
    origin, approvedBusinessOperation: true
  }) !== "APPROVED_BUSINESS_OPERATION") return false;
  let body;
  try { body = JSON.parse(request.postData()); } catch { return false; }
  return body?.ActionType === action && isCorrelation(body.CorrelationId) &&
    body.CorrelationId.toLowerCase() === correlation.toLowerCase();
}

async function suppressOptionalSupportRequest(route, classification, request, url, report) {
  if (!["OPTIONAL_SUPPORT_SUPPRESSED", "OPTIONAL_TELEMETRY_SUPPRESSED"].includes(classification)) {
    return false;
  }
  report.platformSupportRequestsSuppressed++;
  report.optionalSuppressions.push({
    classification, host: url.hostname, path: url.pathname,
    method: request.method(), resourceType: request.resourceType()
  });
  await route.abort("blockedbyclient");
  return true;
}

module.exports = {
  classifyRequest, isLocalizationRequest, isUntrustedLocalizationRedirect,
  matchesCandidateActionResponse, suppressOptionalSupportRequest
};
