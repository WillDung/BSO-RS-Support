const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const { createHash, randomUUID } = require("node:crypto");
const { chromium, expect } = require("@playwright/test");
const {
  loadPinnedAuthenticationCallbackOrigin, resolveAuthenticationRouting,
  inspectAuthenticationHandoff
} = require("./authentication-routing.cjs");
const { isAuthenticationRequest } = require("./authentication-request.cjs");
const { classifyRequest, isUntrustedLocalizationRedirect } = require("./request-classification.cjs");
const { verifyBrowserIdentity } = require("./browser-identity.cjs");
const {
  constrainReferenceRequest, isSingleUserDevDirectReadBlocked
} = require("./lifecycle-support.cjs");
const { createResourceEvidence, safeConsoleUrl, identifyConsoleResource,
  loadResourceManifest, verifyResourceHashes, evaluateCreateGate } =
  require("./served-console-resources.cjs");
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
  const openIdHandoff = request({
    frame: () => ({ url: () => `${callback}/` }),
    postData: () => "code=SYNTHETIC&id_token=SYNTHETIC&session_state=SYNTHETIC&state=SYNTHETIC"
  });
  assert.equal(isAuthenticationRequest(openIdHandoff, new URL(`${organization}/`), callback, organization), true);
  assert.equal(isAuthenticationRequest(request({
    frame: () => ({ url: () => `${callback}/` }),
    postData: () => "code=SYNTHETIC&state=SYNTHETIC&extra=SYNTHETIC"
  }), new URL(`${organization}/`), callback, organization), false);
  assert.equal(isAuthenticationRequest(request({ postData: () => "CandidateName=SYNTHETIC" }),
    new URL(`${organization}/`), callback, organization), false);
}

