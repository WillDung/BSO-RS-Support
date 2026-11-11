'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');

const root = path.join(__dirname, '..');
const flowPath = path.join(root, 'solutions', 'AvailabilityQuery', 'os_sr_avchk.clientdata.json');
const history = spawnSync('git', ['--no-lazy-fetch', '--no-optional-locks', '--no-replace-objects',
  '-C', root, 'show',
  'b658d7502ef9664efa498e4d1a4b54c7242aa934:solutions/AvailabilityQuery/os_sr_avchk.clientdata.json'],
{ encoding: 'utf8', timeout: 30000, maxBuffer: 1024 * 1024 });
assert.equal(history.status, 0, 'Pinned source history must be locally available; no fetch or fallback.');
assert.equal(createHash('sha256').update(history.stdout).digest('hex'),
  '0e1a1de9cfece98440b1ec8b52dcd76648a25826a06bcf36fafcefbb39c701b0',
  'Pinned historical source must match its independent digest.');
const baseline = JSON.parse(history.stdout);
const source = JSON.parse(fs.readFileSync(flowPath, 'utf8'));

// Each reviewed changed property and complete new validator is pinned independently of the candidate.
const changedProperties = [
  ['Check_pending', 'expression', 'd1da29a690bb0b9635c47149c386d7bb0b0fbbf64d288a4e0468007401d228b5'],
  ['Read_query', 'inputs', 'ca829114f4523e1b20fe78086f96b25c8c7f427d797808b873c30113b601ec4b'],
  ['Write_terminal_result', 'inputs', '1a776788a3e7bd5d6ca068905ae2dd1d8e50f0c3dbb2950d4bc2dc3bcb3656f1'],
  ['Check_pending', 'runtimeConfiguration', '8af12b516767e5514188453ed0cab2825b393b7497d54074eda57be6f807803d'],
  ['Count_business_hour_keys', 'runAfter', '37f8dfc91bdc2b9dee8fd223893393178185c0f72ab3458bf513eabead50f6a5'],
  ['Compose_config', 'runAfter', '535a5e2a0d7dd5b09bc4f8027621aefb5cc19d738fb5ed6417df29951003c857'],
  ['Set_phase_reference', 'runAfter', '3133e36a1d50bf6f7eff1e1b103e0886649af33f37190f6090c2ed5149f6c757'],
  ['Set_ta_snapshot', 'runAfter', '2acfde89a1894e0ee2b403fd46c3a3f32a73b18c4cf74b1732144337e95fe1a7'],
  ['Set_location_snapshot', 'runAfter', '8c13fec8147d333a64de25b70bbbac2aea83094fcd75e799c848abcea008efca'],
  ['Compose_validation_error', 'inputs', '69df85246c379045bbe5bb209c61f320bf7bbbf2cc4474a73935209307b498b8'],
  ['Check_response_shape', 'expression', '213016302e47af18d7ef10e2ff8911bc9bb588e009173f8e450b7db80b88eb55'],
  ['Check_response_shape', 'runAfter', '14c5de4da0a6cd0e9560c34f7eb7bb25e55071d2c8c40cc9a7cc520f0b3df1a6'],
  ['For_each_suggestion', 'foreach', '6877a7e1bf690e48a9140b57915c02c6b6205f68fe36303bf431613cb18acb40'],
  ['Find_invalid_attendees', 'inputs', 'e3426f7a31167256d40a8486203943eb8e67db34e3aa31837f301e3d758082a2'],
  ['Compose_free', 'inputs', 'df7be72a63932dd19a04a1985050e1ff4d271b9b0e12aad55b3e3de2e764bbe4'],
  ['Set_result_slots', 'inputs', '2166d4c14732742e6d7788087ca534f40c5cc457f56d86eb459007bb4b125240'],
  ['Clear_failure_slots', 'inputs', '814605dca987e7b7e9a01e4649adbf0e02710653dac7968309a018108474a430'],
  ['Compose_terminal', 'runAfter', 'faf62c0ce7e0f7c808482462869f1ecce5a09fe65c82b4aabc2241c271ae2570']
];
const validators = [
  ['Validate_business_hours', 'Evaluate', 'ed6fd79a8435857c879861f739950b1b175b8bac510691294e3d522d891761c4'],
  ['Validate_config_lists', 'Evaluate', '18290a43b33b6020680ef836fd3e9ec87fa3433ce01599946f065f9286491cb4'],
  ['Validate_request_shape', 'Check_mode', '0cd431412a0a8a98b6d35990b624da10e96ccf7987947877a549dd1d262794bf'],
  ['Validate_ta_response', 'Check_mode', '7efa1a2c68bbbeb7b765f174a318b8ba1db1ecc340b1de603333f0348eb00bae'],
  ['Validate_location_response', 'If_onsite_location_present', '4f2393c2b4adb2dff2abe7a835df2d508c2ff0496bbf801465d56e04a49fb0fb'],
  ['Validate_provider_response', 'Check_validation', '6374bfaed40c5a78ebf2eeaaa77fe7edee253606f6c321c28accfe4798f70402'],
  ['Validate_UTC_timestamps', 'Check_suggestion_timezone', 'd3022297e175bf7c5205517b2918ee09a92887606804da75e3debd809f0b5aec']
];

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}

