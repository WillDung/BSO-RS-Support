const fs = require("node:fs");
const path = require("node:path");

const CALLBACK_HOST = /^[a-z0-9-]+\.crm[0-9]*\.dynamics\.com$/i;
const OPENID_FIELDS = new Set([
  "code", "id_token", "state", "session_state", "error", "error_description", "error_uri"
]);
const FEDERATION_FIELDS = new Set(["wa", "wresult", "wctx"]);
const AUTHENTICATION_FIELDS = new Set([...OPENID_FIELDS, ...FEDERATION_FIELDS]);

function validateOrigin(value, hostPattern, code) {
  if (typeof value !== "string") throw new Error(code);
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new Error(code);
  }
  if (url.protocol !== "https:" || url.origin !== value || url.username || url.password ||
      url.pathname !== "/" || url.search || url.hash || !hostPattern.test(url.hostname)) {
    throw new Error(code);
  }
  return url.origin;
}

function loadPinnedAuthenticationCallbackOrigin(file =
  path.join(__dirname, "lifecycle-approval.local.json")) {
  let approval;
  try {
    approval = JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    throw new Error("UAT_AUTHENTICATION_CALLBACK_PIN_UNAVAILABLE");
  }
  return validateOrigin(approval.authenticationCallbackOrigin, CALLBACK_HOST,
    "UAT_INVALID_AUTHENTICATION_CALLBACK_ORIGIN");
}

function resolveAuthenticationRouting({
  organizationOrigin, scopedCallbackOrigin, pinnedCallbackOrigin
}) {
  const organization = validateOrigin(organizationOrigin,
    /^[a-z0-9-]+\.crm[0-9]*\.dynamics\.com$/i, "UAT_INVALID_AUTHENTICATION_ORGANIZATION_ORIGIN");
  const pinned = validateOrigin(pinnedCallbackOrigin, CALLBACK_HOST,
    "UAT_INVALID_AUTHENTICATION_CALLBACK_ORIGIN");
  if (scopedCallbackOrigin !== undefined && scopedCallbackOrigin !== null) {
    const scoped = validateOrigin(scopedCallbackOrigin, CALLBACK_HOST,
      "UAT_INVALID_AUTHENTICATION_CALLBACK_ORIGIN");
    if (scoped !== pinned) throw new Error("UAT_AUTHENTICATION_CALLBACK_PIN_MISMATCH");
  }
  return Object.freeze({ origin: organization, callbackOrigin: pinned });
}

function sanitizedContentType(headers) {
  const value = headers["content-type"] || "";
  const match = value.trim().match(
    /^(application\/x-www-form-urlencoded)(?:\s*;\s*charset=([a-z0-9._-]+))?$/i);
  return match
    ? `${match[1].toLowerCase()}${match[2] ? `; charset=${match[2].toLowerCase()}` : ""}`
    : "UNRECOGNIZED";
}

function inspectAuthenticationHandoff(request, organizationOrigin) {
  const url = new URL(request.url());
  if (url.origin !== organizationOrigin || url.pathname !== "/" || url.search ||
      request.method() !== "POST" || request.resourceType() !== "document" ||
      !request.isNavigationRequest()) return null;

  const rawBody = request.postData() || "";
  const bodyWithinLimit = Buffer.byteLength(rawBody) <= 65536;
  const entries = bodyWithinLimit ? [...new URLSearchParams(rawBody).entries()] : [];
  const names = entries.map(([name]) => name);
  const uniqueNames = [...new Set(names)].sort();
  const openid = names.includes("state") &&
    (names.includes("code") || names.includes("id_token") || names.includes("error")) &&
    names.every(name => OPENID_FIELDS.has(name));
  const federation = entries.some(([name, value]) => name === "wa" && value === "wsignin1.0") &&
    names.includes("wresult") && names.includes("wctx") &&
    names.every(name => FEDERATION_FIELDS.has(name));
  const redirectChain = [];
  for (let current = request.redirectedFrom(); current && redirectChain.length < 12;
    current = current.redirectedFrom()) {
    const previousUrl = new URL(current.url());
    redirectChain.unshift({
      method: current.method(), origin: previousUrl.origin, path: previousUrl.pathname
    });
  }

  let sourceFrame = null;
  try {
    const sourceUrl = new URL(request.frame().url());
    sourceFrame = { origin: sourceUrl.origin, path: sourceUrl.pathname };
  } catch {}

  return {
    endpoint: { origin: url.origin, path: url.pathname },
    method: request.method(),
    resourceType: request.resourceType(),
    navigation: request.isNavigationRequest(),
    contentType: sanitizedContentType(request.headers()),
    sourceFrame,
    redirectChain,
    payloadSchema: {
      encoding: bodyWithinLimit ? "application/x-www-form-urlencoded" : "BODY_LIMIT_EXCEEDED",
      byteLength: Buffer.byteLength(rawBody),
      parameterCount: entries.length,
      parameterNames: uniqueNames.filter(name => AUTHENTICATION_FIELDS.has(name)),
      unexpectedParameterCount: names.filter(name => !AUTHENTICATION_FIELDS.has(name)).length,
      valueTypes: [...new Set(entries.map(([, value]) => typeof value))],
      authenticationShape: openid ? "OPENID" : federation ? "WS_FEDERATION" : "UNKNOWN"
    }
  };
}

module.exports = {
  loadPinnedAuthenticationCallbackOrigin,
  resolveAuthenticationRouting,
  inspectAuthenticationHandoff
};
