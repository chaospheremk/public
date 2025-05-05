# This is an example of how to sync AD users to an AD security group based on a condition/filter. The example uses
# the Office attribute to filter users. The script will add users to the group if they are not already members and
# remove them if they no longer meet the criteria.

# Log variables
$logPath = 'C:\temp\aaaDynamicADGroupSync\logs\log.jsonl'

$paramsWriteLog = @{
    LogPath = $logPath
}

Write-Log @paramsWriteLog -Message 'Started DynamicADGroupSync'

# initialize the params for the Add and Remove blocks

Write-Log @paramsWriteLog -Message 'Initializing Invoke-DeclarativeReconciliation parameters...'

$targetGroupName = 'TestGroup'
$keyProperty = 'ObjectGuid'

$paramsAd = @{
    Server = 'dougjohnson.me'
    Credential = Get-Credential -Message 'Enter AD credentials'
}

$paramsAddBlock = @{ Identity = $targetGroupName } + $paramsAd

$paramsRemoveBlock = @{
    Identity = $targetGroupName
    Confirm = $false
} + $paramsAd

$addBlock = { param ($Objects) Add-ADGroupMember -Members $Objects.$keyProperty @paramsAddBlock }

$removeBlock = { param ($Objects) Remove-ADGroupMember -Members $Objects.$keyProperty @paramsRemoveBlock }

# initialize params for Invoke-DeclarativeReconciliation

$paramsInvokeDeclarativeReconciliation = @{

    SourceObjectList = Get-ADUser -Filter "Office -eq 'HomeTest'" @paramsAd
    SourceForEachBlock = {
        [PSCustomObject]@{
            Name = $_.Name
            SamAccountName = $_.SamAccountName
            UserPrincipalName = $_.UserPrincipalName
            GivenName = $_.GivenName
            Surname = $_.Surname
            ObjectGuid = $_.ObjectGUID
        }
    }
    TargetObjectList = Get-ADGroupMember -Identity 'TestGroup' @paramsAd
    TargetForEachBlock = {
        [PSCustomObject]@{
            Name = $_.name
            SamAccountName = $_.SamAccountName
            ObjectGuid = $_.ObjectGUID
        }
    }
    KeyProperty = $keyProperty
    AddBlock = $addBlock
    RemoveBlock = $removeBlock
}

Write-Log @paramsWriteLog -Message 'Initialized Invoke-DeclarativeReconciliation parameters successfully.'

Write-Log @paramsWriteLog -Message 'Running Invoke-DeclarativeReconciliation...'

try {
    
    Invoke-DeclarativeReconciliation @paramsInvokeDeclarativeReconciliation

    Write-Log @paramsWriteLog -Message 'Ran Invoke-DeclarativeReconciliation successfully.'
}
catch {

    Write-Log @paramsWriteLog -Message $_.Exception.Message -Level Error -ErrorRecord $_
}

Write-Log @paramsWriteLog -Message 'Ended DynamicADGroupSync'