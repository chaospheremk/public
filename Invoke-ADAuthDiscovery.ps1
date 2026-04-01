#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Discovers Active Directory authentication and service dependencies on a domain controller.

.DESCRIPTION
    Comprehensive discovery tool that collects authentication events, DNS queries, service principals,
    and client activity from a domain controller. Designed for forward-looking data collection to
    identify applications and devices that must be migrated before decommissioning Active Directory.
    
    Collects:
    - LDAP/LDAPS bind activity
    - Kerberos authentication (TGT and service tickets)
    - NTLM authentication
    - DNS query patterns
    - Service Principal Names and usage
    - Service account activity
    - SMB/file share access
    - Client inventory with reverse DNS

.PARAMETER CollectionStartTime
    DateTime to begin collecting events. Defaults to 24 hours ago.

.PARAMETER CollectionEndTime
    DateTime to stop collecting events. Defaults to current time.

.PARAMETER OutputPath
    Directory for output files. Defaults to C:\ADDiscovery

.PARAMETER EnableDnsDebugLogging
    Enable DNS debug logging if not already enabled. Required for DNS client discovery.

.PARAMETER MaxDnsLogSizeMB
    Maximum DNS debug log size in MB. Default 500MB.

.PARAMETER IncludeComputerAccounts
    Include computer account authentications in results. Default $false to focus on service/user accounts.

.EXAMPLE
    .\Invoke-ADAuthDiscovery.ps1 -CollectionStartTime (Get-Date).AddDays(-7)
    
    Collects all authentication data from the past 7 days.

.EXAMPLE
    .\Invoke-ADAuthDiscovery.ps1 -EnableDnsDebugLogging -MaxDnsLogSizeMB 1000
    
    Enables DNS debug logging and collects data from past 24 hours.

.NOTES
    Run this script on each domain controller separately. Aggregate results from all DCs for
    complete environment visibility. 
    
    Performance: Designed for DCs processing millions of events. Uses efficient data structures
    and minimal memory allocation.
    
    Requires: Administrative rights, PowerShell 7, DNS Server role
#>

[CmdletBinding()]
param(
    [Parameter()]
    [datetime]$CollectionStartTime = (Get-Date).AddDays(-1),
    
    [Parameter()]
    [datetime]$CollectionEndTime = (Get-Date),
    
    [Parameter()]
    [string]$OutputPath = 'C:\ADDiscovery',
    
    [Parameter()]
    [switch]$EnableDnsDebugLogging,
    
    [Parameter()]
    [int]$MaxDnsLogSizeMB = 500,
    
    [Parameter()]
    [switch]$IncludeComputerAccounts
)

#region Helper Functions

function Initialize-DiscoveryEnvironment {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [switch]$EnableDnsDebugLogging,
        [int]$MaxDnsLogSizeMB
    )
    
    # Create output directory
    if (-not (Test-Path -Path $OutputPath)) {
        $null = New-Item -Path $OutputPath -ItemType Directory -Force
    }
    
    # Enable DNS debug logging if requested
    if ($EnableDnsDebugLogging) {
        Write-Host "Configuring DNS debug logging..."
        
        $dnsServerSettings = Get-DnsServerDiagnostics
        if (-not $dnsServerSettings.EnableLoggingToFile) {
            Set-DnsServerDiagnostics -EnableLoggingToFile $true `
                                      -LogFilePath "$env:SystemRoot\System32\dns\dns.log" `
                                      -MaxMBFileSize $MaxDnsLogSizeMB `
                                      -Queries $true `
                                      -QueryErrors $true `
                                      -FullPackets $false `
                                      -WriteThrough $true
            
            Write-Host "DNS debug logging enabled. Log file: $env:SystemRoot\System32\dns\dns.log" -ForegroundColor Green
        } else {
            Write-Host "DNS debug logging already enabled." -ForegroundColor Yellow
        }
    }
    
    # Check critical event log sizes
    $criticalLogs = @('Security', 'Directory Service', 'DNS Server')
    foreach ($logName in $criticalLogs) {
        $log = Get-WinEvent -ListLog $logName -ErrorAction SilentlyContinue
        if ($log) {
            $sizeMB = [math]::Round($log.MaximumSizeInBytes / 1MB, 0)
            if ($sizeMB -lt 512) {
                Write-Warning "$logName log size is ${sizeMB}MB. Consider increasing to 1GB+ for comprehensive discovery."
            }
        }
    }
}

