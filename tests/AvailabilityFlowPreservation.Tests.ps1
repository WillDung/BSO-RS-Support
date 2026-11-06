#requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$flowPath = 'solutions\AvailabilityQuery\os_sr_avchk.clientdata.json'
$baselineCommit = '7a64022e1891607b9d4c789d0f03e1c99640df88'
$baselineBlob = '4ba6b0e35cdfaabc0fd9e44c62a438ea5cfc21cc'
$baselineSha256 = 'F901BAAE0ABC5F2A2ECCF74BF59E76FE05189A6E13BF86A981D6D6E4DBEB8811'
$script:checks = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:checks++
}

function Assert-Rejected([scriptblock]$Action, [string]$Name, [string]$ExpectedError) {
    $message = ''
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    if ($message -notmatch $ExpectedError) { throw "FAIL: $Name did not produce the expected rejection." }
    $script:checks++
}

function Assert-UniqueJsonKeys([System.Text.Json.JsonElement]$Element, [string]$Path) {
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $keys.Add($property.Name)) { throw "DUPLICATE_KEY at $Path" }
            Assert-UniqueJsonKeys $property.Value "$Path.$($property.Name)"
        }
    } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        $index = 0
        foreach ($item in $Element.EnumerateArray()) {
            Assert-UniqueJsonKeys $item "$Path[$index]"
            $index++
        }
    }
}

function Read-StrictJson([string]$Json) {
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 256
    try {
        $document = [System.Text.Json.JsonDocument]::Parse($Json, $options)
    } catch {
        throw 'INVALID_JSON'
    }
    try {
        Assert-UniqueJsonKeys $document.RootElement '$'
        return $document
    } catch {
        $document.Dispose()
        throw
    }
}

function Assert-JsonEqual(
    [System.Text.Json.JsonElement]$Expected,
    [System.Text.Json.JsonElement]$Actual,
    [string]$Path
) {
    if ($Expected.ValueKind -ne $Actual.ValueKind) { throw "JSON_MISMATCH at $Path (type)" }
    if ($Expected.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $expectedProperties = @($Expected.EnumerateObject())
        $actualProperties = @($Actual.EnumerateObject())
        if ($expectedProperties.Count -ne $actualProperties.Count) {
            throw "JSON_MISMATCH at $Path (property count)"
        }
        foreach ($property in $expectedProperties) {
            $actualValue = [System.Text.Json.JsonElement]::new()
            if (-not $Actual.TryGetProperty($property.Name, [ref]$actualValue)) {
                throw "JSON_MISMATCH at $Path (property name)"
            }
            Assert-JsonEqual $property.Value $actualValue "$Path.$($property.Name)"
        }
    } elseif ($Expected.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        if ($Expected.GetArrayLength() -ne $Actual.GetArrayLength()) {
            throw "JSON_MISMATCH at $Path (array length)"
        }
        for ($index = 0; $index -lt $Expected.GetArrayLength(); $index++) {
            Assert-JsonEqual $Expected[$index] $Actual[$index] "$Path[$index]"
        }
    } elseif ($Expected.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
        if (-not [string]::Equals($Expected.GetString(), $Actual.GetString(), [StringComparison]::Ordinal)) {
            throw "JSON_MISMATCH at $Path (string)"
        }
    } elseif ($Expected.ValueKind -eq [System.Text.Json.JsonValueKind]::Number) {
        if (-not [string]::Equals($Expected.GetRawText(), $Actual.GetRawText(), [StringComparison]::Ordinal)) {
            throw "JSON_MISMATCH at $Path (number)"
        }
    } elseif ($Expected.ValueKind -notin @(
        [System.Text.Json.JsonValueKind]::True,
        [System.Text.Json.JsonValueKind]::False,
        [System.Text.Json.JsonValueKind]::Null
    )) {
        throw "JSON_MISMATCH at $Path (unsupported value)"
    }
}

function Assert-JsonTextsEqual([string]$Expected, [string]$Actual) {
    $expectedDocument = Read-StrictJson $Expected
    try {
        $actualDocument = Read-StrictJson $Actual
        try {
            Assert-JsonEqual $expectedDocument.RootElement $actualDocument.RootElement '$'
        } finally {
            $actualDocument.Dispose()
        }
    } finally {
        $expectedDocument.Dispose()
    }
}

function Add-FlowActions(
    [System.Text.Json.Nodes.JsonObject]$Actions,
    [System.Collections.Generic.Dictionary[string, System.Text.Json.Nodes.JsonObject]]$Index
) {
    foreach ($entry in $Actions.GetEnumerator()) {
        if ($entry.Value -isnot [System.Text.Json.Nodes.JsonObject]) { throw 'FLOW_INVENTORY: invalid action' }
        $action = $entry.Value.AsObject()
        if (-not $Index.TryAdd($entry.Key, $action)) { throw 'FLOW_INVENTORY: duplicate action name' }
        if ($action.ContainsKey('actions')) {
            Add-FlowActions $action['actions'].AsObject() $Index
        }
        foreach ($containerName in @('else', 'default')) {
            if ($action.ContainsKey($containerName)) {
                $container = $action[$containerName].AsObject()
                if ($container.ContainsKey('actions')) { Add-FlowActions $container['actions'].AsObject() $Index }
            }
        }
        if ($action.ContainsKey('cases')) {
            foreach ($case in $action['cases'].AsObject().GetEnumerator()) {
                $container = $case.Value.AsObject()
                if ($container.ContainsKey('actions')) { Add-FlowActions $container['actions'].AsObject() $Index }
            }
        }
    }
}

