#requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('PlanOnly', 'Preflight', 'Apply', 'CompleteReceipt', 'CompleteLookup', 'Reconcile')][string]$Mode = 'PlanOnly',
    [string]$EnvironmentName,
    [string]$OrganizationUrl,
    [string]$ExpectedEnvironmentId,
    [string]$ExpectedOrganizationId,
    [string]$EvidencePath,
    [string]$PriorEvidencePath,
    [string]$ExpectedPlanSha256
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$baselinePath = Join-Path $PSScriptRoot 'Provision-BsoRsCandidateChildTables.ps1'
$parseTokens = $null
$parseErrors = $null
$baselineAst = [System.Management.Automation.Language.Parser]::ParseFile($baselinePath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Baseline metadata runner has parser errors.' }
# Reuse validated read/identity helpers, never the prior runner's write transport or executable main.
$helperNames = @(
    'Get-Sha256', 'Get-SanitizedDataverseError', 'Get-SanitizedFailureMessage',
    'Assert-TargetInput', 'Assert-PacIdentity', 'Get-ValidatedToken',
    'New-Label', 'New-RequiredLevel', 'Get-Required', 'Get-OptionalMetadata',
    'Get-ReconciliationSnapshot', 'Assert-TableReadback', 'Assert-RelationshipsAndKeys',
    'Get-ChoiceOptionsForRepair', 'Get-StatusChoiceAttribute', 'Assert-StatusChoiceColumn'
)
foreach ($name in $helperNames) {
    $definitions = @($baselineAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -ceq $name
    })
    if ($definitions.Count -ne 1) { throw "Baseline helper is missing or ambiguous: $name" }
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$script:SolutionName = 'os_sr_bso_rs_support'
$script:PublisherName = 'os_bso_rs_support'
$script:PublisherPrefix = 'os'
$script:ChoiceName = 'os_sr_callout'
$script:TableNames = @('os_sr_call', 'os_sr_csh')
$script:Plan = Get-Content -Raw (Join-Path $root 'docs\PHASE_3C_OPERATION_RECEIPT_PLAN.json') | ConvertFrom-Json
$manifest = Get-Content -Raw (Join-Path $root 'docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json') | ConvertFrom-Json
$script:CoreHash = (Get-FileHash (Join-Path $root 'docs\PHASE_3A_CANDIDATE_CORE_METADATA_PLAN.json') -Algorithm SHA256).Hash.ToLowerInvariant()
$script:PlanHash = (Get-FileHash (Join-Path $root 'docs\PHASE_3C_OPERATION_RECEIPT_PLAN.json') -Algorithm SHA256).Hash.ToLowerInvariant()
$script:RequestCounts = @{ GET = 0; POST = 0; PUT = 0 }
$script:WriteStages = [System.Collections.Generic.List[string]]::new()
$script:CandidateGets = 0
$script:AccessToken = $null
$script:Journal = $null
$script:WriteIndex = 0
$script:Solution = $null
$script:ApiRoot = $null

function Get-ReceiptPayloads {
    param([string]$CandidatePrimaryId)
    if ($script:Plan.table -cne 'os_sr_oprc' -or $script:Plan.solution -cne $script:SolutionName -or
        $script:Plan.key.columns.Count -ne 1 -or $script:Plan.key.columns[0] -cne 'os_sr_oprc_corid') {
        throw 'Operation receipt contract identity differs from the authorized extension.'
    }
    $attributes = @(
        foreach ($column in $script:Plan.columns) {
            $attribute = [ordered]@{
                '@odata.type' = "Microsoft.Dynamics.CRM.$($column.type)AttributeMetadata"
                AttributeType = [string]$column.type
                AttributeTypeName = @{ Value = "$($column.type)Type" }
                SchemaName = [string]$column.name
                DisplayName = New-Label -Text $column.label
                RequiredLevel = New-RequiredLevel -Required $column.required
                IsAuditEnabled = @{ Value = $true }
                IsSecured = $false
            }
            if ($column.type -ceq 'String') {
                $attribute.MaxLength = [int]$column.length
                $attribute.FormatName = @{ Value = 'Text' }
                if ($column.name -ceq $script:Plan.primaryName) { $attribute.IsPrimaryName = $true }
            } elseif ($column.type -ceq 'Integer') {
                $attribute.Format = 'None'
                $attribute.MinValue = 0
                $attribute.MaxValue = [int]::MaxValue
            } else { throw 'Unapproved receipt attribute type.' }
            $attribute
        }
    )
    $table = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityMetadata'
        SchemaName = 'os_sr_oprc'
        DisplayName = New-Label -Text 'Operation Receipt'
        DisplayCollectionName = New-Label -Text 'Operation Receipts'
        Description = New-Label -Text 'Immutable Candidate business-operation replay evidence. No raw request payload.'
        OwnershipType = 'UserOwned'
        HasActivities = $false
        HasNotes = $false
        IsActivity = $false
        IsAuditEnabled = @{ Value = $true }
        Attributes = $attributes
    }
    $relationship = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata'
        SchemaName = 'os_sr_cand_oprc'
        ReferencedEntity = 'os_sr_cand'
        ReferencedAttribute = $CandidatePrimaryId
        ReferencingEntity = 'os_sr_oprc'
        CascadeConfiguration = [ordered]@{
            Assign = 'NoCascade'; Delete = 'Restrict'; Merge = 'NoCascade'
            Reparent = 'NoCascade'; Share = 'NoCascade'; Unshare = 'NoCascade'
        }
        Lookup = [ordered]@{
            '@odata.type' = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'
            SchemaName = 'os_sr_oprc_cand'
            DisplayName = New-Label -Text 'Candidate'
            RequiredLevel = New-RequiredLevel -Required $true
            IsAuditEnabled = @{ Value = $true }
            IsSecured = $false
        }
    }
    $key = [ordered]@{
        '@odata.type' = 'Microsoft.Dynamics.CRM.EntityKeyMetadata'
        SchemaName = 'os_sr_oprc_ak_corid'
        DisplayName = New-Label -Text 'Operation Correlation Identity'
        KeyAttributes = @('os_sr_oprc_corid')
    }
    @(
        @{ Path = 'EntityDefinitions'; Body = $table; Gate = 'TABLE' }
        @{ Path = 'RelationshipDefinitions'; Body = $relationship; Gate = 'RELATIONSHIP' }
        @{ Path = "EntityDefinitions(LogicalName='os_sr_oprc')/Keys"; Body = $key; Gate = 'KEY' }
    )
}

