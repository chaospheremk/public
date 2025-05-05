# This is an example of how to sync AD users to an AD security group based on a condition/filter. The example uses
# the Office attribute to filter users. The script will add users to the group if they are not already members and
# remove them if they no longer meet the criteria.

# Log variables
$logPath = 'C:\temp\aaaDynamicADGroupSync\logs\log.jsonl'

$paramsWriteLog = @{
    LogPath = $logPath
}

Write-Log @paramsWriteLog -Message 'Started DynamicADGroupSync'

### declare source object list blocks, filter blocks, and foreach blocks. Create parameter hashtables if required.
# source object list block. Create parameter hashtable if required.
$paramsAd = @{
    Server = 'dougjohnson.me'
    Credential = Get-Credential -Message 'Enter AD credentials'
}

$paramsGetSourceObjectList = @{

    Filter = "msDS-cloudExtensionAttribute1 -like '*'" 
    Properties = 'msDS-cloudExtensionAttribute1'
} + $paramsAd

$sourceObjectListBlock = { Get-ADUser @paramsGetSourceObjectList }

# no source filter block required

# source foreach block
$sourceForEachBlock = {

    [PSCustomObject]@{
        Name = $_.Name
        SamAccountName = $_.SamAccountName
        UserPrincipalName = $_.UserPrincipalName
        GivenName = $_.GivenName
        Surname = $_.Surname
        ObjectGuid = $_.ObjectGUID
    }
}

### declare target object list blocks, filter blocks, and foreach blocks. Create parameter hashtables if required.
# target object list block.
$targetGroupName = 'TestGroup'

$paramsGetTargetObjectList = @{

    Identity = $targetGroupName
} + $paramsAd

$targetObjectListBlock = { Get-ADGroupMember @paramsGetTargetObjectList }

# no target filter block required

# target foreach block
$targetForEachBlock = {

    [PSCustomObject]@{
        Name = $_.name
        SamAccountName = $_.SamAccountName
        ObjectGuid = $_.ObjectGUID
    }
}

##### KEY PROPERTY
# specify the property that will be used to compare source and target objects. It must be unique to each object.
$keyProperty = 'ObjectGuid'

##### ADD AND REMOVE BLOCKS
# add block
Write-Log @paramsWriteLog -Message 'Initializing Invoke-DeclarativeReconciliation parameters...'

$paramsAddBlock = @{ Identity = $targetGroupName } + $paramsAd

$addBlock = { param ($Objects) Add-ADGroupMember -Members $Objects.$keyProperty @paramsAddBlock }

# remove block
$paramsRemoveBlock = @{
    Identity = $targetGroupName
    Confirm = $false
} + $paramsAd

$removeBlock = { param ($Objects) Remove-ADGroupMember -Members $Objects.$keyProperty @paramsRemoveBlock }

# initialize params for Invoke-DeclarativeReconciliation

$paramsInvokeDeclarativeReconciliation = @{

    SourceObjectList = . $sourceObjectListBlock
    SourceForEachBlock = $sourceForEachBlock
    TargetObjectList = . $targetObjectListBlock
    TargetForEachBlock = $targetForEachBlock
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