function sanitizedContentType(headers) {
  const value = headers["content-type"] || "";
  const [mediaType = "", ...parameters] = value.split(";");
  const parsedParameters = parameters.map(parameter => {
    const [rawName, rawValue = ""] = parameter.split("=", 2);
    const name = rawName.trim().toLowerCase();
    const parameterValue = rawValue.trim().replace(/^["']|["']$/g, "");
    return {
      name,
      value: name === "charset" && /^[a-z0-9._-]{1,32}$/i.test(parameterValue)
        ? parameterValue.toLowerCase() : "UNRECOGNIZED"
    };
  }).filter(parameter => /^[a-z0-9_-]+$/i.test(parameter.name));
  return {
    mediaType: /^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+$/i.test(mediaType.trim())
      ? mediaType.trim().toLowerCase() : "UNRECOGNIZED",
    parameters: parsedParameters.sort((left, right) => left.name.localeCompare(right.name))
  };
}

function sanitizedPayloadShape(contentType, rawBody, redactFieldNames = false) {
  const shape = (value, depth = 0) => {
    if (depth > 5) return { type: "DEPTH_LIMIT" };
    if (value === null) return { type: "null" };
    if (Array.isArray(value)) {
      return {
        type: "array", length: value.length,
        itemShapes: [...new Set(value.slice(0, 3).map(item =>
          JSON.stringify(shape(item, depth + 1))))].map(item => JSON.parse(item))
      };
    }
    if (typeof value === "object") {
      const keys = Object.keys(value).sort();
      return {
        type: "object",
        fields: keys.slice(0, 40).map(name => ({
          ...(redactFieldNames ? {} : { name }),
          ...shape(value[name], depth + 1)
        })),
        omittedFieldCount: Math.max(0, keys.length - 40)
      };
    }
    return { type: typeof value };
  };
  const body = String(rawBody || "");
  if (/^application\/json$/i.test(contentType.mediaType)) {
    try { return shape(JSON.parse(body)); } catch { return { type: "MALFORMED_JSON" }; }
  }
  if (/^application\/x-www-form-urlencoded$/i.test(contentType.mediaType)) {
    const form = new URLSearchParams(body);
    const names = [...form.keys()].sort();
    return {
      type: "form",
      fields: [...new Set(names)].slice(0, 40).map(name => ({ name, type: "string" })),
      omittedFieldCount: Math.max(0, new Set(names).size - 40)
    };
  }
  return { type: body ? "OPAQUE_BODY" : "EMPTY_BODY", byteLength: Buffer.byteLength(body) };
}

async function captureLocalizationResponse(response, diagnostic) {
  const request = response.request();
  const headers = response.headers();
  const responseContentType = sanitizedContentType(headers);
  let responseShape = { type: "BODY_UNAVAILABLE" };
  try {
    const body = await response.body();
    responseShape = sanitizedPayloadShape(responseContentType, body.toString("utf8"), true);
  } catch {
    responseShape = { type: "BODY_UNAVAILABLE" };
  }
  const redirectLocation = response.status() >= 300 && response.status() < 400
    ? (() => {
      try {
        const location = new URL(headers.location, new URL(request.url()).origin);
        const sameOrigin = location.origin === new URL(request.url()).origin;
        return { origin: location.origin, path: sameOrigin ? location.pathname : "REDACTED", sameOrigin };
      } catch {
        return { origin: "UNPARSEABLE", path: null, sameOrigin: false };
      }
    })() : null;
  const responseContract = response.status() >= 200 && response.status() < 300 &&
    responseContentType.mediaType === "application/json" &&
    responseContentType.parameters.length === 1 &&
    responseContentType.parameters[0].name === "charset" &&
    responseContentType.parameters[0].value === "utf-8" &&
    responseShape.type === "object" && responseShape.omittedFieldCount === 0 &&
    responseShape.fields.length > 0 &&
    responseShape.fields.every(field => field.type === "string") &&
    redirectLocation === null;
  Object.assign(diagnostic, {
    responseStatus: response.status(),
    responseContentType,
    responseBodyShape: responseShape,
    redirectLocation,
    responseContract: responseContract ? "PASS" : "FAIL"
  });
}

async function verifySingleUserDevProof(page, approval, actorId) {
  const expectedEnvironmentId = approval.environmentId || process.env.BSO_UAT_ENVIRONMENT_ID || null;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(expectedEnvironmentId || "")) {
    throw new Error("UAT_EXPECTED_ENVIRONMENT_ID_REQUIRED");
  }
  const result = await page.evaluate(async ({
    origin, organizationId, environmentId, actorId, correlationId
  }) => {
    const guid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    const normalize = value => String(value || "").replace(/[{}]/g, "").toLowerCase();
    try {
      const response = await fetch(`${origin}/api/data/v9.2/os_sr_cact`, {
        method: "POST", credentials: "same-origin",
        headers: {
          Accept: "application/json", "Content-Type": "application/json; charset=utf-8",
          "OData-MaxVersion": "4.0", "OData-Version": "4.0"
        },
        body: JSON.stringify({ ActionType: "VerifySingleUserDev", CorrelationId: correlationId })
      });
      const body = await response.json().catch(() => null);
      if (!response.ok || body?.ResultCode !== "SingleUserDevVerified" ||
          typeof body.IsolationContract !== "string") {
        return { status: response.status, valid: false, scopeId: null };
      }
      const proof = JSON.parse(body.IsolationContract);
      const proofGuids = ["organizationId", "environmentId", "actorId", "scopeId", "candidateId",
        "positionId", "sourceId", "taId", "locationId"];
      const expiresAt = Date.parse(proof.validUntil);
      const now = Date.now();
      const valid = proof.version === 4 &&
        proof.boundary === "SingleUserDevCandidateCoreApi" &&
        proof.mode === "SingleUserDev" && proof.nativeWritesDenied === false &&
        proof.scopedReads === true && proof.globalGuardsRequired === false &&
        proof.readback === "CallerOwnedScope" && proof.calendarEnabled === false &&
        proofGuids.every(name => guid.test(proof[name])) &&
        normalize(proof.organizationId) === normalize(organizationId) &&
        normalize(proof.actorId) === normalize(actorId) &&
        (!environmentId || normalize(proof.environmentId) === normalize(environmentId)) &&
        normalize(proof.scopeId) === normalize(proof.candidateId) &&
        Number.isFinite(expiresAt) && expiresAt > now && expiresAt <= now + 125000;
      return { status: response.status, valid, scopeId: valid ? proof.scopeId : null };
    } catch {
      return { status: 0, valid: false, scopeId: null };
    }
  }, {
    origin: approval.origin,
    organizationId: approval.organizationId,
    environmentId: expectedEnvironmentId,
    actorId,
    correlationId: randomUUID()
  });
  if (result.status !== 200 || !result.valid ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(result.scopeId || "")) {
    throw new Error("UAT_SINGLE_USER_DEV_PROOF_FAILED");
  }
  return result.scopeId;
}

async function readScopedCandidateBaseline(page, origin, scopeId) {
  const result = await page.evaluate(async ({ origin, scopeId, correlationId }) => {
    try {
      const response = await fetch(`${origin}/api/data/v9.2/os_sr_cact`, {
        method: "POST", credentials: "same-origin",
        headers: {
          Accept: "application/json", "Content-Type": "application/json; charset=utf-8",
          "OData-MaxVersion": "4.0", "OData-Version": "4.0"
        },
        body: JSON.stringify({
          ActionType: "ReadScopedCandidates", CorrelationId: correlationId,
          SyntheticScopeId: scopeId
        })
      });
      const body = await response.json().catch(() => null);
      if (!response.ok || body?.ResultCode !== "ScopedRead" ||
          typeof body.ScopedData !== "string") {
        return { status: response.status, valid: false, count: null };
      }
      const rows = JSON.parse(body.ScopedData);
      if (!Array.isArray(rows) || rows.length > 100 ||
          rows.some(row => !row || typeof row !== "object" || Array.isArray(row) ||
            row.__logicalName !== "os_sr_cand")) {
        return { status: response.status, valid: false, count: null };
      }
      return { status: response.status, valid: true, count: rows.length };
    } catch {
      return { status: 0, valid: false, count: null };
    }
  }, { origin, scopeId, correlationId: randomUUID() });
  if (result.status !== 200 || !result.valid || !Number.isSafeInteger(result.count)) {
    throw new Error("UAT_SCOPED_CANDIDATE_READ_FAILED");
  }
  return result.count;
}

async function main() {
  checkPredicate();
  const approval = loadApproval();
  const ownerReadOnly = approval.identityScope === "OWNER_APPROVED_ELEVATED_READ_ONLY";
  const resourceManifest = !ownerReadOnly && Object.hasOwn(process.env, "BSO_UAT_RESOURCE_MANIFEST_FILE")
    ? loadResourceManifest(process.env.BSO_UAT_RESOURCE_MANIFEST_FILE, approval) : null;
  const routing = resolveAuthenticationRouting({
    organizationOrigin: approval.origin,
    pinnedCallbackOrigin: loadPinnedAuthenticationCallbackOrigin()
  });
  const callback = routing.callbackOrigin;
  const journalPath = path.join(authDirectory, "owner-lifecycle-20261109-01.json");
  const singleUserDevAuthorizationPath = path.join(authDirectory, "singleuserdev-uat-runner-01.authorization.json");
  const independentAuthorizationPath = path.join(authDirectory, "owner-lifecycle-20261109-02.authorization.json");
  const latestIndependentAuthorizationPath = path.join(authDirectory, "owner-lifecycle-20261109-03.authorization.json");
  const preservedPaths = [
    journalPath,
    singleUserDevAuthorizationPath,
    `${singleUserDevAuthorizationPath}.attempt.jsonl`,
    `${journalPath}.login-recovery-claim`,
    `${journalPath}.continuation.jsonl`,
    `${journalPath}.recovery-eligible.json`,
    `${journalPath}.eligible-continuation.jsonl`,
    independentAuthorizationPath,
    `${independentAuthorizationPath}.attempt.jsonl`,
    latestIndependentAuthorizationPath,
    `${latestIndependentAuthorizationPath}.attempt.jsonl`
  ];
  const hash = file => {
    try {
      const stat = fs.lstatSync(file);
      if (!stat.isFile() || stat.isSymbolicLink()) throw new Error("UAT_PROTECTED_EVIDENCE_PATH_INVALID");
      return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
    } catch (error) {
      if (error.code === "ENOENT") return null;
      throw error;
    }
  };
  const before = preservedPaths.map(hash);
  const v4AuthorizationIndex = preservedPaths.indexOf(singleUserDevAuthorizationPath);
  const v4ClaimIndex = preservedPaths.indexOf(`${singleUserDevAuthorizationPath}.attempt.jsonl`);
  const v4AuthorizationBefore = before[v4AuthorizationIndex];
  const v4ClaimBefore = before[v4ClaimIndex];
  const journal = ownerReadOnly ? null : JSON.parse(fs.readFileSync(journalPath, "utf8"));
  protectDirectory(authDirectory);
  protectDirectory(runDirectory);
  const report = {
    authenticationOnly: "FAIL", correctedCrmCallback: "NOT VERIFIED",
    exactIdentityAndOrganization: "FAIL", candidateConsoleReadOnly: "FAIL",
    candidateCoreControlsVisible: "NOT VERIFIED",
    syntheticIsolation: "NOT VERIFIED", createCandidateEnabled: "NOT VERIFIED",
    singleUserDevProof: "NOT RUN", scopedCandidateBaseline: "NOT RUN",
    scopedCandidateCount: null,
    createGateReason: null,
    businessMutationsDispatched: 0, lifecycleJournal: "ERROR",
    singleUseAuthorization: v4AuthorizationBefore === null ? "MISSING"
      : v4ClaimBefore === null ? "UNCLAIMED" : "CLAIMED_OR_ATTEMPTED",
    requestSafety: "NOT RUN",
    predicateChecksPassed: 14, callbackPostsAdmitted: 0, callbackResponseStatuses: [],
    suppressedPlatformRequests: 0, suppressedMetricsRequests: 0, optionalSuppressions: [],
    localizationRequests: [],
    blockedRequests: [], failedRequestClasses: [],
    lifecycleInvoked: false, screenshotsAndTraces: "DISABLED",
    acceptanceScope: ownerReadOnly ? "OWNER_APPROVED_ELEVATED_READ_ONLY_SINGLE_USER_DEV_V4"
      : "ELEVATED_FUNCTIONAL_ONLY",
    servedConsole: {
      iframeUrl: null, scriptElementOrder: [], resources: [], failedLoads: [], pageErrors: [], runtime: null,
      expectedResourceHashes: resourceManifest ? "NOT_RUN" : "NOT_REQUESTED"
    }
  };
  const callbackRequests = new WeakSet();
  const localizationRequests = new WeakMap();
  const consoleResourceCaptures = [];
  const localizationResponseCaptures = [];
  let resourceSequence = 0;
  let verifierRequestCount = 0;
  let scopedCandidateReadRequestCount = 0;
  let verifiedSingleUserDevScopeId = null;
  let phase = "APP_INITIALIZATION";
  let context;
  try {
    context = await chromium.launchPersistentContext(authDirectory, {
      headless: false, viewport: { width: 1440, height: 1000 },
      acceptDownloads: false, serviceWorkers: "block"
    });
    const page = context.pages()[0] || await context.newPage();
    page.on("pageerror", error => {
      const name = ["Error", "TypeError", "ReferenceError", "SyntaxError"].includes(error.name)
        ? error.name : "SCRIPT_ERROR";
      const message = /^[A-Z][A-Z0-9_]{2,100}$/.test(error.message || "") ? error.message : "REDACTED";
      report.servedConsole.pageErrors.push({ name, message });
    });
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
      const localizationCapture = localizationRequests.get(response.request());
      if (localizationCapture) localizationCapture.complete(response);
      const requestUrl = response.url();
      if (!identifyConsoleResource(requestUrl, approval.origin)) return;
      const sequence = ++resourceSequence;
      consoleResourceCaptures.push((async () => {
        let body;
        try {
          body = await response.body();
        } catch {
          report.servedConsole.failedLoads.push({
            sequence, url: safeConsoleUrl(requestUrl, approval.origin), status: response.status(),
            failure: "RESOURCE_BODY_UNAVAILABLE"
          });
          return;
        }
        try {
          const evidence = createResourceEvidence({
            rawUrl: requestUrl, expectedOrigin: approval.origin, status: response.status(),
            headers: response.headers(), body, sequence, fromServiceWorker: response.fromServiceWorker()
          });
          if (evidence) report.servedConsole.resources.push(evidence);
          else report.servedConsole.failedLoads.push({
            sequence, url: safeConsoleUrl(requestUrl, approval.origin), status: response.status(),
            failure: "RESOURCE_IDENTITY_MISMATCH"
          });
        } catch {
          report.servedConsole.failedLoads.push({
            sequence, url: safeConsoleUrl(requestUrl, approval.origin), status: response.status(),
            failure: "RESOURCE_EVIDENCE_CAPTURE_FAILED"
          });
          process.exitCode = 1;
        }
      })());
    });
    context.on("requestfailed", request => {
      const consoleResource = safeConsoleUrl(request.url(), approval.origin);
      if (consoleResource) {
        const error = request.failure()?.errorText || "UNKNOWN";
        report.servedConsole.failedLoads.push({
          sequence: ++resourceSequence, url: consoleResource,
          failure: /^net::ERR_[A-Z_]+$/.test(error) ? error : "RESOURCE_REQUEST_FAILED"
        });
      }
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
      const api = url.origin === approval.origin && /\/api\/data\//i.test(url.pathname);
      const classification = classifyRequest(request, url, routing);
      const endpointEvidence = inspectAuthenticationHandoff(request, approval.origin);
      if (endpointEvidence) {
        console.log(`UAT_AUTH_HANDOFF_ENDPOINT ${JSON.stringify({ ...endpointEvidence, classification })}`);
      }
      let localizationDiagnostic = null;
      if (url.origin === approval.origin &&
          url.pathname === "/AppWebServices/MetadataService.asmx/GetResourceStrings" &&
          request.method() === "POST") {
        const headers = request.headers();
        const contentType = sanitizedContentType(headers);
        localizationDiagnostic = {
          method: request.method(), origin: url.origin, path: url.pathname,
          resourceType: request.resourceType(), navigation: request.isNavigationRequest(),
          requestContentType: contentType,
          requestBodyShape: sanitizedPayloadShape(contentType, request.postData())
        };
        console.log(`UAT_LOCALIZATION_ENDPOINT ${JSON.stringify(localizationDiagnostic)}`);
      }
      if (isUntrustedLocalizationRedirect(request, approval.origin)) {
        report.blockedRequests.push({ ...safeClass(request), classification: "UNKNOWN_REQUEST_BLOCKED" });
        return route.abort("blockedbyclient");
      }
      if (classification === "LOCALIZATION_READ_ALLOWED") {
        if (!localizationDiagnostic) {
          report.blockedRequests.push({ ...safeClass(request), classification: "UNKNOWN_REQUEST_BLOCKED" });
          return route.abort("blockedbyclient");
        }
        report.localizationRequests.push(localizationDiagnostic);
        let resolveCapture;
        const capturePromise = new Promise(resolve => { resolveCapture = resolve; });
        const timeout = setTimeout(() => {
          localizationDiagnostic.responseFailure = "RESPONSE_TIMEOUT";
          localizationDiagnostic.responseContract = "FAIL";
          resolveCapture();
        }, 15_000);
        localizationRequests.set(request, {
          complete: response => {
            void (async () => {
              try {
                await captureLocalizationResponse(response, localizationDiagnostic);
              } catch {
                localizationDiagnostic.responseFailure = "RESPONSE_CAPTURE_FAILED";
                localizationDiagnostic.responseContract = "FAIL";
              } finally {
                clearTimeout(timeout);
                resolveCapture();
              }
            })();
          }
        });
        localizationResponseCaptures.push(capturePromise);
        return route.continue();
      }
      if (["OPTIONAL_SUPPORT_SUPPRESSED", "OPTIONAL_TELEMETRY_SUPPRESSED"].includes(classification)) {
        report.suppressedPlatformRequests++;
        if (url.pathname === "/AppWebServices/MetricsReportingService.asmx/Report") report.suppressedMetricsRequests++;
        report.optionalSuppressions.push({
          classification, host: url.hostname, path: url.pathname,
          method: request.method(), resourceType: request.resourceType()
        });
        return route.abort("blockedbyclient");
      }
      const auth = classification === "AUTH_NAVIGATION";
      if (["FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION", "UNKNOWN_REQUEST_BLOCKED"].includes(classification)) {
        report.blockedRequests.push({ ...safeClass(request), classification });
        return route.abort("blockedbyclient");
      }
      if (classification === "READ_ONLY_VERIFIER_ALLOWED" && ownerReadOnly) {
        try {
          const body = request.postDataJSON();
          if (verifierRequestCount !== 0 || body.ActionType !== "VerifySingleUserDev" ||
              Object.keys(body).sort().join(",") !== "ActionType,CorrelationId" ||
              !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
                .test(body.CorrelationId)) {
            throw new Error("UAT_SINGLE_USER_DEV_VERIFIER_REQUEST_REJECTED");
          }
          verifierRequestCount++;
        } catch {
          report.blockedRequests.push({ ...safeClass(request), classification: "UNKNOWN_REQUEST_BLOCKED" });
          return route.abort("blockedbyclient");
        }
      }
      if (classification === "SCOPED_READ_OPERATION_ALLOWED") {
        try {
          const body = request.postDataJSON();
          if (!ownerReadOnly || scopedCandidateReadRequestCount !== 0 ||
              body.ActionType !== "ReadScopedCandidates" ||
              Object.keys(body).sort().join(",") !== "ActionType,CorrelationId,SyntheticScopeId" ||
              body.SyntheticScopeId !== verifiedSingleUserDevScopeId) {
            throw new Error("UAT_SCOPED_CANDIDATE_READ_REJECTED");
          }
          scopedCandidateReadRequestCount++;
        } catch {
          report.blockedRequests.push({ ...safeClass(request), classification: "UNKNOWN_REQUEST_BLOCKED" });
          return route.abort("blockedbyclient");
        }
      }
      if (auth && [callback, approval.origin].includes(url.origin) && request.method() === "POST") {
        callbackRequests.add(request);
        report.callbackPostsAdmitted++;
      }
      if (ownerReadOnly && api && request.method() === "GET") {
        const referenceScope = constrainReferenceRequest(url);
        if (isSingleUserDevDirectReadBlocked(url) || referenceScope !== "NOT_REFERENCE") {
          report.blockedRequests.push({ ...safeClass(request), classification: "UNKNOWN_REQUEST_BLOCKED" });
          return route.abort("blockedbyclient");
        }
      }
      // The app may auto-read Candidates: limit its list to the preserved synthetic marker.
      if (!ownerReadOnly && api && request.method() === "GET" &&
          url.pathname === "/api/data/v9.2/os_sr_cands") {
        const scope = `os_sr_cand_nm eq '${journal.candidateName}'`;
        const existing = url.searchParams.get("$filter");
        url.searchParams.set("$filter", existing ? `(${existing}) and (${scope})` : scope);
        return route.continue({ url: url.href });
      }
      if (api && request.method() === "GET") {
        const referenceScope = constrainReferenceRequest(url);
        if (referenceScope === "SCOPED") return route.continue({ url: url.href });
        if (referenceScope === "BLOCKED") {
          report.blockedRequests.push({ ...safeClass(request), classification: "UNKNOWN_REQUEST_BLOCKED" });
          return route.abort("blockedbyclient");
        }
      }
      return route.continue();
    });
    console.log("Authentication-only Chromium open; complete Microsoft sign-in/MFA directly if prompted.");
    await page.goto(`${approval.origin}/main.aspx?pagetype=apps`, {
      waitUntil: "domcontentloaded", timeout: 120_000
    });
    const identity = await verifyBrowserIdentity(page, approval, 480_000);
    if (approval.identityScope === "BSO_ONLY" && !identity.bsoRole) {
      throw new Error("UAT_REQUIRED_BSO_ROLE_MISSING");
    }
    if (ownerReadOnly && !identity.elevated) {
      throw new Error("UAT_APPROVED_ELEVATED_IDENTITY_MISSING");
    }
    report.exactIdentityAndOrganization = "PASS";
    if (ownerReadOnly) {
      phase = "singleuserdev-v4-proof";
      verifiedSingleUserDevScopeId = await verifySingleUserDevProof(page, approval, identity.userId);
      report.singleUserDevProof = "PASS";
      report.syntheticIsolation = "PASS";
      phase = "scoped-candidate-baseline";
      report.scopedCandidateCount = await readScopedCandidateBaseline(
        page, approval.origin, verifiedSingleUserDevScopeId);
      report.scopedCandidateBaseline = report.scopedCandidateCount === 0 ? "PASS" : "FAIL";
      if (verifierRequestCount !== 1 || scopedCandidateReadRequestCount !== 1 ||
          report.scopedCandidateCount !== 0) {
        throw new Error("UAT_SCOPED_CANDIDATE_BASELINE_FAILED");
      }
      report.candidateConsoleReadOnly = "NOT RUN";
      report.createCandidateEnabled = "NOT CHECKED";
      report.createGateReason = "READ_ONLY_CHECK_DID_NOT_OPEN_CONSOLE";
      report.authenticationOnly = "PASS";
    } else {
      phase = "SRAPP_INITIALIZATION";
      await page.goto(approval.appUrl, { waitUntil: "domcontentloaded" });
      await page.getByRole("treeitem", { name: "Candidate Management", exact: true }).click();
      phase = "CONSOLE_INITIALIZATION";
      const frame = page.frameLocator('iframe[src*="candidate-console.html"]');
      await expect(frame.getByRole("heading", { name: "Candidate Management", exact: true }))
        .toBeVisible({ timeout: 60_000 });
      const iframeUrl = await page.locator('iframe[src*="candidate-console.html"]').evaluate(element => element.src);
      report.servedConsole.iframeUrl = safeConsoleUrl(iframeUrl, approval.origin);
      report.servedConsole.scriptElementOrder = (await frame.locator("script[src]").evaluateAll(elements =>
        elements.map(element => element.src)))
        .map(url => safeConsoleUrl(url, approval.origin)).filter(Boolean);
      await expect.poll(() => frame.locator("body").evaluate(() =>
        Boolean(window.BsoRsCandidateConsoleConfiguration)), { timeout: 30_000 }).toBe(true);
      await expect.poll(() => frame.locator("body").evaluate(() => document.readyState),
        { timeout: 60_000 }).toBe("complete");
      const config = await frame.locator("body").evaluate(() => {
        const value = window.BsoRsCandidateConsoleConfiguration;
        return { mode: value.mode, core: value.candidateCoreEnabled, synthetic: value.syntheticDataOnly,
          fallback: value.devDirectWriteFallbackEnabled, availability: value.availabilityEnabled === true };
      });
      assert.deepEqual(config, { mode: "DEV", core: true, synthetic: true, fallback: false, availability: false });
      if (resourceManifest) {
        const bindingMatches = await frame.locator("body").evaluate((target) => {
          const config = window.BsoRsCandidateConsoleConfiguration;
          return config.environmentId === target.environmentId && config.organizationId === target.organizationId &&
            config.organizationUrl === target.organizationUrl;
        }, resourceManifest.target);
        if (!bindingMatches) throw new Error("UAT_RESOURCE_CONFIGURATION_BINDING_MISMATCH");
        await Promise.all(consoleResourceCaptures);
        report.servedConsole.expectedResourceHashes =
          verifyResourceHashes(report.servedConsole.resources, resourceManifest);
        if (report.servedConsole.expectedResourceHashes.some(resource => resource.result !== "MATCH")) {
          throw new Error("UAT_SERVED_RESOURCE_HASH_MISMATCH");
        }
        if (report.servedConsole.pageErrors.length) throw new Error("UAT_UNRESOLVED_SCRIPT_ERROR");
      }
      const current = new URL(page.url());
      if (current.origin !== approval.origin ||
          current.searchParams.get("appid") !== new URL(approval.appUrl).searchParams.get("appid")) {
        throw new Error("UAT_APP_ENTRYPOINT_MISMATCH");
      }
      await expect(frame.locator("#availability-submit")).toBeDisabled();
      await expect(frame.locator("#candidate-search")).toBeVisible();
      await expect(frame.locator("#candidate-rows")).toBeVisible();
      await expect(frame.locator("#create-button")).toBeVisible();
      report.candidateCoreControlsVisible = "PASS";
      const gate = await frame.locator("body").evaluate(() => {
        const policy = window.BsoRsCandidateConsolePolicy;
        const button = document.getElementById("create-button");
        const policyAvailable = Boolean(policy && typeof policy.hasSyntheticIsolation === "function");
        const isolation = Boolean(policyAvailable && policy.hasSyntheticIsolation() === true);
        const workflowPath = document.getElementById("workflow-path-badge")?.textContent;
        const notice = document.getElementById("notice")?.textContent || "";
        return {
          policyGlobalAvailable: Boolean(policy),
          policyAvailable,
          isolation,
          createEnabled: Boolean(button && !button.disabled),
          knownIsolationBlock: workflowPath === "SYNTHETIC DATA ACCESS BLOCKED" &&
            notice.includes("server-side synthetic data isolation")
        };
      });
      const gateResult = evaluateCreateGate(gate);
      report.syntheticIsolation = gateResult.syntheticIsolation;
      report.createCandidateEnabled = gateResult.createCandidateEnabled;
      report.servedConsole.runtime = {
        policyGlobalAvailable: gate.policyGlobalAvailable,
        isolationMethodAvailable: gate.policyAvailable, syntheticIsolation: report.syntheticIsolation,
        createCandidateEnabled: report.createCandidateEnabled,
        checkCalendarDisabled: await frame.locator("#availability-submit").isDisabled()
      };
      report.createGateReason = gateResult.reason;
      if (!gateResult.passed) throw new Error("UAT_CREATE_ISOLATION_GATE_UNVERIFIED");
      report.candidateConsoleReadOnly = "PASS";
      report.configuration = config;
      report.authenticationOnly = "PASS";
    }
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
    await Promise.all(consoleResourceCaptures);
    await Promise.all(localizationResponseCaptures);
    report.localizationRouting = report.localizationRequests.length === 0 ? "NOT OBSERVED"
      : report.localizationRequests.every(request => request.responseContract === "PASS")
        ? "PASS" : "FAIL";
    if (report.localizationRouting === "FAIL") process.exitCode = 1;
    report.servedConsole.resources.sort((left, right) => left.sequence - right.sequence);
    report.servedConsole.failedLoads.sort((left, right) => left.sequence - right.sequence);
    if (context) await context.close();
    report.lifecycleJournal = preservedPaths.every((file, index) => hash(file) === before[index])
      ? "PRESERVED" : "ERROR";
    if (hash(singleUserDevAuthorizationPath) !== v4AuthorizationBefore ||
        hash(`${singleUserDevAuthorizationPath}.attempt.jsonl`) !== v4ClaimBefore) {
      report.singleUseAuthorization = "CHANGED";
    }
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