function digest(value) {
  return createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
}

function index(actions, result = new Map()) {
  for (const [name, action] of Object.entries(actions)) {
    assert.equal(result.has(name), false, 'Action names must be unique.');
    result.set(name, action);
    index(action.actions || {}, result);
    index(action.else?.actions || {}, result);
    index(action.default?.actions || {}, result);
    for (const branch of Object.values(action.cases || {})) index(branch.actions || {}, result);
  }
  return result;
}

function assertReviewedDelta(candidate) {
  const expected = structuredClone(baseline);
  const original = index(expected.properties.definition.actions);
  const actual = index(candidate.properties.definition.actions);
  assert.equal(original.size, 96);
  assert.equal(actual.size, 103);
  for (const [name, property, expectedHash] of changedProperties) {
    assert.ok(original.has(name) && actual.has(name), `${name} remains present.`);
    assert.ok(Object.hasOwn(actual.get(name), property), `${name}.${property} remains present.`);
    assert.equal(digest(actual.get(name)[property]), expectedHash, `${name}.${property} is pinned.`);
    original.get(name)[property] = structuredClone(actual.get(name)[property]);
  }
  for (const [name, parent, expectedHash] of validators) {
    assert.equal(original.has(name), false, `${name} is new.`);
    assert.equal(actual.get(name)?.type, 'ParseJson', `${name} remains a validator.`);
    assert.equal(digest(actual.get(name)), expectedHash, `${name} is pinned completely.`);
    assert.ok(original.get(parent)?.actions, `${name} has its reviewed parent.`);
    original.get(parent).actions[name] = structuredClone(actual.get(name));
  }
  for (const action of original.values()) {
    if (action.type !== 'OpenApiConnection') continue;
    assert.deepEqual(action.retryPolicy, { type: 'none' });
    delete action.retryPolicy;
    action.inputs.retryPolicy = { type: 'none' };
  }
  assert.ok(isDeepStrictEqual(expected, candidate),
    'No other source, action placement, binding, trigger, expression or privacy change is permitted.');
}

