function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", IgnoreCase = $true)]
        [string]$Level = "INFO",

        [string]$LogPath = "$(Get-Location)\log.jsonl"
    )

    begin {

        $logDirectory = Split-Path -Parent $LogPath

        if (-not (Test-Path -Path $logDirectory)) {

            $null = New-Item -ItemType Directory -Path $logDirectory -Force
        }
    }

    process {

        $logEntry = @{
            UtcTimestamp = (Get-Date).ToUniversalTime().ToString("o")
            Level        = $Level.ToUpperInvariant()
            Message      = $Message
        }

        $logEntryJson = $logEntry | ConvertTo-Json -Compress

        try { Add-Content -Path $LogPath -Value $logEntryJson }
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