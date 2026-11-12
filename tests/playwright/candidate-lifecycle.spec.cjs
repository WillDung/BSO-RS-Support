const { test, expect, chromium } = require("@playwright/test");
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { authDirectory, runDirectory } = require("./local-settings.cjs");
const { verifyBrowserIdentity } = require("./browser-identity.cjs");
const {
  loadPinnedAuthenticationCallbackOrigin, resolveAuthenticationRouting,
  inspectAuthenticationHandoff
} = require("./authentication-routing.cjs");
const {
  validateSyntheticIsolationProof, validateOperationCorrelation
} = require("./independent-authorization.cjs");
const { classifyRequest, matchesCandidateActionResponse } = require("./request-classification.cjs");
const {
  captureFailure, refreshFailureEvidence, sanitizeBlockedRequest
} = require("./lifecycle-failure.cjs");
const {
  ACTIONS, STATUSES, REFERENCE_LABELS, REFERENCE_SCHEMA, GUID, requireCondition, referenceQuery,
  approvedReferenceId, constrainReferenceRequest, isSingleUserDevDirectReadBlocked,
  loadLifecycleApproval, reserveOneShot, readRows, scopedReadFailure,
  readSingleUserDevRows, readEvidence, counts, validateEvidence
} = require("./lifecycle-support.cjs");

