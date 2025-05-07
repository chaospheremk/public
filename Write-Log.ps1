function Write-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Default', Position = 0)]
        [Parameter(ParameterSetName = 'Error', Position = 0)]
        [string]$Message,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", IgnoreCase = $true)]
        [string]$Level = "INFO",

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [string]$CorrelationId = (New-Guid).Guid,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [string]$LogPath = "$(Get-Location)\log.jsonl",

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [PSObject]$Metadata,

        [Parameter(Mandatory, ParameterSetName = 'Error')]
        [System.Management.Automation.ErrorRecord]$ErrorObject
    )

    begin {

        $utcNow = (Get-Date).ToUniversalTime().ToString('o')

        $logDirectory = Split-Path -Parent $LogPath

        if (-not (Test-Path -Path $logDirectory)) {

            $null = New-Item -ItemType Directory -Path $logDirectory -Force
        }
    }

    process {

        # Create the main log entry using a generic dictionary
        $logEntry = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        $logEntry['UtcTimestamp'] = $utcNow
        $logEntry['Level'] = $Level.ToUpperInvariant()
        $logEntry['Message'] = $Message
        $logEntry['CorrelationId'] = $CorrelationId

        if ($Metadata -or ($Level -eq 'ERROR')) {
            
            $metadataDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        }

        # Initialize internal metadata
        if ($Metadata) {

            if ($Metadata -is [hashtable]) { $metadataDict = ConvertTo-Dictionary -Hashtable $Metadata }
            elseif ($Metadata -is [PSCustomObject]) {

                # Convert PSObject to a dictionary
                $noteProperties = ($Metadata.PSObject.Properties).Where({ $_.MemberType -eq 'NoteProperty'})
                
                foreach ($prop in $noteProperties) { $metadataDict[$prop.Name] = $prop.Value }
            }
            else {

                # If Metadata is not a hashtable or PSObject, throw error
                throw "Metadata must be a hashtable or PSObject. Received: $($Metadata.GetType().FullName)"
            }
        }

        if ($Level -eq 'ERROR') {

            $errorDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            $invocationInfo = $ErrorObject.InvocationInfo

            if ($invocationInfo) {

                $scriptLineNumber = $invocationInfo.ScriptLineNumber

                $errorScriptName = if ([string]::IsNullOrEmpty($invocationInfo.ScriptName)) { $null }
                else { $invocationInfo.ScriptName }

                $errorLineNumber = if ($scriptLineNumber -gt 0) { $scriptLineNumber }
                else { $null }

                $errorCommandName = if ($invocationInfo.MyCommand) { $invocationInfo.MyCommand.Name }
                else { $null }

                $errorCommand = if ([string]::IsNullOrEmpty($errorCommandName)) { $null }
                else { $errorCommandName }
                
                $errorPosition = if ([string]::IsNullOrEmpty($invocationInfo.PositionMessage)) { $null }
                else { ($invocationInfo.PositionMessage -split "\n")[0] }
            }

            if ($ErrorObject.Exception) {

                $errorMessage = if ([string]::IsNullOrEmpty($ErrorObject.Exception.Message)) { $null }
                                else { $ErrorObject.Exception.Message }

                $errorType = $ErrorObject.Exception.GetType().FullName
            }

            $errorDict['ScriptName'] = $errorScriptName
            $errorDict['LineNumber'] = $errorLineNumber
            $errorDict["Command"] = $errorCommand
            $errorDict["PositionMessage"] = $errorPosition
            $errorDict['Type'] = $errorType
            $errorDict['Message'] = $errorMessage
            
            $metadataDict['Error'] = $errorDict
        }

        if ($metadataDict.Count -gt 0) { $logEntry['Metadata'] = $metadataDict }

        try {

            $logEntryJson = $logEntry | ConvertTo-Json -Compress -Depth 5
            Add-Content -Path $LogPath -Value $logEntryJson -Encoding UTF8
        }
        catch { Write-Warning "Failed to write log entry to '$LogPath': $_" }
    }
}

