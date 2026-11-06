'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { isDeepStrictEqual } = require('node:util');
const { runFlow } = require('./helpers/AvailabilityFlowHarness.cjs');

const NOW = '2035-02-05T00:00:00Z';
const ids = {
  query: '10000000-0000-0000-0000-000000000001',
  ta: '20000000-0000-0000-0000-000000000002',
  room: '30000000-0000-0000-0000-000000000003',
  other: '40000000-0000-0000-0000-000000000004'
};
const query = {
  os_sr_avqid: ids.query,
  os_sr_avq_stat: 100000000,
  _os_sr_avq_ta_value: ids.ta,
  os_sr_avq_mod: 100000000,
  os_sr_avq_strt: '2035-02-05T03:00:00Z',
  os_sr_avq_end: '2035-02-05T05:00:00Z',
  os_sr_avq_dur: 30
};
const hours = Object.fromEntries(
  ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']
    .map(day => [day, { opens: '09:00', closes: '17:00' }]));
const parameters = {
  'Availability Business Hours (os_sr_avq_bhrs)': JSON.stringify(hours),
  'Availability Allowed Durations (os_sr_avq_durs)': '30,60',
  'Availability Minimum Lead Time (os_sr_avq_lead)': 60,
  'Availability Maximum Horizon (os_sr_avq_hzn)': 14,
  'Availability Result Expiry (os_sr_avq_exp)': 10,
  'Availability Allowed Email Domains (os_sr_avq_dom)': 'example.invalid',
  'Availability Maximum Candidates (os_sr_avq_maxc)': 20
};

function attendee(address = 'ta@example.invalid', type = 'required', availability = 'free') {
  return { attendee: { type, emailAddress: { address } }, availability };
}

function suggestion(start = '2035-02-05T03:00:00', end = '2035-02-05T03:30:00',
  attendees = [attendee()]) {
  return {
    meetingTimeSlot: {
      start: { dateTime: start, timeZone: 'UTC' },
      end: { dateTime: end, timeZone: 'UTC' }
    },
    attendeeAvailability: attendees
  };
}

async function execute(options = {}) {
  const writes = [];
  const providerCalls = [];
  const reads = [];
  const ta = { os_sr_taid: ids.ta, statecode: 0, os_sr_ta_eml: ' TA@example.invalid ' };
  const room = { os_sr_locid: ids.room, statecode: 0, os_sr_loc_rmeml: ' room@example.invalid ' };
  const input = { ...query, ...options.query };
  const result = await runFlow({
    query: input,
    parameters: { ...parameters, ...options.parameters },
    now: options.now || NOW,
    getItem: async (params, name) => {
      reads.push(name);
      if (name === 'Read_query') return input;
      if (options.readReference) return options.readReference(params, name, { ta, room });
      return name.includes('location') ? room : ta;
    },
    outlook: async params => {
      providerCalls.push(params);
      if (options.providerError) throw options.providerError;
      return options.provider || { emptySuggestionsReason: '', meetingTimeSuggestions: [suggestion()] };
    },
    updateItem: async params => {
      writes.push(params);
      return {};
    }
  });
  const patch = writes.length
    ? Object.fromEntries(Object.entries(writes[0])
      .filter(([name]) => name.startsWith('item/'))
      .map(([name, value]) => [name.slice('item/'.length), value]))
    : undefined;
  return { result, patch, writes, reads, providerCalls };
}

function failed(run, error) {
  assert.equal(run.writes.length, 1, 'one terminal write');
  assert.equal(run.patch.os_sr_avq_stat, 100000003);
  assert.equal(run.patch.os_sr_avq_err, error);
  assert.equal(run.patch.os_sr_avq_rsn, null);
  assert.equal(run.patch.os_sr_avq_slts, '[]');
}