function Get-LdapBindActivity {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,
        [datetime]$EndTime,
        [switch]$ExcludeComputers
    )
    
    Write-Host "Collecting LDAP bind activity..."
    
    $ldapBinds = [System.Collections.Generic.List[PSObject]]::new()
    $uniqueClients = [System.Collections.Generic.Dictionary[string,int]]::new()
    
    # Event 2889 - Unsigned LDAP binds (security concern)
    $filterHash = @{
        LogName = 'Directory Service'
        ID = 2889
        StartTime = $StartTime
        EndTime = $EndTime
    }
    
    $winEvents = Get-WinEvent -FilterHashtable $filterHash -ErrorAction SilentlyContinue
    if ($winEvents) {
        foreach ($winEvent in $winEvents) {
            $message = $winEvent.Message
            
            # Parse client IP from message
            if ($message -match 'The following client performed a SASL \(Negotiate/Kerberos/NTLM/Digest\) LDAP bind without requesting signing.*?Client IP address:\s*([^\s]+)') {
                $clientIP = $Matches[1]
                
                if ($uniqueClients.ContainsKey($clientIP)) {
                    $uniqueClients[$clientIP]++
                } else {
                    $uniqueClients[$clientIP] = 1
                }
            }
        }
    }
    
    # Convert to output objects
    foreach ($kvp in $uniqueClients.GetEnumerator()) {
        $ldapBinds.Add([PSCustomObject]@{
            ClientIP = $kvp.Key
            UnsignedBindCount = $kvp.Value
            ClientHostname = (Resolve-DnsNameSafe -IPAddress $kvp.Key)
            BindType = 'Unsigned'
        })
    }
    
    Write-Host "  Found $($uniqueClients.Count) unique clients performing LDAP binds" -ForegroundColor Cyan
    
    return $ldapBinds
}

function Get-KerberosActivity {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,
        [datetime]$EndTime,
        [switch]$ExcludeComputers
    )
    
    Write-Host "Collecting Kerberos activity..."
    
    $tgtRequests = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    $serviceTickets = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    
    # Event 4768 - TGT requests
    $filterHash = @{
        LogName = 'Security'
        ID = 4768
        StartTime = $StartTime
        EndTime = $EndTime
    }
    
    $winEvents = Get-WinEvent -FilterHashtable $filterHash -ErrorAction SilentlyContinue
    if ($winEvents) {
        foreach ($winEvent in $winEvents) {
            $xml = [xml]$winEvent.ToXml()
            $eventData = $xml.Event.EventData.Data
            
            $accountName = ($eventData.Where({ $_.Name -eq 'TargetUserName' }).'#text')
            $clientIP = ($eventData.Where({ $_.Name -eq 'IpAddress' }).'#text')
            
            # Skip computer accounts if requested
            if ($ExcludeComputers -and $accountName -like '*$') {
                continue
            }
            
            $key = "$accountName|$clientIP"
            if ($tgtRequests.TryGetValue($key, [ref]$null)) {
                $tgtRequests[$key].Count++
            } else {
                $tgtRequests[$key] = [PSCustomObject]@{
                    AccountName = $accountName
                    ClientIP = $clientIP
                    ClientHostname = $null
                    Count = 1
                    AuthType = 'Kerberos-TGT'
                }
            }
        }
    }
    
    # Event 4769 - Service ticket requests (reveals SPNs being accessed)
    $filterHash = @{
        LogName = 'Security'
        ID = 4769
        StartTime = $StartTime
        EndTime = $EndTime
    }
    
    $winEvents = Get-WinEvent -FilterHashtable $filterHash -ErrorAction SilentlyContinue
    if ($winEvents) {
        foreach ($winEvent in $winEvents) {
            $xml = [xml]$winEvent.ToXml()
            $eventData = $xml.Event.EventData.Data
            
            $accountName = ($eventData.Where({ $_.Name -eq 'TargetUserName' }).'#text')
            $serviceName = ($eventData.Where({ $_.Name -eq 'ServiceName' }).'#text')
            $clientIP = ($eventData.Where({ $_.Name -eq 'IpAddress' }).'#text')
            
            # Filter out common noise (krbtgt, computer accounts if requested)
            if ($serviceName -like 'krbtgt/*' -or ($ExcludeComputers -and $accountName -like '*$')) {
                continue
            }
            
            $key = "$accountName|$serviceName|$clientIP"
            if ($serviceTickets.TryGetValue($key, [ref]$null)) {
                $serviceTickets[$key].Count++
            } else {
                $serviceTickets[$key] = [PSCustomObject]@{
                    AccountName = $accountName
                    ServiceName = $serviceName
                    ClientIP = $clientIP
                    ClientHostname = $null
                    Count = 1
                    AuthType = 'Kerberos-ServiceTicket'
                }
            }
        }
    }
    
    Write-Host "  Found $($tgtRequests.Count) unique TGT requests, $($serviceTickets.Count) unique service tickets" -ForegroundColor Cyan
    
    # Combine and resolve hostnames
    $allKerberos = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($ticket in $tgtRequests.Values) {
        $ticket.ClientHostname = Resolve-DnsNameSafe -IPAddress $ticket.ClientIP
        $allKerberos.Add($ticket)
    }
    foreach ($ticket in $serviceTickets.Values) {
        $ticket.ClientHostname = Resolve-DnsNameSafe -IPAddress $ticket.ClientIP
        $allKerberos.Add($ticket)
    }
    
    return $allKerberos
}