function Read-Log {
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName = 'Default')]
        [string]$LogPath = "$(Get-Location)\log.jsonl",

        [Parameter(ParameterSetName = 'Default')]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', IgnoreCase = $true)]
        [string[]]$Level,

        [Parameter(ParameterSetName = 'Default')]
        [string]$MessageContains,

        [Parameter(ParameterSetName = 'Default')]
        [datetime]$Since,

        [Parameter(ParameterSetName = 'Default')]
        [datetime]$Until,

        [Parameter(ParameterSetName = 'Default')]
        [switch]$Colorize,

        [Parameter(ParameterSetName = 'Default')]
        [switch]$ExportCsv,
        
        [Parameter(ParameterSetName = 'Default')]
        [string]$CsvPath = "$(Get-Location)\log.csv"
    )

    begin {

        if (-not (Test-Path -Path $LogPath)) {
            
            Write-Warning "Log file not found at path: $LogPath"
            return
        }

        $resultsList = [System.Collections.Generic.List[PSObject]]::new()
        $dictList = [System.Collections.Generic.List[System.Collections.Generic.Dictionary[string, PSObject]]]::new()
        $allKeys = [System.Collections.Generic.HashSet[string]]::new()

        $lines = Get-Content -Path $LogPath
    } # begin

    process {

        foreach ($line in $lines) {

            # skip line if it is not a valid JSON object, warn
            try {

                $entry = $line | ConvertFrom-Json -Depth 5

                $entryLevel = $entry.Level.ToUpperInvariant()
                $entryMessage = $entry.Message
                $entryCorrelationId = $entry.CorrelationId
            }
            catch {

                Write-Warning "Skipping invalid JSON line: $line"
                continue
            }

            # skip line if timestamp is not valid, warn
            try { $timestampUtc = [datetime]$entry.UtcTimestamp }
            catch {

                Write-Warning "Skipping log line with invalid timestamp: $($entry.UtcTimestamp)"
                continue
            }

            # skip line if Level or Message is not valid, warn
            if ((-not $entryLevel) -or (-not $entryMessage)) {

                Write-Warning "Skipping log line due to missing Level or Message field."
                continue
            }

            $timestampLocal = $timestampUtc.ToLocalTime()

            # filtering block
            if (
                ($Level -and ($entryLevel -notin $Level)) -or
                ($MessageContains -and ($entryMessage -notlike "*$MessageContains*")) -or
                ($Since -and ($timestampUtc -lt $Since.ToUniversalTime())) -or
                ($Until -and ($timestampUtc -gt $Until.ToUniversalTime()))
            ) { continue }

            # Use dictionary for efficient property assignment and access
            $logDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
            $logDict['LocalTime'] = $timestampLocal
            $logDict['UtcTime'] = $timestampUtc
            $logDict['Level'] = $entryLevel
            $logDict['Message'] = $entryMessage
            $logDict['CorrelationId'] = $entryCorrelationId

            # Flatten metadata if it exists
            if ($entry.Metadata) {

                foreach ($metaKey in $entry.Metadata.PSObject.Properties.Name) {

                    $metaValue = $entry.Metadata.$metaKey

                    if (($metaValue -is [PSObject]) -and ($metaValue.PSObject.Properties.Count -gt 0)) {

                        foreach ($subKey in $metaValue.PSObject.Properties.Name) {
                            
                            $logDict["$metaKey$subKey"] = $metaValue.$subKey
                        }
                    }
                    else { $logDict[$metaKey] = $metaValue }
                }
            }

            $null = $allKeys.UnionWith($logDict.Keys)
            $dictList.Add($logDict)

            if ($Colorize) {

                $levelAbbr = switch ($entryLevel) {

                    'DEBUG' { 'DBG' }
                    'ERROR' { 'ERR' }
                    'INFO' { 'INF' }
                    'WARN' { 'WRN' }
                }

                $color = switch ($entryLevel) {

                    'DEBUG' { 'DarkGray' }
                    'ERROR' { 'Red' }
                    'INFO' { 'Gray' }
                    'WARN' { 'Yellow' }
                }

                $formatted = "{0} [{1}] {2}" -f $logDict["LocalTime"].ToString("yyyy-MM-dd HH:mm:ss"), $levelAbbr, $logDict['Message']
                Write-Host $formatted -ForegroundColor $color
            }
        }

        # Normalize and convert to PSObjects
        foreach ($dict in $dictList) {

            foreach ($key in $allKeys) { if (-not $dict.ContainsKey($key)) { $dict[$key] = $null } }

            # Convert to ordered hashtable to preserve column order
            $orderedHashtable = [ordered]@{}
            foreach ($key in $allKeys) { $orderedHashtable[$key] = $dict[$key] }

            $resultsList.Add([PSCustomObject]$orderedHashtable)
        }

        if ($ExportCsv -and ($resultsList.Count -gt 0)) {

            try {

                $resultsList | Export-Csv -Path $CsvPath -NoTypeInformation -Force
                Write-Host "Exported filtered log to: $CsvPath" -ForegroundColor 'Green'
            }
            catch { Write-Warning "Failed to export log to CSV: $_" }
        }

        if ((-not $Colorize) -and (-not $ExportCsv)) { $resultsList }
    } # process
}