function noSlots(run) {
  assert.equal(run.patch.os_sr_avq_stat, 100000002);
  assert.equal(run.patch.os_sr_avq_rsn, 'NO_COMMON_SLOT');
  assert.equal(run.patch.os_sr_avq_err, null);
  assert.equal(run.patch.os_sr_avq_slts, '[]');
}

test('actual WDL writes only six canonical terminal fields and exact Outlook inputs', async () => {
  const run = await execute();
  assert.equal(run.patch.os_sr_avq_stat, 100000001);
  assert.deepEqual(Object.keys(run.patch).sort(),
    ['os_sr_avq_stat', 'os_sr_avq_rsn', 'os_sr_avq_err', 'os_sr_avq_slts', 'os_sr_avq_qat', 'os_sr_avq_exp'].sort());
  assert.deepEqual(JSON.parse(run.patch.os_sr_avq_slts),
    [{ startUtc: '2035-02-05T03:00:00Z', endUtc: '2035-02-05T03:30:00Z' }]);
  assert.equal(Date.parse(run.patch.os_sr_avq_qat), Date.parse(NOW));
  assert.equal(Date.parse(run.patch.os_sr_avq_exp) - Date.parse(NOW), 600000);
  assert.equal(run.providerCalls.length, 1);
  const request = run.providerCalls[0];
  assert.equal(request['body/RequiredAttendees'], 'ta@example.invalid');
  assert.equal(request['body/ResourceAttendees'], '');
  assert.equal(request['body/MinimumAttendeePercentage'], '100');
  assert.equal(request['body/IsOrganizerOptional'], true);
  assert.equal(request['body/ActivityDomain'], 'Work');
  assert.equal(request['body/Start'], query.os_sr_avq_strt);
  assert.ok(run.reads.includes('Reread_ta'));
});

test('non-Pending read cancels without a connector write or provider call', async () => {
  const run = await execute({ query: { os_sr_avq_stat: 100000001 } });
  assert.equal(run.writes.length, 0);
  assert.equal(run.providerCalls.length, 0);
});

for (const [label, change] of [
  ['offset request', { os_sr_avq_strt: '2035-02-05T10:00:00+07:00' }],
  ['unspecified UTC request', { os_sr_avq_strt: '2035-02-05T03:00:00' }],
  ['fractional duration', { os_sr_avq_dur: 30.5 }],
  ['missing TA', { _os_sr_avq_ta_value: null }],
  ['empty TA GUID', { _os_sr_avq_ta_value: '00000000-0000-0000-0000-000000000000' }],
  ['invalid mode', { os_sr_avq_mod: 7 }],
  ['window below duration', { os_sr_avq_end: '2035-02-05T03:15:00Z' }],
  ['horizon exceeded', { os_sr_avq_end: '2035-03-05T05:00:00Z' }]
]) {
  test(`request fails closed: ${label}`, async () => {
    const run = await execute({ query: change });
    failed(run, 'INVALID_REQUEST');
    assert.equal(run.providerCalls.length, 0);
  });
}

for (const [label, value] of [
  ['unknown weekday', { ...hours, funday: { opens: '09:00', closes: '17:00' } }],
  ['negative clock component', { monday: { opens: '-1:00', closes: '17:00' } }],
  ['extra bound', { monday: { opens: '09:00', closes: '17:00', extra: 1 } }],
  ['wrong bound type', { monday: { opens: 900, closes: '17:00' } }],
  ['reversed hours', { monday: { opens: '17:00', closes: '09:00' } }]
]) {
  test(`configuration fails closed: ${label}`, async () => {
    const run = await execute({
      parameters: { 'Availability Business Hours (os_sr_avq_bhrs)': JSON.stringify(value) }
    });
    failed(run, 'CONFIGURATION_INVALID');
    assert.equal(run.providerCalls.length, 0);
  });
}

test('mismatched initial reference id never reaches Outlook', async () => {
  const run = await execute({
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_taid: ids.other })
  });
  failed(run, 'REFERENCE_READ_FAILED');
  assert.equal(run.providerCalls.length, 0);
});