function Get-NtlmActivity {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,
        [datetime]$EndTime,
        [switch]$ExcludeComputers
    )
    
    Write-Host "Collecting NTLM activity..."
    
    $ntlmAuth = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    
    # Event 4776 - NTLM authentication
    $filterHash = @{
        LogName = 'Security'
        ID = 4776
        StartTime = $StartTime
        EndTime = $EndTime
    }
    
    $winEvents = Get-WinEvent -FilterHashtable $filterHash -ErrorAction SilentlyContinue
    if ($winEvents) {
        foreach ($winEvent in $winEvents) {
            $xml = [xml]$winEvent.ToXml()
            $eventData = $xml.Event.EventData.Data
            
            $accountName = ($eventData.Where({ $_.Name -eq 'TargetUserName' }).'#text')
            $workstation = ($eventData.Where({ $_.Name -eq 'Workstation' }).'#text')
            
            if ($ExcludeComputers -and $accountName -like '*$') {
                continue
            }
            
            $key = "$accountName|$workstation"
            if ($ntlmAuth.TryGetValue($key, [ref]$null)) {
                $ntlmAuth[$key].Count++
            } else {
                $ntlmAuth[$key] = [PSCustomObject]@{
                    AccountName = $accountName
                    SourceWorkstation = $workstation
                    Count = 1
                    AuthType = 'NTLM'
                }
            }
        }
    }
    
    Write-Host "  Found $($ntlmAuth.Count) unique NTLM authentication sources" -ForegroundColor Cyan
    
    return [System.Collections.Generic.List[PSObject]]::new($ntlmAuth.Values)
}

