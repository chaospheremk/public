function Add-iOSDeviceOwnersToGroup {
    <#
    .SYNOPSIS
        Adds owners of iOS devices with compliance status to a security group.

    .DESCRIPTION
        Queries Entra ID for all iOS devices that report a compliance status (true or false).
        For each device, retrieves the registered owner and adds them to the specified security
        group if they are not already a member.

        Requires Microsoft.Graph.Devices and Microsoft.Graph.Groups modules with appropriate
        delegated or application permissions (Device.Read.All, GroupMember.ReadWrite.All).

    .PARAMETER GroupId
        The Object ID of the target security group.

    .PARAMETER GroupName
        The display name of the target security group. If both GroupId and GroupName are provided,
        GroupId takes precedence.

    .EXAMPLE
        Add-iOSDeviceOwnersToGroup -GroupId "12345678-1234-1234-1234-123456789012"

        Adds iOS device owners to the specified group using its Object ID.

    .EXAMPLE
        Add-iOSDeviceOwnersToGroup -GroupName "iOS Compliant Users"

        Adds iOS device owners to the group named "iOS Compliant Users".

    .NOTES
        Performance: Batches all API calls and uses dictionaries for O(1) member lookups.
        Designed for PowerShell 7 with Microsoft.Graph SDK v2.x or later.
    #>

    [CmdletBinding(DefaultParameterSetName = 'ById')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupId,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$GroupName
    )

    begin {
        # Verify Graph connection
        try {
            $null = Get-MgContext -ErrorAction Stop
        }
        catch {
            Write-Error "Not connected to Microsoft Graph. Run Connect-MgGraph first."
            return
        }

        # Initialize collections
        $results = [System.Collections.Generic.List[PSObject]]::new()
        $errors = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {
        try {
            # Resolve target group
            if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                Write-Verbose "Resolving group by name: $GroupName"
                $group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction Stop
                if (-not $group) {
                    Write-Error "Group '$GroupName' not found."
                    return
                }
                $targetGroupId = $group.Id
            }
            else {
                $targetGroupId = $GroupId
                Write-Verbose "Using group ID: $targetGroupId"
            }

            # Retrieve all iOS devices with required properties
            Write-Verbose "Retrieving iOS devices from Entra ID..."
            $allDevices = Get-MgDevice -All -Filter "operatingSystem eq 'iOS'" `
                -Property Id,DisplayName,IsCompliant,RegisteredOwners `
                -ExpandProperty RegisteredOwners -ErrorAction Stop

            # Filter devices with compliance status reported
            $devicesWithCompliance = $allDevices.Where({ $null -ne $_.IsCompliant })
            
            if ($devicesWithCompliance.Count -eq 0) {
                Write-Warning "No iOS devices found with reported compliance status."
                return
            }

            Write-Verbose "Found $($devicesWithCompliance.Count) iOS devices with compliance status."

            # Build unique owner dictionary (avoid duplicate processing)
            $uniqueOwners = [System.Collections.Generic.Dictionary[string,PSObject]]::new()
            
            foreach ($device in $devicesWithCompliance) {
                if ($device.RegisteredOwners.Count -gt 0) {
                    $owner = $device.RegisteredOwners[0]
                    $ownerId = $owner.Id
                    
                    if (-not $uniqueOwners.ContainsKey($ownerId)) {
                        $uniqueOwners[$ownerId] = [PSCustomObject]@{
                            UserId      = $ownerId
                            UserPrincipal = $owner.AdditionalProperties['userPrincipalName']
                            DeviceCount = 1
                        }
                    }
                    else {
                        $uniqueOwners[$ownerId].DeviceCount++
                    }
                }
                else {
                    $errors.Add([PSCustomObject]@{
                        DeviceId = $device.Id
                        DeviceName = $device.DisplayName
                        Issue = "No registered owner"
                    })
                }
            }

            Write-Verbose "Identified $($uniqueOwners.Count) unique device owners."

            # Get current group members as dictionary for O(1) lookup
            Write-Verbose "Retrieving current group members..."
            $currentMembers = Get-MgGroupMember -GroupId $targetGroupId -All -ErrorAction Stop
            $memberDict = [System.Collections.Generic.Dictionary[string,bool]]::new()
            
            foreach ($member in $currentMembers) {
                $memberDict[$member.Id] = $true
            }

            Write-Verbose "Group currently has $($memberDict.Count) members."

            # Process each owner
            $addedCount = 0
            $skippedCount = 0

            foreach ($owner in $uniqueOwners.Values) {
                if ($memberDict.ContainsKey($owner.UserId)) {
                    Write-Verbose "User $($owner.UserPrincipal) already in group. Skipping."
                    $skippedCount++
                }
                else {
                    try {
                        New-MgGroupMember -GroupId $targetGroupId `
                            -DirectoryObjectId $owner.UserId `
                            -ErrorAction Stop
                        
                        Write-Verbose "Added user $($owner.UserPrincipal) to group."
                        $addedCount++
                        
                        $results.Add([PSCustomObject]@{
                            UserId = $owner.UserId
                            UserPrincipal = $owner.UserPrincipal
                            DeviceCount = $owner.DeviceCount
                            Action = "Added"
                        })
                    }
                    catch {
                        $errors.Add([PSCustomObject]@{
                            UserId = $owner.UserId
                            UserPrincipal = $owner.UserPrincipal
                            Issue = $_.Exception.Message
                        })
                        Write-Warning "Failed to add user $($owner.UserPrincipal): $($_.Exception.Message)"
                    }
                }
            }

            # Summary output
            Write-Host "`nOperation Summary:" -ForegroundColor Cyan
            Write-Host "  iOS devices with compliance status: $($devicesWithCompliance.Count)"
            Write-Host "  Unique device owners identified: $($uniqueOwners.Count)"
            Write-Host "  Users added to group: $addedCount" -ForegroundColor Green
            Write-Host "  Users already in group: $skippedCount"
            
            if ($errors.Count -gt 0) {
                Write-Host "  Errors encountered: $($errors.Count)" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Error "Operation failed: $($_.Exception.Message)"
            return
        }
    }

    end {
        # Return structured results
        if ($results.Count -gt 0 -or $errors.Count -gt 0) {
            [PSCustomObject]@{
                AddedUsers = $results
                Errors = $errors
                Timestamp = Get-Date -Format 'o'
            }
        }
    }
}