function Get-FlowActionIndex([System.Text.Json.Nodes.JsonNode]$Flow) {
    $index = [System.Collections.Generic.Dictionary[string, System.Text.Json.Nodes.JsonObject]]::new(
        [System.StringComparer]::Ordinal
    )
    Add-FlowActions $Flow['properties']['definition']['actions'].AsObject() $index
    return ,$index
}

function Test-HasSecureData([System.Text.Json.Nodes.JsonObject]$Item) {
    if (-not $Item.ContainsKey('runtimeConfiguration')) { return $false }
    if ($Item['runtimeConfiguration'] -isnot [System.Text.Json.Nodes.JsonObject]) {
        throw 'PRIVACY_INVALID: runtimeConfiguration is not an object'
    }
    return $Item['runtimeConfiguration'].AsObject().ContainsKey('secureData')
}

function Assert-SecureData([System.Text.Json.Nodes.JsonObject]$Item, [string]$Expected, [string]$Name) {
    if (-not (Test-HasSecureData $Item) -or $null -eq $Item['runtimeConfiguration']['secureData']) {
        throw "PRIVACY_INVALID: missing setting for $Name"
    }
    Assert-JsonTextsEqual $Expected $Item['runtimeConfiguration']['secureData'].ToJsonString()
    $script:checks++
}

function Set-SecureData([System.Text.Json.Nodes.JsonObject]$Item, [string]$Json) {
    if (-not $Item.ContainsKey('runtimeConfiguration')) {
        $Item['runtimeConfiguration'] = [System.Text.Json.Nodes.JsonObject]::new()
    }
    $Item['runtimeConfiguration']['secureData'] = [System.Text.Json.Nodes.JsonNode]::Parse($Json)
}

function Assert-ExpectedFlow([System.Text.Json.JsonDocument]$Expected, [string]$Candidate) {
    $actualDocument = Read-StrictJson $Candidate
    try {
        Assert-JsonEqual $Expected.RootElement $actualDocument.RootElement '$'
    } finally {
        $actualDocument.Dispose()
    }
}

function Assert-SnapshotInvariant([System.Text.Json.JsonElement]$Snapshot) {
    try {
        $workflow = $Snapshot.GetProperty('workflow')
        $flowId = $workflow.GetProperty('workflowid').GetString()
        $installationId = $workflow.GetProperty('workflowidunique').GetString()
        $owner = $workflow.GetProperty('owner').GetString()
        if ([string]::IsNullOrWhiteSpace($flowId) -or [string]::IsNullOrWhiteSpace($installationId) -or
            [string]::IsNullOrWhiteSpace($owner) -or
            $workflow.GetProperty('name').GetString() -cne 'os_sr_avchk' -or
            $workflow.GetProperty('category').GetInt32() -ne 5 -or
            $workflow.GetProperty('type').GetInt32() -ne 1 -or
            $workflow.GetProperty('statecode').GetInt32() -ne 0 -or
            $workflow.GetProperty('statuscode').GetInt32() -ne 1 -or
            $workflow.GetProperty('ismanaged').GetBoolean() -or
            $workflow.GetProperty('componentstate').GetInt32() -ne 0) {
            throw 'workflow'
        }

        $members = @($Snapshot.GetProperty('solutionMemberships').EnumerateObject())
        $targetCount = 0
        foreach ($member in $members) {
            $row = $member.Value
            if ($row.GetProperty('membershipid').GetString() -cne $member.Name -or
                $row.GetProperty('objectid').GetString() -cne $flowId -or
                $row.GetProperty('componenttype').GetInt32() -ne 29 -or
                [string]::IsNullOrWhiteSpace($row.GetProperty('solutionid').GetString()) -or
                [string]::IsNullOrWhiteSpace($row.GetProperty('solutionuniquename').GetString())) {
                throw 'membership'
            }
            if ($row.GetProperty('solutionuniquename').GetString() -ceq 'os_sr_bso_rs_support') {
                $targetCount++
            }
        }
        if ($targetCount -ne 1) { throw 'target membership' }

        $bindings = $Snapshot.GetProperty('bindings')
        if (@($bindings.EnumerateObject()).Count -ne 2) { throw 'binding count' }
        foreach ($pair in @(
            @{ Name = 'os_sr_avchk_dataverse_cr'; Connector = 'shared_commondataserviceforapps' },
            @{ Name = 'os_sr_avchk_outlook_cr'; Connector = 'shared_office365' }
        )) {
            $binding = $bindings.GetProperty($pair.Name)
            if ($binding.GetProperty('referenceName').GetString() -cne $pair.Name -or
                $binding.GetProperty('connector').GetString() -cne $pair.Connector -or
                [string]::IsNullOrWhiteSpace($binding.GetProperty('referenceId').GetString()) -or
                [string]::IsNullOrWhiteSpace($binding.GetProperty('referenceOwner').GetString()) -or
                $binding.GetProperty('referenceState').GetString() -cne 'Active' -or
                [string]::IsNullOrWhiteSpace($binding.GetProperty('connectionId').GetString()) -or
                $binding.GetProperty('connectionOwner').GetString() -cne $owner -or
                $binding.GetProperty('connectionStatus').GetString() -cne 'Connected') {
                throw 'binding'
            }
            foreach ($member in $binding.GetProperty('referenceMemberships').EnumerateObject()) {
                if ($member.Value.GetProperty('membershipid').GetString() -cne $member.Name -or
                    $member.Value.GetProperty('objectid').GetString() -cne $binding.GetProperty('referenceId').GetString() -or
                    [string]::IsNullOrWhiteSpace($member.Value.GetProperty('solutionid').GetString())) {
                    throw 'reference membership'
                }
            }
        }
    } catch {
        throw 'SNAPSHOT_INVARIANT'
    }
}

