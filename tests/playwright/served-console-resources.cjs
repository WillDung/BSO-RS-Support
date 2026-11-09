const { createHash } = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const RESOURCE_NAME = /^candidate-console(?:-(?:environment|policy|availability))?\.(?:html|js|css)$/i;
const SOURCE_DIRECTORY = path.join(__dirname, "..", "..", "solutions", "CandidateConsole",
  "WebResources", "os_", "bso");

function identifyConsoleResource(rawUrl, expectedOrigin) {
  let url;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }
  const name = path.posix.basename(url.pathname);
  if (url.protocol !== "https:" || url.origin !== expectedOrigin || !RESOURCE_NAME.test(name)) return null;
  return { name, url };
}

function safeResourceUrl(url) {
  return {
    origin: url.origin,
    path: url.pathname,
    query: [...url.searchParams.keys()].sort().map(key => {
      const value = url.searchParams.get(key);
      return {
        key,
        value: /^(?:v|ver|version|hash)$/i.test(key) && /^[a-z0-9_-]{1,128}$/i.test(value || "")
          ? value : "REDACTED"
      };
    })
  };
}

function checkedInHash(name) {
  const sourcePath = path.join(SOURCE_DIRECTORY, name);
  return fs.existsSync(sourcePath)
    ? createHash("sha256").update(fs.readFileSync(sourcePath)).digest("hex")
    : null;
}

function decisionStatements(source, functionName) {
  const expression = new RegExp(`(?:async\\s+)?function\\s+${functionName}\\s*\\([^)]*\\)\\s*\\{([\\s\\S]*?)^\\s{2}\\}`,
    "m");
  const match = expression.exec(source);
  if (!match) return [];
  const baseLine = source.slice(0, match.index).split(/\r?\n/).length;
  return match[1].split(/\r?\n/).flatMap((line, index) =>
    /\b(?:if|return|throw)\b|hasSyntheticIsolation|BsoRsCandidateConsolePolicy|create-button/.test(line)
      ? [{ line: baseLine + index + 1, statement: line.trim() }]
      : []);
}

function analyzeSource(name, source, baseUrl) {
  if (name === "candidate-console.html") {
    const scripts = [];
    for (const match of source.matchAll(/<script\b[^>]*\bsrc\s*=\s*(["'])(.*?)\1[^>]*>/gi)) {
      let url;
      try {
        url = new URL(match[2], baseUrl || "https://console-resource.invalid/");
      } catch {
        continue;
      }
      if (RESOURCE_NAME.test(path.posix.basename(url.pathname))) {
        scripts.push(safeResourceUrl(url));
      }
    }
    const createButton = source.match(/<button\b[^>]*\bid=["']create-button["'][^>]*>/i)?.[0] || "";
    return {
      deferredScriptReferences: scripts,
      createButtonInitiallyDisabled: /\sdisabled(?:\s|=|>)/i.test(createButton)
    };
  }

  if (name === "candidate-console-policy.js") {
    return {
      definesPolicyGlobal: /defineProperty\s*\(\s*global\s*,\s*["']BsoRsCandidateConsolePolicy["']/.test(source),
      definesIsolationCheck: /function\s+hasSyntheticIsolation\s*\(/.test(source),
      isolationReturnsLiteralFalse:
        /function\s+hasSyntheticIsolation\s*\(\s*\)\s*\{[^}]*return\s+false\s*;?[^}]*\}/s.test(source)
    };
  }

  if (name === "candidate-console.js") {
    const createButtonAssignments = [];
    const lines = source.split(/\r?\n/);
    lines.forEach((line, index) => {
      if (!/create-button/i.test(line)) return;
      const assignment = line.match(/\.disabled\s*=\s*(true|false)\b/i);
      if (assignment) createButtonAssignments.push({ line: index + 1, disabled: assignment[1].toLowerCase() });
    });
    return {
      referencesPolicyGlobal: /BsoRsCandidateConsolePolicy/.test(source),
      requiresTrueIsolationResult: /hasSyntheticIsolation\s*\(\s*\)\s*===\s*true/.test(source),
      hasInitializationEarlyExit: /if\s*\(\s*!isCandidateCoreEnabled\s*\(\s*\)\s*\)\s*\{[\s\S]{0,1200}?\breturn\s*;/.test(source),
      createButtonAssignments,
      enablementDecisionStatements: decisionStatements(source, "isCandidateCoreEnabled"),
      initializationDecisionStatements: decisionStatements(source, "initialize")
    };
  }
  return {};
}

function createResourceEvidence({ rawUrl, expectedOrigin, status, headers, body, sequence, fromServiceWorker }) {
  const identified = identifyConsoleResource(rawUrl, expectedOrigin);
  if (!identified) return null;
  const bytes = Buffer.isBuffer(body) ? body : Buffer.from(body || "");
  const hash = createHash("sha256").update(bytes).digest("hex");
  const localHash = checkedInHash(identified.name);
  const contentType = headers["content-type"] || "";
  const cacheControl = headers["cache-control"] || "";
  const etag = headers.etag || "";
  const lastModified = headers["last-modified"] || "";
  const source = bytes.toString("utf8");
  const evidence = {
    sequence,
    name: identified.name,
    url: safeResourceUrl(identified.url),
    status,
    contentType: /^[a-z0-9!#$&^_.+-]+\/[a-z0-9!#$&^_.+-]+(?:;\s*charset=[a-z0-9._-]+)?$/i.test(contentType)
      ? contentType : "REDACTED",
    cacheControl: /^[a-z0-9=,;_\-.* ]{0,256}$/i.test(cacheControl) ? cacheControl : "REDACTED",
    etag: /^(?:W\/)?"?[a-z0-9._:-]{1,128}"?$/i.test(etag) ? etag : "REDACTED",
    lastModified: Number.isNaN(Date.parse(lastModified)) ? null : new Date(lastModified).toUTCString(),
    fromServiceWorker: fromServiceWorker === true,
    byteLength: bytes.length,
    sha256: hash,
    checkedInSha256: localHash,
    sourceMatch: hash === localHash ? "MATCH" : "DIFFERS",
    sourceFacts: /\.(?:html|js)$/i.test(identified.name)
      ? analyzeSource(identified.name, source, identified.url) : {}
  };
  return evidence;
}

function safeConsoleUrl(rawUrl, expectedOrigin) {
  const identified = identifyConsoleResource(rawUrl, expectedOrigin);
  return identified ? safeResourceUrl(identified.url) : null;
}

module.exports = { analyzeSource, createResourceEvidence, identifyConsoleResource, safeConsoleUrl };
