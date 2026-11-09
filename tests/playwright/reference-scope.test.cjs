"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  REFERENCE_LABELS, REFERENCE_SCHEMA, referenceQuery, approvedReferenceId, constrainReferenceRequest,
  readRows, scopedReadFailure
} = require("./lifecycle-support.cjs");

const logicalNames = Object.freeze({
  position: "os_sr_pos",
  source: "os_sr_csrc",
  ta: "os_sr_ta",
  location: "os_sr_loc"
});
const origin = "https://orgsynthetic.crm4.dynamics.com";

test("lifecycle reference selectors import the shared approved labels", () => {
  const source = fs.readFileSync(path.join(__dirname, "candidate-lifecycle.spec.cjs"), "utf8");
  const imports = source.match(/const\s*{([^{}]+)}\s*=\s*require\("\.\/lifecycle-support\.cjs"\)/);
  assert.ok(imports);
  assert.match(imports[1], /\bREFERENCE_LABELS\b/);
  assert.match(source, /hasText:\s*REFERENCE_LABELS\[key\]/);
});

for (const [key, logicalName] of Object.entries(logicalNames)) {
  test(`${key} query uses the exported reference schema and exact approved label`, () => {
    const schema = REFERENCE_SCHEMA[key];
    const query = referenceQuery(key);
    const xml = fs.readFileSync(path.join(__dirname, "..", "..", "solutions", "Entities",
      logicalName, "Entity.xml"), "utf8");
    const attributes = Array.from(xml.matchAll(/<attribute PhysicalName="[^"]+">([\s\S]*?)<\/attribute>/g),
      match => match[1]);
    const primaryId = attributes.find(attribute => /<Type>primarykey<\/Type>/.test(attribute));
    const primaryName = attributes.find(attribute => /<DisplayMask>PrimaryName(?:\||<)/.test(attribute));
    assert.ok(primaryId && primaryId.includes(`<LogicalName>${schema.id}</LogicalName>`));
    assert.ok(primaryName && primaryName.includes(`<LogicalName>${schema.name}</LogicalName>`));
    assert.ok(xml.includes(`<EntitySetName>${schema.collection}</EntitySetName>`));
    assert.deepEqual(query.columns, [schema.id, schema.name, "statecode"]);
    assert.equal(query.collection, schema.collection);
    assert.equal(query.filter, `${schema.name} eq '${REFERENCE_LABELS[key]}' and statecode eq 0`);
    const id = "11111111-1111-4111-8111-111111111111";
    const approved = { [schema.id]: id, [schema.name]: REFERENCE_LABELS[key], statecode: 0 };
    assert.equal(approvedReferenceId(key, [approved]), id);
    for (const rows of [[], [approved, approved], [{ ...approved, [schema.id]: "invalid" }],
      [{ ...approved, [schema.name]: REFERENCE_LABELS[key].toLowerCase() }], [{ ...approved, statecode: 1 }]]) {
      assert.throws(() => approvedReferenceId(key, rows), /UAT_APPROVED_REFERENCE_NOT_UNIQUE_ACTIVE/);
    }
  });

  test(`${key} collection reads remain limited to the exact active approved reference`, () => {
    const query = referenceQuery(key);
    const url = new URL(`${origin}/api/data/v9.2/${query.collection}`);
    url.searchParams.set("$filter", "statecode eq 1 or statecode eq 0");
    assert.equal(constrainReferenceRequest(url), "SCOPED");
    assert.equal(url.searchParams.get("$filter"),
      `(statecode eq 1 or statecode eq 0) and (${query.filter})`);
    const noFilter = new URL(`${origin}/api/data/v9.2/${query.collection.toUpperCase()}/`);
    assert.equal(constrainReferenceRequest(noFilter), "SCOPED");
    assert.equal(noFilter.searchParams.get("$filter"), query.filter);
  });

  test(`${key} direct-record and unsupported queries cannot bypass the reference filter`, () => {
    const { collection } = referenceQuery(key);
    const direct = new URL(`${origin}/api/data/v9.2/${collection}%2811111111-1111-4111-8111-111111111111%29`);
    const navigation = new URL(`${origin}/api/data/v9.2/${collection}/related`);
    assert.equal(constrainReferenceRequest(direct), "BLOCKED");
    assert.equal(constrainReferenceRequest(navigation), "BLOCKED");
    for (const option of ["fetchXml", "$expand", "$apply", "$FILTER", "savedQuery"]) {
      const url = new URL(`${origin}/api/data/v9.2/${collection}`);
      url.searchParams.set(option, "synthetic");
      assert.equal(constrainReferenceRequest(url), "BLOCKED");
    }
    assert.equal(constrainReferenceRequest(new URL(`${origin}/api/data/v9.1/${collection}`)), "BLOCKED");
  });
}

