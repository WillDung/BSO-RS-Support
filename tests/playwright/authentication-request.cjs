function isAuthenticationRequest(request, url, callbackOrigin, organizationOrigin) {
  if (url.protocol !== "https:") return false;
  if (url.hostname.toLowerCase() === "login.microsoft.com" ||
      /(^|\.)(microsoftonline\.com|msauth\.net|msftauth\.net)$/i.test(url.hostname)) return true;
  const callbackTarget = url.origin === callbackOrigin || url.origin === organizationOrigin;
  if (!callbackOrigin || !callbackTarget || url.pathname !== "/" || url.search ||
      request.method() !== "POST" || request.resourceType() !== "document" ||
      !request.isNavigationRequest()) return false;
  const headers = request.headers();
  if (!/^application\/x-www-form-urlencoded(?:;|$)/i.test(headers["content-type"] || "")) return false;
  const source = new URL(request.frame().url());
  const microsoftSource = ["login.microsoftonline.com", "login.microsoft.com"].includes(source.hostname.toLowerCase());
  const crmHandoff = url.origin === organizationOrigin && source.origin === callbackOrigin;
  if (source.protocol !== "https:" || (!microsoftSource && !crmHandoff)) return false;
  // Inspect only the response shape in memory; never persist values or headers.
  const fields = new URLSearchParams(request.postData() || "");
  const allowed = new Set(["code", "id_token", "state", "session_state", "error", "error_description", "error_uri"]);
  const openId = fields.has("state") && (fields.has("code") || fields.has("id_token") || fields.has("error")) &&
    [...fields.keys()].every(key => allowed.has(key));
  const federation = fields.get("wa") === "wsignin1.0" && fields.has("wresult") && fields.has("wctx") &&
    [...fields.keys()].every(key => ["wa", "wresult", "wctx"].includes(key));
  return (microsoftSource && openId) || (crmHandoff && federation);
}

module.exports = { isAuthenticationRequest };
