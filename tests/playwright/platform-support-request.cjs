function isOptionalMetricsRequest(request, url, organizationOrigin) {
  return url.protocol === "https:" && url.origin === organizationOrigin &&
    url.pathname === "/AppWebServices/MetricsReportingService.asmx/Report" && !url.search &&
    request.method() === "POST" && request.resourceType() === "xhr" &&
    !request.isNavigationRequest();
}

function isOptionalTelemetryRequest(request, url) {
  if (url.protocol !== "https:" || request.method() !== "POST" || request.isNavigationRequest()) return false;
  return (url.hostname === "browser.pipe.aria.microsoft.com" &&
      url.pathname === "/Collector/3.0/" && ["xhr", "fetch", "ping"].includes(request.resourceType())) ||
    (["apac.events.data.microsoft.com", "browser.events.data.microsoft.com",
      "eu-mobile.events.data.microsoft.com"].includes(url.hostname) &&
      url.pathname === "/OneCollector/1.0/" && ["xhr", "fetch", "ping"].includes(request.resourceType()));
}

module.exports = { isOptionalMetricsRequest, isOptionalTelemetryRequest };
