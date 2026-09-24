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
            # Read the property directly: returned from a function such as Get-MemberValue,
            # a one-item array would unroll to its item and validate as the wrong type.
            ConvertTo-JsonSchemaValidationValue -Value $Value.PSObject.Properties[$propertyName].Value -Result ([ref]$convertedValue)
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
    'minimum', 'minLength', 'maxLength', 'minItems', 'items',
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
    # true and false are complete schemas with no keywords to check.
    if ($null -eq $Schema -or $Schema -is [bool]) {
        return $warnings.ToArray()
    }

    foreach ($name in @(Get-ObjectPropertyNames $Schema)) {
        if ($name -notin $script:SupportedSchemaKeywords) {
            $warnings.Add("$Path uses schema keyword '$name' outside the project compatibility allowlist")
        }
    }

    # Every place a subschema can sit is walked, so a keyword outside the allowlist cannot
    # hide inside a composition branch, a conditional, or a definition nested below the root.
    $children = [System.Collections.Generic.List[object]]::new()
    foreach ($mapKeyword in @('properties', 'patternProperties', 'dependentSchemas', 'dependencies', '$defs', 'definitions')) {
        $map = Get-MemberValue -Object $Schema -Name $mapKeyword
        if ($null -eq $map) { continue }
        foreach ($childName in @(Get-ObjectPropertyNames $map)) {
            $childSchema = Get-MemberValue -Object $map -Name $childName
            # A "dependencies" value can also be a list of property names, which is not a schema.
            if (Test-JsonArrayWrapper $childSchema) { continue }
            $childPath = if ($Path -eq '$' -and $mapKeyword -in @('$defs', 'definitions')) { "$mapKeyword.$childName" } else { "$Path.$mapKeyword.$childName" }
            $children.Add([pscustomobject]@{ Path = $childPath; Schema = $childSchema })
        }
    }
    foreach ($listKeyword in @('allOf', 'anyOf', 'oneOf', 'prefixItems', 'items')) {
        $value = Get-MemberValue -Object $Schema -Name $listKeyword
        if ($null -eq $value -or -not (Test-JsonArrayWrapper $value)) { continue }
        $list = @(Get-JsonArrayItems $value)
        for ($index = 0; $index -lt $list.Count; $index++) {
            $children.Add([pscustomobject]@{ Path = "$Path.$listKeyword[$index]"; Schema = $list[$index] })
        }
    }
    foreach ($singleKeyword in @('items', 'additionalItems', 'additionalProperties', 'unevaluatedItems', 'unevaluatedProperties', 'contains', 'propertyNames', 'contentSchema', 'not', 'if', 'then', 'else')) {
        $value = Get-MemberValue -Object $Schema -Name $singleKeyword
        if ($null -eq $value -or (Test-JsonArrayWrapper $value)) { continue }
        $children.Add([pscustomobject]@{ Path = "$Path.$singleKeyword"; Schema = $value })
    }
    foreach ($child in $children) {
        foreach ($w in @(Test-SchemaKeywordCoverage -Schema $child.Schema -Path $child.Path -RootSchema $RootSchema)) {
            $warnings.Add($w)
        }
    }

    return $warnings.ToArray()
}

function New-SchemaContractError {
    <#
    .SYNOPSIS
    Builds one schema contract error in the JSON Schema output-format shape.
    .PARAMETER Message
    What failed.
    .PARAMETER InstanceLocation
    JSON Pointer to the failing value; empty for the document root, null when the error is
    not about the document (for example an unreadable schema file).
    .PARAMETER KeywordLocation
    JSON Pointer through the schema to the keyword that failed, or null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        # Untyped on purpose: a [string] parameter turns $null into "", which is the pointer
        # to the document root rather than "no location".
        [AllowNull()]$InstanceLocation = $null,
        [AllowNull()]$KeywordLocation = $null
    )

    return [ordered]@{
        instanceLocation = if ($null -eq $InstanceLocation) { $null } else { [string]$InstanceLocation }
        keywordLocation = if ($null -eq $KeywordLocation) { $null } else { [string]$KeywordLocation }
        message = $Message
    }
}