function Get-DnsQueryActivity {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    
    Write-Host "Collecting DNS query activity..."
    
    $dnsLogPath = "$env:SystemRoot\System32\dns\dns.log"
    if (-not (Test-Path $dnsLogPath)) {
        Write-Warning "DNS debug log not found at $dnsLogPath. Enable DNS debug logging first."
        return [System.Collections.Generic.List[PSObject]]::new()
    }
    
    $clientQueries = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    $adRelatedQueries = [System.Collections.Generic.Dictionary[string,int]]::new()
    
    # Parse DNS log (format: date time thread context packet_id protocol send/recv remote_ip [...] query_type query_name)
    $content = Get-Content -Path $dnsLogPath -Tail 100000 -ErrorAction SilentlyContinue
    if ($content) {
        foreach ($line in $content) {
            # Skip headers and blank lines
            if ($line -match '^\s*$' -or $line -match '^#' -or $line -notmatch '^\d{1,2}/\d{1,2}/\d{4}') {
                continue
            }
            
            # Parse log line (simplified - full parsing is complex due to varying formats)
            $parts = $line -split '\s+'
            if ($parts.Count -lt 10) { continue }
            
            # Extract client IP (typically field 8 or 9 depending on format)
            $clientIP = $null
            foreach ($part in $parts[7..9]) {
                if ($part -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                    $clientIP = $part
                    break
                }
            }
            
            if (-not $clientIP) { continue }
            
            # Check for AD-related queries (_ldap, _kerberos, _gc, _msdcs)
            $queryName = $parts[-1]
            if ($queryName -match '_ldap|_kerberos|_gc|_msdcs|_kpasswd') {
                $key = "$clientIP|$queryName"
                if ($adRelatedQueries.TryGetValue($key, [ref]$null)) {
                    $adRelatedQueries[$key]++
                } else {
                    $adRelatedQueries[$key] = 1
                }
            }
            
            # Track unique clients
            if ($clientQueries.TryGetValue($clientIP, [ref]$null)) {
                $clientQueries[$clientIP].QueryCount++
            } else {
                $clientQueries[$clientIP] = [PSCustomObject]@{
                    ClientIP = $clientIP
                    ClientHostname = $null
                    QueryCount = 1
                    ADRelatedQueries = 0
                }
            }
        }
        
        # Add AD-related query counts to client objects
        foreach ($kvp in $adRelatedQueries.GetEnumerator()) {
            $parts = $kvp.Key -split '\|'
            $clientIP = $parts[0]
            if ($clientQueries.TryGetValue($clientIP, [ref]$null)) {
                $clientQueries[$clientIP].ADRelatedQueries += $kvp.Value
            }
        }
        
        # Resolve hostnames
        foreach ($client in $clientQueries.Values) {
            $client.ClientHostname = Resolve-DnsNameSafe -IPAddress $client.ClientIP
        }
    }
    
    Write-Host "  Found $($clientQueries.Count) unique DNS clients, $($adRelatedQueries.Count) AD-related queries" -ForegroundColor Cyan
    
    return [System.Collections.Generic.List[PSObject]]::new($clientQueries.Values)
}

function Get-ServicePrincipalInventory {
    [CmdletBinding()]
    param()
    
    Write-Host "Collecting Service Principal Names inventory..."
    
    $spnList = [System.Collections.Generic.List[PSObject]]::new()
    
    # Query AD for all objects with SPNs
    $searcher = [ADSISearcher]::new()
    $searcher.Filter = '(servicePrincipalName=*)'
    $searcher.PropertiesToLoad.AddRange(@('servicePrincipalName', 'sAMAccountName', 'cn', 'whenCreated', 'pwdLastSet'))
    $searcher.PageSize = 1000
    
    $results = $searcher.FindAll()
    
    foreach ($result in $results) {
        $account = $result.Properties['samaccountname'][0]
        $spns = $result.Properties['serviceprincipalname']
        
        foreach ($spn in $spns) {
            $spnList.Add([PSCustomObject]@{
                ServicePrincipalName = $spn
                AccountName = $account
                AccountType = if ($account -like '*$') { 'Computer' } else { 'User/Service' }
                Created = if ($result.Properties['whencreated'].Count -gt 0) { 
                    [datetime]$result.Properties['whencreated'][0] 
                } else { $null }
            })
        }
    }
    
    $results.Dispose()
    $searcher.Dispose()
    
    Write-Host "  Found $($spnList.Count) Service Principal Names" -ForegroundColor Cyan
    
    return $spnList
}

