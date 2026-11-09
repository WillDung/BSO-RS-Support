const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { createHash } = require("node:crypto");
const { chromium, expect } = require("@playwright/test");
const { isAuthenticationRequest } = require("./authentication-request.cjs");
const { isOptionalMetricsRequest, isOptionalTelemetryRequest } = require("./platform-support-request.cjs");
const { verifyBrowserIdentity } = require("./browser-identity.cjs");
const { authDirectory, runDirectory, protectDirectory, loadApproval } = require("./local-settings.cjs");

function checkPredicate() {
  const callback = "https://auth-callback.crm4.dynamics.com";
  const request = (overrides = {}) => ({
    method: () => "POST", resourceType: () => "document", isNavigationRequest: () => true,
    headers: () => ({ "content-type": "application/x-www-form-urlencoded" }),
    frame: () => ({ url: () => "https://login.microsoftonline.com/authorize" }),
    postData: () => "code=SYNTHETIC&state=SYNTHETIC", ...overrides
  });
  assert.equal(isAuthenticationRequest(request(), new URL("https://login.microsoft.com/bridge"), callback), true);
  assert.equal(isAuthenticationRequest(request(), new URL(`${callback}/`), callback), true);
  assert.equal(isAuthenticationRequest(request(), new URL(`${callback}/api/data/v9.2/os_sr_cact`), callback), false);
  assert.equal(isAuthenticationRequest(request({ resourceType: () => "fetch" }), new URL(`${callback}/`), callback), false);
  assert.equal(isAuthenticationRequest(request({ frame: () => ({ url: () => "https://app.crm4.dynamics.com/" }) }),
    new URL(`${callback}/`), callback), false);
  assert.equal(isAuthenticationRequest(request({ postData: () => "unapproved=1&state=SYNTHETIC" }),
    new URL(`${callback}/`), callback), false);
  assert.equal(isAuthenticationRequest(request(), new URL("https://graph.microsoft.com/v1.0/me/events"), callback), false);
  assert.equal(isAuthenticationRequest(request(), new URL("https://login.microsoft.com.evil.invalid/bridge"), callback), false);
  assert.equal(isAuthenticationRequest(request(), new URL("http://login.microsoft.com/bridge"), callback), false);
  const organization = "https://orgsynthetic.crm4.dynamics.com";
  const handoff = request({
    frame: () => ({ url: () => `${callback}/` }),
    postData: () => "wa=wsignin1.0&wresult=SYNTHETIC&wctx=SYNTHETIC"
  });
  assert.equal(isAuthenticationRequest(handoff, new URL(`${organization}/`), callback, organization), true);
  assert.equal(isAuthenticationRequest(handoff, new URL(`${organization}/api/data/v9.2/os_sr_cact`),
    callback, organization), false);
  assert.equal(isAuthenticationRequest(request({ postData: () => "CandidateName=SYNTHETIC" }),
    new URL(`${organization}/`), callback, organization), false);
}

