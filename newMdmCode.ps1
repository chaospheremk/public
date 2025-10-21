$migratedGroupId = '5cbbd66a-59ab-4d49-98c1-cedda56fbcca'
$results = [System.Collections.Generic.List[psobject]]::new()

# get all users dictionary
$propsMgUsers = @(
    'UserPrincipalName',
    'Id',
    'EmployeeId'
)

$whereAllMgUsers = {
    $_.UserPrincipalName -notmatch 'svc' -and
    $_.UserPrincipalName -match '@domain\.com$' -and
    $_.UserPrincipalName -notmatch '-az@domain\.com$' -and
    -not [string]::IsNullOrWhiteSpace($_.EmployeeId)
}

$paramsGetMgUser = @{
    All = $true
    Property = $propsMgUsers
}

$paramsMgUsersDict = @{
    ObjectList  = (Get-MgUser @paramsGetMgUser).Where($whereAllMgUsers) | Select-Object -Property $propsMgUsers
    KeyProperty = 'Id'
}

$allMgUsersDict = ConvertTo-Dictionary @paramsMgUsersDict

# get all compliance iOS devices dictionary
$propsMgDevices = @(
    'Id',
    'OperatingSystem',
    'IsCompliant',
    'IsManaged',
    'MdmAppId'
)

$paramsGetMgDevice = @{
    All = $true
    Filter = "OperatingSystem eq 'iOS' and IsManaged eq true and MdmAppId eq '0000000a-0000-0000-c000-000000000000'"
    Property = $propsMgDevices
}

$paramsMgDevicesDict = @{
    ObjectList  = Get-MgDevice @paramsGetMgDevice | Select-Object -Property $propsMgDevices
    KeyProperty = 'Id'
}

$allMgDevicesDict = ConvertTo-Dictionary @paramsMgDevicesDict

# get already migrated users group members
$migratedGroupMembers = Get-MgGroupMember -GroupId $migratedGroupId

foreach ($member in $migratedGroupMembers) {

    $user = $allMgUsersDict[$member.Id]

    $results.Add(
        [pscustomobject]@{

            UserPrincipalName = $user.UserPrincipalName
            EmployeeId = $user.EmployeeId
            Status = "Already migrated"
            Error = $null
        }
    )
}

# create list for new users to add to the list
$newMigratedUsersList = [System.Collections.Generic.List[psobject]]::new()

foreach ($device in $allMgDevicesDict.Keys) {

    $registeredOwner = Get-MgDeviceRegisteredOwner -DeviceId $device

    $user = $allMgUsersDict[$registeredOwner.Id]

    if ($migratedGroupMembers.Id -notcontains $user.Id -and $newMigratedUsersList.Id -notcontains $user.Id) {
        
        $newMigratedUsersList.Add($allMgUsersDict[$registeredOwner.Id])
    }
}

# add new users to the group
foreach ($user in $newMigratedUsersList) {
    
    try {

        New-MgGroupMember -GroupId $migratedGroupId -DirectoryObjectId $user.Id

        $results.Add(
            [pscustomobject]@{

                UserPrincipalName = $user.UserPrincipalName
                EmployeeId = $user.EmployeeId
                Status = "Migrated $(Get-Date -Format yyyy/MM/dd)"
                Error = $null
            }
        )
    }
    catch {

        $results.Add(
            [pscustomobject]@{

                UserPrincipalName = $user.UserPrincipalName
                EmployeeId = $user.EmployeeId
                Status = 'Error'
                Error = $_.Exception.Message
            }
        )
    }
}
