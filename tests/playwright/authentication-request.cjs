function isAuthenticationRequest(request, url, callbackOrigin) {
  if (url.protocol !== "https:") return false;
  if (url.hostname.toLowerCase() === "login.microsoft.com" ||
      /(^|\.)(microsoftonline\.com|msauth\.net|msftauth\.net)$/i.test(url.hostname)) return true;
  if (!callbackOrigin || url.origin !== callbackOrigin || url.pathname !== "/" || url.search ||
      request.method() !== "POST" || request.resourceType() !== "document" ||
      !request.isNavigationRequest()) return false;
  const headers = request.headers();
  if (!/^application\/x-www-form-urlencoded(?:;|$)/i.test(headers["content-type"] || "")) return false;
  const source = new URL(request.frame().url());
  if (source.protocol !== "https:" ||
      !["login.microsoftonline.com", "login.microsoft.com"].includes(source.hostname.toLowerCase())) return false;
  // Inspect only the response shape in memory; never persist values or headers.
  const fields = new URLSearchParams(request.postData() || "");
  const allowed = new Set(["code", "id_token", "state", "session_state", "error", "error_description", "error_uri"]);
  return fields.has("state") && (fields.has("code") || fields.has("id_token") || fields.has("error")) &&
    [...fields.keys()].every(key => allowed.has(key));
}

module.exports = { isAuthenticationRequest };
