function isOptionalMetricsRequest(request, url, organizationOrigin) {
  return url.protocol === "https:" && url.origin === organizationOrigin &&
    url.pathname === "/AppWebServices/MetricsReportingService.asmx/Report" && !url.search &&
    request.method() === "POST" && request.resourceType() === "xhr" &&
    !request.isNavigationRequest();
}

module.exports = { isOptionalMetricsRequest };
