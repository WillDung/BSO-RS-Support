const test = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
const dashboard = require("../solutions/RecruitmentDashboard/WebResources/os_/bso/recruitment-dashboard.js");

const RANGE = {
  year: 2026,
  startUtc: "2025-12-31T17:00:00.000Z",
  endExclusiveUtc: "2026-06-01T05:00:00.001Z",
  startMs: Date.parse("2025-12-31T17:00:00.000Z"),
  endExclusiveMs: Date.parse("2026-06-01T05:00:00.001Z")
};

const CANDIDATE_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const TA_ID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSITION_ID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const SOURCE_ID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";

function schedule(candidate, options = {}) {
  return {
    statecode: 0,
    os_sr_intvid: options.scheduleId || "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    _os_sr_intv_cand_value: options.candidateId || CANDIDATE_ID,
    _os_sr_intv_ta_value: options.scheduleTaId || TA_ID,
    os_sr_intv_rnd: options.round ?? 100000000,
    os_sr_intv_strt: options.start || "2026-01-06T00:00:00.000Z",
    os_sr_intv_stat: options.status ?? 100000001,
    createdon: options.createdOn || "2026-01-03T00:00:00.000Z",
    os_sr_intv_cand: candidate
  };
}

function candidate(options = {}) {
  return {
    os_sr_candid: options.id || CANDIDATE_ID,
    os_sr_cand_stat: options.status ?? 100010003,
    _os_sr_cand_pos_value: options.positionId || POSITION_ID,
    _os_sr_cand_csrc_value: options.sourceId || SOURCE_ID,
    _os_sr_cand_ta_value: options.taId || TA_ID,
    statecode: options.statecode ?? 0,
    createdon: options.createdOn || "2026-01-02T00:00:00.000Z"
  };
}

test("YTD boundaries use Vietnam local time and clip a prior-year leap day", () => {
  const now = new Date("2028-02-29T05:00:00.000Z");
  const range = dashboard.getYtdRange(2027, now);
  assert.equal(range.startUtc, "2026-12-31T17:00:00.000Z");
  assert.equal(range.endExclusiveUtc, "2027-02-28T05:00:00.001Z");
  assert.throws(() => dashboard.getYtdRange(2029, now), /INVALID_PERIOD/);
});

test("pipeline aggregates preserve known statuses and count unknown statuses separately", () => {
  const result = dashboard.summarizePipeline([
    { status: 100010000, candidateCount: 2 },
    { status: 100010001, candidateCount: "3" },
    { status: 100010003, candidateCount: 4 },
    { status: 12345, candidateCount: 1 }
  ]);
  assert.equal(result.total, 10);
  assert.equal(result.pending, 5);
  assert.equal(result.otherCount, 1);
  assert.equal(result.counts[100010002], 0);
  assert.throws(() => dashboard.summarizePipeline([{ status: 100010000, candidateCount: -1 }]), /INVALID_AGGREGATE/);
  assert.throws(() => dashboard.summarizePipeline([{ status: 100010000, candidateCount: null }]), /INVALID_AGGREGATE/);
});

test("candidate filters are limited to validated YTD, status, and lookup values", () => {
  const filters = { year: 2026, positionId: POSITION_ID, sourceId: "", taId: TA_ID };
  const xml = dashboard.buildPipelineFetchXml(filters, RANGE);
  assert.match(xml, /statecode.*value="0"/);
  assert.match(xml, /createdon.*operator="ge"/);
  assert.match(xml, /createdon.*operator="lt"/);
  assert.match(xml, /os_sr_cand_pos.*cccccccc-cccc-4ccc-8ccc-cccccccccccc/);
  assert.doesNotMatch(xml, /os_sr_cand_eml|os_sr_cand_phn|cvurl/);
  assert.throws(
    () => dashboard.buildPipelineFetchXml({ ...filters, taId: "not-a-guid" }, RANGE),
    /INVALID_FILTER/
  );
});