async function main() {
  checkPredicate();
  const approval = loadApproval();
  const callback = JSON.parse(fs.readFileSync(path.join(__dirname, "lifecycle-approval.local.json"), "utf8"))
    .authenticationCallbackOrigin;
  const callbackUrl = new URL(callback);
  if (callbackUrl.protocol !== "https:" || callbackUrl.origin !== callback ||
      !/^[a-z0-9-]+\.crm[0-9]*\.dynamics\.com$/i.test(callbackUrl.hostname)) {
    throw new Error("UAT_INVALID_AUTHENTICATION_CALLBACK_ORIGIN");
  }
  const journalPath = path.join(authDirectory, "owner-lifecycle-20261109-01.json");
  const preservedPaths = [journalPath, `${journalPath}.login-recovery-claim`];
  const hash = file => createHash("sha256").update(fs.readFileSync(file)).digest("hex");
  const before = preservedPaths.map(hash);
  const journal = JSON.parse(fs.readFileSync(journalPath, "utf8"));
  protectDirectory(authDirectory);
  protectDirectory(runDirectory);
  const report = {
    authenticationOnly: "FAIL", correctedCrmCallback: "NOT VERIFIED",
    exactIdentityAndOrganization: "FAIL", candidateConsoleReadOnly: "FAIL",
    businessMutationsDispatched: 0, lifecycleJournal: "ERROR",
    requestSafety: "NOT RUN",
    predicateChecksPassed: 12, callbackPostsAdmitted: 0, callbackResponseStatuses: [],
    suppressedPlatformRequests: 0, suppressedMetricsRequests: 0, optionalSuppressions: [],
    blockedRequests: [], failedRequestClasses: [],
    lifecycleInvoked: false, screenshotsAndTraces: "DISABLED",
    acceptanceScope: "ELEVATED_FUNCTIONAL_ONLY"
  };
  const callbackRequests = new WeakSet();
  let phase = "APP_INITIALIZATION";
  let context;
  try {
    context = await chromium.launchPersistentContext(authDirectory, {
      headless: false, viewport: { width: 1440, height: 1000 },
      acceptDownloads: false, serviceWorkers: "block"
    });
    const page = context.pages()[0] || await context.newPage();
    const safeClass = request => {
      const url = new URL(request.url());
      const authHost = /(^|\.)(microsoftonline\.com|microsoft\.com|msauth\.net|msftauth\.net)$/i.test(url.hostname);
      const operationPath = url.origin === approval.origin && !request.isNavigationRequest()
        ? url.pathname.split("/").map(segment =>
          /^[a-z_$][a-z0-9_.$-]*$/i.test(segment) || /^v[0-9.]+$/.test(segment) || segment === ""
            ? segment : "REDACTED").join("/")
        : undefined;
      return { method: request.method(), host: url.hostname,
        resourceType: request.resourceType(), navigation: request.isNavigationRequest(),
        operationPath, phase,
        requestClass: callbackRequests.has(request) ? "CRM_AUTH_CALLBACK"
          : authHost ? "MICROSOFT_AUTH_OR_SUPPORT" : "OTHER" };
    };
    context.on("response", response => {
      if (callbackRequests.has(response.request())) report.callbackResponseStatuses.push(response.status());
    });
    context.on("requestfailed", request => {
      if (callbackRequests.has(request) ||
          /(^|\.)(microsoftonline\.com|msauth\.net|msftauth\.net)$/.test(new URL(request.url()).hostname) ||
          new URL(request.url()).hostname === "login.microsoft.com") {
        const error = request.failure()?.errorText || "UNKNOWN";
        report.failedRequestClasses.push({ ...safeClass(request),
          error: /^net::ERR_[A-Z_]+$/.test(error) ? error : "REQUEST_FAILED" });
      }
    });
    await context.route("**/*", async route => {
      const request = route.request();
      const url = new URL(request.url());
      const mutation = !["GET", "HEAD", "OPTIONS"].includes(request.method());
      const api = url.origin === approval.origin && /\/api\/data\//i.test(url.pathname);
      if (isOptionalMetricsRequest(request, url, approval.origin)) {
        report.suppressedPlatformRequests++;
        report.suppressedMetricsRequests++;
        return route.abort("blockedbyclient");
      }
      const support = api && request.method() === "POST" &&
        ["msdyn_ReportToMonitoringHub", "GetRecentItems", "GetCopilotSettingsForEnvironment"]
          .includes(url.pathname.split("/").pop());
      const telemetry = isOptionalTelemetryRequest(request, url);
      if (support || telemetry) {
        report.suppressedPlatformRequests++;
        if (telemetry) report.optionalSuppressions.push({
          classification: "SUPPRESSED_OPTIONAL", host: url.hostname, path: url.pathname,
          method: request.method(), resourceType: request.resourceType()
        });
        return route.abort("blockedbyclient");
      }
      const auth = isAuthenticationRequest(request, url, callback, approval.origin);
      const provider = /(^|\.)(graph\.microsoft\.com|outlook\.office365\.com|outlook\.office\.com)$/i.test(url.hostname);
      if (provider || (mutation && (!auth || api))) {
        report.blockedRequests.push(safeClass(request));
        return route.abort("blockedbyclient");
      }
      if (auth && [callback, approval.origin].includes(url.origin) && request.method() === "POST") {
        callbackRequests.add(request);
        report.callbackPostsAdmitted++;
      }
      // The app may auto-read Candidates: limit its list to the preserved synthetic marker.
      if (api && request.method() === "GET" && url.pathname === "/api/data/v9.2/os_sr_cands") {
        const scope = `os_sr_cand_nm eq '${journal.candidateName}'`;
        const existing = url.searchParams.get("$filter");
        url.searchParams.set("$filter", existing ? `(${existing}) and (${scope})` : scope);
        return route.continue({ url: url.href });
      }
      return route.continue();
    });
    console.log("Authentication-only Chromium open; complete Microsoft sign-in/MFA directly if prompted.");
    await page.goto(`${approval.origin}/main.aspx?pagetype=apps`, {
      waitUntil: "domcontentloaded", timeout: 120_000
    });
    const identity = await verifyBrowserIdentity(page, approval, 480_000);
    if (!identity.bsoRole) throw new Error("UAT_REQUIRED_BSO_ROLE_MISSING");
    report.exactIdentityAndOrganization = "PASS";
    phase = "SRAPP_INITIALIZATION";
    await page.goto(approval.appUrl, { waitUntil: "domcontentloaded" });
    await page.getByRole("treeitem", { name: "Candidate Management", exact: true }).click();
    phase = "CONSOLE_INITIALIZATION";
    const frame = page.frameLocator('iframe[src*="candidate-console.html"]');
    await expect(frame.getByRole("heading", { name: "Candidate Management", exact: true }))
      .toBeVisible({ timeout: 60_000 });
    await expect.poll(() => frame.locator("body").evaluate(() =>
      Boolean(window.BsoRsCandidateConsoleConfiguration)), { timeout: 30_000 }).toBe(true);
    const config = await frame.locator("body").evaluate(() => {
      const value = window.BsoRsCandidateConsoleConfiguration;
      return { mode: value.mode, core: value.candidateCoreEnabled, synthetic: value.syntheticDataOnly,
        fallback: value.devDirectWriteFallbackEnabled, availability: value.availabilityEnabled === true };
    });
    assert.deepEqual(config, { mode: "DEV", core: true, synthetic: true, fallback: false, availability: false });
    const current = new URL(page.url());
    if (current.origin !== approval.origin ||
        current.searchParams.get("appid") !== new URL(approval.appUrl).searchParams.get("appid")) {
      throw new Error("UAT_APP_ENTRYPOINT_MISMATCH");
    }
    await expect(frame.locator("#availability-submit")).toBeDisabled();
    report.candidateConsoleReadOnly = "PASS";
    report.configuration = config;
    report.authenticationOnly = "PASS";
    if (report.callbackPostsAdmitted > 0 &&
        report.callbackResponseStatuses.some(status => status >= 200 && status < 400) &&
        !report.failedRequestClasses.some(request => request.requestClass === "CRM_AUTH_CALLBACK")) {
      report.correctedCrmCallback = "VERIFIED";
    }
    report.requestSafety = report.blockedRequests.length ? "FAIL" : "PASS";
    if (report.blockedRequests.length) throw new Error("UAT_UNEXPECTED_REQUEST_BLOCKED");
  } catch (error) {
    report.failure = String(error.message || "").match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_AUTHENTICATION_ONLY_FAILED";
    process.exitCode = 1;
  } finally {
    if (context) await context.close();
    report.lifecycleJournal = preservedPaths.every((file, index) => hash(file) === before[index])
      ? "PRESERVED" : "ERROR";
    if (report.lifecycleJournal !== "PRESERVED") {
      report.authenticationOnly = "FAIL";
      process.exitCode = 1;
    }
    fs.writeFileSync(path.join(runDirectory, "authentication-only-report.json"), JSON.stringify(report, null, 2));
    console.log(`Authentication-only: ${report.authenticationOnly}; callback: ${report.correctedCrmCallback}`);
    console.log(`Protected evidence: ${runDirectory}`);
  }
}

main().catch(() => {
  console.error("UAT_AUTHENTICATION_ONLY_SETUP_FAILED");
  process.exitCode = 1;
});