function Get-ServiceAccountActivity {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    
    Write-Host "Collecting service account activity..."
    
    $serviceLogons = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    
    # Event 4624 - Logon events, filter for service logons (Type 5) and network logons (Type 3)
    $filterHash = @{
        LogName = 'Security'
        ID = 4624
        StartTime = $StartTime
        EndTime = $EndTime
    }
    
    $winEvents = Get-WinEvent -FilterHashtable $filterHash -ErrorAction SilentlyContinue
    if ($winEvents) {
        foreach ($winEvent in $winEvents) {
            $xml = [xml]$winEvent.ToXml()
            $eventData = $xml.Event.EventData.Data
            
            $logonType = ($eventData.Where({ $_.Name -eq 'LogonType' }).'#text')
            
            # Only interested in service (5) and network (3) logons
            if ($logonType -notin @('3', '5')) {
                continue
            }
            
            $accountName = ($eventData.Where({ $_.Name -eq 'TargetUserName' }).'#text')
            $workstation = ($eventData.Where({ $_.Name -eq 'WorkstationName' }).'#text')
            $sourceIP = ($eventData.Where({ $_.Name -eq 'IpAddress' }).'#text')
            
            # Skip system accounts
            if ($accountName -in @('SYSTEM', 'LOCAL SERVICE', 'NETWORK SERVICE', 'ANONYMOUS LOGON', '-')) {
                continue
            }
            
            $key = "$accountName|$logonType|$sourceIP"
            if ($serviceLogons.TryGetValue($key, [ref]$null)) {
                $serviceLogons[$key].Count++
            } else {
                $serviceLogons[$key] = [PSCustomObject]@{
                    AccountName = $accountName
                    LogonType = switch ($logonType) {
                        '3' { 'Network' }
                        '5' { 'Service' }
                        default { $logonType }
                    }
                    SourceIP = $sourceIP
                    Workstation = $workstation
                    Count = 1
                }
            }
        }
    }
    
    Write-Host "  Found $($serviceLogons.Count) unique service/network logon patterns" -ForegroundColor Cyan
    
    return [System.Collections.Generic.List[PSObject]]::new($serviceLogons.Values)
}

function Get-SmbAccessActivity {
    [CmdletBinding()]
    param(
        [datetime]$StartTime,
        [datetime]$EndTime
    )
    
    Write-Host "Collecting SMB/file share access activity..."
    
    $smbAccess = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    
    # Event 5140 - Share accessed
    $filterHash = @{
        LogName = 'Security'
        ID = 5140
        StartTime = $StartTime
        EndTime = $EndTime
    }
    
    $winEvents = Get-WinEvent -FilterHashtable $filterHash -ErrorAction SilentlyContinue
    if ($winEvents) {
        foreach ($winEvent in $winEvents) {
            $xml = [xml]$winEvent.ToXml()
            $eventData = $xml.Event.EventData.Data
            
            $accountName = ($eventData.Where({ $_.Name -eq 'SubjectUserName' }).'#text')
            $shareName = ($eventData.Where({ $_.Name -eq 'ShareName' }).'#text')
            $sourceIP = ($eventData.Where({ $_.Name -eq 'IpAddress' }).'#text')
            
            # Skip administrative shares and system accounts
            if ($shareName -like '*$' -or $accountName -in @('SYSTEM', 'ANONYMOUS LOGON', '-')) {
                continue
            }
            
            $key = "$accountName|$shareName|$sourceIP"
            if ($smbAccess.TryGetValue($key, [ref]$null)) {
                $smbAccess[$key].AccessCount++
            } else {
                $smbAccess[$key] = [PSCustomObject]@{
                    AccountName = $accountName
                    ShareName = $shareName
                    SourceIP = $sourceIP
                    SourceHostname = $null
                    AccessCount = 1
                }
            }
        }
        
        # Resolve hostnames
        foreach ($access in $smbAccess.Values) {
            $access.SourceHostname = Resolve-DnsNameSafe -IPAddress $access.SourceIP
        }
    }
    
    Write-Host "  Found $($smbAccess.Count) unique SMB access patterns" -ForegroundColor Cyan
    
    return [System.Collections.Generic.List[PSObject]]::new($smbAccess.Values)
}