const typeCounts = {
  AppendToArrayVariable: 2, Compose: 11, Foreach: 1, If: 15, InitializeVariable: 15,
  OpenApiConnection: 7, ParseJson: 7, Query: 7, Scope: 4, Select: 2, SetVariable: 31, Terminate: 1
};
const readContracts = {
  Read_query: ['os_sr_avqs', "@triggerOutputs()?['body/os_sr_avqid']",
    'os_sr_avqid,os_sr_avq_corr,os_sr_avq_cat,os_sr_avq_dead,os_sr_avq_stat,_os_sr_avq_ta_value,_os_sr_avq_loc_value,os_sr_avq_mod,os_sr_avq_strt,os_sr_avq_end,os_sr_avq_dur'],
  Read_ta: ['os_sr_tas', "@body('Read_query')?['_os_sr_avq_ta_value']", 'os_sr_taid,statecode,os_sr_ta_eml'],
  Read_location: ['os_sr_locs', "@body('Read_query')?['_os_sr_avq_loc_value']", 'os_sr_locid,statecode,os_sr_loc_rmeml'],
  Reread_ta: ['os_sr_tas', "@variables('v_ta')['id']", 'os_sr_taid,statecode,os_sr_ta_eml'],
  Reread_location: ['os_sr_locs', "@variables('v_loc')['id']", 'os_sr_locid,statecode,os_sr_loc_rmeml']
};
const terminalParameters = {
  entityName: 'os_sr_avqs',
  recordId: "@body('Read_query')?['os_sr_avqid']",
  'If-Match': "@body('Read_query')?['@odata.etag']",
  'item/os_sr_avq_corr': "@body('Read_query')?['os_sr_avq_corr']",
  'item/os_sr_avq_stat': "@outputs('Compose_terminal')['state']",
  'item/os_sr_avq_rsn': "@outputs('Compose_terminal')['reason']",
  'item/os_sr_avq_err': "@outputs('Compose_terminal')['error']",
  'item/os_sr_avq_slts': "@outputs('Compose_terminal')['slots']",
  'item/os_sr_avq_qat': "@outputs('Compose_terminal')['queriedAt']",
  'item/os_sr_avq_exp': "@addMinutes(outputs('Compose_terminal')['queriedAt'], variables('v_expMinutes'))"
};
const outlookParameters = {
  'body/RequiredAttendees': "@coalesce(variables('v_ta')?['email'], '')",
  'body/ResourceAttendees': "@if(equals(body('Read_query')?['os_sr_avq_mod'], 100000001), coalesce(variables('v_loc')?['email'], ''), '')",
  'body/MeetingDuration': "@body('Read_query')?['os_sr_avq_dur']",
  'body/Start': "@formatDateTime(body('Read_query')?['os_sr_avq_strt'], 'yyyy-MM-ddTHH:mm:ssZ')",
  'body/End': "@formatDateTime(body('Read_query')?['os_sr_avq_end'], 'yyyy-MM-ddTHH:mm:ssZ')",
  'body/MaxCandidates': "@variables('v_cfg')['maxc']",
  'body/MinimumAttendeePercentage': '100',
  'body/IsOrganizerOptional': true,
  'body/ActivityDomain': 'Work'
};

function assertExecutionBoundary(candidate) {
  const actions = new Map();
  const counts = {};
  function visit(container) {
    assert.ok(container && typeof container === 'object' && !Array.isArray(container));
    for (const [name, action] of Object.entries(container)) {
      assert.ok(action && typeof action === 'object' && !Array.isArray(action));
      assert.ok(Object.hasOwn(typeCounts, action.type), `Unexpected action type in ${name}.`);
      assert.equal(actions.has(name), false, 'Action names must be unique.');
      actions.set(name, action);
      counts[action.type] = (counts[action.type] || 0) + 1;
      assert.equal(Object.hasOwn(action, 'cases'), false, `${name} has no switch branches.`);
      assert.equal(Object.hasOwn(action, 'default'), false, `${name} has no default branch.`);
      if (Object.hasOwn(action, 'actions')) {
        assert.ok(['If', 'Scope', 'Foreach'].includes(action.type), `${name} cannot contain actions.`);
        visit(action.actions);
      }
      if (Object.hasOwn(action, 'else')) {
        assert.equal(action.type, 'If', `${name} cannot contain an else branch.`);
        assert.deepEqual(Object.keys(action.else), ['actions']);
        visit(action.else.actions);
      }
    }
  }
  visit(candidate.properties.definition.actions);
  assert.deepEqual(canonical(counts), canonical(typeCounts));
  const connectors = [...actions].filter(([, action]) => action.type === 'OpenApiConnection')
    .map(([name]) => name).sort();
  assert.deepEqual(connectors, [...Object.keys(readContracts), 'Find_meeting_times', 'Write_terminal_result'].sort());
  for (const name of connectors) {
    const action = actions.get(name);
    const outlook = name === 'Find_meeting_times';
    const api = outlook ? 'shared_office365' : 'shared_commondataserviceforapps';
    assert.deepEqual(action.inputs.host, {
      connectionName: api,
      operationId: outlook ? 'FindMeetingTimes_V2' : name === 'Write_terminal_result' ? 'UpdateOnlyRecord' : 'GetItem',
      apiId: `/providers/Microsoft.PowerApps/apis/${api}`
    });
    assert.equal(action.inputs.authentication, "@parameters('$authentication')");
    assert.deepEqual(action.inputs.retryPolicy, { type: 'none' });
    assert.equal(Object.hasOwn(action, 'retryPolicy'), false);
    if (Object.hasOwn(readContracts, name)) {
      const [entityName, recordId, select] = readContracts[name];
      assert.deepEqual(action.inputs.parameters, { entityName, recordId, $select: select });
    }
  }
  assert.deepEqual(actions.get('Find_meeting_times').inputs.parameters, outlookParameters);
  assert.deepEqual(actions.get('Write_terminal_result').inputs.parameters, terminalParameters);
  assert.strictEqual(candidate.properties.definition.actions.Write_terminal_result, actions.get('Write_terminal_result'));
  assert.deepEqual(actions.get('Write_terminal_result').runAfter, { Compose_terminal: ['Succeeded'] });
  assert.deepEqual(actions.get('Compose_terminal').runAfter.Check_pending, ['Succeeded']);
  assert.equal(digest(actions.get('Check_pending').expression), changedProperties[0][2]);
  assert.deepEqual(actions.get('Write_terminal_result').runtimeConfiguration.secureData,
    { properties: ['inputs', 'outputs'] });
}

