# Get a list of all domain controllers
$DCs = (Get-ADDomainController -Filter *).Hostname

# Event ID 4624 with NTLMv1 is indicated by Authentication Package = NTLM and LmPackageName = NTLM V1
$filterHashTable = @{
    LogName   = 'Security'
    ID        = 4624
    StartTime = (Get-Date).AddDays(-7)  # Adjust the timeframe as needed
}

foreach ($DC in $DCs) {
    Write-Host "Checking NTLMv1 logons on $DC..." -ForegroundColor Cyan

    try {
        $events = Get-WinEvent -ComputerName $DC -FilterHashtable $filterHashTable -ErrorAction Stop |
            Where-Object {
                ([xml]$_.ToXml()).Event.EventData.Data | Where-Object {
                    $_.'#text' -match 'NTLM V1'
                }
            }

        foreach ($event in $events) {
            $xml = [xml]$event.ToXml()
            $timeCreated = $xml.Event.System.TimeCreated.SystemTime
            $userName = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
            $ipAddress = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'IpAddress' }).'#text'

            [PSCustomObject]@{
                DomainController = $DC
                TimeCreated      = $timeCreated
                UserName         = $userName
                IPAddress        = $ipAddress
            }
        }

        if (-not $events) {
            Write-Host "No NTLMv1 logons found on $DC." -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Failed to query $DC`: $_"
    }
}
