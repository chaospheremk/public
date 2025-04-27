# This is an example of how to sync AD users to an AD security group based on a condition/filter. The example uses
# the Office attribute to filter users. The script will add users to the group if they are not already members and
# remove them if they no longer meet the criteria.

# initialize the params for the Add and Remove blocks

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

Invoke-DeclarativeReconciliation @paramsInvokeDeclarativeReconciliation