test("One owner-approved synthetic Candidate lifecycle", async ({}, testInfo) => {
  const approval = loadLifecycleApproval();
  const readOnlyMode = process.env.BSO_UAT_LIFECYCLE_READ_ONLY === "true";
  const report = {
    preparation: "READY",
    ownerMutationApproval: approval.approved ? "PRESENT" : "MISSING",
    bsoIdentity: "NOT RUN",
    authenticatedOwner: "NOT RUN",
    scopedV2Proof: "NOT RUN",
    singleUserDevProof: "NOT RUN",
    lifecycle: "NOT RUN",
    acceptanceScope: approval.identityScope === "SINGLE_USER_DEV"
      ? "SINGLE_USER_DEV_V4_BOUNDED_FUNCTIONAL"
      : "BSO_ONLY_SCOPED_V2_PROOF_REQUIRED",
    scopedReadFailure: null,
    baselineCounts: null,
    counts: null,
    reloadPersistence: "NOT RUN",
    forbiddenRequestsBlocked: 0,
    deliberatelyCreatedEmailCalendarOrAvailability: 0,
    platformSupportRequestsSuppressed: 0,
    optionalSuppressions: [],
    unknownRequestsBlocked: 0,
    blockedRequestKinds: [],
    firstRelevantBlockedRequest: null,
    authenticationHandoffs: [],
    requestCategoryCounts: {},
    readOnlyVerification: readOnlyMode ? "PENDING" : "NOT REQUESTED",
    dispatchedOperations: [],
    screenshotsAndTraces: "DISABLED"
  };
  const writeReport = () => fs.writeFileSync(path.join(runDirectory, "lifecycle-report.json"),
    JSON.stringify(report, null, 2));
  writeReport();
  test.skip(!approval.approved, "UAT_OWNER_LIFECYCLE_MUTATION_APPROVAL_MISSING");
  let record = approval.independentAuthorizationRecord ? {
    authorizationId: approval.independentAuthorizationRecord.scope.authorizationId,
    attemptId: approval.independentAuthorizationRecord.attemptId,
    marker: approval.independentAuthorizationRecord.marker,
    candidateName: approval.independentAuthorizationRecord.candidateName,
    candidateEmail: approval.independentAuthorizationRecord.candidateEmail,
    candidateId: null,
    attempts: [],
    status: "RESERVED_NO_DISPATCH"
  } : null;
  let context;
  let journal;
  let armed = null;
  let routeFailure = null;
  let phase = "runner-configuration";
  const failureState = {};
  let page;
  let references;
  let schedule;
  let evidence;
  let syntheticProofObservation;
  const save = () => { if (journal) journal.save(); writeReport(); };
  const assertNoUnexpected = () => requireCondition(!routeFailure &&
    report.forbiddenRequestsBlocked === 0, routeFailure || "UAT_UNEXPECTED_MUTATION");
  const countClassification = classification => {
    report.requestCategoryCounts[classification] = (report.requestCategoryCounts[classification] || 0) + 1;
  };
  const recordBlockedRequest = kind => {
    const safeKind = sanitizeBlockedRequest(kind);
    report.firstRelevantBlockedRequest ??= safeKind;
    if (!report.blockedRequestKinds.some(existing => JSON.stringify(existing) === JSON.stringify(safeKind))) {
      report.blockedRequestKinds.push(safeKind);
    }
  };

  try {
    requireCondition(["BSO_ONLY", "SINGLE_USER_DEV"].includes(approval.identityScope) &&
      approval.independentAuthorizationRecord,
    "UAT_SUPPORTED_INDEPENDENT_AUTHORIZATION_REQUIRED");
    requireCondition(testInfo.config.workers === 1 && testInfo.project.retries === 0 &&
      testInfo.project.repeatEach === 1 && testInfo.retry === 0 && testInfo.repeatEachIndex === 0,
    "UAT_ONE_SHOT_RUNNER_CONFIGURATION_REQUIRED");
    requireCondition(record, "UAT_SUPPORTED_INDEPENDENT_AUTHORIZATION_REQUIRED");
    phase = "browser-initialization";
    context = await chromium.launchPersistentContext(authDirectory, {
      headless: false, viewport: { width: 1440, height: 1000 },
      timezoneId: "Asia/Ho_Chi_Minh", acceptDownloads: false, serviceWorkers: "block"
    });
    page = context.pages()[0] || await context.newPage();
    const routing = resolveAuthenticationRouting({
      organizationOrigin: approval.origin,
      scopedCallbackOrigin: approval.lifecycleScope.authenticationCallbackOrigin,
      pinnedCallbackOrigin: loadPinnedAuthenticationCallbackOrigin()
    });
    await context.route("**/*", async route => {
      const request = route.request();
      const url = new URL(request.url());
      const mutation = !["GET", "HEAD", "OPTIONS"].includes(request.method());
      const api = url.origin === approval.origin && /\/api\/data\//i.test(url.pathname);
      const classificationOptions = routing;
      const classification = classifyRequest(request, url, classificationOptions);
      countClassification(classification);
      const handoffEvidence = inspectAuthenticationHandoff(request, approval.origin);
      if (handoffEvidence) {
        report.authenticationHandoffs.push({ ...handoffEvidence, classification });
      }
      if (["OPTIONAL_SUPPORT_SUPPRESSED", "OPTIONAL_TELEMETRY_SUPPRESSED"].includes(classification)) {
        report.platformSupportRequestsSuppressed++;
        report.optionalSuppressions.push({
          classification, host: url.hostname, path: url.pathname,
          method: request.method(), resourceType: request.resourceType()
        });
        return route.abort("blockedbyclient");
      }
      if (classification === "READ_ONLY_VERIFIER_ALLOWED") {
        try {
          const body = request.postDataJSON();
          const expectedAction = approval.identityScope === "SINGLE_USER_DEV"
            ? "VerifySingleUserDev" : "VerifySyntheticIsolation";
          requireCondition(body.ActionType === expectedAction &&
            Object.keys(body).sort().join(",") === "ActionType,CorrelationId" &&
            GUID.test(body.CorrelationId),
          "UAT_VERIFIER_REQUEST_SCOPE_MISMATCH");
          return route.continue();
        } catch (error) {
          routeFailure = String(error.message).match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_VERIFIER_REQUEST_REJECTED";
          report.forbiddenRequestsBlocked++;
          return route.abort("blockedbyclient");
        }
      }
      if (classification === "SCOPED_READ_OPERATION_ALLOWED") {
        try {
          const body = request.postDataJSON();
          requireCondition(approval.identityScope === "SINGLE_USER_DEV" &&
            body.SyntheticScopeId === approval.lifecycleScope.syntheticIsolation.scopeId,
          "UAT_SCOPED_READ_BOUNDARY_MISMATCH");
          return route.continue();
        } catch (error) {
          routeFailure = String(error.message).match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_SCOPED_READ_REJECTED";
          report.forbiddenRequestsBlocked++;
          return route.abort("blockedbyclient");
        }
      }
      if (api && mutation && url.pathname === "/api/data/v9.2/os_sr_cact") {
        try {
          requireCondition(!readOnlyMode && request.method() === "POST" && armed && !routeFailure &&
            Date.parse(approval.lifecycleScope.expiresAt) > Date.now(), "UAT_UNARMED_OR_REPEATED_OPERATION");
          const body = request.postDataJSON();
          const index = record.attempts.length;
          requireCondition(body.ActionType === ACTIONS[index] && body.ActionType === armed.action &&
            (approval.identityScope !== "SINGLE_USER_DEV" ||
              body.SyntheticScopeId === approval.lifecycleScope.syntheticIsolation.scopeId),
          "UAT_OPERATION_SEQUENCE_MISMATCH");
          const correlation = validateOperationCorrelation(
            body.CorrelationId, record, approval.independentAuthorizationRecord);
          const expected = { ...armed.inputs, ActionType: armed.action, CorrelationId: body.CorrelationId };
          if (approval.identityScope === "SINGLE_USER_DEV") {
            expected.SyntheticScopeId = approval.lifecycleScope.syntheticIsolation.scopeId;
          }
          if (armed.action === "RecordCall") {
            const contacted = Date.parse(body.ContactedAt);
            requireCondition(Number.isFinite(contacted) && contacted <= Date.now() + 5000 &&
              contacted >= Date.now() - 15000, "UAT_CALL_TIME_MISMATCH");
            expected.ContactedAt = body.ContactedAt;
          }
          requireCondition(Object.keys(body).length === Object.keys(expected).length &&
            Object.keys(expected).every(key => body[key] === expected[key]), "UAT_OPERATION_PAYLOAD_MISMATCH");
          requireCondition(classifyRequest(request, url, {
            ...classificationOptions, approvedBusinessOperation: true
          }) === "APPROVED_BUSINESS_OPERATION", "UAT_BUSINESS_REQUEST_SHAPE_MISMATCH");
          report.requestCategoryCounts.FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION--;
          countClassification("APPROVED_BUSINESS_OPERATION");
          // Consume the arm before awaiting anything; a concurrent retry must not pass.
          armed = null;
          if (approval.identityScope !== "SINGLE_USER_DEV") {
            const previous = await readRows(page, approval.origin, "os_sr_oprcs", ["os_sr_oprcid"],
              `os_sr_oprc_corid eq '${correlation}'`);
            requireCondition(previous.length === 0, "UAT_CORRELATION_ALREADY_EXISTS");
          }
          assertNoUnexpected();
          record.attempts.push({
            action: body.ActionType, correlation,
            classification: "APPROVED_BUSINESS_OPERATION",
            contactedAt: body.ContactedAt, outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
          });
          record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
          save();
          return await route.continue();
        } catch (error) {
          armed = null;
          routeFailure = String(error.message).match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_DISPATCH_GUARD_FAILED";
          report.forbiddenRequestsBlocked++;
          recordBlockedRequest({
            classification: "FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION",
            method: request.method(), host: url.hostname, path: url.pathname,
            resourceType: request.resourceType(), navigation: request.isNavigationRequest()
          });
          return route.abort("blockedbyclient");
        }
      }
      // Outside Microsoft authentication, no other HTTP write or provider call is admitted.
      if (["FORBIDDEN_BUSINESS_OR_PROVIDER_OPERATION", "UNKNOWN_REQUEST_BLOCKED"].includes(classification)) {
        const unknown = classification === "UNKNOWN_REQUEST_BLOCKED";
        routeFailure = unknown ? "UAT_UNKNOWN_REQUEST_BLOCKED" : "UAT_UNEXPECTED_BUSINESS_OR_PROVIDER_REQUEST";
        if (unknown) report.unknownRequestsBlocked++;
        else report.forbiddenRequestsBlocked++;
        const kind = { classification, method: request.method(), host: url.hostname, path: url.pathname,
          resourceType: request.resourceType(), navigation: request.isNavigationRequest() };
        recordBlockedRequest(kind);
        return route.abort("blockedbyclient");
      }
      if (approval.identityScope === "SINGLE_USER_DEV" && api &&
          request.method() === "GET" && isSingleUserDevDirectReadBlocked(url)) {
        routeFailure = "UAT_UNSCOPED_SINGLE_USER_DEV_READ_BLOCKED";
        report.unknownRequestsBlocked++;
        recordBlockedRequest({
          classification: "UNKNOWN_REQUEST_BLOCKED", method: request.method(),
          host: url.hostname, path: url.pathname, resourceType: request.resourceType(),
          navigation: request.isNavigationRequest()
        });
        return route.abort("blockedbyclient");
      }
      // Keep the normal Console list path, but constrain the server response to this one marker.
      if (api && request.method() === "GET" && url.pathname === "/api/data/v9.2/os_sr_cands") {
        const existing = url.searchParams.get("$filter");
        const scope = `os_sr_cand_nm eq '${record.candidateName}' or os_sr_cand_eml eq '${record.candidateEmail}'`;
        url.searchParams.set("$filter", existing ? `(${existing}) and (${scope})` : scope);
        return route.continue({ url: url.href });
      }
      if (api && request.method() === "GET") {
        const referenceScope = constrainReferenceRequest(url);
        if (referenceScope === "SCOPED") {
          return route.continue({ url: url.href });
        }
        if (referenceScope === "BLOCKED") {
          routeFailure = "UAT_UNSCOPED_REFERENCE_READ_BLOCKED";
          report.requestCategoryCounts.READ_REQUEST_ALLOWED--;
          countClassification("UNKNOWN_REQUEST_BLOCKED");
          report.unknownRequestsBlocked++;
          recordBlockedRequest({
            classification: "UNKNOWN_REQUEST_BLOCKED", method: request.method(),
            host: url.hostname, path: url.pathname, resourceType: request.resourceType(),
            navigation: request.isNavigationRequest()
          });
          return route.abort("blockedbyclient");
        }
      }
      return route.continue();
    });

    phase = "identity-verification";
    await page.goto(`${approval.origin}/main.aspx?pagetype=apps`, { waitUntil: "domcontentloaded" });
    const identity = await verifyBrowserIdentity(page, approval, 480_000);
    requireCondition(identity.userId === approval.expectedActorId.toLowerCase(),
      "UAT_APPROVED_ACTOR_IDENTITY_MISMATCH");
    if (approval.identityScope === "BSO_ONLY") {
      requireCondition(identity.bsoRole && !identity.elevated, "UAT_APPROVED_BSO_IDENTITY_MISMATCH");
      report.bsoIdentity = "PASS";
    } else {
      report.authenticatedOwner = "PASS";
    }
    report.exactOrganizationAndAccount = "VERIFIED";
    assertNoUnexpected();

    phase = "approved-reference-readback";
    references = {};
    for (const key of Object.keys(REFERENCE_SCHEMA)) {
      const query = referenceQuery(key);
      const rows = approval.identityScope === "SINGLE_USER_DEV"
        ? await readSingleUserDevRows(page, approval.origin, {
          position: "os_sr_pos", source: "os_sr_csrc", ta: "os_sr_ta", location: "os_sr_loc"
        }[key], approval.lifecycleScope.syntheticIsolation.scopeId, record)
        : await readRows(page, approval.origin, query.collection, query.columns, query.filter);
      references[key] = approvedReferenceId(key, rows);
    }
    if (["BSO_ONLY", "SINGLE_USER_DEV"].includes(approval.identityScope)) {
      const binding = approval.lifecycleScope.syntheticIsolation;
      requireCondition(references.position.toLowerCase() === binding.positionId.toLowerCase() &&
        references.source.toLowerCase() === binding.sourceId.toLowerCase() &&
        references.ta.toLowerCase() === binding.taId.toLowerCase() &&
        references.location.toLowerCase() === binding.locationId.toLowerCase(),
      "UAT_APPROVED_REFERENCE_PROFILE_BINDING_MISMATCH");
    }

    phase = "synthetic-baseline-readback";
    evidence = await readEvidence(page, approval.origin, record, approval.independentAuthorizationRecord);
    report.baselineCounts = counts(evidence);
    requireCondition(Object.values(report.baselineCounts).every(count => count === 0), "UAT_NONEMPTY_SYNTHETIC_BASELINE");
    save();

    phase = "candidate-console-navigation";
    const verifierAction = approval.identityScope === "SINGLE_USER_DEV"
      ? "VerifySingleUserDev" : "VerifySyntheticIsolation";
    const verifierResultCode = approval.identityScope === "SINGLE_USER_DEV"
      ? "SingleUserDevVerified" : "SyntheticIsolationVerified";
    const verifierResponse = page.waitForResponse(response => {
      const request = response.request();
      const url = new URL(response.url());
      if (request.method() !== "POST" || url.origin !== approval.origin ||
          url.pathname !== "/api/data/v9.2/os_sr_cact") return false;
      try {
        return request.postDataJSON().ActionType === verifierAction;
      } catch {
        return false;
      }
    }, { timeout: 30_000 }).then(async response => {
      const requestBody = response.request().postDataJSON();
      requireCondition(Object.keys(requestBody).sort().join(",") === "ActionType,CorrelationId" &&
        requestBody.ActionType === verifierAction && GUID.test(requestBody.CorrelationId),
      "UAT_SYNTHETIC_PROOF_REQUEST_SHAPE_INVALID");
      requireCondition(response.ok(), "UAT_SYNTHETIC_PROOF_REQUEST_FAILED");
      const body = await response.json();
      requireCondition(body.ResultCode === verifierResultCode &&
        typeof body.IsolationContract === "string", "UAT_SYNTHETIC_PROOF_RESPONSE_INVALID");
      return { correlationId: requestBody.CorrelationId, contract: body.IsolationContract };
    });
    const observedVerifier = verifierResponse.then(proof => ({ proof }), error => ({ error }));
    await page.goto(approval.appUrl, { waitUntil: "domcontentloaded" });
    await page.getByRole("treeitem", { name: "Candidate Management", exact: true }).click();
    const frame = page.frameLocator('iframe[src*="candidate-console.html"]');
    phase = "candidate-console-initialization";
    await expect(frame.getByRole("heading", { name: "Candidate Management", exact: true })).toBeVisible();
    await expect.poll(() => frame.locator("body").evaluate(() =>
      Boolean(window.BsoRsCandidateConsoleConfiguration))).toBe(true);
    const configuration = await frame.locator("body").evaluate(({ identityScope }) => {
      const config = window.BsoRsCandidateConsoleConfiguration;
      return config.mode === "DEV" && config.candidateCoreEnabled === true &&
        config.syntheticDataOnly === true && config.devDirectWriteFallbackEnabled === false &&
        (identityScope !== "SINGLE_USER_DEV" || config.candidateOperationMode === "SingleUserDev") &&
        config.availabilityEnabled !== true;
    }, { identityScope: approval.identityScope });
    requireCondition(configuration, "UAT_UNSAFE_CONSOLE_CONFIGURATION");
    await expect(frame.locator("#availability-submit")).toBeDisabled();
    await expect(frame.locator("#create-button")).toBeEnabled();
    const verifier = await observedVerifier;
    requireCondition(verifier.proof && !verifier.error, "UAT_SYNTHETIC_PROOF_NOT_OBSERVED");
    syntheticProofObservation = verifier.proof;
    validateSyntheticIsolationProof(syntheticProofObservation,
      approval.independentAuthorizationRecord);
    if (approval.identityScope === "SINGLE_USER_DEV") report.singleUserDevProof = "VERIFIED";
    else report.scopedV2Proof = "VERIFIED";
    if (readOnlyMode) {
      requireCondition(Object.values(report.baselineCounts || {}).every(count => count === 0),
        "UAT_READ_ONLY_BASELINE_NOT_EMPTY");
      assertNoUnexpected();
      report.readOnlyVerification = "PASS";
      report.lifecycle = "NOT RUN";
      writeReport();
      return;
    }
    const tomorrow = new Date(Date.now() + 7 * 3600000);
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    while ([0, 6].includes(tomorrow.getUTCDay())) tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    const date = tomorrow.toISOString().slice(0, 10);
    schedule = { start: `${date}T02:00:00.000Z`, end: `${date}T03:00:00.000Z` };
    const cv = `https://careers.example.invalid/cv/playwright-${record.marker}`;

    const invokeOnce = async (action, inputs, click) => {
      phase = `${action}-dispatch-and-readback`;
      assertNoUnexpected();
      requireCondition(!armed && record.attempts.length === ACTIONS.indexOf(action), "UAT_OPERATION_NOT_NEXT");
      armed = { action, inputs };
      save();
      const responsePromise = page.waitForResponse(response =>
        matchesCandidateActionResponse(response, approval.origin, action,
          record.attempts.at(-1)?.correlation), { timeout: 30_000 });
      // Attach rejection handling before clicking, so a failed click cannot leave an unhandled waiter.
      const observed = responsePromise.then(response => ({ response }), () => ({ error: true }));
      await click();
      const result = await observed;
      assertNoUnexpected();
      requireCondition(result.response && !result.error, "UAT_OPERATION_OUTCOME_UNKNOWN_NO_RETRY");
      const response = result.response;
      requireCondition(await response.finished() === null && response.ok(), "UAT_OPERATION_REJECTED_NO_RETRY");
      const body = await response.json();
      const index = ACTIONS.indexOf(action);
      requireCondition(body.ResultCode === "Applied" && body.CurrentStatus === STATUSES[index] &&
        (body.PreviousStatus ?? null) === (index === 0 ? null : STATUSES[index - 1]),
      "UAT_UNEXPECTED_OPERATION_OUTCOME");
      record.attempts[index].response = {
        ResultCode: body.ResultCode, CurrentStatus: body.CurrentStatus,
        PreviousStatus: body.PreviousStatus, CallLogId: body.CallLogId, StatusHistoryId: body.StatusHistoryId
      };
      record.attempts[index].outcome = "APPLIED";
      report.dispatchedOperations.push(action);
      save();

      evidence = await readEvidence(page, approval.origin, record, approval.independentAuthorizationRecord);
      if (index === 0) {
        requireCondition(evidence.candidate.length === 1, "UAT_CREATED_CANDIDATE_NOT_UNIQUE");
        record.candidateId = evidence.candidate[0].os_sr_candid;
        requireCondition(GUID.test(record.candidateId), "UAT_CREATED_CANDIDATE_ID_INVALID");
        // Read again with exact lookups now that the generated Candidate ID is known.
        evidence = await readEvidence(page, approval.origin, record, approval.independentAuthorizationRecord);
      }
      report.counts = counts(evidence);
      validateEvidence(evidence, record, index + 1, identity.userId, references, schedule,
        approval.identityScope);
      save();
      await expect(frame.locator("#detail-heading")).toHaveText(record.candidateName);
      const status = frame.locator("#candidate-details dt").filter({ hasText: /^Status$/ }).locator("+ dd");
      await expect(status).toHaveText([
        "Need Call Candidate", "Candidate Answered", "Waiting Manual Scheduling", "Round 1 Scheduled"
      ][index]);
      await expect(frame.locator("#create-button")).toBeEnabled();
    };

    await frame.getByRole("textbox", { name: "Candidate Name", exact: true }).fill(record.candidateName);
    await frame.getByRole("textbox", { name: "Email", exact: true }).fill(record.candidateEmail);
    await frame.locator("#candidate-cv-url").fill(cv);
    for (const [key, id] of [
      ["position", "candidate-position"], ["source", "candidate-source"], ["ta", "candidate-assigned-ta"]
    ]) {
      await expect(frame.locator(`#${id} option`).filter({ hasText: REFERENCE_LABELS[key] })).toHaveCount(1);
      await frame.locator(`#${id}`).selectOption(references[key]);
    }
    if (!journal) {
      phase = "one-shot-claim-acquisition";
      journal = reserveOneShot(approval, {
        workers: testInfo.config.workers, retries: testInfo.project.retries,
        repeatEach: testInfo.project.repeatEach, retry: testInfo.retry,
        repeatEachIndex: testInfo.repeatEachIndex
      }, syntheticProofObservation);
      if (approval.identityScope === "SINGLE_USER_DEV") report.singleUserDevProof = "PASS";
      else report.scopedV2Proof = "PASS";
      requireCondition(record.marker === journal.record.marker &&
        record.candidateName === journal.record.candidateName &&
        record.candidateEmail === journal.record.candidateEmail &&
        record.attemptId === journal.record.attemptId,
      "UAT_CLAIM_IDENTITY_MISMATCH");
      record = journal.record;
    }
    await invokeOnce("CreateCandidate", {
      CandidateName: record.candidateName, CandidateEmail: record.candidateEmail,
      CandidateCvUrl: cv, PositionId: references.position, CandidateSourceId: references.source,
      AssignedTaId: references.ta
    }, () => frame.getByRole("button", { name: "Create Candidate", exact: true }).click());
    await expect(frame.locator("#candidate-details")).toContainText(evidence.candidate[0].os_sr_cand_cnum);

    await frame.locator("#candidate-rows tr").getByRole("button", { name: "Record Call", exact: true }).click();
    await frame.locator("#call-outcome").selectOption("100010000");
    await invokeOnce("RecordCall", {
      CandidateId: record.candidateId, ExpectedStatus: STATUSES[0], CallOutcome: 100010000
    }, () => frame.getByRole("button", { name: "Save Call", exact: true }).click());
    await expect(frame.locator("#call-history-rows tr:not(:has(td.empty))")).toHaveCount(1);

    await invokeOnce("ProceedToScheduling", {
      CandidateId: record.candidateId, ExpectedStatus: STATUSES[1]
    }, () => frame.getByRole("button", { name: "Move to Waiting Manual Scheduling", exact: true }).click());
    await frame.getByRole("button", { name: "Schedule Round 1", exact: true }).click();
    await frame.locator("#scheduling-ta").selectOption(references.ta);
    await frame.locator("#scheduling-location").selectOption(references.location);
    await frame.locator("#scheduling-date").fill(date);
    await frame.locator("#scheduling-time").fill("09:00");
    await frame.locator("#scheduling-end-time").fill("10:00");
    await invokeOnce("MarkRound1Scheduled", {
      CandidateId: record.candidateId, ExpectedStatus: STATUSES[2], InterviewerId: references.ta,
      LocationId: references.location, StartAt: schedule.start, EndAt: schedule.end
    }, () => frame.getByRole("button", { name: "Save Schedule", exact: true }).click());

    phase = "reload-persistence-readback";
    const fingerprint = value => createHash("sha256").update(JSON.stringify(Object.fromEntries(
      Object.entries(value).map(([name, rows]) => [name,
        rows.map(row => Object.fromEntries(Object.entries(row).sort(([a], [b]) => a.localeCompare(b))))
          .sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)))])))).digest("hex");
    const before = fingerprint(evidence);
    await page.reload({ waitUntil: "domcontentloaded" });
    await expect(frame.getByRole("heading", { name: "Candidate Management", exact: true })).toBeVisible();
    const row = frame.locator("#candidate-rows tr").filter({
      has: page.getByRole("cell", { name: record.candidateName, exact: true })
    });
    await expect(row).toHaveCount(1);
    await row.getByRole("button", { name: "Open", exact: true }).click();
    await expect(frame.locator("#detail-heading")).toHaveText(record.candidateName);
    await expect(frame.locator("#call-history-rows tr:not(:has(td.empty))")).toHaveCount(1);
    await expect(frame.locator("#schedule-history-rows tr:not(:has(td.empty))")).toHaveCount(1);
    await expect(frame.locator("#status-history-rows tr:not(:has(td.empty))")).toHaveCount(3);
    await expect(frame.locator("#availability-submit")).toBeDisabled();
    evidence = await readEvidence(page, approval.origin, record, approval.independentAuthorizationRecord);
    validateEvidence(evidence, record, 4, identity.userId, references, schedule,
      approval.identityScope);
    requireCondition(fingerprint(evidence) === before, "UAT_RELOAD_PERSISTENCE_MISMATCH");
    assertNoUnexpected();
    requireCondition(record.attempts.length === 4 && report.dispatchedOperations.length === 4,
      "UAT_OPERATION_ATTEMPT_COUNT_MISMATCH");
    report.counts = counts(evidence);
    report.reloadPersistence = "PASS";
    report.lifecycle = "PASS";
    record.status = "COMPLETED_DO_NOT_RERUN";
    save();
  } catch (error) {
    armed = null;
    if (phase === "identity-verification" && report.bsoIdentity !== "PASS") {
      if (approval.identityScope === "SINGLE_USER_DEV") report.authenticatedOwner = "FAIL";
      else report.bsoIdentity = "FAIL";
    }
    if (report.scopedV2Proof === "VERIFIED") report.scopedV2Proof = "FAIL";
    if (report.singleUserDevProof === "VERIFIED") report.singleUserDevProof = "FAIL";
    report.lifecycle = "FAIL";
    report.scopedReadFailure = scopedReadFailure(error);
    const primaryError = captureFailure(failureState, error, phase, report);
    if (journal) {
      journal.record.status = "STOPPED_NO_RETRY_RECONCILE_ONLY";
      try {
        journal.save();
      } catch (cleanupError) {
        captureFailure(failureState, cleanupError, "journal-stop-save", report);
      }
    }
    try {
      writeReport();
    } catch (cleanupError) {
      captureFailure(failureState, cleanupError, "failure-report-write", report);
      console.error("UAT_FAILURE_REPORT_WRITE_FAILED");
    }
    throw primaryError;
  } finally {
    armed = null;
    if (context) {
      try {
        await context.close();
      } catch (cleanupError) {
        captureFailure(failureState, cleanupError, "browser-context-close", report);
        console.error("UAT_BROWSER_CLEANUP_FAILED");
      }
    }
    refreshFailureEvidence(report);
    try {
      writeReport();
    } catch (cleanupError) {
      captureFailure(failureState, cleanupError, "final-report-write", report);
      console.error("UAT_FINAL_REPORT_WRITE_FAILED");
    }
    if (failureState.primaryError) throw failureState.primaryError;
  }
});
