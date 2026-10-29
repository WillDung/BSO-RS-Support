(function (global) {
  "use strict";

  const GUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const ENVIRONMENT_MODES = new Set(["DEV", "TEST", "PROD"]);

  function blocked(reason) {
    return Object.freeze({ allowed: false, reason });
  }

  function normalizeGuid(value) {
    if (typeof value !== "string") return "";
    const normalized = value.replace(/^\{([^{}]+)\}$/, "$1");
    return GUID_PATTERN.test(normalized) ? normalized.toLowerCase() : "";
  }

  function resolve(configuration, runtime) {
    if (!configuration || typeof configuration !== "object" || !runtime || typeof runtime !== "object") {
      return blocked("CONFIGURATION_MISSING");
    }

    const mode = typeof configuration.mode === "string" ? configuration.mode.toUpperCase() : "";
    if (!ENVIRONMENT_MODES.has(mode)) return blocked("BLOCK_UNRECOGNIZED_ENVIRONMENT");

    if (!normalizeGuid(configuration.environmentId) ||
        !normalizeGuid(configuration.organizationId) ||
        typeof configuration.organizationUrl !== "string" ||
        configuration.candidateCoreEnabled !== true ||
        typeof configuration.syntheticDataOnly !== "boolean" ||
        typeof configuration.devDirectWriteFallbackEnabled !== "boolean" ||
        !["OFF", "SAFE"].includes(configuration.diagnosticsMode)) {
      return blocked("CONFIGURATION_INVALID");
    }

    if (mode !== "PROD" && configuration.syntheticDataOnly !== true) {
      return blocked("CONFIGURATION_INVALID");
    }

    let expectedUrl;
    let actualUrl;
    try {
      expectedUrl = new URL(configuration.organizationUrl);
      actualUrl = new URL(runtime.organizationUrl);
    } catch {
      return blocked("CONFIGURATION_INVALID");
    }

    if (expectedUrl.protocol !== "https:" ||
        expectedUrl.username || expectedUrl.password ||
        expectedUrl.pathname !== "/" || expectedUrl.search || expectedUrl.hash) {
      return blocked("CONFIGURATION_INVALID");
    }

    if (actualUrl.protocol !== "https:" ||
        actualUrl.username || actualUrl.password ||
        actualUrl.origin.toLowerCase() !== expectedUrl.origin.toLowerCase() ||
        normalizeGuid(runtime.organizationId) !== normalizeGuid(configuration.organizationId)) {
      return blocked("ENVIRONMENT_IDENTITY_MISMATCH");
    }

    return Object.freeze({
      allowed: true,
      mode,
      syntheticDataOnly: configuration.syntheticDataOnly,
      directWriteFallbackAvailable: mode === "DEV" && configuration.devDirectWriteFallbackEnabled,
      diagnosticsMode: configuration.diagnosticsMode
    });
  }

  Object.defineProperty(global, "BsoRsCandidateConsolePolicy", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze({ resolve })
  });
})(window);