function Resolve-DnsNameSafe {
    [CmdletBinding()]
    param(
        [string]$IPAddress
    )
    
    # Skip invalid IPs
    if ([string]::IsNullOrWhiteSpace($IPAddress) -or $IPAddress -eq '-' -or $IPAddress -eq '::1' -or $IPAddress -eq '127.0.0.1') {
        return $null
    }
    
    try {
        $result = [System.Net.Dns]::GetHostEntry($IPAddress)
        return $result.HostName
    } catch {
        return $null
    }
}

function Export-DiscoveryResults {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [object]$Results
    )
    
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $dcName = $env:COMPUTERNAME
    
    # Export each collection type
    foreach ($kvp in $Results.GetEnumerator()) {
        $fileName = "{0}_{1}_{2}.csv" -f $dcName, $kvp.Key, $timestamp
        $fullPath = Join-Path -Path $OutputPath -ChildPath $fileName
        
        if ($kvp.Value.Count -gt 0) {
            $kvp.Value | Export-Csv -Path $fullPath -NoTypeInformation
            Write-Host "Exported $($kvp.Value.Count) records to $fileName" -ForegroundColor Green
        }
    }
    
    # Create summary report
    $summaryPath = Join-Path -Path $OutputPath -ChildPath "${dcName}_Summary_${timestamp}.txt"
    $summary = @"
AD Authentication Discovery Summary
Domain Controller: $dcName
Collection Period: $($Results.CollectionStartTime) to $($Results.CollectionEndTime)
Generated: $(Get-Date)

=== DISCOVERY RESULTS ===

LDAP Binds:
  Unique clients with unsigned binds: $($Results.LdapBinds.Count)

Kerberos Activity:
  Total unique authentication patterns: $($Results.KerberosActivity.Count)
  TGT requests: $(($Results.KerberosActivity.Where({ $_.AuthType -eq 'Kerberos-TGT' })).Count)
  Service tickets: $(($Results.KerberosActivity.Where({ $_.AuthType -eq 'Kerberos-ServiceTicket' })).Count)

NTLM Activity:
  Unique NTLM authentication sources: $($Results.NtlmActivity.Count)

DNS Queries:
  Unique DNS clients: $($Results.DnsQueries.Count)
  Clients with AD-related queries: $(($Results.DnsQueries.Where({ $_.ADRelatedQueries -gt 0 })).Count)

Service Principals:
  Total SPNs registered: $($Results.ServicePrincipals.Count)
  User/Service accounts: $(($Results.ServicePrincipals.Where({ $_.AccountType -eq 'User/Service' })).Count)
  Computer accounts: $(($Results.ServicePrincipals.Where({ $_.AccountType -eq 'Computer' })).Count)

Service Account Activity:
  Unique service/network logon patterns: $($Results.ServiceAccountActivity.Count)

SMB Access:
  Unique share access patterns: $($Results.SmbAccess.Count)

=== UNIQUE CLIENTS DISCOVERED ===

Total unique client IPs across all sources: $($Results.UniqueClients.Count)

Top 20 most active clients:
$($Results.TopClients | Format-Table -AutoSize | Out-String)

=== NEXT STEPS ===

1. Review CSV files for detailed client, account, and service information
2. Cross-reference client IPs with your asset inventory
3. Identify applications using NTLM (highest migration priority)
4. Map service accounts to applications via SPN correlation
5. Run discovery again in 1-2 weeks to capture periodic batch jobs

Files exported to: $OutputPath
"@
    
    $summary | Out-File -FilePath $summaryPath -Encoding utf8
    Write-Host "`nSummary report: $summaryPath" -ForegroundColor Green
}