test("queue query includes only pending statuses and requests no contact details", () => {
  const options = dashboard.buildQueueOptions(
    { year: 2026, positionId: "", sourceId: "", taId: "" },
    RANGE
  );
  const decoded = decodeURIComponent(options);
  assert.match(decoded, /os_sr_cand_stat eq 100010000/);
  assert.match(decoded, /os_sr_cand_stat eq 100010001/);
  assert.match(decoded, /os_sr_cand_stat eq 100010002/);
  assert.match(decoded, /createdon asc/);
  assert.doesNotMatch(decoded, /os_sr_cand_eml|os_sr_cand_phn|cvurl/);
});

test("schedule metrics count each Candidate once and average only positive lead times", () => {
  const first = candidate();
  const secondId = "ffffffff-ffff-4fff-8fff-ffffffffffff";
  const second = candidate({ id: secondId, createdOn: "2026-01-04T00:00:00.000Z" });
  const rows = [
    schedule(first, { createdOn: "2026-01-02T01:00:00.000Z", start: "2026-01-05T00:00:00.000Z" }),
    schedule(first, { createdOn: "2026-01-03T01:00:00.000Z", start: "2026-01-06T00:00:00.000Z" }),
    schedule(second, { candidateId: secondId, createdOn: "2026-01-05T00:00:00.000Z", start: "2026-01-03T00:00:00.000Z" }),
    schedule(first, { status: 100000000, createdOn: "2026-01-07T00:00:00.000Z" }),
    schedule(first, { status: 100000002, createdOn: "2026-01-08T00:00:00.000Z" }),
    schedule(first, { round: 100000001, createdOn: "2026-01-09T00:00:00.000Z" }),
    schedule(candidate({ statecode: 1 }), { createdOn: "2026-01-10T00:00:00.000Z" })
  ];
  const result = dashboard.getScheduleMetrics(
    rows,
    { year: 2026, positionId: POSITION_ID, sourceId: SOURCE_ID, taId: TA_ID },
    RANGE
  );
  assert.equal(result.scheduled, 2);
  assert.equal(result.averageLeadDenominator, 1);
  assert.equal(result.averageLeadDays, 4);
});

test("TA filter requires both Candidate assignment and scheduled TA to match", () => {
  const rows = [
    schedule(candidate(), { scheduleTaId: TA_ID }),
    schedule(candidate({ id: "ffffffff-ffff-4fff-8fff-ffffffffffff", taId: SOURCE_ID }), {
      candidateId: "ffffffff-ffff-4fff-8fff-ffffffffffff",
      scheduleTaId: TA_ID
    }),
    schedule(candidate({ id: "99999999-9999-4999-8999-999999999999" }), {
      candidateId: "99999999-9999-4999-8999-999999999999",
      scheduleTaId: SOURCE_ID
    })
  ];
  const result = dashboard.getScheduleMetrics(
    rows,
    { year: 2026, positionId: "", sourceId: "", taId: TA_ID },
    RANGE
  );
  assert.equal(result.scheduled, 1);
  assert.equal(result.averageLeadDenominator, 1);
});

test("schedule query stays read-only and selects only scheduling and filter fields", () => {
  const decoded = decodeURIComponent(dashboard.buildScheduleOptions({
    year: 2026, positionId: "", sourceId: "", taId: TA_ID
  }));
  assert.match(decoded, /statecode eq 0/);
  assert.match(decoded, /os_sr_intv_rnd eq 100000000/);
  assert.match(decoded, /os_sr_intv_stat eq 100000001 or os_sr_intv_stat eq null/);
  assert.match(decoded, /_os_sr_intv_ta_value eq bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/);
  assert.match(decoded, /\$expand=os_sr_intv_cand/);
  assert.doesNotMatch(decoded, /PATCH|POST|os_sr_cand_eml|os_sr_cand_phn|cvurl/);
});

