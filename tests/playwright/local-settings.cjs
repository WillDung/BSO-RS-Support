const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

function protectDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  if (process.platform === "win32") {
    const identity = execFileSync("whoami", ["/user", "/fo", "csv", "/nh"], { encoding: "utf8" });
    const sid = identity.match(/S-1-[0-9]+(?:-[0-9]+)+/);
    if (!sid) throw new Error("UAT_LOCAL_IDENTITY_UNAVAILABLE");
    execFileSync("icacls", [directory, "/inheritance:r", "/grant:r", `*${sid[0]}:(OI)(CI)F`],
      { stdio: "pipe" });
  } else {
    fs.chmodSync(directory, 0o700);
  }
}

function loadApproval() {
  const approvalPath = process.env.BSO_UAT_APPROVAL_FILE;
  if (!approvalPath || !path.isAbsolute(approvalPath)) {
    throw new Error("UAT_ABSOLUTE_LOCAL_APPROVAL_FILE_REQUIRED");
  }
  const approval = JSON.parse(fs.readFileSync(approvalPath, "utf8"));
  const url = new URL(approval.appUrl);
  if (url.protocol !== "https:" || !/^org[a-z0-9]+\.crm[0-9]*\.dynamics\.com$/i.test(url.hostname) ||
      url.pathname !== "/main.aspx" || url.username || url.password ||
      !/^[0-9a-f-]{36}$/i.test(url.searchParams.get("appid") || "") ||
      !/^[0-9a-f-]{36}$/i.test(approval.organizationId || "") ||
      typeof approval.expectedUpn !== "string" || !approval.expectedUpn.includes("@") ||
      !/^CAND-[0-9]+$/.test(approval.candidateNumber || "") ||
      approval.syntheticReadScopeApproved !== true ||
      approval.syntheticLifecycleAuthorized !== false ||
      !["BSO_ONLY", "OWNER_APPROVED_ELEVATED_READ_ONLY"].includes(approval.identityScope || "BSO_ONLY")) {
    throw new Error("UAT_INVALID_OR_UNAUTHORIZED_LOCAL_APPROVAL");
  }
  // The read-only approval never authorizes the separate lifecycle suite.
  return Object.freeze({ ...approval, origin: url.origin, identityScope: approval.identityScope || "BSO_ONLY" });
}

const authDirectory = path.join(__dirname, ".auth");
const runDirectory = process.env.BSO_UAT_RUN_DIRECTORY ||
  path.join(__dirname, "results", new Date().toISOString().replace(/[:.]/g, "-"));

module.exports = { protectDirectory, loadApproval, authDirectory, runDirectory };