function Assert-SnapshotPreserved([string]$Before, [string]$After) {
    $beforeDocument = Read-StrictJson $Before
    try {
        $afterDocument = Read-StrictJson $After
        try {
            Assert-SnapshotInvariant $beforeDocument.RootElement
            Assert-SnapshotInvariant $afterDocument.RootElement
            Assert-JsonEqual $beforeDocument.RootElement $afterDocument.RootElement '$'
        } finally {
            $afterDocument.Dispose()
        }
    } finally {
        $beforeDocument.Dispose()
    }
}

function Assert-Plan(
    [System.Text.Json.Nodes.JsonObject]$Plan,
    [string]$FreshETag,
    [System.Text.Json.JsonDocument]$Expected
) {
    try {
        if ($Plan.Count -ne 7 -or
            $Plan['method'].GetValue[string]() -cne 'PATCH' -or
            $Plan['flowId'].GetValue[string]() -cne 'synthetic-flow' -or
            [string]::IsNullOrWhiteSpace($FreshETag) -or $FreshETag -ceq '*' -or
            -not [string]::Equals($Plan['ifMatch'].GetValue[string](), $FreshETag, [StringComparison]::Ordinal) -or
            $Plan['retryCount'].GetValue[int]() -ne 0 -or
            $Plan['redirectsAllowed'].GetValue[bool]() -or
            $Plan['maxDispatches'].GetValue[int]() -ne 1) {
            throw 'precondition'
        }
        $body = $Plan['body'].AsObject()
        if ($body.Count -ne 1 -or -not $body.ContainsKey('clientdata')) { throw 'body' }
        $clientdata = $body['clientdata'].GetValue[string]()
    } catch {
        throw 'PLAN_INVARIANT'
    }
    Assert-ExpectedFlow $Expected $clientdata
}

function Get-PinnedHistoricalFlow([string]$GitPath, [string]$Commit, [string]$Blob, [string]$Sha256) {
    $tree = @(& $GitPath --no-lazy-fetch --no-optional-locks --no-replace-objects -C $root ls-tree -r --full-tree $Commit -- $flowPath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $tree.Count -ne 1) {
        throw 'Required pre-hardening Git commit/tree is unavailable; no fallback is permitted.'
    }
    $treeParts = $tree[0] -split "`t", 2
    if ($treeParts.Count -ne 2 -or $treeParts[0] -cne "100644 blob $Blob" -or
        $treeParts[1].Replace([char]47, [char]92) -cne $flowPath) {
        throw 'Required pre-hardening Git path or blob does not match the pinned baseline.'
    }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitPath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    foreach ($argument in @('--no-lazy-fetch', '--no-optional-locks', '--no-replace-objects', '-C', $root, 'cat-file', 'blob', $Blob)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $buffer = [System.IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'Required pre-hardening Git blob could not be read.' }
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $process.WaitForExit()
        if ($process.ExitCode -ne 0 -or $buffer.Length -eq 0) {
            throw 'Required pre-hardening Git blob is unavailable; no fallback is permitted.'
        }
        $baselineBytes = $buffer.ToArray()
        if ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($baselineBytes)) -cne $Sha256) {
            throw 'Required pre-hardening Git blob does not match the pinned SHA-256.'
        }
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($baselineBytes)
    } finally {
        $buffer.Dispose()
        $process.Dispose()
    }
}

$git = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $git) { throw 'Git is required to retrieve the pinned pre-hardening source; no fallback is permitted.' }
$null = & $git.Source --no-lazy-fetch --no-optional-locks --no-replace-objects --version 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Git cannot enforce offline historical-object reads; no fallback is permitted.' }
$baselineText = Get-PinnedHistoricalFlow $git.Source $baselineCommit $baselineBlob $baselineSha256
Assert-Rejected { Get-PinnedHistoricalFlow $git.Source ('0' * 40) $baselineBlob $baselineSha256 } 'Missing historical commit rejects' 'commit/tree is unavailable'
Assert-Rejected { Get-PinnedHistoricalFlow $git.Source $baselineCommit ('0' * 40) $baselineSha256 } 'Unexpected historical blob rejects' 'path or blob does not match'
Assert-Rejected { Get-PinnedHistoricalFlow $git.Source $baselineCommit $baselineBlob ('0' * 64) } 'Unexpected historical SHA-256 rejects' 'does not match the pinned SHA-256'
$currentText = [System.IO.File]::ReadAllText((Join-Path $root $flowPath))
$baselineDocument = Read-StrictJson $baselineText
$baselineDocument.Dispose()
$currentDocument = Read-StrictJson $currentText
$currentDocument.Dispose()

