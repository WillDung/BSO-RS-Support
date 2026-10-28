#requires -Version 7.4
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$scriptPath = Join-Path $root 'scripts\Test-BsoRsCandidateCorePhase5A.ps1'
$source = Get-Content -LiteralPath $scriptPath -Raw
$script:Passed = 0

function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:Passed++
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$errors
)
Assert-Test ($errors.Count -eq 0) 'Phase 5A runtime runner parses'
Assert-Test ($source -match "ValidateSet\('PlanOnly', 'Apply'\)" -and
    $source -match "EnvironmentName -cne 'VN LMV IT'" -and
    $source -match "https://org14938ec2\.crm4\.dynamics\.com") `
    'Runtime runner is pinned to VN LMV IT'
Assert-Test ($source -match "ExpectedDispatches = 27" -and
    $source -match 'MaximumReads = 180' -and
    $source -match 'DispatchCount -ne \$script:ExpectedDispatches') `
    'Runtime API dispatch and read budgets are fixed'
Assert-Test ($source -match "'os_sr_cact'" -and
    $source.Contains("`$script:ApiRoot + 'os_sr_cact'") -and
    $source -match 'Invoke-WebRequest' -and
    $source -match 'MaximumRetryCount 0' -and
    $source -match 'MaximumRedirection 0' -and
    $source -match 'UNCERTAIN_OUTCOME_NO_RETRY' -and
    $source -match 'ErrorSummary = \$null') `
    'Only the Custom API is written and network retries are disabled'
Assert-Test ($source -match 'customapirequestparameters' -and
    $source -match 'PHASE_3C_API_CONTRACT\.json' -and
    $source -match 'missing=\$missingText' -and
    $source -match 'unexpected=\$unexpectedText') `
    'PlanOnly verifies the complete live Custom API request-parameter contract'
Assert-Test ($source -match 'CurrentStage = "CUSTOM_API_\$action"' -and
    $source -match 'StopStage = \$script:CurrentStage') `
    'Runtime diagnostics preserve the actual failing Custom API operation stage'
Assert-Test ($source -match 'prvReados_sr_cand' -and
    $source -match 'CORRELATION_CONFLICT' -and
    $source -match 'STALE_EXPECTED_STATUS') `
    'Live privilege, conflicting replay, and stale-status contracts are asserted'
Assert-Test ($source -match 'example\.invalid' -and
    $source -match 'StartsWith\(''\[DEV\]''' -and
    $source -match "filter = 'statecode eq 0'" -and
    $source -match '%24top=5000') `
    'Fixtures use .invalid addresses and active DEV-prefixed references only'
Assert-Test ($source -match 'RecordCall' -and
    $source -match 'ProceedToScheduling' -and
    $source -match 'MarkRound1Scheduled' -and
    $source -match 'RecordPass' -and $source -match 'RecordFail' -and
    $source -match 'RequestReschedule' -and $source -match 'CancelRound1') `
    'The supported Candidate Core workflow is included'
Assert-Test ($source -match "Outcome = 'PHASE_5A_CANDIDATE_CORE_RUNTIME_MATRIX_PASSED'" -and
    $source -match 'OperationReceipts = \$allReceipts.Count' -and
    $source.Contains("State -eq 'ACKNOWLEDGED').Count -ne 24") -and
    $source.Contains("State -eq 'EXPECTED_REJECTION').Count -ne 3") -and
    $source -match "State -eq 'EXPECTED_REJECTION'") `
    'The runner requires durable record reconciliation and journals the outcome'
Assert-Test ($source -match '_os_sr_intv_ta_value,_os_sr_intv_loc_value' -and
    $source -match "CurrentStage = 'DURABLE_STATE_RECONCILIATION'" -and
    $source -notmatch 'os_sr_intv_rnts,os_sr_intv_ta,os_sr_intv_loc') `
    'Schedule readback selects lookup-value columns and labels the persistence stage'
Assert-Test ($source -match 'os_sr_csh_newstat -notin @\(100010000, 100010001, 100010002, 100010003, 100010004, 100010005\)') `
    'Status History reconciliation accepts each canonical Candidate workflow state'
Assert-Test ($source -match 'Get-Phase5AErrorSummary' -and
    $source -match 'SYNTHETIC_NAME' -and $source -match 'SYNTHETIC_EMAIL' -and
    $source -match 'Custom API rejected \$action with HTTP') `
    'Unexpected API rejections persist only a redacted diagnostic summary'
foreach ($functionName in @('Get-Phase5AErrorCode', 'Get-Phase5AErrorSummary')) {
    $definition = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $_.Name -ceq $functionName
    })
    Assert-Test ($definition.Count -eq 1) "$functionName is defined once"
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$syntheticErrorBody = [ordered]@{
    CandidateName = 'SYNTHETIC Runtime Test'
    CandidateEmail = 'runtime-test@example.invalid'
}
$summary = Get-Phase5AErrorSummary -ResponseText `
    '<html><head><style>body{color:black}</style></head><body><h1>Runtime Error</h1><p>SYNTHETIC Runtime Test runtime-test@example.invalid</p></body></html>' `
    -RequestBody $syntheticErrorBody
Assert-Test ($summary.Contains('Runtime Error') -and
    $summary.Contains('[SYNTHETIC_NAME]') -and $summary.Contains('[SYNTHETIC_EMAIL]') -and
    -not $summary.Contains('runtime-test@example.invalid') -and
    -not $summary.Contains('SYNTHETIC Runtime Test')) `
    'HTML error diagnostics are reduced and redact synthetic fixture identity'
$errorCode = Get-Phase5AErrorCode -Response '{"error":{"message":"CORRELATION_CONFLICT"}}'
Assert-Test ($errorCode -ceq 'CORRELATION_CONFLICT') 'Expected API errors are classified from JSON responses'
$contractPath = Join-Path (Split-Path $PSScriptRoot) 'docs\PHASE_3C_API_CONTRACT.json'
$apiContract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$scheduleInputs = @($apiContract.inputs | Where-Object {
    $_.name -in @('InterviewerId', 'LocationId', 'StartAt', 'EndAt')
} | ForEach-Object { '{0}|{1}|{2}' -f $_.name, [int]$_.type, [bool]$_.optional } | Sort-Object -CaseSensitive)
Assert-Test ([string]::Join(';', $scheduleInputs) -ceq
    'EndAt|1|True;InterviewerId|12|True;LocationId|12|True;StartAt|1|True') `
    'Approved Custom API contract declares schedule evidence inputs with exact types'
Assert-Test ($source -notmatch 'ProtectCandidateCore|DIRECT_WRITE_GUARD_REJECTED|pac admin assign-user|PublishAllXml') `
    'Runtime acceptance does not diagnose guards, assign roles, or publish'

Write-Output "PASS: $script:Passed offline Phase 5A runtime-runner assertions; no authentication/network."