test('control characters in the TA address fail before Outlook', async () => {
  const run = await execute({
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: 't\ta@example.invalid' })
  });
  failed(run, 'TA_EMAIL_INVALID');
  assert.equal(run.providerCalls.length, 0);
});

for (const value of ['tentative', 'busy', 'oof', 'workingElsewhere', 'unknown']) {
  test(`TA ${value} is never free`, async () => {
    noSlots(await execute({
      provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
        suggestion(undefined, undefined, [attendee(undefined, undefined, value)])
      ] }
    }));
  });
}

for (const [label, entries] of [
  ['absent TA', []],
  ['duplicate TA', [attendee(), attendee()]],
  ['optional TA', [attendee(undefined, 'optional')]]
]) {
  test(`${label} safely excludes the slot without first(empty) failure`, async () => {
    noSlots(await execute({
      provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
        suggestion(undefined, undefined, entries)
      ] }
    }));
  });
}

test('Onsite requires exactly one free resource room as well as a free TA', async () => {
  const input = { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room };
  const response = entries => ({ emptySuggestionsReason: '', meetingTimeSuggestions: [
    suggestion(undefined, undefined, entries)
  ] });
  noSlots(await execute({ query: input, provider: response([attendee()]) }));
  noSlots(await execute({ query: input, provider: response([
    attendee(), attendee('room@example.invalid', 'resource', 'unknown')
  ]) }));
  const good = await execute({ query: input, provider: response([
    attendee(), attendee('room@example.invalid', 'resource')
  ]) });
  assert.equal(good.patch.os_sr_avq_stat, 100000001);
  assert.equal(good.providerCalls[0]['body/ResourceAttendees'], 'room@example.invalid');
  assert.ok(good.reads.includes('Reread_location'));
});

for (const [label, mutate] of [
  ['string instead of suggestion array', body => { body.meetingTimeSuggestions = '[]'; }],
  ['unknown top-level field', body => { body.unapproved = true; }],
  ['wrong optional field type', body => { body.meetingTimeSuggestions[0].confidence = '100'; }],
  ['invalid nested location', body => { body.meetingTimeSuggestions[0].locations = [{ address: 1 }]; }],
  ['offset UTC timestamp', body => { body.meetingTimeSuggestions[0].meetingTimeSlot.start.dateTime += '+07:00'; }],
  ['whitespace UTC timestamp', body => { body.meetingTimeSuggestions[0].meetingTimeSlot.start.dateTime += 'Z\n'; }],
  ['excess timestamp precision', body => { body.meetingTimeSuggestions[0].meetingTimeSlot.start.dateTime += '.12345678'; }],
  ['unknown attendee availability', body => { body.meetingTimeSuggestions[0].attendeeAvailability[0].availability = 'maybe'; }],
  ['malformed irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad')); }]
]) {
  test(`whole provider response fails closed: ${label}`, async () => {
    const body = { emptySuggestionsReason: '', meetingTimeSuggestions: [suggestion()] };
    mutate(body);
    failed(await execute({ provider: body }), 'PROVIDER_RESPONSE_INVALID');
  });
}

test('non-UTC timezone is explicit unsupported, never automatically converted', async () => {
  const body = { emptySuggestionsReason: '', meetingTimeSuggestions: [suggestion()] };
  body.meetingTimeSuggestions[0].meetingTimeSlot.start.timeZone = 'SE Asia Standard Time';
  failed(await execute({ provider: body }), 'PROVIDER_TIMEZONE_UNSUPPORTED');
});

test('conflicting duplicate observations invalidate all slots', async () => {
  failed(await execute({ provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
    suggestion(), suggestion(undefined, undefined, [attendee(undefined, undefined, 'busy')])
  ] } }), 'PROVIDER_RESPONSE_INVALID');
});