foreach ($duplicate in @(
    '{"key":1,"key":2}',
    '{"value":1,"\u0076alue":2}',
    '{"outer":{"secureData":{"properties":["inputs"],"properties":["outputs"]}}}',
    '{"array":[{"name":"a","name":"b"}]}'
)) {
    Assert-Rejected { $document = Read-StrictJson $duplicate; $document.Dispose() } 'Duplicate JSON keys reject at every depth' 'DUPLICATE_KEY'
}
Assert-Rejected { $document = Read-StrictJson '{"a":1,}'; $document.Dispose() } 'Malformed JSON rejects' 'INVALID_JSON'
Assert-JsonTextsEqual '{"b":"\u0078","a":[1,true,null]}' '{"a":[1,true,null],"b":"x"}'
Assert-Test $true 'Object order and equivalent string escaping are serialization-only differences.'
foreach ($pair in @(
    @('{"s":"ABC"}', '{"s":"abc"}'),
    @('{"n":1}', '{"n":1.0}'),
    @('{"a":[1,2]}', '{"a":[2,1]}'),
    @('{"a":null}', '{}'),
    @('{"key":1}', '{"Key":1}')
)) {
    Assert-Rejected { Assert-JsonTextsEqual $pair[0] $pair[1] } 'Non-equivalent values and normalization reject' 'JSON_MISMATCH'
}

$expectedNode = [System.Text.Json.Nodes.JsonNode]::Parse($baselineText)
$currentNode = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
$beforeActions = Get-FlowActionIndex $expectedNode
$currentActions = Get-FlowActionIndex $currentNode
Assert-Test ($beforeActions.Count -eq 96 -and $currentActions.Count -eq 96) 'All 96 nested action identities remain present.'
Assert-Test (@($beforeActions.Keys | Where-Object { Test-HasSecureData $beforeActions[$_] }).Count -eq 13) 'Exactly 13 actions were already protected.'
Assert-Test (@($currentActions.Keys | Where-Object { Test-HasSecureData $currentActions[$_] }).Count -eq 33) 'Exactly 33 actions are protected in current source.'

$triggerName = 'When_a_Pending_availability_query_is_added'
$beforeTriggers = $expectedNode['properties']['definition']['triggers'].AsObject()
$currentTriggers = $currentNode['properties']['definition']['triggers'].AsObject()
Assert-Test ($beforeTriggers.Count -eq 1 -and $currentTriggers.Count -eq 1 -and
    $beforeTriggers.ContainsKey($triggerName) -and $currentTriggers.ContainsKey($triggerName)) 'The exact single trigger is retained.'
$beforeTrigger = $beforeTriggers[$triggerName].AsObject()
$currentTrigger = $currentTriggers[$triggerName].AsObject()
Assert-Test ($currentTrigger['type'].GetValue[string]() -ceq 'OpenApiConnectionWebhook' -and
    $currentTrigger['inputs']['parameters']['subscriptionRequest/entityname'].GetValue[string]() -ceq 'os_sr_avq' -and
    $currentTrigger['inputs']['parameters']['subscriptionRequest/message'].GetValue[int]() -eq 1 -and
    $currentTrigger['inputs']['parameters']['subscriptionRequest/filterexpression'].GetValue[string]() -ceq 'os_sr_avq_stat eq 100000000' -and
    $currentTrigger['runtimeConfiguration']['concurrency']['runs'].GetValue[int]() -eq 1) 'Trigger identity, Pending filter and concurrency remain exact.'
Assert-Test (-not (Test-HasSecureData $beforeTrigger)) 'Trigger protection was absent before hardening.'
Assert-SecureData $currentTrigger '{"properties":["outputs"]}' $triggerName
Set-SecureData $beforeTrigger '{"properties":["outputs"]}'

