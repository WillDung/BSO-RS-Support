const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const sourcePath = path.join(
  __dirname,
  "..",
  "solutions",
  "CandidateConsole",
  "WebResources",
  "os_",
  "bso",
  "candidate-console.js"
);
const source = fs.readFileSync(sourcePath, "utf8");

function loadCanonicalMask() {
  const orderStart = source.indexOf("  const PROFILE_FIELD_ORDER = [");
  const orderEnd = source.indexOf("  ];", orderStart) + "  ];".length;
  const functionStart = source.indexOf("  function canonicalProfileFieldMask(", orderEnd);
  const functionEnd = source.indexOf("\n  }", functionStart) + "\n  }".length;
  assert.ok(orderStart >= 0 && orderEnd > orderStart);
  assert.ok(functionStart >= orderEnd && functionEnd > functionStart);

  const context = {};
  vm.runInNewContext(
    `${source.slice(orderStart, orderEnd)}\n${source.slice(functionStart, functionEnd)}\nglobalThis.mask = canonicalProfileFieldMask;`,
    context
  );
  return context.mask;
}

test("profile mask contains exactly changed fields in canonical contract order", () => {
  const mask = loadCanonicalMask();
  assert.equal(
    mask(["AssignedTaId", "CandidatePhone", "CandidateName"]),
    "CandidateName,CandidatePhone,AssignedTaId"
  );
  assert.equal(mask(["CandidateCvUrl", "CandidatePhone"]), "CandidatePhone,CandidateCvUrl");
  assert.equal(mask([]), "");
});

test("Edit Candidate sends only changed values, including explicit null clears", () => {
  const start = source.indexOf("  async function updateCandidateThroughCore(event)");
  const end = source.indexOf("  async function recordCallThroughCore(event)", start);
  const update = source.slice(start, end);

  assert.ok(update.includes("const changedProfileFields = new Set();"));
  assert.equal((update.match(/changedProfileFields\.add\(inputName\)/g) || []).length, 2);
  assert.ok(update.includes("changedProfileFields.add(inputName);"));
  assert.ok(update.includes('inputs.ProfileFieldMask = canonicalProfileFieldMask(changedProfileFields);'));
  assert.ok(update.includes("const next = optional ? (value || null) : value;"));
  assert.ok(update.includes("inputs[inputName] = next;"));
  assert.ok(update.includes("if (Object.keys(baseline).length === 0)"));
  assert.ok(update.includes('invokeCandidateCore("UpdateCandidate", inputs, newCorrelationId())'));
  assert.equal((update.match(/invokeCandidateCore\("UpdateCandidate"/g) || []).length, 1);
  assert.ok(!update.includes("WebApi.updateRecord"));
});