test("unknown reference keys fail and unrelated collections are not rewritten", () => {
  for (const key of ["unknown", "toString", "__proto__"]) {
    assert.throws(() => referenceQuery(key), /UAT_REFERENCE_TYPE_NOT_APPROVED/);
  }
  const url = new URL(`${origin}/api/data/v9.2/os_sr_cands?$filter=synthetic`);
  assert.equal(constrainReferenceRequest(url), "NOT_REFERENCE");
  assert.equal(url.searchParams.get("$filter"), "synthetic");
  assert.equal(constrainReferenceRequest(new URL(`${origin}/api/data/v9.2/os_sr_poss`)), "BLOCKED");
  assert.equal(constrainReferenceRequest(new URL(`${origin}/api/data/v9.2/%ZZ`)), "BLOCKED");
});

test("scoped read failures expose only the collection and HTTP status", async () => {
  const originalFetch = globalThis.fetch;
  const page = { evaluate: async (operation, args) => operation(args) };
  globalThis.fetch = async () => ({ ok: false, status: 404 });
  try {
    let failure;
    try {
      await readRows(page, origin, "os_sr_poses", ["os_sr_posid"], "synthetic-private-filter");
    } catch (error) {
      failure = error;
    }
    assert.ok(failure);
    assert.deepEqual(scopedReadFailure(failure), { collection: "os_sr_poses", httpStatus: 404 });
    assert.doesNotMatch(failure.message, /synthetic-private-filter|orgsynthetic/);
    assert.equal(scopedReadFailure(new Error("UAT_SCOPED_READ_FAILED:os_sr_poses:999")), null);
    assert.equal(scopedReadFailure(new Error("UAT_SCOPED_READ_FAILED")), null);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("scoped reads accept only complete counted responses and valid collection names", async () => {
  const originalFetch = globalThis.fetch;
  const page = { evaluate: async (operation, args) => operation(args) };
  const row = { os_sr_posid: "11111111-1111-4111-8111-111111111111" };
  let response = { value: [row], "@odata.count": 1 };
  globalThis.fetch = async url => {
    const request = new URL(url);
    assert.equal(request.pathname, "/api/data/v9.2/os_sr_poses");
    assert.equal(request.searchParams.get("$filter"), "synthetic");
    return { ok: true, json: async () => response };
  };
  try {
    assert.deepEqual(await readRows(page, origin, "os_sr_poses", ["os_sr_posid"], "synthetic"), [row]);
    for (response of [
      { value: [row], "@odata.count": 2 },
      { value: [row], "@odata.count": 1, "@odata.nextLink": "synthetic" },
      { value: null, "@odata.count": 0 }
    ]) {
      await assert.rejects(readRows(page, origin, "os_sr_poses", ["os_sr_posid"], "synthetic"),
        /UAT_SCOPED_READ_INCOMPLETE/);
    }
    await assert.rejects(readRows(page, origin, "../invalid", ["os_sr_posid"], "synthetic"),
      /UAT_SCOPED_READ_TABLE_INVALID/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