test('complete functional delta and seven validators match independent pins and pinned history', () => {
  assertReviewedDelta(source);
});

test('every changed property, added validator and unrelated mutation is detected', () => {
  for (const [name, property] of changedProperties) {
    const mutant = structuredClone(source);
    const action = index(mutant.properties.definition.actions).get(name);
    if (typeof action[property] === 'string') action[property] += ' ';
    else action[property].syntheticMutation = true;
    assert.throws(() => assertReviewedDelta(mutant), `${name}.${property}`);
  }
  for (const [name] of validators) {
    const mutant = structuredClone(source);
    index(mutant.properties.definition.actions).get(name).inputs.schema.syntheticMutation = true;
    assert.throws(() => assertReviewedDelta(mutant), name);
  }
  const changedWrite = structuredClone(source);
  changedWrite.properties.definition.actions.Write_terminal_result.inputs.parameters['item/os_sr_avq_stat'] = 'synthetic';
  assert.throws(() => assertReviewedDelta(changedWrite), 'Unexpected terminal expression changes reject.');
  const moved = structuredClone(source);
  const movedActions = index(moved.properties.definition.actions);
  movedActions.get('Evaluate').actions.Validate_provider_response =
    movedActions.get('Check_validation').actions.Validate_provider_response;
  delete movedActions.get('Check_validation').actions.Validate_provider_response;
  assert.throws(() => assertReviewedDelta(moved), 'Moving a pinned validator rejects.');
});

test('all executable branches enforce the exact single terminal-write and connector boundary', () => {
  assertExecutionBoundary(source);
});

test('write, connector, branch and Pending-gate mutations are rejected', () => {
  const variants = [
    candidate => { candidate.properties.definition.actions.Write_terminal_result.inputs.parameters['item/synthetic'] = 'x'; },
    candidate => { candidate.properties.definition.actions.Write_terminal_result.inputs.parameters.recordId = "@triggerOutputs()?['body/os_sr_avqid']"; },
    candidate => { candidate.properties.definition.actions.Read_query.inputs.host.operationId = 'UpdateOnlyRecord'; },
    candidate => { delete candidate.properties.definition.actions.Compose_terminal.runAfter.Check_pending; },
    candidate => { candidate.properties.definition.actions.Check_pending.cases = {}; },
    candidate => { candidate.properties.definition.actions.Check_pending.else.actions.Synthetic = { type: 'Http', inputs: {} }; }
  ];
  for (const mutate of variants) {
    const mutant = structuredClone(source);
    mutate(mutant);
    assert.throws(() => assertExecutionBoundary(mutant));
  }
});

test('every source expression remains within the 8192-character safety bound', () => {
  function visit(value) {
    if (typeof value === 'string' && value.startsWith('@')) assert.ok(value.length <= 8192);
    else if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') Object.values(value).forEach(visit);
  }
  visit(source.properties.definition);
});
