'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
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
      if (name === 'Read_query') {
        return options.readQuery ? options.readQuery(params, name, input) : input;
      }
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
  assert.equal(run.result.status, 'Cancelled');
  assert.deepEqual(run.reads, ['Read_query']);
  assert.equal(run.writes.length, 0);
  assert.equal(run.providerCalls.length, 0);
});

test('an empty triggering request ID cancels without a write or provider call', async () => {
  const run = await execute({ query: { os_sr_avqid: '' } });
  assert.equal(run.result.status, 'Cancelled');
  assert.deepEqual(run.reads, ['Read_query']);
  assert.equal(run.writes.length, 0);
  assert.equal(run.providerCalls.length, 0);
});

test('a different returned request ID cancels without a write or provider call', async () => {
  const run = await execute({
    readQuery: (_params, _name, input) => ({ ...input, os_sr_avqid: ids.other })
  });
  assert.equal(run.result.status, 'Cancelled');
  assert.deepEqual(run.reads, ['Read_query']);
  assert.equal(run.writes.length, 0);
  assert.equal(run.providerCalls.length, 0);
});

test('a failed initial request read does not write or call the provider', async () => {
  const run = await execute({
    readQuery: () => { throw new Error('SYNTHETIC_QUERY_READ_FAILURE'); }
  });
  assert.equal(run.result.status, 'Failed');
  assert.deepEqual(run.reads, ['Read_query']);
  assert.equal(run.writes.length, 0);
  assert.equal(run.providerCalls.length, 0);
});

test('a timed-out initial request read does not write or call the provider', async () => {
  const run = await execute({
    readQuery: () => { throw Object.assign(new Error('SYNTHETIC_QUERY_TIMEOUT'), { status: 'TimedOut' }); }
  });
  assert.deepEqual(run.reads, ['Read_query']);
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

for (const [label, expected, options] of [
  ['inactive TA before invalid mailbox', 'TA_INACTIVE', {
    readReference: (_params, _name, { ta }) => ({ ...ta, statecode: 1, os_sr_ta_eml: 'invalid' })
  }],
  ['missing TA mailbox', 'TA_EMAIL_MISSING', {
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: null })
  }],
  ['invalid TA mailbox before missing location', 'TA_EMAIL_INVALID', {
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: null },
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: 'invalid' })
  }],
  ['disallowed TA domain', 'TA_EMAIL_DOMAIN_NOT_ALLOWED', {
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: 'ta@elsewhere.invalid' })
  }],
  ['missing location', 'LOCATION_REQUIRED', {
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: null }
  }],
  ['inactive location before missing mailbox', 'LOCATION_INACTIVE', {
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
    readReference: (_params, name, { ta, room }) => name.includes('location')
      ? { ...room, statecode: 1, os_sr_loc_rmeml: null } : ta
  }],
  ['missing room mailbox', 'ROOM_EMAIL_MISSING', {
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
    readReference: (_params, name, { ta, room }) => name.includes('location')
      ? { ...room, os_sr_loc_rmeml: null } : ta
  }],
  ['disallowed room domain', 'ROOM_EMAIL_DOMAIN_NOT_ALLOWED', {
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
    readReference: (_params, name, { ta, room }) => name.includes('location')
      ? { ...room, os_sr_loc_rmeml: 'room@elsewhere.invalid' } : ta
  }],
  ['room and TA share a mailbox', 'ROOM_EMAIL_INVALID', {
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
    readReference: (_params, name, { ta, room }) => name.includes('location')
      ? { ...room, os_sr_loc_rmeml: 'ta@example.invalid' } : ta
  }]
]) {
  test(`reference validation preserves failure precedence: ${label}`, async () => {
    const run = await execute(options);
    failed(run, expected);
    assert.equal(run.providerCalls.length, 0);
  });
}

test('synthetic substituted TA shows the Flow lacks an exact-target authorization guard', async () => {
  const run = await execute({
    query: { _os_sr_avq_ta_value: ids.other },
    readReference: (_params, _name, { ta }) => ({
      ...ta, os_sr_taid: ids.other, os_sr_ta_eml: 'other@example.invalid'
    })
  });
  assert.equal(run.providerCalls.length, 1);
  assert.equal(run.providerCalls[0]['body/RequiredAttendees'], 'other@example.invalid');
});

test('synthetic substituted room shows the Flow lacks an exact-target authorization guard', async () => {
  const run = await execute({
    query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.other },
    readReference: (_params, name, { ta, room }) => name.includes('location')
      ? { ...room, os_sr_locid: ids.other, os_sr_loc_rmeml: 'other-room@example.invalid' } : ta
  });
  assert.equal(run.providerCalls.length, 1);
  assert.equal(run.providerCalls[0]['body/ResourceAttendees'], 'other-room@example.invalid');
});

