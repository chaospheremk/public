#requires -Version 7.0

<#
.SYNOPSIS
    Migrates users with compliant iOS devices to a specified group.

.DESCRIPTION
    Identifies users who own compliant, managed iOS devices and adds them to the
    migration group if not already members. Returns a list of migration results.

.PARAMETER MigratedGroupId
    The Azure AD group ID for migrated users.

.EXAMPLE
    $results = Add-iOSDeviceUsersToGroup -MigratedGroupId '5cbbd66a-59ab-4d49-98c1-cedda56fbcca'

.NOTES
    Performance: Uses HashSets for membership checks, validates dictionary lookups,
    and implements early exits for empty collections.
#>
function Add-iOSDeviceUsersToGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$MigratedGroupId = '5cbbd66a-59ab-4d49-98c1-cedda56fbcca'
    )

    $results = [System.Collections.Generic.List[psobject]]::new()
    $migrationDate = Get-Date -Format 'yyyy/MM/dd'

    # Retrieve all eligible users
    $propsMgUsers = @('UserPrincipalName', 'Id', 'EmployeeId')
    $whereAllMgUsers = {
        $_.UserPrincipalName -notmatch 'svc' -and
        $_.UserPrincipalName -match '@domain\.com$' -and
        $_.UserPrincipalName -notmatch '-az@domain\.com$' -and
        -not [string]::IsNullOrWhiteSpace($_.EmployeeId)
    }
    
    $paramsGetMgUser = @{
        All      = $true
        Property = $propsMgUsers
    }
    
    Write-Verbose "Retrieving all eligible users..."
    $allUsers = (Get-MgUser @paramsGetMgUser).Where($whereAllMgUsers)
    
    if ($allUsers.Count -eq 0) {
        Write-Warning "No eligible users found"
        return $results
    }

    $paramsMgUsersDict = @{
        ObjectList  = $allUsers | Select-Object -Property $propsMgUsers
        KeyProperty = 'Id'
    }
    $allMgUsersDict = ConvertTo-Dictionary @paramsMgUsersDict
    Write-Verbose "Loaded $($allMgUsersDict.Count) users into dictionary"

    # Retrieve all compliant iOS devices
    $propsMgDevices = @('Id', 'OperatingSystem', 'IsCompliant', 'IsManaged', 'MdmAppId')
    $paramsGetMgDevice = @{
        All      = $true
        Filter   = "OperatingSystem eq 'iOS' and IsManaged eq true and MdmAppId eq '0000000a-0000-0000-c000-000000000000'"
        Property = $propsMgDevices
    }
    
    Write-Verbose "Retrieving compliant iOS devices..."
    $allDevices = Get-MgDevice @paramsGetMgDevice | Select-Object -Property $propsMgDevices
    
    if ($allDevices.Count -eq 0) {
        Write-Warning "No compliant iOS devices found"
        return $results
    }

    $paramsMgDevicesDict = @{
        ObjectList  = $allDevices
        KeyProperty = 'Id'
    }
    $allMgDevicesDict = ConvertTo-Dictionary @paramsMgDevicesDict
    Write-Verbose "Loaded $($allMgDevicesDict.Count) devices into dictionary"

    # Get existing group members and build HashSet for fast lookups
    Write-Verbose "Retrieving existing group members..."
    $migratedGroupMembers = Get-MgGroupMember -GroupId $MigratedGroupId
    $migratedMemberIds = [System.Collections.Generic.HashSet[string]]::new([string[]]$migratedGroupMembers.Id)

    # Record already-migrated users
    foreach ($member in $migratedGroupMembers) {
        if ($allMgUsersDict.ContainsKey($member.Id)) {
            $user = $allMgUsersDict[$member.Id]
            $results.Add([pscustomobject]@{
                UserPrincipalName = $user.UserPrincipalName
                EmployeeId        = $user.EmployeeId
                Status            = 'Already migrated'
                Error             = $null
            })
        }
    }

    # Identify new users to migrate
    $newMigratedUsersList = [System.Collections.Generic.List[psobject]]::new()
    $newMigratedUserIds = [System.Collections.Generic.HashSet[string]]::new()

    Write-Verbose "Identifying device owners for migration..."
    foreach ($device in $allMgDevicesDict.Values) {
        $registeredOwner = Get-MgDeviceRegisteredOwner -DeviceId $device.Id
        
        if (-not $registeredOwner -or -not $registeredOwner.Id) {
            Write-Verbose "Device $($device.Id) has no registered owner"
            continue
        }

        if (-not $allMgUsersDict.ContainsKey($registeredOwner.Id)) {
            Write-Verbose "Registered owner $($registeredOwner.Id) not in eligible user dictionary"
            continue
        }

        $user = $allMgUsersDict[$registeredOwner.Id]

        if (-not $migratedMemberIds.Contains($user.Id) -and -not $newMigratedUserIds.Contains($user.Id)) {
            $newMigratedUsersList.Add($user)
            [void]$newMigratedUserIds.Add($user.Id)
        }
    }

    # Early exit if no new users to migrate
    if ($newMigratedUsersList.Count -eq 0) {
        Write-Verbose "No new users to migrate"
        return $results
    }

    Write-Verbose "Migrating $($newMigratedUsersList.Count) new users to group..."

    # Add new users to the group
    foreach ($user in $newMigratedUsersList) {
        try {
            New-MgGroupMember -GroupId $MigratedGroupId -DirectoryObjectId $user.Id -ErrorAction Stop
            $results.Add([pscustomobject]@{
                UserPrincipalName = $user.UserPrincipalName
                EmployeeId        = $user.EmployeeId
                Status            = "Migrated $migrationDate"
                Error             = $null
            })
        }
        catch {
            $results.Add([pscustomobject]@{
                UserPrincipalName = $user.UserPrincipalName
                EmployeeId        = $user.EmployeeId
                Status            = 'Error'
                Error             = $_.Exception.Message
            })
        }
    }

    Write-Verbose "Migration complete. Total results: $($results.Count)"
    return $results
}

# Execute the migration
$results = Add-iOSDeviceUsersToGroup -MigratedGroupId '5cbbd66a-59ab-4d49-98c1-cedda56fbcca' -Verbose
$results