test('slots are distinct and sorted regardless of suggestion order', async () => {
  const run = await execute({ provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
    suggestion('2035-02-05T04:00:00Z', '2035-02-05T04:30:00Z'), suggestion(), suggestion()
  ] } });
  assert.deepEqual(JSON.parse(run.patch.os_sr_avq_slts).map(slot => slot.startUtc),
    ['2035-02-05T03:00:00Z', '2035-02-05T04:00:00Z']);
});

test('configured lead and local business hours filter otherwise free suggestions', async () => {
  noSlots(await execute({
    parameters: { 'Availability Minimum Lead Time (os_sr_avq_lead)': 240 }
  }));
  noSlots(await execute({
    parameters: { 'Availability Business Hours (os_sr_avq_bhrs)': JSON.stringify(
      Object.fromEntries(Object.keys(hours).map(day => [day, { opens: '14:00', closes: '17:00' }]))) }
  }));
});

test('reference drift overrides Available, NoSlots and malformed provider results', async () => {
  for (const body of [
    { emptySuggestionsReason: '', meetingTimeSuggestions: [suggestion()] },
    { emptySuggestionsReason: '', meetingTimeSuggestions: [] },
    { malformed: true }
  ]) {
    failed(await execute({
      provider: body,
      readReference: (_params, name, { ta }) => ({
        ...ta, statecode: name === 'Reread_ta' ? 1 : 0
      })
    }), 'REFERENCE_CHANGED');
  }
});

for (const [statusCode, error] of [
  [401, 'PROVIDER_AUTH'],
  [403, 'PROVIDER_PERMISSION'],
  [404, 'MAILBOX_NOT_FOUND'],
  [429, 'PROVIDER_THROTTLED'],
  [500, 'PROVIDER_UNAVAILABLE']
]) {
  test(`provider ${statusCode} is sanitized and never retried`, async () => {
    const fault = Object.assign(new Error('SYNTHETIC_PROVIDER_FAILURE'), { statusCode });
    const run = await execute({ providerError: fault });
    failed(run, error);
    assert.equal(run.providerCalls.length, 1);
    assert.ok(run.reads.includes('Reread_ta'));
  });
}

test('failed final reference read overrides a proposed success', async () => {
  failed(await execute({
    readReference: (_params, name, { ta }) => {
      if (name === 'Reread_ta') throw new Error('SYNTHETIC_REFERENCE_FAILURE');
      return ta;
    }
  }), 'REFERENCE_CHANGED');
});

test('every executable connector action explicitly disables retries in inputs', () => {
  const source = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'solutions',
    'AvailabilityQuery', 'os_sr_avchk.clientdata.json'), 'utf8'));
  let count = 0;
  function visit(actions) {
    for (const action of Object.values(actions)) {
      if (action.type === 'OpenApiConnection') {
        count++;
        assert.deepEqual(action.inputs.retryPolicy, { type: 'none' });
        assert.equal(Object.hasOwn(action, 'retryPolicy'), false);
      }
      visit(action.actions || {});
      visit(action.else?.actions || {});
    }
  }
  visit(source.properties.definition.actions);
  assert.equal(count, 7);
});

