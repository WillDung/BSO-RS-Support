const { test, expect, chromium } = require("@playwright/test");
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { authDirectory, runDirectory } = require("./local-settings.cjs");
const { verifyBrowserIdentity } = require("./browser-identity.cjs");
const { isAuthenticationRequest } = require("./authentication-request.cjs");
const {
  ACTIONS, STATUSES, REFERENCE_LABELS, GUID, requireCondition, loadLifecycleApproval,
  reserveOneShot, readRows, readEvidence, counts, validateEvidence
} = require("./lifecycle-support.cjs");

test("One owner-approved synthetic Candidate lifecycle", async ({}, testInfo) => {
  const approval = loadLifecycleApproval();
  const report = {
    preparation: "READY",
    ownerMutationApproval: approval.approved ? "PRESENT" : "MISSING",
    lifecycle: "NOT RUN",
    acceptanceScope: "ELEVATED_FUNCTIONAL_ONLY_NOT_CLEAN_BSO_SECURITY",
    baselineCounts: null,
    counts: null,
    reloadPersistence: "NOT RUN",
    unexpectedBusinessOrProviderMutations: 0,
    deliberatelyCreatedEmailCalendarOrAvailability: 0,
    platformSupportRequestsSuppressed: 0,
    blockedRequestKinds: [],
    dispatchedOperations: [],
    screenshotsAndTraces: "DISABLED"
  };
  const writeReport = () => fs.writeFileSync(path.join(runDirectory, "lifecycle-report.json"),
    JSON.stringify(report, null, 2));
  writeReport();
  test.skip(!approval.approved, "UAT_OWNER_LIFECYCLE_MUTATION_APPROVAL_MISSING");
  requireCondition(testInfo.config.workers === 1 && testInfo.project.retries === 0 &&
    testInfo.project.repeatEach === 1 && testInfo.retry === 0 && testInfo.repeatEachIndex === 0,
  "UAT_ONE_SHOT_RUNNER_CONFIGURATION_REQUIRED");

  let context;
  let journal;
  let armed = null;
  let routeFailure = null;
  let page;
  let references;
  let schedule;
  let evidence;
  const save = () => { journal.save(); writeReport(); };
  const assertNoUnexpected = () => requireCondition(!routeFailure &&
    report.unexpectedBusinessOrProviderMutations === 0, routeFailure || "UAT_UNEXPECTED_MUTATION");

  try {
    journal = reserveOneShot(approval);
    const record = journal.record;
    context = await chromium.launchPersistentContext(authDirectory, {
      headless: false, viewport: { width: 1440, height: 1000 },
      timezoneId: "Asia/Ho_Chi_Minh", acceptDownloads: false, serviceWorkers: "block"
    });
    page = context.pages()[0] || await context.newPage();
    await context.route("**/*", async route => {
      const request = route.request();
      const url = new URL(request.url());
      const mutation = !["GET", "HEAD", "OPTIONS"].includes(request.method());
      const api = url.origin === approval.origin && /\/api\/data\//i.test(url.pathname);
      const operation = url.pathname.split("/").pop();
      const platformSupport = api && request.method() === "POST" &&
        ["msdyn_ReportToMonitoringHub", "GetRecentItems", "GetCopilotSettingsForEnvironment"].includes(operation);
      if (platformSupport) {
        report.platformSupportRequestsSuppressed++;
        return route.abort("blockedbyclient");
      }
      if (api && mutation && url.pathname === "/api/data/v9.2/os_sr_cact") {
        try {
          requireCondition(request.method() === "POST" && armed && !routeFailure &&
            Date.parse(approval.lifecycleScope.expiresAt) > Date.now(), "UAT_UNARMED_OR_REPEATED_OPERATION");
          const body = request.postDataJSON();
          const index = record.attempts.length;
          requireCondition(body.ActionType === ACTIONS[index] && body.ActionType === armed.action &&
            GUID.test(body.CorrelationId) &&
            !record.attempts.some(attempt => attempt.correlation === body.CorrelationId.toLowerCase()),
          "UAT_OPERATION_SEQUENCE_MISMATCH");
          const expected = { ...armed.inputs, ActionType: armed.action, CorrelationId: body.CorrelationId };
          if (armed.action === "RecordCall") {
            const contacted = Date.parse(body.ContactedAt);
            requireCondition(Number.isFinite(contacted) && contacted <= Date.now() + 5000 &&
              contacted >= Date.now() - 15000, "UAT_CALL_TIME_MISMATCH");
            expected.ContactedAt = body.ContactedAt;
          }
          requireCondition(Object.keys(body).length === Object.keys(expected).length &&
            Object.keys(expected).every(key => body[key] === expected[key]), "UAT_OPERATION_PAYLOAD_MISMATCH");
          // Consume the arm before awaiting anything; a concurrent retry must not pass.
          armed = null;
          const previous = await readRows(page, approval.origin, "os_sr_oprcs", ["os_sr_oprcid"],
            `os_sr_oprc_corid eq '${body.CorrelationId.toLowerCase()}'`);
          requireCondition(previous.length === 0, "UAT_CORRELATION_ALREADY_EXISTS");
          assertNoUnexpected();
          record.attempts.push({
            action: body.ActionType, correlation: body.CorrelationId.toLowerCase(),
            contactedAt: body.ContactedAt, outcome: "DISPATCH_RESERVED_OUTCOME_UNKNOWN"
          });
          record.status = "DISPATCH_RESERVED_OUTCOME_UNKNOWN";
          save();
          return await route.continue();
        } catch (error) {
          armed = null;
          routeFailure = String(error.message).match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_DISPATCH_GUARD_FAILED";
          report.unexpectedBusinessOrProviderMutations++;
          return route.abort("blockedbyclient");
        }
      }
      // Outside Microsoft authentication, no other HTTP write or provider call is admitted.
      const signIn = isAuthenticationRequest(request, url, approval.lifecycleScope.authenticationCallbackOrigin);
      const provider = /(^|\.)(graph\.microsoft\.com|outlook\.office365\.com|outlook\.office\.com)$/i.test(url.hostname);
      if (provider || (mutation && !signIn)) {
        routeFailure = "UAT_UNEXPECTED_BUSINESS_OR_PROVIDER_REQUEST";
        report.unexpectedBusinessOrProviderMutations++;
        const kind = { method: request.method(), host: url.hostname, path: url.pathname };
        if (!report.blockedRequestKinds.some(existing => JSON.stringify(existing) === JSON.stringify(kind))) {
          report.blockedRequestKinds.push(kind);
        }
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
        const reference = [
          ["os_sr_pos", "position"], ["os_sr_csrc", "source"], ["os_sr_ta", "ta"], ["os_sr_loc", "location"]
        ].find(([stem]) => url.pathname === `/api/data/v9.2/${stem}s`);
        if (reference) {
          const [stem, key] = reference;
          const scope = `${stem}_nm eq '${REFERENCE_LABELS[key]}' and statecode eq 0`;
          const existing = url.searchParams.get("$filter");
          url.searchParams.set("$filter", existing ? `(${existing}) and (${scope})` : scope);
          return route.continue({ url: url.href });
        }
      }
      return route.continue();
    });

    await page.goto(`${approval.origin}/main.aspx?pagetype=apps`, { waitUntil: "domcontentloaded" });
    const identity = await verifyBrowserIdentity(page, approval, 480_000);
    requireCondition(identity.bsoRole && identity.elevated, "UAT_APPROVED_FUNCTIONAL_IDENTITY_MISMATCH");
    report.exactOrganizationAndAccount = "VERIFIED";
    assertNoUnexpected();

    references = {};
    for (const [key, stem] of [
      ["position", "os_sr_pos"], ["source", "os_sr_csrc"], ["ta", "os_sr_ta"], ["location", "os_sr_loc"]
    ]) {
      const rows = await readRows(page, approval.origin, `${stem}s`, [`${stem}id`, `${stem}_nm`, "statecode"],
        `${stem}_nm eq '${REFERENCE_LABELS[key]}' and statecode eq 0`);
      requireCondition(rows.length === 1 && GUID.test(rows[0][`${stem}id`]), "UAT_APPROVED_REFERENCE_NOT_UNIQUE_ACTIVE");
      references[key] = rows[0][`${stem}id`];
    }

    evidence = await readEvidence(page, approval.origin, record);
    report.baselineCounts = counts(evidence);
    requireCondition(Object.values(report.baselineCounts).every(count => count === 0), "UAT_NONEMPTY_SYNTHETIC_BASELINE");
    save();

    await page.goto(approval.appUrl, { waitUntil: "domcontentloaded" });
    await page.getByRole("treeitem", { name: "Candidate Management", exact: true }).click();
    const frame = page.frameLocator('iframe[src*="candidate-console.html"]');
    await expect(frame.getByRole("heading", { name: "Candidate Management", exact: true })).toBeVisible();
    await expect.poll(() => frame.locator("body").evaluate(() =>
      Boolean(window.BsoRsCandidateConsoleConfiguration))).toBe(true);
    const configuration = await frame.locator("body").evaluate(() => {
      const config = window.BsoRsCandidateConsoleConfiguration;
      return config.mode === "DEV" && config.candidateCoreEnabled === true &&
        config.syntheticDataOnly === true && config.devDirectWriteFallbackEnabled === false &&
        config.availabilityEnabled !== true;
    });
    requireCondition(configuration, "UAT_UNSAFE_CONSOLE_CONFIGURATION");
    await expect(frame.locator("#availability-submit")).toBeDisabled();
    await expect(frame.locator("#create-button")).toBeEnabled();
    const tomorrow = new Date(Date.now() + 7 * 3600000);
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    while ([0, 6].includes(tomorrow.getUTCDay())) tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    const date = tomorrow.toISOString().slice(0, 10);
    schedule = { start: `${date}T02:00:00.000Z`, end: `${date}T03:00:00.000Z` };
    const cv = `https://careers.example.invalid/cv/playwright-${record.marker}`;

    const invokeOnce = async (action, inputs, click) => {
      assertNoUnexpected();
      requireCondition(!armed && record.attempts.length === ACTIONS.indexOf(action), "UAT_OPERATION_NOT_NEXT");
      armed = { action, inputs };
      save();
      const responsePromise = page.waitForResponse(response =>
        response.url() === `${approval.origin}/api/data/v9.2/os_sr_cact` &&
        response.request().method() === "POST", { timeout: 30_000 });
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

      evidence = await readEvidence(page, approval.origin, record);
      if (index === 0) {
        requireCondition(evidence.candidate.length === 1, "UAT_CREATED_CANDIDATE_NOT_UNIQUE");
        record.candidateId = evidence.candidate[0].os_sr_candid;
        requireCondition(GUID.test(record.candidateId), "UAT_CREATED_CANDIDATE_ID_INVALID");
        // Read again with exact lookups now that the generated Candidate ID is known.
        evidence = await readEvidence(page, approval.origin, record);
      }
      report.counts = counts(evidence);
      validateEvidence(evidence, record, index + 1, identity.userId, references, schedule);
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
    evidence = await readEvidence(page, approval.origin, record);
    validateEvidence(evidence, record, 4, identity.userId, references, schedule);
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
    report.lifecycle = "FAIL";
    report.failure = String(error.message || "").match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_LIFECYCLE_ASSERTION_FAILED";
    if (journal) {
      journal.record.status = "STOPPED_NO_RETRY_RECONCILE_ONLY";
      journal.save();
    }
    throw new Error(report.failure);
  } finally {
    armed = null;
    if (context) await context.close();
    writeReport();
  }
});
