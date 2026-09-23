# JSON Schema contracts for the catalog, feed and report: keyword coverage and
# validation of generated JSON against the committed schemas. Dot-sourced by
# scripts/sync-profile.ps1.

function Test-NativeJsonSchemaAvailable {
    $command = Get-Command Test-Json -ErrorAction SilentlyContinue
    return [bool]($command -and $command.Parameters.ContainsKey("SchemaFile"))
}

function ConvertTo-JsonSchemaValidationValue {
    param(
        [object]$Value,
        [ref]$Result
    )

    if ($null -eq $Value) {
        $Result.Value = $null
        return
    }

    if (Test-JsonArrayWrapper $Value) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value.Items) {
            $convertedItem = $null
            ConvertTo-JsonSchemaValidationValue -Value $item -Result ([ref]$convertedItem)
            $items.Add($convertedItem)
        }
        $Result.Value = [object[]]$items.ToArray()
        return
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $hash = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $convertedValue = $null
            ConvertTo-JsonSchemaValidationValue -Value $Value[$key] -Result ([ref]$convertedValue)
            $hash[[string]$key] = $convertedValue
        }
        $Result.Value = $hash
        return
    }

    if ($Value -is [string] -or $Value -is [datetime] -or $Value -is [datetimeoffset] -or
        $Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or
        $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        $Result.Value = $Value
        return
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $convertedItem = $null
            ConvertTo-JsonSchemaValidationValue -Value $item -Result ([ref]$convertedItem)
            $items.Add($convertedItem)
        }
        $Result.Value = [object[]]$items.ToArray()
        return
    }

    $propertyNames = @(Get-ObjectPropertyNames $Value)
    if ($propertyNames.Count -gt 0) {
        $hash = [ordered]@{}
        foreach ($propertyName in $propertyNames) {
            $convertedValue = $null
            ConvertTo-JsonSchemaValidationValue -Value (Get-MemberValue -Object $Value -Name $propertyName) -Result ([ref]$convertedValue)
            $hash[$propertyName] = $convertedValue
        }
        $Result.Value = $hash
        return
    }

    $Result.Value = $Value
}

$script:SupportedSchemaKeywords = @(
    '$schema', '$id', '$ref', '$defs', 'definitions',
    'title', 'description',
    'type', 'const', 'enum', 'format', 'pattern',
    'minimum', 'minLength', 'minItems', 'items',
    'required', 'properties', 'additionalProperties'
)

function Test-SchemaKeywordCoverage {
    param(
        [object]$Schema,
        [string]$Path = '$',
        [object]$RootSchema = $null
    )

    if ($null -eq $RootSchema) { $RootSchema = $Schema }
    $warnings = New-Object System.Collections.Generic.List[string]

    foreach ($name in @(Get-ObjectPropertyNames $Schema)) {
        if ($name -notin $script:SupportedSchemaKeywords) {
            $warnings.Add("$Path uses schema keyword '$name' outside the project compatibility allowlist")
        }
    }

    $properties = Get-MemberValue -Object $Schema -Name "properties"
    if ($properties) {
        foreach ($propName in @(Get-ObjectPropertyNames $properties)) {
            $propSchema = Get-MemberValue -Object $properties -Name $propName
            if ($propSchema) {
                foreach ($w in @(Test-SchemaKeywordCoverage -Schema $propSchema -Path "$Path.properties.$propName" -RootSchema $RootSchema)) {
                    $warnings.Add($w)
                }
            }
        }
    }

    $items = Get-MemberValue -Object $Schema -Name "items"
    if ($items) {
        foreach ($w in @(Test-SchemaKeywordCoverage -Schema $items -Path "$Path.items" -RootSchema $RootSchema)) {
            $warnings.Add($w)
        }
    }

    $defs = Get-MemberValue -Object $Schema -Name '$defs'
    if (-not $defs) { $defs = Get-MemberValue -Object $Schema -Name 'definitions' }
    if ($defs -and $Path -eq '$') {
        foreach ($defName in @(Get-ObjectPropertyNames $defs)) {
            $defSchema = Get-MemberValue -Object $defs -Name $defName
            if ($defSchema) {
                foreach ($w in @(Test-SchemaKeywordCoverage -Schema $defSchema -Path "`$defs.$defName" -RootSchema $RootSchema)) {
                    $warnings.Add($w)
                }
            }
        }
    }

    return $warnings.ToArray()
}

