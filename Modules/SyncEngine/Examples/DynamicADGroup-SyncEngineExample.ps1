# This is an example of how to sync AD users to an AD security group based on a condition/filter. The example uses
# the Office attribute to filter users. The script will add users to the group if they are not already members and
# remove them if they no longer meet the criteria.

# Log variables
$logPath = 'C:\temp\aaaDynamicADGroupSync\logs\log.jsonl'

$correlationId = New-Guid

$paramsWriteLog = @{
    Level = 'INFO'
    LogPath = $logPath
    CorrelationId = $correlationId
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

$sourceObjectListBlock = {
    
    try {

        Write-Log @paramsWriteLog -Message 'Retrieving AD user list...'

        Get-ADUser @paramsGetSourceObjectList

        Write-Log @paramsWriteLog -Message 'AD user list retrieved successfully.'
    }
    catch {

        Write-Log @paramsWriteLog -Message 'AD user list could not be retrieved.' -Level 'ERROR' -ErrorObject $_

        Write-Error -Message $_.Exception.Message -ErrorAction 'Stop'
    }
}

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

$targetObjectListBlock = {
    
    try {

        Write-Log @paramsWriteLog -Message 'Retrieving current group membership list...'

        Get-ADGroupMember @paramsGetTargetObjectList

        Write-Log @paramsWriteLog -Message 'Current group membership list retrieved successfully.'
    }
    catch {

        $logMessage = 'Current group membership list could not be retrieved.'

        Write-Log @paramsWriteLog -Message $logMessage -Level 'ERROR' -ErrorObject $_

        Write-Error -Message $_.Exception.Message -ErrorAction 'Stop'
    }
}

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

$addBlock = {
    param ($Objects)
    
    if (-not $Objects.count -gt 0) {

        Write-Log @paramsWriteLog -Message "No users to add to group $targetGroupName."
        continue
    }

    try {

        $logMessage = "Adding $($Objects.count) users to group $targetGroupName..."
        Write-Log @paramsWriteLog -Message $logMessage

        Add-ADGroupMember -Members $Objects.$keyProperty @paramsAddBlock

        $logMessage = "Added $($Objects.count) users to group $targetGroupName successfully."
        Write-Log @paramsWriteLog -Message $logMessage
    }
    catch {

        $logMessage = "$($Objects.count) users could not be added to group $targetGroupName."
        Write-Log @paramsWriteLog -Message $logMessage -Level 'ERROR' -ErrorObject $_

        Write-Error -Message $_.Exception.Message -ErrorAction 'Stop'
    }
}

# remove block
$paramsRemoveBlock = @{
    Identity = $targetGroupName
    Confirm = $false
} + $paramsAd

$removeBlock = {
    param ($Objects)
    
    if (-not $Objects.count -gt 0) {

        Write-Log @paramsWriteLog -Message "No users to remove from group $targetGroupName."
        continue
    }

    try {

        $logMessage = "Removing $($Objects.count) users from group $targetGroupName..."
        Write-Log @paramsWriteLog -Message $logMessage

        Remove-ADGroupMember -Members $Objects.$keyProperty @paramsRemoveBlock

        $logMessage = "Removed $($Objects.count) users from group $targetGroupName successfully."
        Write-Log @paramsWriteLog -Message $logMessage
    }
    catch {

        $logMessage = "$($Objects.count) users could not be removed from group $targetGroupName."
        Write-Log @paramsWriteLog -Message $logMessage -Level 'ERROR' -ErrorObject $_

        Write-Error -Message $_.Exception.Message -ErrorAction 'Stop'
    }
}

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

    Write-Log @paramsWriteLog -Message $_.Exception.Message -Level 'Error' -ErrorObject $_
}

Write-Log @paramsWriteLog -Message 'Ended DynamicADGroupSync'