$changedGroups = @(
    @{ Type = 'Compose'; Previous = 'inputs'; Names = @('Compose_free', 'Compose_slot', 'Compose_validation_error', 'Compose_drift', 'Compose_location_drift') },
    @{ Type = 'Compose'; Previous = 'absent'; Names = @('Compose_terminal', 'Compose_canonical_slots', 'Compose_proposed_result') },
    @{ Type = 'If'; Previous = 'absent'; Names = @('Check_response_shape', 'Check_slot_eligible', 'Check_suggestion_valid', 'Check_suggestion_timezone', 'If_validated_snapshot') },
    @{ Type = 'AppendToArrayVariable'; Previous = 'absent'; Names = @('Append_observation', 'Append_slot') },
    @{ Type = 'Foreach'; Previous = 'absent'; Names = @('For_each_suggestion') },
    @{ Type = 'SetVariable'; Previous = 'absent'; Names = @('Set_result_slots', 'Set_location_snapshot', 'Set_ta_snapshot', 'Set_location_changed') },
    @{ Type = 'Scope'; Previous = 'absent'; Names = @('Evaluate', 'Reread_references', 'Map_failure') },
    @{ Type = 'OpenApiConnection'; Previous = 'absent'; Names = @('Read_query', 'Write_terminal_result') }
)
$retainedGroups = @(
    @{ Type = 'OpenApiConnection'; Names = @('Read_ta', 'Read_location', 'Find_meeting_times', 'Reread_ta', 'Reread_location') },
    @{ Type = 'Query'; Names = @('Find_invalid_attendees', 'Find_ta_entries', 'Find_room_entries') }
)
$changedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$retainedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($group in $changedGroups) {
    foreach ($name in $group.Names) {
        Assert-Test ($changedNames.Add($name) -and $beforeActions.ContainsKey($name) -and $currentActions.ContainsKey($name)) "Changed action $name is unique and present."
        Assert-Test ($beforeActions[$name]['type'].GetValue[string]() -ceq $group.Type -and
            $currentActions[$name]['type'].GetValue[string]() -ceq $group.Type) "Changed action $name retains its type."
        if ($group.Previous -ceq 'inputs') {
            Assert-SecureData $beforeActions[$name] '{"properties":["inputs"]}' $name
        } else {
            Assert-Test (-not (Test-HasSecureData $beforeActions[$name])) "Changed action $name previously had no secureData."
        }
        Assert-SecureData $currentActions[$name] '{"properties":["inputs","outputs"]}' $name
        Set-SecureData $beforeActions[$name] '{"properties":["inputs","outputs"]}'
    }
}
foreach ($group in $retainedGroups) {
    foreach ($name in $group.Names) {
        Assert-Test ($retainedNames.Add($name) -and -not $changedNames.Contains($name) -and
            $beforeActions.ContainsKey($name) -and $currentActions.ContainsKey($name)) "Retained action $name is unique and present."
        Assert-Test ($beforeActions[$name]['type'].GetValue[string]() -ceq $group.Type -and
            $currentActions[$name]['type'].GetValue[string]() -ceq $group.Type) "Retained action $name retains its type."
        Assert-SecureData $beforeActions[$name] '{"properties":["inputs","outputs"]}' $name
        Assert-SecureData $currentActions[$name] '{"properties":["inputs","outputs"]}' $name
    }
}
Assert-Test ($changedNames.Count -eq 25 -and $retainedNames.Count -eq 8 -and
    ($changedNames.Count + 1) -eq 26) 'Exactly 25 actions and one trigger change; eight more actions retain protection.'
foreach ($name in $currentActions.Keys) {
    if (Test-HasSecureData $currentActions[$name]) {
        Assert-Test ($changedNames.Contains($name) -or $retainedNames.Contains($name)) "Protected action $name belongs to the exact inventory."
    }
}

$references = $currentNode['properties']['connectionReferences'].AsObject()
Assert-Test ($references.Count -eq 2) 'The definition has exactly two connection references.'
foreach ($pair in @(
    @{ Key = 'shared_commondataserviceforapps'; Name = 'os_sr_avchk_dataverse_cr' },
    @{ Key = 'shared_office365'; Name = 'os_sr_avchk_outlook_cr' }
)) {
    Assert-Test ($references.ContainsKey($pair.Key) -and
        $references[$pair.Key]['runtimeSource'].GetValue[string]() -ceq 'embedded' -and
        $references[$pair.Key]['api']['name'].GetValue[string]() -ceq $pair.Key -and
        $references[$pair.Key]['connection']['connectionReferenceLogicalName'].GetValue[string]() -ceq $pair.Name) "Connection reference $($pair.Key) is exact."
}

