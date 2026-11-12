(function (global) {
  "use strict";

  const GUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const ENVIRONMENT_MODES = new Set(["DEV", "TEST", "PROD"]);
  const CANDIDATE_OPERATION_MODES = new Set(["BsoSynthetic", "SingleUserDev"]);
  let isolation = null;

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

    const candidateOperationMode = configuration.candidateOperationMode || "BsoSynthetic";
    if (!CANDIDATE_OPERATION_MODES.has(candidateOperationMode) ||
        candidateOperationMode === "SingleUserDev" &&
        (mode !== "DEV" || configuration.syntheticDataOnly !== true ||
          configuration.devDirectWriteFallbackEnabled !== false)) {
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
      candidateOperationMode,
      syntheticDataOnly: configuration.syntheticDataOnly,
      directWriteFallbackAvailable: candidateOperationMode !== "SingleUserDev" &&
        mode === "DEV" && configuration.devDirectWriteFallbackEnabled,
      diagnosticsMode: configuration.diagnosticsMode
    });
  }

  function allowsReference(label, syntheticDataOnly) {
    if (typeof label !== "string" || !label.trim() || typeof syntheticDataOnly !== "boolean") return false;
    const developmentReference = label.startsWith("[DEV]");
    return syntheticDataOnly ? developmentReference : !developmentReference;
  }

  function hasSyntheticIsolation() {
    return isolation !== null && Date.parse(isolation.validUntil) > Date.now();
  }

  function getSyntheticScope() {
    return hasSyntheticIsolation() ? isolation : null;
  }

  async function verifySyntheticIsolation(configuration, runtime) {
    isolation = null;
    const resolved = resolve(configuration, runtime);
    if (!resolved.allowed || resolved.mode !== "DEV" || !resolved.syntheticDataOnly ||
        !normalizeGuid(runtime.actorId)) throw new Error("SYNTHETIC_VERIFIER_CONTEXT_REJECTED");
    const correlationId = typeof global.crypto?.randomUUID === "function" ? global.crypto.randomUUID() : null;
    if (!normalizeGuid(correlationId) || correlationId === "00000000-0000-0000-0000-000000000000") {
      throw new Error("SYNTHETIC_VERIFIER_CORRELATION_UNAVAILABLE");
    }
    const singleUserDev = resolved.candidateOperationMode === "SingleUserDev";
    const resultCode = singleUserDev ? "SingleUserDevVerified" : "SyntheticIsolationVerified";
    const response = await global.fetch("/api/data/v9.2/os_sr_cact", {
      method: "POST",
      credentials: "same-origin",
      headers: {
        Accept: "application/json", "Content-Type": "application/json; charset=utf-8",
        "OData-MaxVersion": "4.0", "OData-Version": "4.0"
      },
      body: JSON.stringify({
        ActionType: singleUserDev ? "VerifySingleUserDev" : "VerifySyntheticIsolation",
        CorrelationId: correlationId
      })
    });
    if (!response.ok) throw new Error("SYNTHETIC_VERIFIER_UNAVAILABLE");
    const result = await response.json();
    if (!result || result.ResultCode !== resultCode ||
        typeof result.IsolationContract !== "string") throw new Error("SYNTHETIC_VERIFIER_RESPONSE_INVALID");
    const proof = JSON.parse(result.IsolationContract);
    const expectedBoundary = singleUserDev ? "SingleUserDevCandidateCoreApi" : "ScopedCandidateCoreApi";
    const expectedVersion = singleUserDev ? 4 : 2;
    const expectedNativeWritesDenied = !singleUserDev;
    const guids = ["organizationId", "environmentId", "actorId", "scopeId", "candidateId",
      "positionId", "sourceId", "taId", "locationId"];
    if (!proof || proof.version !== expectedVersion || proof.boundary !== expectedBoundary ||
        proof.mode !== (singleUserDev ? "SingleUserDev" : undefined) ||
        proof.nativeWritesDenied !== expectedNativeWritesDenied ||
        singleUserDev && (proof.scopedReads !== true || proof.globalGuardsRequired !== false) ||
        proof.readback !== "CallerOwnedScope" || proof.calendarEnabled !== false ||
        guids.some((name) => !normalizeGuid(proof[name])) ||
        normalizeGuid(proof.organizationId) !== normalizeGuid(runtime.organizationId) ||
        normalizeGuid(proof.environmentId) !== normalizeGuid(configuration.environmentId) ||
        normalizeGuid(proof.actorId) !== normalizeGuid(runtime.actorId) ||
        normalizeGuid(proof.scopeId) !== normalizeGuid(proof.candidateId) ||
        !Number.isFinite(Date.parse(proof.validUntil)) ||
        Date.parse(proof.validUntil) <= Date.now() ||
        Date.parse(proof.validUntil) > Date.now() + 125000) {
      throw new Error("SYNTHETIC_VERIFIER_RESPONSE_INVALID");
    }
    isolation = Object.freeze({ ...proof });
    return isolation;
  }

  function identifier(value) {
    if (typeof value !== "string" || !/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(value)) {
      throw new Error("CONSOLE_QUERY_ATTRIBUTE_INVALID");
    }
    return value;
  }

  // These predicates narrow queries; server authorization remains independently required.
  function syntheticCandidateFilter(navigation = "") {
    const path = navigation ? `${identifier(navigation)}/` : "";
    const scope = getSyntheticScope();
    const exact = scope ? `${path}os_sr_candid eq ${normalizeGuid(scope.candidateId)} and ` : "";
    return exact + `startswith(${path}os_sr_cand_nm,'[[]SYNTHETIC-E2E]') and ` +
      `endswith(${path}os_sr_cand_eml,'.invalid')`;
  }

  function syntheticReferenceFilter(nameAttribute, navigation = "") {
    const path = navigation ? `${identifier(navigation)}/` : "";
    const binding = {
      os_sr_pos_ttl: ["os_sr_posid", "positionId"], os_sr_csrc_nm: ["os_sr_csrcid", "sourceId"],
      os_sr_ta_nm: ["os_sr_taid", "taId"], os_sr_loc_nm: ["os_sr_locid", "locationId"]
    }[nameAttribute];
    const scope = getSyntheticScope();
    if (scope && !binding) throw new Error("CONSOLE_QUERY_ATTRIBUTE_INVALID");
    const exact = scope ? `${path}${binding[0]} eq ${normalizeGuid(scope[binding[1]])} and ` : "";
    return exact + `startswith(${path}${identifier(nameAttribute)},'[[]DEV]')`;
  }

  Object.defineProperty(global, "BsoRsCandidateConsolePolicy", {
    configurable: false,
    enumerable: false,
    writable: false,
    value: Object.freeze({
      allowsReference, hasSyntheticIsolation, getSyntheticScope, verifySyntheticIsolation,
      resolve, syntheticCandidateFilter, syntheticReferenceFilter
    })
  });
})(window);