function Get-JsonSchemaEvaluationErrors {
    <#
    .SYNOPSIS
    Evaluates JSON text against a schema file and returns every failing keyword.
    .DESCRIPTION
    Test-Json reduces a failure to one exception string. The JsonSchema.Net evaluator it
    wraps can report each failing node, so this returns one error per failing keyword with
    its instance and keyword locations, sorted so the report is stable between runs. Only
    failing nodes are followed: an anyOf branch that failed while another branch passed
    did not cause the failure and is not reported.
    .PARAMETER SchemaPath
    Absolute path of the schema file.
    .PARAMETER Json
    Document to evaluate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$Json
    )

    if (-not ('Json.Schema.JsonSchema' -as [type])) {
        Add-Type -AssemblyName JsonSchema.Net
    }
    $schema = [Json.Schema.JsonSchema]::FromFile($SchemaPath)
    $options = [Json.Schema.EvaluationOptions]::new()
    $options.OutputFormat = [Json.Schema.OutputFormat]::Hierarchical
    # Off by default, so a date-time of "yesterday" or a uri of "not a uri" passed.
    $options.RequireFormatValidation = $true
    $evaluation = $schema.Evaluate([System.Text.Json.Nodes.JsonNode]::Parse($Json), $options)
    if ($evaluation.IsValid) {
        return @()
    }

    $failures = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push($evaluation)
    while ($pending.Count -gt 0) {
        $node = $pending.Pop()
        # A passing node did not cause the failure, and neither did anything below it.
        if ($null -eq $node -or $node.IsValid) { continue }
        # JsonPointer enumerates its segments, so a [string] cast would join them with
        # spaces; ToString() gives the pointer text.
        $nodePath = $node.EvaluationPath.ToString()
        $instancePath = $node.InstanceLocation.ToString()
        $invalidChildren = @($node.Details | Where-Object { $null -ne $_ -and -not $_.IsValid })
        if ($node.HasErrors) {
            foreach ($entry in $node.Errors.GetEnumerator()) {
                # A false subschema reports its error with an empty keyword: the path already
                # ends at the keyword that held it (for example /additionalProperties).
                $keywordLocation = $nodePath
                if (-not [string]::IsNullOrEmpty([string]$entry.Key)) {
                    $keywordLocation += '/' + (([string]$entry.Key -replace '~', '~0') -replace '/', '~1')
                }
                # The evaluator writes values JSON-encoded. A const failure reads Expected, then
                # the value's JSON text escaped a second time, and a required failure lists its
                # names as JSON. Each is parsed and printed by its structure, never decoded twice:
                # a string const as written (as a JSON string when it holds a control or format
                # character), anything else as JSON without HTML-style escapes.
                $message = [string]$entry.Value
                $relaxed = [System.Text.Json.JsonSerializerOptions]::new()
                $relaxed.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
                try {
                    if ($message -match '^Expected "(?<value>.*)"\z') {
                        $valueJson = [System.Text.Json.JsonDocument]::Parse('"' + $Matches['value'] + '"').RootElement.GetString()
                        $valueElement = [System.Text.Json.JsonDocument]::Parse($valueJson).RootElement
                        $message = if ($valueElement.ValueKind -eq [System.Text.Json.JsonValueKind]::String -and $valueElement.GetString() -notmatch '[\p{Cc}\p{Cf}]') {
                            'Expected "' + $valueElement.GetString() + '"'
                        } else {
                            'Expected ' + [System.Text.Json.JsonSerializer]::Serialize($valueElement, [System.Text.Json.JsonElement], $relaxed)
                        }
                    } elseif ($message -match '^(?<lead>Required properties )(?<names>\[.*\])(?<tail> are not present)\z') {
                        $namesElement = [System.Text.Json.JsonDocument]::Parse($Matches['names']).RootElement
                        $message = $Matches['lead'] + [System.Text.Json.JsonSerializer]::Serialize($namesElement, [System.Text.Json.JsonElement], $relaxed) + $Matches['tail']
                    }
                } catch [System.Text.Json.JsonException] {
                    Write-Verbose "Schema message kept as the evaluator wrote it: $($_.Exception.Message)"
                }
                $failures.Add((New-SchemaContractError -Message $message -InstanceLocation $instancePath -KeywordLocation $keywordLocation))
            }
        } elseif ($invalidChildren.Count -eq 0) {
            # Failing with no message and no failing child: a "not" whose subschema passed.
            $negated = @($node.Details | Where-Object { $null -ne $_ -and $_.EvaluationPath.ToString().EndsWith('/not', [StringComparison]::Ordinal) }) | Select-Object -First 1
            if ($negated) {
                $failures.Add((New-SchemaContractError -Message 'The value matches the schema under "not", which it must not.' -InstanceLocation $instancePath -KeywordLocation $negated.EvaluationPath.ToString()))
            } else {
                $failures.Add((New-SchemaContractError -Message 'The value does not match this schema.' -InstanceLocation $instancePath -KeywordLocation $nodePath))
            }
        }
        foreach ($child in $invalidChildren) {
            $pending.Push($child)
        }
    }
    $sorted = @($failures | Sort-Object `
            @{ Expression = { ConvertTo-OrdinalSortKey $_.instanceLocation } },
            @{ Expression = { ConvertTo-OrdinalSortKey $_.keywordLocation } },
            @{ Expression = { ConvertTo-OrdinalSortKey $_.message } })
    if ($sorted.Count -eq 0) {
        # Invalid with no failing node is not expected; never report a failure with no reason.
        return @(New-SchemaContractError -Message 'The document does not match the schema, and the evaluator reported no failing keyword.' -InstanceLocation '')
    }
    return $sorted
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
    $errors = New-Object System.Collections.Generic.List[object]
    $schema = $null
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $errors.Add((New-SchemaContractError -Message "schema file not found: $SchemaPath"))
    } else {
        try {
            $schema = ConvertFrom-JsonPreservingArrays -Json (Get-Content -LiteralPath $fullPath -Raw)
        } catch {
            $errors.Add((New-SchemaContractError -Message "schema file is unreadable: $($_.Exception.Message)"))
        }
    }

    $keywordWarnings = @()
    if ($schema) {
        $keywordWarnings = @(Test-SchemaKeywordCoverage -Schema $schema)

        if (-not (Test-NativeJsonSchemaAvailable)) {
            $errors.Add((New-SchemaContractError -Message "Test-Json -SchemaFile is unavailable; PowerShell 7.4+ is required."))
        } else {
            try {
                $validationValue = $null
                ConvertTo-JsonSchemaValidationValue -Value $Value -Result ([ref]$validationValue)
                $json = ConvertTo-Json -InputObject $validationValue -Depth 100
                foreach ($schemaError in @(Get-JsonSchemaEvaluationErrors -SchemaPath (Resolve-Path -LiteralPath $fullPath).Path -Json $json)) {
                    $errors.Add($schemaError)
                }
            } catch {
                $errors.Add((New-SchemaContractError -Message $_.Exception.Message))
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
    $projectsParseErrors = New-Object System.Collections.Generic.List[object]
    try {
        if ([string]::IsNullOrWhiteSpace($ProjectsJson)) {
            throw "generated projects feed is empty"
        }
        $projectsPayload = ConvertFrom-JsonPreservingArrays -Json $ProjectsJson
    } catch {
        $projectsParseErrors.Add((New-SchemaContractError -Message "generated projects feed is unreadable: $($_.Exception.Message)"))
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
