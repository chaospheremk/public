$ErrorActionPreference = 'Stop'
##### SOURCE AND TARGET OBJECT LISTS
### authenticate for pulling Source and Target object lists
# this should be manually added to any AD related parameter blocks
$paramsAd = @{

    Server = 'dougjohnson.me'
    Credential = Get-Credential -Message 'Enter AD credentials'
}

### declare source object list blocks, filter blocks, and foreach blocks. Create parameter hashtables if required.
# source object list block. Create parameter hashtable if required.
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
        ExternalEmailAddress = $_.'msDS-cloudExtensionAttribute1'
    }
}

### declare target object list blocks, filter blocks, and foreach blocks. Create parameter hashtables if required.
# target object list block.
$targetObjectListBlock = { Get-MailContact -ResultSize 'Unlimited' }

# target filter block
$targetFilterBlock = { $_.CustomAttribute1 -like 'DJM' }

# target foreach block
$targetForEachBlock = {

    [PSCustomObject]@{
        DisplayName = $_.DisplayName
        ExternalEmailAddress = $_.ExternalEmailAddress -replace 'SMTP:'
    }
}

##### KEY PROPERTY
# specify the property that will be used to compare source and target objects. It must be unique to each object.
$keyProperty = 'ExternalEmailAddress'

##### ADD AND REMOVE BLOCKS
# add block
$addBlock = {
    param ($Objects)
    
    foreach ($object in $Objects) {

        $contactName = "DJM_$($object.Name -replace ' ')"

        $paramsNewMailContact = @{

            Name = $contactName
            ExternalEmailAddress = $object.$keyProperty
        }
        
        $null = New-MailContact @paramsNewMailContact

        Set-MailContact -Identity $contactName -CustomAttribute1 'DJM'
    }
}

# remove block
$removeBlock = {
    param ($Objects)
    
    foreach ($object in $Objects) {

        $identity = $object.DisplayName
        
        Remove-MailContact -Identity $identity -Confirm:$false
    }
}

# initialize params for Invoke-DeclarativeReconciliation
$paramsInvokeDeclarativeReconciliation = @{

    SourceObjectList = & $sourceObjectListBlock
    SourceForEachBlock = $sourceForEachBlock
    TargetObjectList = & $targetObjectListBlock
    TargetFilterBlock = $targetFilterBlock
    TargetForEachBlock = $targetForEachBlock
    KeyProperty = $keyProperty
    AddBlock = $addBlock
    RemoveBlock = $removeBlock
}

Invoke-DeclarativeReconciliation @paramsInvokeDeclarativeReconciliation
$ErrorActionPreference = 'Continue'