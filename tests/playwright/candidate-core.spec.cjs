const { test, expect, chromium } = require("@playwright/test");
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { loadApproval, authDirectory, runDirectory } = require("./local-settings.cjs");
const { verifyBrowserIdentity } = require("./browser-identity.cjs");

test("Candidate Core owner browser UAT (read-only)", async () => {
  const approval = loadApproval();
  const report = {
    authentication: "BLOCKED",
    identityScope: approval.identityScope,
    bsoOnlySecurityAcceptance: "NOT ESTABLISHED",
    candidateConsole: "NOT RUN",
    syntheticReadOnly: "NOT RUN",
    syntheticLifecycle: "NOT AUTHORIZED",
    reloadPersistence: "NOT RUN",
    checkCalendarDisabled: "NOT VERIFIED",
    requestSafety: "NOT VERIFIED",
    blockedRequestKinds: [],
    suppressedPlatformSupportRequests: 0,
    platformSideEffectsAudited: false,
    deliberateBusinessMutations: 0,
    outlookOrEmailActionInvocations: 0,
    traces: "DISABLED: authentication headers/cookies must not be recorded",
    screenshots: [],
    completedSteps: []
  };
  let context;
  let forbiddenRequests = 0;
  let phase = "authentication";
  const fail = code => { throw new Error(code); };
  const step = async (name, action) => {
    await test.step(name, action);
    report.completedSteps.push(name);
  };

  try {
    context = await chromium.launchPersistentContext(authDirectory, {
      headless: false,
      viewport: { width: 1440, height: 1000 },
      acceptDownloads: false,
      serviceWorkers: "block"
    });
    // Keep API writes blocked, including optional shell calls; sign-in is separate.
    await context.route("**/*", async route => {
      const request = route.request();
      const url = new URL(request.url());
      const mutation = !["GET", "HEAD", "OPTIONS"].includes(request.method());
      const businessApi = url.origin === approval.origin && /\/api\/data\//i.test(url.pathname);
      const provider = /(^|\.)(graph\.microsoft\.com|outlook\.office365\.com|outlook\.office\.com)$/i.test(url.hostname);
      if ((businessApi && mutation) || provider) {
        const operation = businessApi
          ? url.pathname.match(/\/api\/data\/v[0-9.]+\/([a-z_][a-z0-9_.]{0,80})(?=[/(]|$)/i)?.[1] || "OTHER"
          : "PROVIDER";
        const platformSupport = businessApi && request.method() === "POST" &&
          ["msdyn_ReportToMonitoringHub", "GetRecentItems", "GetCopilotSettingsForEnvironment"].includes(operation) &&
          url.pathname.endsWith(`/${operation}`);
        if (platformSupport) report.suppressedPlatformSupportRequests++;
        else forbiddenRequests++;
        const kind = { method: request.method(), operation, phase,
          classification: platformSupport ? "SUPPRESSED_PLATFORM_SUPPORT" : "FORBIDDEN_BUSINESS_OR_PROVIDER" };
        if (!report.blockedRequestKinds.some(existing =>
          existing.method === kind.method && existing.operation === kind.operation && existing.phase === kind.phase)) {
          report.blockedRequestKinds.push(kind);
        }
        await route.abort("blockedbyclient");
      } else {
        await route.continue();
      }
    });
    const page = context.pages()[0] || await context.newPage();
    const consoleFrame = page.frameLocator('iframe[src*="candidate-console.html"]');

    await step("Authenticate interactively and verify exact organization/BSO", async () => {
      // The app auto-reads Candidates. Verify identity on the app-list shell first.
      await page.goto(`${approval.origin}/main.aspx?pagetype=apps`, { waitUntil: "domcontentloaded" });
      const identity = await verifyBrowserIdentity(page, approval, 480_000);
      report.identityChecks = {
        organizationMatched: identity.target,
        accountMatched: identity.account,
        bsoRolePresent: identity.bsoRole,
        elevatedRolePresent: identity.elevated
      };
      report.authentication = "PASS";
    });

    phase = "candidateConsole";
    await step("Open exact srapp and Candidate Management", async () => {
      await page.goto(approval.appUrl, { waitUntil: "domcontentloaded" });
      await page.getByRole("treeitem", { name: "Candidate Management", exact: true }).click();
      await expect(consoleFrame.getByRole("heading", { name: "Candidate Management", exact: true })).toBeVisible();
      await expect.poll(() => consoleFrame.locator("body").evaluate(() =>
        Boolean(window.BsoRsCandidateConsoleConfiguration))).toBe(true);
      const actual = await consoleFrame.locator("body").evaluate(() => {
        const config = window.BsoRsCandidateConsoleConfiguration;
        return {
          mode: config?.mode,
          core: config?.candidateCoreEnabled,
          synthetic: config?.syntheticDataOnly,
          fallback: config?.devDirectWriteFallbackEnabled,
          availability: config?.availabilityEnabled === true
        };
      });
      report.consoleConfiguration = actual;
      if (actual.mode !== "DEV" || actual.core !== true ||
          actual.synthetic !== true || actual.fallback !== false || actual.availability) {
        fail("UAT_UNSAFE_CONSOLE_CONFIGURATION");
      }
      report.candidateConsole = "PASS";
    });

    const availabilityDisabled = async () => {
      for (const id of ["availability-ta", "availability-mode", "availability-start",
        "availability-end", "availability-duration", "availability-submit"]) {
        await expect(consoleFrame.locator(`#${id}`)).toBeDisabled();
      }
      report.checkCalendarDisabled = "VERIFIED";
    };
    const openApprovedCandidate = async () => {
      const row = consoleFrame.locator("#candidate-rows tr").filter({
        has: page.getByRole("cell", { name: approval.candidateNumber, exact: true })
      });
      await expect(row).toHaveCount(1);
      const permitted = await row.evaluate(element => {
        const cells = element.querySelectorAll("td");
        return cells[1]?.textContent.startsWith("[SYNTHETIC-E2E]") &&
          /^[^\s@]+@[^\s@]+\.invalid$/i.test(cells[2]?.textContent.trim() || "");
      });
      if (!permitted) fail("UAT_SELECTED_CANDIDATE_OUTSIDE_SYNTHETIC_SCOPE");
      await row.getByRole("button", { name: "Open", exact: true }).click();
      await expect(consoleFrame.locator("#detail-panel")).toBeVisible();
      await expect(consoleFrame.locator("#detail-heading")).toHaveText(/^\[SYNTHETIC-E2E\]/);
    };
    const persistedEvidence = async () => {
      for (const [id, count] of [["call-history-rows", 1], ["schedule-history-rows", 1],
        ["status-history-rows", 3]]) {
        await expect(consoleFrame.locator(`#${id} tr:not(:has(td.empty))`)).toHaveCount(count);
      }
      await expect(consoleFrame.locator("#call-history-rows")).toContainText("Answered");
      await expect(consoleFrame.locator("#schedule-history-rows")).toContainText("Round 1");
      await expect(consoleFrame.locator("#schedule-history-rows")).toContainText("[DEV]");
      await expect(consoleFrame.locator("#schedule-history-rows")).toContainText("ACTIVE / SCHEDULED");
      for (const status of ["Need Call Candidate", "Candidate Answered",
        "Waiting Manual Scheduling", "Round 1 Scheduled"]) {
        await expect(consoleFrame.locator("#status-history-rows")).toContainText(status);
      }
      const status = await consoleFrame.locator("#candidate-details").evaluate(element => {
        const label = [...element.querySelectorAll("dt")].find(node => node.textContent === "Status");
        return label?.nextElementSibling?.textContent;
      });
      if (status !== "Round 1 Scheduled") fail("UAT_PERSISTED_STATUS_MISMATCH");
      const snapshot = await consoleFrame.locator("#detail-panel").evaluate(element =>
        ["candidate-details", "call-history-rows", "schedule-history-rows", "status-history-rows"]
          .map(id => element.querySelector(`#${id}`).textContent.trim()).join("\n"));
      return createHash("sha256").update(snapshot).digest("hex");
    };

    phase = "syntheticReadOnly";
    let beforeReload;
    await step("Read approved synthetic Candidate and exact persisted evidence", async () => {
      await openApprovedCandidate();
      const permittedList = await consoleFrame.locator("#candidate-rows tr").evaluateAll(rows =>
        rows.every(row => {
          const cells = row.querySelectorAll("td");
          return cells.length === 11 && cells[1].textContent.startsWith("[SYNTHETIC-E2E]") &&
            /^[^\s@]+@[^\s@]+\.invalid$/i.test(cells[2].textContent.trim());
        }));
      if (!permittedList) fail("UAT_VISIBLE_LIST_OUTSIDE_SYNTHETIC_SCOPE");
      for (const id of ["candidate-position", "candidate-source", "candidate-assigned-ta", "scheduling-location"]) {
        const permitted = await consoleFrame.locator(`#${id}`).evaluate(select => {
          const references = [...select.options].filter(option => option.value);
          return references.length > 0 && references.every(option => option.textContent.startsWith("[DEV]"));
        });
        if (!permitted) fail("UAT_REFERENCE_SELECTOR_OUTSIDE_APPROVED_SCOPE");
      }
      beforeReload = await persistedEvidence();
      await availabilityDisabled();
      const screenshot = "synthetic-candidate-detail.png";
      await consoleFrame.locator("#detail-panel").screenshot({
        path: path.join(runDirectory, screenshot),
        mask: [consoleFrame.locator('#candidate-details dt:has-text("Owner") + dd')]
      });
      report.screenshots.push(screenshot);
      report.syntheticReadOnly = "PASS";
    });

    phase = "reloadPersistence";
    await step("Reload and verify exact evidence persistence and Calendar disabled", async () => {
      await page.reload({ waitUntil: "domcontentloaded" });
      await expect(consoleFrame.getByRole("heading", { name: "Candidate Management", exact: true })).toBeVisible();
      await openApprovedCandidate();
      const afterReload = await persistedEvidence();
      if (afterReload !== beforeReload) fail("UAT_RELOAD_PERSISTENCE_MISMATCH");
      await availabilityDisabled();
      report.reloadPersistence = "PASS";
    });
    phase = "requestSafety";
    await step("Verify no business mutation or provider request was attempted", async () => {
      if (forbiddenRequests !== 0) fail("UAT_UNEXPECTED_BUSINESS_OR_PROVIDER_REQUEST");
      report.requestSafety = "PASS";
    });
    await test.step("Synthetic lifecycle NOT AUTHORIZED: no mutation attempted", async () => {
      test.info().annotations.push({ type: "scope", description: "Phase 4 not authorized by owner; no mutations" });
    });
  } catch (error) {
    if (phase !== "authentication") report[phase] = "FAIL";
    const code = String(error.message || "").match(/\bUAT_[A-Z_]+\b/)?.[0] || "UAT_BROWSER_ASSERTION_FAILED";
    report.failure = code;
    throw new Error(code);
  } finally {
    report.blockedBusinessOrProviderRequests = forbiddenRequests;
    fs.writeFileSync(path.join(runDirectory, "uat-report.json"), JSON.stringify(report, null, 2));
    if (context) await context.close();
  }
});
