Import-Module GroupPolicy

$allGPOs = Get-GPO -All

$cseUsage = @{}

foreach ($gpo in $allGPOs) {
    $reportPath = [System.IO.Path]::GetTempFileName()
    Get-GPOReport -Guid $gpo.Id -ReportType Xml -Path $reportPath
    $xml = [xml](Get-Content $reportPath)

    foreach ($section in @('User', 'Computer')) {
        $extensions = $xml.GPO.$section.ExtensionData.Extension
        foreach ($ext in $extensions) {
            $cseId = $ext.Name
            if ($ext.Settings -ne $null) {
                if (-not $cseUsage.ContainsKey($cseId)) {
                    $cseUsage[$cseId] = [System.Collections.Generic.List[string]]::new()
                }
                $cseUsage[$cseId].Add($gpo.DisplayName)
            }
        }
    }

    Remove-Item $reportPath -Force
}

# Output all used CSEs and which GPOs use them
$cseUsage.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        CSE_ID     = $_.Key
        GPO_Count  = $_.Value.Count
        GPOs       = ($_.Value -join '; ')
    }
}