test('functional source delta is confined to the reviewed validation and retry-setting locations', () => {
  const root = path.join(__dirname, '..');
  const historical = spawnSync('git', ['--no-lazy-fetch', '--no-optional-locks', '--no-replace-objects',
    '-C', root, 'show',
    'b658d7502ef9664efa498e4d1a4b54c7242aa934:solutions/AvailabilityQuery/os_sr_avchk.clientdata.json'],
  { encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
  assert.equal(historical.status, 0, 'Pinned source history must be locally available; no fetch or fallback.');
  const before = JSON.parse(historical.stdout);
  const after = JSON.parse(fs.readFileSync(path.join(root, 'solutions', 'AvailabilityQuery',
    'os_sr_avchk.clientdata.json'), 'utf8'));
  function index(actions, result = new Map()) {
    for (const [name, action] of Object.entries(actions)) {
      assert.equal(result.has(name), false, 'Action names must be unique in this Flow.');
      result.set(name, action);
      index(action.actions || {}, result);
      index(action.else?.actions || {}, result);
    }
    return result;
  }
  const expected = index(before.properties.definition.actions);
  const actual = index(after.properties.definition.actions);
  const fields = {
    Check_pending: ['expression', 'runtimeConfiguration'],
    Check_response_shape: ['expression', 'runAfter'],
    Compose_free: ['inputs'],
    Find_invalid_attendees: ['inputs'],
    For_each_suggestion: ['foreach'],
    Set_result_slots: ['inputs'],
    Compose_validation_error: ['inputs'],
    Set_location_snapshot: ['runAfter'],
    Set_phase_reference: ['runAfter'],
    Set_ta_snapshot: ['runAfter'],
    Compose_config: ['runAfter'],
    Count_business_hour_keys: ['runAfter'],
    Clear_failure_slots: ['inputs']
  };
  for (const [name, properties] of Object.entries(fields)) {
    for (const property of properties) expected.get(name)[property] = structuredClone(actual.get(name)[property]);
  }
  for (const [name, parent] of Object.entries({
    Validate_business_hours: 'Evaluate',
    Validate_config_lists: 'Evaluate',
    Validate_request_shape: 'Check_mode',
    Validate_ta_response: 'Check_mode',
    Validate_location_response: 'If_onsite_location_present',
    Validate_provider_response: 'Check_validation',
    Validate_UTC_timestamps: 'Check_suggestion_timezone'
  })) {
    assert.equal(actual.get(name).type, 'ParseJson');
    expected.get(parent).actions[name] = structuredClone(actual.get(name));
  }
  for (const action of expected.values()) {
    if (action.type !== 'OpenApiConnection') continue;
    assert.deepEqual(action.retryPolicy, { type: 'none' });
    delete action.retryPolicy;
    action.inputs.retryPolicy = { type: 'none' };
  }
  assert.equal(isDeepStrictEqual(before, after), true,
    'No other definition, mapping, trigger, expression or privacy change is permitted.');
});

test('all original protected actions and trigger retain exact privacy settings', () => {
  const source = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'solutions',
    'AvailabilityQuery', 'os_sr_avchk.clientdata.json'), 'utf8'));
  const original = [
    'Read_query', 'Read_ta', 'Set_ta_snapshot', 'Read_location', 'Set_location_snapshot',
    'Compose_validation_error', 'Find_meeting_times', 'Check_response_shape', 'For_each_suggestion',
    'Check_suggestion_timezone', 'Compose_slot', 'Find_invalid_attendees', 'Find_ta_entries',
    'Find_room_entries', 'Compose_free', 'Check_suggestion_valid', 'Append_observation',
    'Check_slot_eligible', 'Append_slot', 'Compose_canonical_slots', 'Compose_proposed_result',
    'Set_result_slots', 'Evaluate', 'Map_failure', 'If_validated_snapshot', 'Reread_references',
    'Reread_ta', 'Compose_drift', 'Reread_location', 'Compose_location_drift',
    'Set_location_changed', 'Compose_terminal', 'Write_terminal_result'
  ];
  const index = {};
  function visit(actions) {
    for (const [name, action] of Object.entries(actions)) {
      index[name] = action;
      visit(action.actions || {});
      visit(action.else?.actions || {});
    }
  }
  visit(source.properties.definition.actions);
  assert.equal(original.length, 33);
  for (const name of original) {
    assert.deepEqual(index[name].runtimeConfiguration.secureData,
      { properties: ['inputs', 'outputs'] }, name);
  }
  const trigger = source.properties.definition.triggers.When_a_Pending_availability_query_is_added;
  assert.deepEqual(trigger.runtimeConfiguration, {
    concurrency: { runs: 1 }, secureData: { properties: ['outputs'] }
  });
});
