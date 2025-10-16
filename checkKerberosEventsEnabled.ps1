# What we expect to be enabled on all DCs
$Subcats = @(
  'Kerberos Authentication Service',
  'Kerberos Service Ticket Operations'
)

# Gather all DCs in the current forest
$DCs = (Get-ADForest).Domains |
  ForEach-Object { Get-ADDomainController -Server $_ -Filter * } |
  Select-Object -ExpandProperty HostName -Unique

# Run auditpol on each DC and parse the effective setting
$scriptBlock = {
  param($Subcats)

  $text = & auditpol.exe /get /category:"Account Logon" 2>$null
  foreach ($name in $Subcats) {
    $rx = "^\s*{0}\s+(?<Setting>.+?)\s*$" -f [regex]::Escape($name)
    $line = $text | Where-Object { $_ -match $rx } | Select-Object -First 1

    if (-not $line) {
      [pscustomobject]@{
        ComputerName    = $env:COMPUTERNAME
        Subcategory     = $name
        Setting         = $null
        SuccessEnabled  = $false
        FailureEnabled  = $false
        Compliant       = $false
        Note            = 'Subcategory not found'
      }
    } else {
      $setting = ([regex]::Match($line, $rx)).Groups['Setting'].Value.Trim()
      $success = $setting -match 'Success'
      $failure = $setting -match 'Failure'
      [pscustomobject]@{
        ComputerName    = $env:COMPUTERNAME
        Subcategory     = $name
        Setting         = $setting
        SuccessEnabled  = $success
        FailureEnabled  = $failure
        Compliant       = ($success -and $failure)
        Note            = $null
      }
    }
  }
}

$results = Invoke-Command -ComputerName $DCs -ScriptBlock $scriptBlock -ArgumentList (,$Subcats) -ErrorAction Continue

# Nice on-screen view
$results |
  Sort-Object ComputerName, Subcategory |
  Format-Table ComputerName, Subcategory, Setting, SuccessEnabled, FailureEnabled, Compliant

# Optional: save a CSV for your migration worksheet
# $results | Export-Csv .\Kerberos-AuditPolicy-Status.csv -NoTypeInformation

# Remediate
$nonCompliant = $results |
  Where-Object { -not $_.Compliant } |
  Select-Object -ExpandProperty ComputerName -Unique

Invoke-Command -ComputerName $nonCompliant -ScriptBlock {
  auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
  auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
}