test('control characters in the TA address fail before Outlook', async () => {
  const run = await execute({
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: 't\ta@example.invalid' })
  });
  failed(run, 'TA_EMAIL_INVALID');
  assert.equal(run.providerCalls.length, 0);
});

for (const [label, address] of [
  ['colon', 'bad:name@example.invalid'],
  ['brackets', 'bad[part]@example.invalid'],
  ['NUL', 'bad\u0000name@example.invalid'],
  ['non-whitespace control', 'bad\u0001name@example.invalid'],
  ['DEL', 'bad\u007fname@example.invalid']
]) {
  test(`malformed unquoted reference mailboxes fail before Outlook: ${label}`, async () => {
    const taRun = await execute({
      readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: address })
    });
    failed(taRun, 'TA_EMAIL_INVALID');
    assert.equal(taRun.providerCalls.length, 0);

    const roomRun = await execute({
      query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
      readReference: (_params, name, { ta, room }) => name.includes('location')
        ? { ...room, os_sr_loc_rmeml: address } : ta
    });
    failed(roomRun, 'ROOM_EMAIL_INVALID');
    assert.equal(roomRun.providerCalls.length, 0);
  });
}

test('all ASCII control characters in reference mailboxes fail before Outlook', async () => {
  for (const code of [...Array(32).keys(), 127]) {
    const address = `bad${String.fromCharCode(code)}name@example.invalid`;
    const taRun = await execute({
      readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: address })
    });
    failed(taRun, 'TA_EMAIL_INVALID');
    assert.equal(taRun.providerCalls.length, 0, `TA control code ${code}`);

    const roomRun = await execute({
      query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
      readReference: (_params, name, { ta, room }) => name.includes('location')
        ? { ...room, os_sr_loc_rmeml: address } : ta
    });
    failed(roomRun, 'ROOM_EMAIL_INVALID');
    assert.equal(roomRun.providerCalls.length, 0, `room control code ${code}`);
  }
});

test('literal percent escapes in a valid reference mailbox are not mistaken for controls', async () => {
  const address = 'case%01@example.invalid';
  const run = await execute({
    readReference: (_params, _name, { ta }) => ({ ...ta, os_sr_ta_eml: address }),
    provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
      suggestion(undefined, undefined, [attendee(address)])
    ] }
  });
  assert.equal(run.patch.os_sr_avq_stat, 100000001);
  assert.equal(run.providerCalls[0]['body/RequiredAttendees'], address);
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

test('combined availability requires both resources free across all 36 known state pairs', async () => {
  const states = ['free', 'tentative', 'busy', 'oof', 'workingElsewhere', 'unknown'];
  for (const taState of states) {
    for (const roomState of states) {
      const run = await execute({
        query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
        provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
          suggestion(undefined, undefined, [
            attendee('ta@example.invalid', 'required', taState),
            attendee('room@example.invalid', 'resource', roomState)
          ])
        ] }
      });
      if (taState === 'free' && roomState === 'free') {
        assert.equal(run.patch.os_sr_avq_stat, 100000001);
        assert.equal(JSON.parse(run.patch.os_sr_avq_slts).length, 1);
      } else {
        noSlots(run);
      }
      assert.equal(run.providerCalls.length, 1, 'one combined call, no independent resource retries');
    }
  }
});

test('combined calendar excludes optional BSO from the mandatory TA and room intersection', async () => {
  const states = ['free', 'tentative', 'busy', 'oof', 'workingElsewhere', 'unknown'];
  for (const bsoState of states) {
    for (const [taState, roomState] of [['free', 'free'], ['busy', 'free'], ['free', 'busy']]) {
      const slot = suggestion(undefined, undefined, [
        attendee('ta@example.invalid', 'required', taState),
        attendee('room@example.invalid', 'resource', roomState),
        attendee('bso@example.invalid', 'optional', bsoState)
      ]);
      slot.organizerAvailability = bsoState;
      const run = await execute({
        query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room },
        provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [slot] }
      });
      assert.equal(run.providerCalls[0]['body/RequiredAttendees'], 'ta@example.invalid');
      assert.equal(run.providerCalls[0]['body/ResourceAttendees'], 'room@example.invalid');
      assert.equal(run.providerCalls[0]['body/IsOrganizerOptional'], true);
      assert.ok(!JSON.stringify(run.providerCalls[0]).includes('bso@example.invalid'));
      if (taState === 'free' && roomState === 'free') {
        assert.equal(run.patch.os_sr_avq_stat, 100000001);
      } else {
        noSlots(run);
      }
    }
  }
});