function Get-UniqueClientInventory {
    [CmdletBinding()]
    param(
        [object]$AllResults
    )
    
    $clientInventory = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
    
    # Aggregate all client IPs from all sources
    $sources = @(
        @{ Name = 'LDAP'; Data = $AllResults.LdapBinds; IPField = 'ClientIP'; HostField = 'ClientHostname' }
        @{ Name = 'Kerberos'; Data = $AllResults.KerberosActivity; IPField = 'ClientIP'; HostField = 'ClientHostname' }
        @{ Name = 'DNS'; Data = $AllResults.DnsQueries; IPField = 'ClientIP'; HostField = 'ClientHostname' }
        @{ Name = 'SMB'; Data = $AllResults.SmbAccess; IPField = 'SourceIP'; HostField = 'SourceHostname' }
    )
    
    foreach ($source in $sources) {
        foreach ($record in $source.Data) {
            $ip = $record.($source.IPField)
            if ([string]::IsNullOrWhiteSpace($ip) -or $ip -eq '-') { continue }
            
            if ($clientInventory.TryGetValue($ip, [ref]$null)) {
                $clientInventory[$ip].Sources += ", $($source.Name)"
                $clientInventory[$ip].ActivityCount++
            } else {
                $clientInventory[$ip] = [PSCustomObject]@{
                    ClientIP = $ip
                    ClientHostname = $record.($source.HostField)
                    Sources = $source.Name
                    ActivityCount = 1
                }
            }
        }
    }
    
    # Get top clients by activity
    $topClients = $clientInventory.Values | 
        Sort-Object -Property ActivityCount -Descending | 
        Select-Object -First 20 -Property ClientIP, ClientHostname, ActivityCount, Sources
    
    return @{
        AllClients = [System.Collections.Generic.List[PSObject]]::new($clientInventory.Values)
        TopClients = $topClients
    }
}

#endregion

#region Main Execution

try {
    Write-Host "`n=== AD Authentication Discovery Tool ===" -ForegroundColor Cyan
    Write-Host "Domain Controller: $env:COMPUTERNAME"
    Write-Host "Collection Period: $CollectionStartTime to $CollectionEndTime"
    Write-Host "Output Path: $OutputPath`n"
    
    # Initialize environment
    Initialize-DiscoveryEnvironment -OutputPath $OutputPath `
                                     -EnableDnsDebugLogging:$EnableDnsDebugLogging `
                                     -MaxDnsLogSizeMB $MaxDnsLogSizeMB
    
    Write-Host "`nStarting data collection...`n" -ForegroundColor Yellow
    
    # Collect all data sources
    $results = @{
        CollectionStartTime = $CollectionStartTime
        CollectionEndTime = $CollectionEndTime
        DomainController = $env:COMPUTERNAME
        LdapBinds = Get-LdapBindActivity -StartTime $CollectionStartTime -EndTime $CollectionEndTime -ExcludeComputers:(-not $IncludeComputerAccounts)
        KerberosActivity = Get-KerberosActivity -StartTime $CollectionStartTime -EndTime $CollectionEndTime -ExcludeComputers:(-not $IncludeComputerAccounts)
        NtlmActivity = Get-NtlmActivity -StartTime $CollectionStartTime -EndTime $CollectionEndTime -ExcludeComputers:(-not $IncludeComputerAccounts)
        DnsQueries = Get-DnsQueryActivity -StartTime $CollectionStartTime -EndTime $CollectionEndTime
        ServicePrincipals = Get-ServicePrincipalInventory
        ServiceAccountActivity = Get-ServiceAccountActivity -StartTime $CollectionStartTime -EndTime $CollectionEndTime
        SmbAccess = Get-SmbAccessActivity -StartTime $CollectionStartTime -EndTime $CollectionEndTime
    }
    
    Write-Host "`nAggregating client inventory..." -ForegroundColor Yellow
    $clientInventory = Get-UniqueClientInventory -AllResults $results
    $results.UniqueClients = $clientInventory.AllClients
    $results.TopClients = $clientInventory.TopClients
    
    Write-Host "`nExporting results..." -ForegroundColor Yellow
    Export-DiscoveryResults -OutputPath $OutputPath -Results $results
    
    Write-Host "`n=== Discovery Complete ===" -ForegroundColor Green
    Write-Host "Results saved to: $OutputPath"
    Write-Host "`nRun this script on all domain controllers and aggregate results for complete visibility.`n"
    
} catch {
    Write-Error "Discovery failed: $_"
    throw
}

#endregion