$expectedDocument = Read-StrictJson $expectedNode.ToJsonString()
try {
    Assert-ExpectedFlow $expectedDocument $currentText
    Assert-Test $true 'The complete current definition equals the historical definition plus exactly the 26 privacy changes.'

    foreach ($name in @($changedNames) + @($retainedNames)) {
        $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
        $mutantActions = Get-FlowActionIndex $mutant
        $null = $mutantActions[$name]['runtimeConfiguration'].AsObject().Remove('secureData')
        Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } "Removing protection from $name rejects" 'JSON_MISMATCH'
    }
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    $null = $mutant['properties']['definition']['triggers'][$triggerName]['runtimeConfiguration'].AsObject().Remove('secureData')
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Removing trigger protection rejects' 'JSON_MISMATCH'

    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    $mutant['properties']['definition']['triggers'][$triggerName]['inputs']['parameters']['subscriptionRequest/filterexpression'] =
        [System.Text.Json.Nodes.JsonValue]::Create('os_sr_avq_stat eq 100000001')
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Trigger filter mutation rejects' 'JSON_MISMATCH'
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    $mutant['properties']['definition']['triggers'][$triggerName]['runtimeConfiguration']['concurrency']['runs'] =
        [System.Text.Json.Nodes.JsonNode]::Parse('1.0')
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Numeric normalization of trigger concurrency rejects' 'JSON_MISMATCH'
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    (Get-FlowActionIndex $mutant)['Compose_canonical_slots']['inputs'] =
        [System.Text.Json.Nodes.JsonValue]::Create("@sort(variables('v_slots'))")
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Expression mutation rejects' 'JSON_MISMATCH'
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    (Get-FlowActionIndex $mutant)['Find_meeting_times']['retryPolicy']['type'] =
        [System.Text.Json.Nodes.JsonValue]::Create('fixed')
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Connector retry-policy mutation rejects' 'JSON_MISMATCH'
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    (Get-FlowActionIndex $mutant)['Write_terminal_result']['inputs']['parameters']['item/os_sr_avq_stat'] =
        [System.Text.Json.Nodes.JsonValue]::Create('synthetic-changed-expression')
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Terminal-write mutation rejects' 'JSON_MISMATCH'
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    $mutant['properties']['connectionReferences']['shared_office365']['connection']['connectionReferenceLogicalName'] =
        [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-reference')
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Connection-reference mutation rejects' 'JSON_MISMATCH'
    foreach ($replacement in @(
        '{"properties":["outputs","inputs"]}',
        '{"properties":["inputs"]}',
        '{"properties":["inputs","inputs","outputs"]}',
        '{"properties":["inputs","outputs"],"mode":"synthetic"}',
        '{"properties":"inputs,outputs"}'
    )) {
        $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
        (Get-FlowActionIndex $mutant)['Compose_free']['runtimeConfiguration']['secureData'] =
            [System.Text.Json.Nodes.JsonNode]::Parse($replacement)
        Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'secureData tampering or normalization rejects' 'JSON_MISMATCH'
    }
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    (Get-FlowActionIndex $mutant)['Compose_free']['runtimeConfiguration']['secureData'] = $null
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Null secureData normalization rejects' 'JSON_MISMATCH'
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    Set-SecureData (Get-FlowActionIndex $mutant)['Initialize_phase'] '{"properties":["inputs","outputs"]}'
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $mutant.ToJsonString() } 'Unexpected additional protection/normalization rejects' 'JSON_MISMATCH'
    $duplicateFlow = $currentText -replace '^\{\s*"properties"\s*:', '{"properties":null,"properties":'
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $duplicateFlow } 'Duplicate Flow property rejects before comparison' 'DUPLICATE_KEY'
    $compactFlow = $currentNode.ToJsonString()
    $duplicatePrivacy = $compactFlow.Replace('{"properties":["inputs","outputs"]}', '{"properties":["inputs"],"properties":["inputs","outputs"]}')
    Assert-Test ($duplicatePrivacy -cne $compactFlow) 'Nested secureData duplicate canary was inserted.'
    Assert-Rejected { Assert-ExpectedFlow $expectedDocument $duplicatePrivacy } 'Duplicate nested secureData rejects before comparison' 'DUPLICATE_KEY'

    $snapshot = @'
{
  "workflow": {
    "workflowid": "synthetic-flow", "workflowidunique": "synthetic-installation",
    "name": "os_sr_avchk", "owner": "synthetic-owner", "category": 5, "type": 1,
    "statecode": 0, "statuscode": 1, "ismanaged": false, "componentstate": 0
  },
  "solutionMemberships": {
    "synthetic-target-membership": {
      "membershipid": "synthetic-target-membership", "objectid": "synthetic-flow",
      "componenttype": 29, "solutionid": "synthetic-target-solution",
      "solutionuniquename": "os_sr_bso_rs_support", "rootcomponentbehavior": 0,
      "rootsolutioncomponentid": null
    },
    "synthetic-other-membership": {
      "membershipid": "synthetic-other-membership", "objectid": "synthetic-flow",
      "componenttype": 29, "solutionid": "synthetic-other-solution",
      "solutionuniquename": "synthetic_other_solution", "rootcomponentbehavior": 0,
      "rootsolutioncomponentid": null
    }
  },
  "bindings": {
    "os_sr_avchk_dataverse_cr": {
      "referenceName": "os_sr_avchk_dataverse_cr", "connector": "shared_commondataserviceforapps",
      "referenceId": "synthetic-dataverse-reference", "referenceOwner": "synthetic-reference-owner",
      "referenceState": "Active", "connectionId": "synthetic-dataverse-connection",
      "connectionOwner": "synthetic-owner", "connectionStatus": "Connected",
      "referenceMemberships": {
        "synthetic-dataverse-reference-membership": {
          "membershipid": "synthetic-dataverse-reference-membership",
          "objectid": "synthetic-dataverse-reference", "solutionid": "synthetic-target-solution"
        }
      }
    },
    "os_sr_avchk_outlook_cr": {
      "referenceName": "os_sr_avchk_outlook_cr", "connector": "shared_office365",
      "referenceId": "synthetic-outlook-reference", "referenceOwner": "synthetic-reference-owner",
      "referenceState": "Active", "connectionId": "synthetic-outlook-connection",
      "connectionOwner": "synthetic-owner", "connectionStatus": "Connected",
      "referenceMemberships": {
        "synthetic-outlook-reference-membership": {
          "membershipid": "synthetic-outlook-reference-membership",
          "objectid": "synthetic-outlook-reference", "solutionid": "synthetic-target-solution"
        }
      }
    }
  }
}
'@
    Assert-SnapshotPreserved $snapshot $snapshot
    Assert-Test $true 'The entirely synthetic stable snapshot is self-consistent.'
    $snapshotMutations = @(
        @{ Name = 'Flow identity'; Change = { param($s) $s['workflow']['workflowid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-flow') } },
        @{ Name = 'coherent Flow retarget'; Change = {
            param($s)
            $s['workflow']['workflowid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-flow')
            foreach ($member in $s['solutionMemberships'].AsObject().GetEnumerator()) {
                $member.Value['objectid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-flow')
            }
        } },
        @{ Name = 'installation identity'; Change = { param($s) $s['workflow']['workflowidunique'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-installation') } },
        @{ Name = 'owner'; Change = { param($s) $s['workflow']['owner'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-owner') } },
        @{ Name = 'coherent owner replacement'; Change = {
            param($s)
            $s['workflow']['owner'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-owner')
            foreach ($binding in $s['bindings'].AsObject().GetEnumerator()) {
                $binding.Value['connectionOwner'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-owner')
            }
        } },
        @{ Name = 'OFF state'; Change = { param($s) $s['workflow']['statecode'] = [System.Text.Json.Nodes.JsonValue]::Create(1) } },
        @{ Name = 'OFF status'; Change = { param($s) $s['workflow']['statuscode'] = [System.Text.Json.Nodes.JsonValue]::Create(2) } },
        @{ Name = 'category'; Change = { param($s) $s['workflow']['category'] = [System.Text.Json.Nodes.JsonValue]::Create(4) } },
        @{ Name = 'type'; Change = { param($s) $s['workflow']['type'] = [System.Text.Json.Nodes.JsonValue]::Create(2) } },
        @{ Name = 'managed layer'; Change = { param($s) $s['workflow']['ismanaged'] = [System.Text.Json.Nodes.JsonValue]::Create($true) } },
        @{ Name = 'component layer'; Change = { param($s) $s['workflow']['componentstate'] = [System.Text.Json.Nodes.JsonValue]::Create(1) } },
        @{ Name = 'target Solution'; Change = { param($s) $s['solutionMemberships']['synthetic-target-membership']['solutionid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-different-solution') } },
        @{ Name = 'membership row identity'; Change = { param($s) $s['solutionMemberships']['synthetic-target-membership']['membershipid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-different-membership') } },
        @{ Name = 'membership behavior'; Change = { param($s) $s['solutionMemberships']['synthetic-target-membership']['rootcomponentbehavior'] = [System.Text.Json.Nodes.JsonValue]::Create(1) } },
        @{ Name = 'membership root'; Change = { param($s) $s['solutionMemberships']['synthetic-target-membership']['rootsolutioncomponentid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-different-root') } },
        @{ Name = 'second target membership'; Change = { param($s) $s['solutionMemberships']['synthetic-other-membership']['solutionuniquename'] = [System.Text.Json.Nodes.JsonValue]::Create('os_sr_bso_rs_support') } },
        @{ Name = 'removed target membership'; Change = { param($s) $null = $s['solutionMemberships'].AsObject().Remove('synthetic-target-membership') } },
        @{ Name = 'removed other membership'; Change = { param($s) $null = $s['solutionMemberships'].AsObject().Remove('synthetic-other-membership') } },
        @{ Name = 'added membership'; Change = { param($s) $s['solutionMemberships']['synthetic-added-membership'] = [System.Text.Json.Nodes.JsonNode]::Parse('{"membershipid":"synthetic-added-membership","objectid":"synthetic-flow","componenttype":29,"solutionid":"synthetic-added-solution","solutionuniquename":"synthetic_added_solution","rootcomponentbehavior":0}') } },
        @{ Name = 'binding connector'; Change = { param($s) $s['bindings']['os_sr_avchk_outlook_cr']['connector'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-connector') } },
        @{ Name = 'reference state'; Change = { param($s) $s['bindings']['os_sr_avchk_outlook_cr']['referenceState'] = [System.Text.Json.Nodes.JsonValue]::Create('Inactive') } },
        @{ Name = 'binding owner'; Change = { param($s) $s['bindings']['os_sr_avchk_outlook_cr']['connectionOwner'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-owner') } },
        @{ Name = 'binding state'; Change = { param($s) $s['bindings']['os_sr_avchk_dataverse_cr']['connectionStatus'] = [System.Text.Json.Nodes.JsonValue]::Create('Disconnected') } }
    )
    foreach ($case in $snapshotMutations) {
        $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($snapshot)
        & $case.Change $mutant | Out-Null
        Assert-Rejected { Assert-SnapshotPreserved $snapshot $mutant.ToJsonString() } "Synthetic $($case.Name) drift rejects" 'SNAPSHOT_INVARIANT|JSON_MISMATCH'
    }
    foreach ($name in @('os_sr_avchk_dataverse_cr', 'os_sr_avchk_outlook_cr')) {
        foreach ($field in @('referenceId', 'referenceOwner', 'connectionId')) {
            $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($snapshot)
            $mutant['bindings'][$name][$field] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-changed-binding')
            Assert-Rejected { Assert-SnapshotPreserved $snapshot $mutant.ToJsonString() } "Synthetic $name $field drift rejects independently of a Workflow ETag" 'SNAPSHOT_INVARIANT|JSON_MISMATCH'
        }
        $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($snapshot)
        $mutant['bindings'][$name]['referenceMemberships'].AsObject().Clear()
        Assert-Rejected { Assert-SnapshotPreserved $snapshot $mutant.ToJsonString() } "Synthetic $name reference membership drift rejects independently of a Workflow ETag" 'JSON_MISMATCH'
    }
    $mutant = [System.Text.Json.Nodes.JsonNode]::Parse($snapshot)
    $mutant['workflow']['statecode'] = [System.Text.Json.Nodes.JsonValue]::Create(1)
    Assert-Rejected { Assert-SnapshotPreserved $mutant.ToJsonString() $mutant.ToJsonString() } 'Identical ON snapshots do not pass the OFF prerequisite' 'SNAPSHOT_INVARIANT'
    $duplicateSnapshot = $snapshot.Replace('"synthetic-target-membership": {', '"synthetic-target-membership": {}, "synthetic-target-membership": {')
    Assert-Rejected { Assert-SnapshotPreserved $snapshot $duplicateSnapshot } 'Duplicate synthetic membership key rejects' 'DUPLICATE_KEY'

    $freshTag = 'W/"synthetic-fresh-etag"'
    $plan = [System.Text.Json.Nodes.JsonNode]::Parse('{"method":"PATCH","flowId":"synthetic-flow","ifMatch":"W/\"synthetic-fresh-etag\"","body":{"clientdata":""},"retryCount":0,"redirectsAllowed":false,"maxDispatches":1}').AsObject()
    $plan['body']['clientdata'] = [System.Text.Json.Nodes.JsonValue]::Create($currentText)
    Assert-Plan $plan $freshTag $expectedDocument
    Assert-Test $true 'The in-memory request model has one clientdata property and the exact synthetic fresh ETag.'
    $planMutations = @(
        @{ Name = 'wildcard ETag'; Change = { param($p) $p['ifMatch'] = [System.Text.Json.Nodes.JsonValue]::Create('*') } },
        @{ Name = 'stale ETag'; Change = { param($p) $p['ifMatch'] = [System.Text.Json.Nodes.JsonValue]::Create('W/"synthetic-stale-etag"') } },
        @{ Name = 'wrong Flow'; Change = { param($p) $p['flowId'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-other-flow') } },
        @{ Name = 'wrong method'; Change = { param($p) $p['method'] = [System.Text.Json.Nodes.JsonValue]::Create('PUT') } },
        @{ Name = 'owner update'; Change = { param($p) $p['body']['ownerid'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-owner') } },
        @{ Name = 'state update'; Change = { param($p) $p['body']['statecode'] = [System.Text.Json.Nodes.JsonValue]::Create(1) } },
        @{ Name = 'binding update'; Change = { param($p) $p['body']['connectionReference'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-reference') } },
        @{ Name = 'membership update'; Change = { param($p) $p['body']['solutionMembership'] = [System.Text.Json.Nodes.JsonValue]::Create('synthetic-membership') } },
        @{ Name = 'retry'; Change = { param($p) $p['retryCount'] = [System.Text.Json.Nodes.JsonValue]::Create(1) } },
        @{ Name = 'redirect'; Change = { param($p) $p['redirectsAllowed'] = [System.Text.Json.Nodes.JsonValue]::Create($true) } },
        @{ Name = 'second dispatch'; Change = { param($p) $p['maxDispatches'] = [System.Text.Json.Nodes.JsonValue]::Create(2) } }
    )
    foreach ($case in $planMutations) {
        $mutantPlan = $plan.DeepClone().AsObject()
        & $case.Change $mutantPlan | Out-Null
        Assert-Rejected { Assert-Plan $mutantPlan $freshTag $expectedDocument } "Synthetic plan $($case.Name) rejects" 'PLAN_INVARIANT'
    }
    Assert-Rejected { Assert-Plan $plan '*' $expectedDocument } 'A wildcard cannot serve as the fresh ETag' 'PLAN_INVARIANT'
    $mutantPlan = $plan.DeepClone().AsObject()
    $mutantPlan['body']['clientdata'] = [System.Text.Json.Nodes.JsonValue]::Create($duplicateFlow)
    Assert-Rejected { Assert-Plan $mutantPlan $freshTag $expectedDocument } 'Duplicate embedded clientdata rejects' 'DUPLICATE_KEY'
    $mutantFlow = [System.Text.Json.Nodes.JsonNode]::Parse($currentText)
    (Get-FlowActionIndex $mutantFlow)['Compose_free']['runtimeConfiguration']['secureData'] =
        [System.Text.Json.Nodes.JsonNode]::Parse('{"properties":["inputs"]}')
    $mutantPlan = $plan.DeepClone().AsObject()
    $mutantPlan['body']['clientdata'] = [System.Text.Json.Nodes.JsonValue]::Create($mutantFlow.ToJsonString())
    Assert-Rejected { Assert-Plan $mutantPlan $freshTag $expectedDocument } 'Changed embedded privacy setting rejects' 'JSON_MISMATCH'
} finally {
    $expectedDocument.Dispose()
}

Write-Output "Availability Flow preservation checks passed: $script:checks"
Write-Output 'Offline repository comparison and in-memory synthetic models only; no live, binding, ETag-enforcement or runtime-privacy assurance.'