function Invoke-DataverseRequest {
    param([ValidateSet('GET', 'POST', 'PUT')][string]$Method, [string]$Path, [object]$Body)
    $uri = [Uri]($script:ApiRoot + $Path)
    if ($uri.Scheme -cne 'https' -or $uri.Authority -ine ([Uri]$OrganizationUrl).Authority -or
        $uri.AbsolutePath -notmatch '^/api/data/v9\.2/' -or $uri.UserInfo -or $uri.Fragment) {
        throw 'Request outside the guarded Dataverse API.'
    }
    $headers = @{
        Authorization = "Bearer $script:AccessToken"; Accept = 'application/json'
        'OData-Version' = '4.0'; 'OData-MaxVersion' = '4.0'; Consistency = 'Strong'
    }
    $arguments = @{
        Uri = $uri; Method = $Method; Headers = $headers
        MaximumRetryCount = 0; MaximumRedirection = 0; TimeoutSec = 120
        SkipHttpErrorCheck = $true
    }
    if ($Method -cne 'GET') {
        if ($Mode -cnotin @('Apply', 'CompleteReceipt', 'CompleteLookup') -or $null -eq $script:Journal -or
            $script:WriteIndex -ge $script:Journal.Writes.Count -or $script:WriteIndex -ge 3) {
            throw 'Receipt metadata write is not authorized in this mode or exceeds ceiling.'
        }
        $entry = $script:Journal.Writes[$script:WriteIndex]
        $json = ConvertTo-Json -InputObject $Body -Depth 80 -Compress
        $hash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($json))
        if ($Path -cne $entry.Path -or $Method -cne $entry.Method -or $hash -cne $entry.PayloadSha256 -or $entry.State -cne 'PLANNED') {
            throw 'Receipt write path/body/order differs from precomputed plan.'
        }
        $entry.State = 'DISPATCH_RESERVED'
        Save-ReceiptJournal
        $script:WriteIndex++
        $headers['MSCRM.SolutionUniqueName'] = $script:SolutionName
        if ($Method -ceq 'PUT') { $headers['MSCRM.MergeLabels'] = 'true' }
        $arguments.Body = $json
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    $script:RequestCounts[$Method]++
    try { $response = Invoke-WebRequest @arguments }
    catch { throw "UNCERTAIN_TRANSPORT_$Method; reconcile once and stop; response content suppressed." }
    if ($Method -cne 'GET') {
        $entry.HttpStatus = [int]$response.StatusCode
        $entry.State = if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) { 'ACKNOWLEDGED' } else { 'REJECTED' }
        Save-ReceiptJournal
    }
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        $parsed = $null
        try { $parsed = $response.Content | ConvertFrom-Json } catch { $parsed = $null }
        throw (Get-SanitizedDataverseError -StatusCode $response.StatusCode -Response $parsed)
    }
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) { $response.Content | ConvertFrom-Json }
}