function Test-JsonSchemaContract {
    <#
    .SYNOPSIS
    Validates a JSON-shaped value against a repository JSON Schema file.
    .PARAMETER Value
    Object graph to validate after converting preserved JSON arrays back to arrays.
    .PARAMETER SchemaPath
    Absolute or repository-relative schema file path.
    #>
    [CmdletBinding()]
    param(
        [object]$Value,
        [string]$SchemaPath
    )

    $fullPath = if ([System.IO.Path]::IsPathRooted($SchemaPath)) { $SchemaPath } else { Join-Path $RepoRoot $SchemaPath }
    $errors = New-Object System.Collections.Generic.List[string]
    $schema = $null
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $errors.Add("schema file not found: $SchemaPath")
    } else {
        try {
            $schema = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $fullPath -Raw)
        } catch {
            $errors.Add("schema file is unreadable: $($_.Exception.Message)")
        }
    }

    $keywordWarnings = @()
    if ($schema) {
        $keywordWarnings = @(Test-SchemaKeywordCoverage -Schema $schema)

        $testJsonCommand = Get-Command Test-Json -ErrorAction SilentlyContinue
        if (-not $testJsonCommand -or -not $testJsonCommand.Parameters.ContainsKey("SchemaFile")) {
            $errors.Add("Test-Json -SchemaFile is unavailable; PowerShell 7.4+ is required.")
        } else {
            try {
                $validationValue = $null
                ConvertTo-JsonSchemaValidationValue -Value $Value -Result ([ref]$validationValue)
                $json = ConvertTo-Json -InputObject $validationValue -Depth 100
                $null = Test-Json -Json $json -SchemaFile $fullPath -ErrorAction Stop
            } catch {
                $errors.Add($_.Exception.Message)
            }
        }
    }

    $resolvedSchemaPath = Resolve-Path -LiteralPath $fullPath -ErrorAction SilentlyContinue
    $schemaPathForReport = if ($resolvedSchemaPath) {
        ([System.IO.Path]::GetRelativePath($RepoRoot, $resolvedSchemaPath.Path) -replace '\\', '/')
    } else {
        $SchemaPath
    }

    return [ordered]@{
        schemaPath = [string]$schemaPathForReport
        schemaId = if ($schema) { Get-MemberValue -Object $schema -Name '$id' } else { $null }
        valid = [bool]($errors.Count -eq 0)
        errors = $errors.ToArray()
        unsupportedKeywords = $keywordWarnings
    }
}

function Test-FeedSchemaContracts {
    <#
    .SYNOPSIS
    Validates catalog and projects feed schema contracts together.
    .PARAMETER Catalog
    Normalized profile catalog returned by Get-Catalog.
    .PARAMETER ProjectsJson
    Generated projects.json text to parse and validate.
    #>
    [CmdletBinding()]
    param(
        [hashtable]$Catalog,
        [string]$ProjectsJson
    )

    $projectsPayload = $null
    $projectsParseErrors = New-Object System.Collections.Generic.List[string]
    try {
        if ([string]::IsNullOrWhiteSpace($ProjectsJson)) {
            throw "generated projects feed is empty"
        }
        $projectsPayload = ConvertFrom-JsonPreservingArrays -Json $ProjectsJson
    } catch {
        $projectsParseErrors.Add("generated projects feed is unreadable: $($_.Exception.Message)")
    }

    $catalogResult = Test-JsonSchemaContract -Value $Catalog -SchemaPath $CatalogSchemaPath
    $projectsResult = if ($projectsPayload) {
        Test-JsonSchemaContract -Value $projectsPayload -SchemaPath $ProjectsSchemaPath
    } else {
        [ordered]@{
            schemaPath = "schemas/profile-projects.v1.json"
            schemaId = $ProjectsSchemaUrl
            valid = $false
            errors = $projectsParseErrors.ToArray()
            unsupportedKeywords = @()
        }
    }

    return [ordered]@{
        passed = [bool]($catalogResult.valid -and $projectsResult.valid)
        catalog = $catalogResult
        projects = $projectsResult
    }
}