for (const duration of [15, 30, 45, 60]) {
  test(`combined ${duration}-minute meetings retain exact duration on a 15-minute start grid`, async () => {
    const start = Date.parse('2035-02-05T03:00:00Z');
    const format = time => new Date(time).toISOString().slice(0, 19);
    const times = [0, 15, 30].map(offset => start + offset * 60000);
    const run = await execute({
      query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room, os_sr_avq_dur: duration },
      parameters: { 'Availability Allowed Durations (os_sr_avq_durs)': '15,30,45,60' },
      provider: { emptySuggestionsReason: '', meetingTimeSuggestions: times.map(time =>
        suggestion(format(time), format(time + duration * 60000), [
          attendee(), attendee('room@example.invalid', 'resource')
        ]))
      }
    });
    assert.equal(run.patch.os_sr_avq_stat, 100000001);
    assert.equal(run.providerCalls[0]['body/MeetingDuration'], duration);
    assert.deepEqual(JSON.parse(run.patch.os_sr_avq_slts), times.map(time => ({
      startUtc: format(time) + 'Z', endUtc: format(time + duration * 60000) + 'Z'
    })));
    assert.equal(run.writes.length, 1);
  });
}

test('separate resource windows or short adjacent suggestions never synthesize a whole-duration free slot', async () => {
  const taFree = attendee();
  const roomFree = attendee('room@example.invalid', 'resource');
  for (const suggestions of [
    [
      suggestion('2035-02-05T03:00:00', '2035-02-05T03:30:00', [taFree, roomFree]),
      suggestion('2035-02-05T03:30:00', '2035-02-05T04:00:00', [taFree, roomFree])
    ],
    [
      suggestion('2035-02-05T03:00:00', '2035-02-05T04:00:00',
        [taFree, attendee('room@example.invalid', 'resource', 'busy')]),
      suggestion('2035-02-05T03:15:00', '2035-02-05T04:15:00',
        [attendee('ta@example.invalid', 'required', 'busy'), roomFree])
    ],
    [suggestion('2035-02-05T03:05:00', '2035-02-05T04:05:00', [taFree, roomFree])]
  ]) {
    noSlots(await execute({
      query: { os_sr_avq_mod: 100000001, _os_sr_avq_loc_value: ids.room, os_sr_avq_dur: 60 },
      provider: { emptySuggestionsReason: '', meetingTimeSuggestions: suggestions }
    }));
  }
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
  ['malformed irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad')); }],
  ['unquoted colon in irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad:name@example.invalid', 'optional')); }],
  ['unquoted bracket in irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad[part]@example.invalid', 'optional')); }],
  ['unquoted comment in irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad(comment)@example.invalid', 'optional')); }],
  ['double-dot local part', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad..part@example.invalid', 'optional')); }],
  ['double-dot domain', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad@example..invalid', 'optional')); }],
  ['control in irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad\u0001name@example.invalid', 'optional')); }],
  ['trailing control in irrelevant attendee', body => { body.meetingTimeSuggestions[0].attendeeAvailability.push(attendee('bad@example.invalid\n', 'optional')); }]
]) {
  test(`whole provider response fails closed: ${label}`, async () => {
    const body = { emptySuggestionsReason: '', meetingTimeSuggestions: [suggestion()] };
    mutate(body);
    failed(await execute({ provider: body }), 'PROVIDER_RESPONSE_INVALID');
  });
}

for (const [label, address] of [
  ['quoted colon', '"valid:part"@example.invalid'],
  ['quoted empty local part', '""@example.invalid'],
  ['quoted double dot', '"valid..part"@example.invalid'],
  ['escaped quote', '"valid\\"part"@example.invalid'],
  ['dotted address literal', 'valid@[192.0.2.1]'],
  ['double dot in an address literal', 'valid@[a..b]'],
  ['punctuation in unquoted local part', "valid!#$%&'*+-/=?^_`{|}~@example.invalid"]
]) {
  test(`valid unrelated provider attendee remains accepted: ${label}`, async () => {
    const run = await execute({
      provider: { emptySuggestionsReason: '', meetingTimeSuggestions: [
        suggestion(undefined, undefined, [attendee(), attendee(address, 'optional')])
      ] }
    });
    assert.equal(run.patch.os_sr_avq_stat, 100000001);
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

test('provider timeout is sanitized, not retried, and followed by a reference recheck', async () => {
  const fault = Object.assign(new Error('SYNTHETIC_PROVIDER_TIMEOUT'), { status: 'TimedOut' });
  const run = await execute({ providerError: fault });
  failed(run, 'PROVIDER_TIMEOUT');
  assert.equal(run.providerCalls.length, 1);
  assert.ok(run.reads.includes('Reread_ta'));
});

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
