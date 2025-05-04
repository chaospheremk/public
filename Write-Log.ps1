function Write-Log {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [string]$Message,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Error')]
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", IgnoreCase = $true)]
        [string]$Level = "INFO",

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

        if ($Metadata -or ($Level -eq 'ERROR')) {
            
            $metadataDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
        }

        # Initialize internal metadata
        if ($Metadata) {

            if ($Metadata -is [hashtable]) {

                # Convert hashtable to a dictionary
                $genDict = ConvertTo-Dictionary -Hashtable $Metadata

                foreach ($key in $genDict.Keys) { $metadataDict[$key] = $genDict[$key] }
            }
            elseif ($Metadata -is [PSCustomObject] -or $Metadata.PSObject.Members.Count -gt 0) {

                # Convert PSObject to a dictionary
                foreach ($prop in $Metadata.PSObject.Properties) { $metadataDict[$prop.Name] = $prop.Value }
            }
            else {

                # If Metadata is not a hashtable or PSObject, treat it as a raw value
                # and store it under a special key
                $metadataDict['RawValue'] = $Metadata
            }
        }

        if($Level -eq 'ERROR') {

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
        [string]$LogPath = "$(Get-Location)\log.jsonl",

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', IgnoreCase = $true)]
        [string[]]$Level,

        [string]$MessageContains,

        [datetime]$Since,

        [datetime]$Until,

        [switch]$Colorize,

        [switch]$ExportCsv,
        
        [string]$CsvPath = "$(Get-Location)\log.csv"
    )

    begin {

        if (-not (Test-Path -Path $LogPath)) {
            
            Write-Warning "Log file not found at path: $LogPath"
            return
        }

        $resultsList = [System.Collections.Generic.List[PSObject]]::new()

        $lines = Get-Content -Path $LogPath
    } # begin

    process {

        foreach ($line in $lines) {

            try { $entry = $line | ConvertFrom-Json }
            catch {

                Write-Warning "Skipping invalid JSON line: $line"
                continue
            }

            $timestampUtc   = [datetime]$entry.UtcTimestamp
            $timestampLocal = $timestampUtc.ToLocalTime()

            if (
                ($Level -and ($entry.Level -notin $Level)) -or
                (-not [string]::IsNullOrWhiteSpace($MessageContains) -and
                    ($entry.Message -notlike "*$MessageContains*")) -or
                ($Since -and $timestampUtc -lt $Since.ToUniversalTime()) -or
                ($Until -and $timestampUtc -gt $Until.ToUniversalTime())
            ) { continue }

            $logObject = [PSCustomObject]@{
                LocalTime = $timestampLocal
                UtcTime   = $timestampUtc
                Level     = $entry.Level
                Message   = $entry.Message
            }

            $resultsList.Add($logObject)

            if ($Colorize) {

                $levelAbbr = switch ($entry.Level.ToUpperInvariant()) {
                    'ERROR' { 'ERR' }
                    'WARN'  { 'WRN' }
                    'INFO'  { 'INF' }
                    'DEBUG' { 'DBG' }
                    default { $entry.Level.Substring(0, [Math]::Min(3, $entry.Level.Length)).ToUpperInvariant() }
                }

                $color = switch ($entry.Level.ToUpperInvariant()) {
                    'ERROR' { 'Red' }
                    'WARN'  { 'Yellow' }
                    'DEBUG' { 'DarkGray' }
                    default { 'Gray' }
                }

                $formatted = "{0} [{1}] {2}" -f $logObject.LocalTime.ToString("yyyy-MM-dd HH:mm:ss"), $levelAbbr, $logObject.Message
                Write-Host $formatted -ForegroundColor $color
            }
        }

        if ($ExportCsv -and ($resultsList.Count -gt 0)) {

            try {

                $resultsList | Export-Csv -Path $CsvPath -NoTypeInformation -Force
                Write-Host "Exported filtered log to: $CsvPath" -ForegroundColor 'Green'
            }
            catch { Write-Warning "Failed to export log to CSV: $_" }
        }

        if ((-not $Colorize) -and (-not $ExportCsv)) { $resultsList }
    }
}