test("browser without a Node global loads Dataverse data and applies all four filters", async () => {
  const source = readFileSync(require.resolve("../solutions/RecruitmentDashboard/WebResources/os_/bso/recruitment-dashboard.js"), "utf8");
  const elements = new Map();
  function element() {
    return {
      value: "", children: [], events: {}, style: {},
      replaceChildren(...children) { this.children = children; this.value = children[0]?.value || ""; },
      add(child) { if (!this.children.length) this.value = child.value; this.children.push(child); },
      append(...children) { this.children.push(...children); },
      addEventListener(name, callback) { this.events[name] = callback; }
    };
  }
  const doc = element();
  doc.getElementById = (id) => {
    if (!elements.has(id)) elements.set(id, element());
    return elements.get(id);
  };
  doc.createElement = element;
  const $ = doc.getElementById;
  const calls = [];
  let pipelineFails = false;
  const WebApi = {
    async retrieveMultipleRecords(table, options, size) {
      calls.push({ table, options, size });
      if (table === "os_sr_pos") {
        assert.match(options, /\$select=os_sr_posid,os_sr_pos_ttl/);
        return { entities: [{ os_sr_posid: POSITION_ID, os_sr_pos_ttl: "Synthetic position" }] };
      }
      if (table === "os_sr_csrc") return { entities: [{ os_sr_csrcid: SOURCE_ID, os_sr_csrc_nm: "Synthetic source" }] };
      if (table === "os_sr_ta") return { entities: [{ os_sr_taid: TA_ID, os_sr_ta_nm: "Synthetic TA" }] };
      if (table === "os_sr_intv") return { entities: [schedule(candidate())] };
      if (options.startsWith("?fetchXml=")) {
        assert.match(options, /^\?fetchXml=<fetch/);
        if (pipelineFails) throw new Error("Read rejected");
        return { entities: [{ status: 100010000, candidateCount: 2 }, { status: 100010003, candidateCount: 1 }] };
      }
      assert.equal(size, 50);
      assert.doesNotMatch(options, /\$top=/);
      const continuation = "?$skiptoken=%3Ccookie%3E";
      if (options.includes("$skiptoken")) assert.equal(options, continuation);
      return {
        entities: [{
          os_sr_candid: options === continuation ? SOURCE_ID : CANDIDATE_ID,
          os_sr_cand_nm: "Synthetic candidate", os_sr_cand_cnum: "TEST-001", os_sr_cand_stat: 100010000
        }],
        nextLink: options === continuation ? null : `https://example.invalid/api/data/v9.2/os_sr_cands${continuation}`
      };
    }
  };
  vm.runInNewContext(source, {
    document: doc, window: { parent: { Xrm: { WebApi } } },
    Option: class { constructor(text, value) { Object.assign(this, { text, value }); } },
    Date: class extends Date { constructor(...args) { super(...(args.length ? args : ["2026-06-01T05:00:00Z"])); } }
  });
  doc.events.DOMContentLoaded();
  await new Promise(setImmediate);
  assert.match($("status").textContent, /^Updated/);
  assert.equal($("metric-candidates").textContent, "3");
  assert.equal($("metric-pending").textContent, "2");
  assert.equal($("metric-scheduled").textContent, "1");
  assert.equal($("metric-lead-time").textContent, "4.0 days");
  assert.equal($("pipeline").children.length, 6);
  await $("load-more").events.click();
  assert.match($("queue-summary").textContent, /Showing 2 of 2/);

  for (const [id, value] of [["year", "2025"], ["position", POSITION_ID], ["source", SOURCE_ID], ["ta", TA_ID]]) {
    if (id !== "year") assert.equal($(`filter-${id}`).children[1].value, value);
    $(`filter-${id}`).value = value;
    await $(`filter-${id}`).events.change();
  }
  const [pipeline, interviews, queue] = calls.slice(-3);
  assert.match(pipeline.options, /2024-12-31T17:00:00/);
  for (const id of [POSITION_ID, SOURCE_ID, TA_ID]) {
    assert.ok(pipeline.options.includes(id));
    assert.ok(decodeURIComponent(queue.options).includes(id));
  }
  assert.ok(decodeURIComponent(interviews.options).includes(TA_ID));

  pipelineFails = true;
  await $("filter-ta").events.change();
  assert.match($("status").textContent, /could not be verified/);
  assert.equal($("metric-candidates").textContent, "—");
  assert.equal($("queue").children.length, 0);
});