function Get-ODataRows {
    param([string]$Path)
    do {
        $page = Invoke-DataverseRequest -Method GET -Path $Path
        $page.value
        $next = [string]$page.'@odata.nextLink'
        if ($next) {
            $nextUri = [Uri]$next
            if (-not $next.StartsWith($script:ApiRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Foreign paging URL.' }
            $Path = $nextUri.AbsoluteUri.Substring($script:ApiRoot.Length)
        } else { $Path = $null }
    } while ($Path)
}

function Save-ReceiptJournal {
    $json = ConvertTo-Json -InputObject $script:Journal -Depth 80
    $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.SetLength(0)
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}

function Assert-ReceiptReadback {
    param([ValidateSet('TABLE', 'RELATIONSHIP', 'KEY')][string]$Gate, [switch]$AllowKnownPrimaryDefaults, [switch]$AllowKnownLookupAuditDefault)
    $metadata = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='os_sr_oprc')"
    if ($metadata.LogicalName -cne 'os_sr_oprc' -or $metadata.SchemaName -cne 'os_sr_oprc' -or
        $metadata.OwnershipType -cne 'UserOwned' -or $metadata.IsAuditEnabled.Value -ne $true -or
        $metadata.PrimaryNameAttribute -cne 'os_sr_oprc_nm' -or $metadata.IsManaged -ne $false) {
        throw 'Operation Receipt table identity/ownership/audit differs.'
    }
    $attributes = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/Attributes")
    $custom = @($attributes | Where-Object {
        $_.LogicalName -like 'os_sr_oprc_*' -and $_.AttributeType -cne 'Virtual' -and -not $_.AttributeOf
    })
    $expected = @($script:Plan.columns.name)
    if ($Gate -ne 'TABLE') { $expected += 'os_sr_oprc_cand' }
    if ((Compare-Object $expected @($custom.LogicalName)).Count) { throw 'Receipt attribute inventory differs.' }
    foreach ($column in $script:Plan.columns) {
        $actual = @($custom | Where-Object LogicalName -CEQ $column.name)
        $primaryDefault = $AllowKnownPrimaryDefaults -and $column.name -ceq 'os_sr_oprc_nm'
        if ($actual.Count -ne 1 -or $actual[0].SchemaName -cne $column.name -or
            $actual[0].AttributeType -cne $column.type -or
            $actual[0].RequiredLevel.Value -cne $(if ($primaryDefault) { 'None' } elseif ($column.required) { 'ApplicationRequired' } else { 'None' }) -or
            $actual[0].DisplayName.UserLocalizedLabel.Label -cne $column.label -or
            $actual[0].IsAuditEnabled.Value -ne $true -or $actual[0].IsSecured -ne $false) {
            throw "Receipt attribute contract differs: $($column.name)"
        }
        if ($column.type -ceq 'String' -and ($actual[0].MaxLength -ne $(if ($primaryDefault) { 850 } else { $column.length }) -or $actual[0].FormatName.Value -cne 'Text')) {
            throw 'Receipt String length/format differs.'
        }
        if ($column.type -ceq 'Integer' -and ($actual[0].MinValue -ne 0 -or $actual[0].MaxValue -ne [int]::MaxValue)) {
            throw 'Receipt Integer bounds differ.'
        }
    }
    $filter = [Uri]::EscapeDataString("_solutionid_value eq $($script:Solution.solutionid)")
    $components = @(Get-ODataRows -Path "solutioncomponents?`$select=objectid,componenttype,rootcomponentbehavior&`$filter=$filter")
    $rootRows = @($components | Where-Object {
        $_.componenttype -eq 1 -and [string]$_.objectid -ieq [string]$metadata.MetadataId -and $_.rootcomponentbehavior -eq 0
    })
    if ($rootRows.Count -ne 1) { throw 'Receipt table not in exact Solution with subcomponents.' }
    if ($Gate -ne 'TABLE') {
        $relations = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/ManyToOneRelationships")
        $project = @($relations | Where-Object SchemaName -Like 'os_sr_*')
        if ($project.Count -ne 1 -or $project[0].SchemaName -cne 'os_sr_cand_oprc' -or
            $project[0].ReferencedEntity -cne 'os_sr_cand' -or $project[0].ReferencingEntity -cne 'os_sr_oprc' -or
            $project[0].ReferencedAttribute -cne $script:CandidatePrimaryId -or
            $project[0].ReferencingAttribute -cne 'os_sr_oprc_cand' -or
            $project[0].CascadeConfiguration.Delete -cne 'Restrict') { throw 'Receipt Candidate relationship differs.' }
        foreach ($cascade in @('Assign', 'Share', 'Unshare', 'Reparent', 'Merge')) {
            if ($project[0].CascadeConfiguration.$cascade -cne 'NoCascade') { throw 'Receipt relationship cascade differs.' }
        }
        $lookup = @($custom | Where-Object LogicalName -CEQ 'os_sr_oprc_cand')
        if ($lookup.Count -ne 1 -or $lookup[0].AttributeType -cne 'Lookup' -or
            $lookup[0].RequiredLevel.Value -cne 'ApplicationRequired' -or
            $lookup[0].IsAuditEnabled.Value -ne (-not $AllowKnownLookupAuditDefault) -or
            $lookup[0].IsSecured -ne $false) { throw 'Receipt Candidate lookup differs.' }
    }
    if ($Gate -ceq 'KEY') {
        $keys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/Keys")
        if ($keys.Count -ne 1 -or $keys[0].SchemaName -cne 'os_sr_oprc_ak_corid' -or
            $keys[0].KeyAttributes.Count -ne 1 -or $keys[0].KeyAttributes[0] -cne 'os_sr_oprc_corid' -or
            $keys[0].EntityKeyIndexStatus -cne 'Active') { throw 'Receipt key is not exact and Active; no resend allowed.' }
    }
    $metadata
}

if ($Mode -ceq 'PlanOnly') {
    [ordered]@{ Result = 'LOCAL_PLAN_ONLY'; PlanSha256 = $script:PlanHash; CoreManifestSha256 = $script:CoreHash
        MaximumWrites = 5; AutomaticRetries = 0; Requests = $script:RequestCounts
        Payloads = @(Get-ReceiptPayloads -CandidatePrimaryId 'RESOLVE_LIVE_BEFORE_DISPATCH' | ForEach-Object {
            @{ Path = $_.Path; Gate = $_.Gate; Body = $_.Body }
        })
    } | ConvertTo-Json -Depth 80
    return
}

try {
    Assert-TargetInput
    if ($Mode -cin @('Apply', 'CompleteReceipt', 'CompleteLookup') -and ($ExpectedPlanSha256 -cne $script:PlanHash -or -not $EvidencePath)) {
        throw 'Apply requires the exact reviewed plan SHA and a new durable evidence path.'
    }
    $candidateOutput = @(& (Join-Path $PSScriptRoot 'Provision-BsoRsCandidateTable.ps1') -ReconcileOnly `
        -EnvironmentName $EnvironmentName -OrganizationUrl $OrganizationUrl `
        -ExpectedEnvironmentId $ExpectedEnvironmentId -ExpectedOrganizationId $ExpectedOrganizationId)
    $candidate = ($candidateOutput -join "`n") | ConvertFrom-Json
    $candidateResult = $candidate
    if ($candidate.Result -cne 'CANDIDATE_TABLE_KEYS_LOOKUPS_AND_SOLUTION_MEMBERSHIP_RECONCILED' -or $candidate.Requests.POST -ne 0) {
        throw 'CANDIDATE_CORE_STORAGE_DRIFT: Candidate reconciliation failed.'
    }
    $script:CandidateGets = [int]$candidate.Requests.GET
    Assert-PacIdentity
    Get-ValidatedToken
    $script:ApiRoot = $OrganizationUrl.TrimEnd('/') + '/api/data/v9.2/'
    $null = Get-ReconciliationSnapshot
    $callChoice = Invoke-DataverseRequest -Method GET -Path "GlobalOptionSetDefinitions(Name='os_sr_callout')"
    $statusChoice = Invoke-DataverseRequest -Method GET -Path "GlobalOptionSetDefinitions(Name='os_sr_candstat')"
    $null = Get-ChoiceOptionsForRepair -Choice $callChoice -ExpectedOptions $manifest.callOutcomeChoice.options -ExpectedName 'os_sr_callout'
    $null = Get-ChoiceOptionsForRepair -Choice $statusChoice -ExpectedOptions $manifest.globalChoice.options -ExpectedName 'os_sr_candstat'
    foreach ($table in @($manifest.tables | Where-Object logicalName -In $script:TableNames)) {
        $null = Assert-TableReadback -Table $table -Choice $callChoice
    }
    $null = Assert-RelationshipsAndKeys
    $historyDefinition = @($manifest.tables | Where-Object logicalName -CEQ 'os_sr_csh')[0]
    foreach ($column in @($historyDefinition.columns | Where-Object type -CEQ 'GlobalChoice')) {
        $attribute = Get-StatusChoiceAttribute -LogicalName $column.logicalName
        Assert-StatusChoiceColumn -Attribute $attribute -ManifestColumn $column -ExpectedChoiceName 'os_sr_candstat' -ExpectedChoice $statusChoice
        $retainedHashes = @{
            os_sr_csh_prevstat = '6ed63930c2ce3a845cc0a616a46b4abbb44e67f23e2409235587a7f4636f6926'
            os_sr_csh_newstat = '0adf2dbde97832dc641eb837a5f5d942ab92d2d09a83b2bed46c45472ea94549'
        }
        $actualHash = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes(([string]$attribute.MetadataId).ToLowerInvariant()))
        if ($actualHash -cne $retainedHashes[$column.logicalName]) { throw 'Repaired attribute identity differs from retained successful state.' }
    }
    $candidateMetadata = Invoke-DataverseRequest -Method GET -Path "EntityDefinitions(LogicalName='os_sr_cand')?`$select=PrimaryIdAttribute,IsOptimisticConcurrencyEnabled,Privileges"
    if ($candidateMetadata.IsOptimisticConcurrencyEnabled -ne $true) { throw 'Candidate concurrency is not enabled.' }
    $script:CandidatePrimaryId = [string]$candidateMetadata.PrimaryIdAttribute
    $privilegeNames = @($candidateMetadata.Privileges.Name)
    foreach ($required in @('prvCreateos_sr_cand', 'prvReados_sr_cand', 'prvWriteos_sr_cand')) {
        if ($required -cnotin $privilegeNames) { throw 'Required generated Candidate privilege not found.' }
    }
    $audit = Invoke-DataverseRequest -Method GET -Path "organizations($ExpectedOrganizationId)?`$select=isauditenabled"
    $existing = Get-OptionalMetadata -Path "EntityDefinitions(LogicalName='os_sr_oprc')?`$select=MetadataId"
    $payloads = @(Get-ReceiptPayloads -CandidatePrimaryId $script:CandidatePrimaryId)
    if ($Mode -ceq 'CompleteReceipt') {
        if (-not $PriorEvidencePath -or -not (Test-Path -LiteralPath $PriorEvidencePath) -or $null -eq $existing) {
            throw 'Completion requires the retained acknowledged table-create journal and live table.'
        }
        $prior = Get-Content -Raw -LiteralPath $PriorEvidencePath | ConvertFrom-Json
        if ($prior.Writes.Count -ne 3 -or $prior.Writes[0].State -cne 'ACKNOWLEDGED' -or
            $prior.Writes[0].HttpStatus -ne 204 -or $prior.Writes[0].Path -cne 'EntityDefinitions' -or
            $prior.Writes[0].PayloadSha256 -cne 'db7e9b6f31c541a8a71d1914c25ca57b68fe1c7dbe4f8062dced4892f88f33e7' -or
            $prior.Writes[1].State -cne 'PLANNED' -or $prior.Writes[2].State -cne 'PLANNED') {
            throw 'Retained table-create dispatch state differs; no continuation.'
        }
        $null = Assert-ReceiptReadback -Gate TABLE -AllowKnownPrimaryDefaults
        $priorRelationships = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/ManyToOneRelationships" |
            Where-Object SchemaName -Like 'os_sr_*')
        $priorKeys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/Keys")
        if ($priorRelationships.Count -or $priorKeys.Count) { throw 'Receipt continuation expected no project relationship/key.' }
        $primary = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/Attributes/Microsoft.Dynamics.CRM.StringAttributeMetadata?`$filter=LogicalName eq 'os_sr_oprc_nm'")
        if ($primary.Count -ne 1 -or $primary[0].IsPrimaryName -ne $true) { throw 'Primary-name identity not proven.' }
        $body = ConvertFrom-Json -AsHashtable -InputObject (ConvertTo-Json -InputObject $primary[0] -Depth 80)
        foreach ($keyName in @($body.Keys | Where-Object { $_ -like '@odata.*' })) { $body.Remove($keyName) }
        $body['@odata.type'] = 'Microsoft.Dynamics.CRM.StringAttributeMetadata'
        $body.MaxLength = 36
        $body.RequiredLevel.Value = 'ApplicationRequired'
        $payloads = @(
            @{ Method = 'PUT'; Path = "EntityDefinitions(LogicalName='os_sr_oprc')/Attributes($($primary[0].MetadataId))"; Body = $body; Gate = 'TABLE' }
            $payloads[1]
            $payloads[2]
        )
    }
    if ($Mode -ceq 'CompleteLookup') {
        if (-not $PriorEvidencePath -or -not (Test-Path -LiteralPath $PriorEvidencePath) -or $null -eq $existing) {
            throw 'Lookup completion requires retained primary/relationship dispatch evidence.'
        }
        $prior = Get-Content -Raw -LiteralPath $PriorEvidencePath | ConvertFrom-Json
        if ($prior.Writes.Count -ne 3 -or $prior.Writes[0].State -cne 'GET_RECONCILED' -or
            $prior.Writes[0].PayloadSha256 -cne '05cc75550333c60cbdfdf5623ddffd62017cec23e6cc422590fc57428251b543' -or
            $prior.Writes[1].State -cne 'ACKNOWLEDGED' -or $prior.Writes[1].HttpStatus -ne 204 -or
            $prior.Writes[1].PayloadSha256 -cne 'ddea14f3a458d540c9b55f674439a0ce0b694b1b3baac73a7580ac5e6186fe5b' -or
            $prior.Writes[2].State -cne 'PLANNED') { throw 'Lookup completion evidence differs.' }
        $null = Assert-ReceiptReadback -Gate RELATIONSHIP -AllowKnownLookupAuditDefault
        $priorKeys = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/Keys")
        if ($priorKeys.Count) { throw 'Lookup completion requires key still absent.' }
        $lookup = @(Get-ODataRows -Path "EntityDefinitions(LogicalName='os_sr_oprc')/Attributes/Microsoft.Dynamics.CRM.LookupAttributeMetadata?`$filter=LogicalName eq 'os_sr_oprc_cand'")
        if ($lookup.Count -ne 1) { throw 'Lookup identity ambiguous.' }
        $body = ConvertFrom-Json -AsHashtable -InputObject (ConvertTo-Json -InputObject $lookup[0] -Depth 80)
        foreach ($keyName in @($body.Keys | Where-Object { $_ -like '@odata.*' })) { $body.Remove($keyName) }
        $body['@odata.type'] = 'Microsoft.Dynamics.CRM.LookupAttributeMetadata'
        $body.IsAuditEnabled.Value = $true
        $payloads = @(
            @{ Method = 'PUT'; Path = "EntityDefinitions(LogicalName='os_sr_oprc')/Attributes($($lookup[0].MetadataId))"; Body = $body; Gate = 'RELATIONSHIP' }
            $payloads[2]
        )
    }
    $planEntries = @($payloads | ForEach-Object {
        [ordered]@{ Method = $(if ($_.Method) { $_.Method } else { 'POST' }); Path = $_.Path; Gate = $_.Gate; State = 'PLANNED'; HttpStatus = $null
            PayloadSha256 = Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $_.Body -Depth 80 -Compress))) }
    })
    if ($Mode -cin @('Apply', 'CompleteReceipt', 'CompleteLookup')) {
        if ($Mode -ceq 'Apply' -and $null -ne $existing) { throw 'Receipt already exists; use read-only reconciliation; no repeat create.' }
        $script:Journal = [ordered]@{ PlanSha256 = $script:PlanHash; CoreManifestSha256 = $script:CoreHash; Writes = $planEntries; AutomaticRetries = 0 }
        $stream = [IO.File]::Open($EvidencePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        Save-ReceiptJournal
        foreach ($payload in $payloads) {
            try {
                $method = if ($payload.Method) { $payload.Method } else { 'POST' }
                $null = Invoke-DataverseRequest -Method $method -Path $payload.Path -Body $payload.Body
            } catch {
                $original = $_
                try { $null = Assert-ReceiptReadback -Gate $payload.Gate }
                catch { Write-Warning 'Failed/uncertain receipt dispatch reconciliation did not prove the intended state; no resend.' }
                throw $original
            }
            # Alternate-key indexing is asynchronous; allow propagation before a single exact GET readback.
            if ($payload.Gate -ceq 'KEY') { Start-Sleep -Seconds 30 }
            $null = Assert-ReceiptReadback -Gate $payload.Gate
            $script:Journal.Writes[$script:WriteIndex - 1].State = 'GET_RECONCILED'
            Save-ReceiptJournal
        }
    } elseif ($Mode -ceq 'Reconcile') {
        if ($null -eq $existing) { throw 'Receipt absent; no create is authorized by reconciliation.' }
        $null = Assert-ReceiptReadback -Gate 'KEY'
    } elseif ($null -ne $existing) {
        throw 'Receipt exists; use Reconcile rather than preflight for an absent-table plan.'
    }
    [ordered]@{
        Result = if ($Mode -in @('Apply', 'CompleteReceipt', 'CompleteLookup', 'Reconcile')) { 'OPERATION_RECEIPT_STORAGE_RECONCILED' } else { 'RECEIPT_PREFLIGHT_PASSED' }
        PlanSha256 = $script:PlanHash; CoreManifestSha256 = $script:CoreHash
        CandidateCore = 'EXACT'; PreviousAndNewStatus = 'RETAINED_REPAIR_IDENTITIES_EXACT'
        CandidatePrimaryId = $script:CandidatePrimaryId
        ExecutePrivilegeCandidate = 'prvWriteos_sr_cand'
        OrganizationAuditing = [bool]$audit.isauditenabled
        ReceiptWrites = $planEntries; Requests = $script:RequestCounts; CandidateGET = $script:CandidateGets
        BusinessDataWrites = 0; AppWrites = 0; PublishXml = 0; AutomaticRetries = 0
    } | ConvertTo-Json -Depth 80
} catch {
    [ordered]@{ Result = 'PRE_DEPLOYMENT_GATE_BLOCKED'; Error = Get-SanitizedFailureMessage -Message $_.Exception.Message
        Requests = $script:RequestCounts; CandidateGET = $script:CandidateGets; AutomaticRetries = 0 } | ConvertTo-Json -Depth 8
    throw 'Phase 3C receipt runner stopped; inspect the sanitized result; no automatic retry.'
} finally {
    $script:AccessToken = $null
    [Environment]::SetEnvironmentVariable('BSO_RS_EXPECTED_USER_ID', $null, 'Process')
}
