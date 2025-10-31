function Get-AzUniqueRbacUserAccounts {
    <#
    .SYNOPSIS
        Retrieves all unique user accounts with Azure RBAC role assignments across the entire tenant.

    .DESCRIPTION
        Queries all subscriptions in the current Azure tenant to identify user accounts (excluding groups 
        and service principals) that have been assigned any Azure RBAC role. Returns a deduplicated list 
        of user objects with their associated role counts.

    .PARAMETER IncludeRoleDetails
        When specified, includes detailed role assignment information for each user.

    .EXAMPLE
        Get-AzUniqueRbacUserAccounts

        Returns all unique user accounts with RBAC assignments.

    .EXAMPLE
        Get-AzUniqueRbacUserAccounts -IncludeRoleDetails | Export-Csv -Path users.csv -NoTypeInformation

        Exports detailed user and role information to CSV.

    .NOTES
        Requires Az.Accounts and Az.Resources modules.
        Must be connected to Azure via Connect-AzAccount before execution.
        Performance: Processes subscriptions sequentially; large tenants may take several minutes.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeRoleDetails
    )

    begin {
        # Verify Azure context
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $context) {
            throw "No Azure context found. Run Connect-AzAccount first."
        }

        Write-Verbose "Connected to tenant: $($context.Tenant.Id)"
    }

    process {
        # Get all subscriptions in tenant
        Write-Verbose "Retrieving subscriptions..."
        $subscriptions = Get-AzSubscription -TenantId $context.Tenant.Id

        if ($subscriptions.Count -eq 0) {
            Write-Warning "No subscriptions found in tenant."
            return
        }

        Write-Verbose "Found $($subscriptions.Count) subscription(s)"

        # Use dictionary for O(1) lookups and deduplication
        $userDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()

        # Process each subscription
        foreach ($sub in $subscriptions) {
            Write-Verbose "Processing subscription: $($sub.Name) ($($sub.Id))"
            
            $null = Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue
            
            # Get all role assignments for this subscription
            $assignments = Get-AzRoleAssignment -ErrorAction SilentlyContinue
            
            if (-not $assignments) {
                continue
            }

            # Filter for user principals only (ObjectType = 'User')
            $userAssignments = $assignments.Where({ $_.ObjectType -eq 'User' })

            foreach ($assignment in $userAssignments) {
                $userId = $assignment.ObjectId

                if ($userDict.ContainsKey($userId)) {
                    # Existing user - increment role count
                    $userDict[$userId].RoleAssignmentCount++
                    
                    if ($IncludeRoleDetails) {
                        $userDict[$userId].Roles += $assignment.RoleDefinitionName
                        $userDict[$userId].Scopes += $assignment.Scope
                    }
                }
                else {
                    # New user - create entry
                    $userObj = [PSCustomObject]@{
                        ObjectId             = $userId
                        DisplayName          = $assignment.DisplayName
                        SignInName           = $assignment.SignInName
                        RoleAssignmentCount  = 1
                    }

                    if ($IncludeRoleDetails) {
                        $userObj | Add-Member -NotePropertyName 'Roles' -NotePropertyValue @($assignment.RoleDefinitionName)
                        $userObj | Add-Member -NotePropertyName 'Scopes' -NotePropertyValue @($assignment.Scope)
                    }

                    $userDict.Add($userId, $userObj)
                }
            }

            # Clear large temporary
            $assignments = $null
        }

        Write-Verbose "Found $($userDict.Count) unique user(s) with RBAC assignments"

        # Return collection
        $userDict.Values
    }
}

# Execute the function
Get-AzUniqueRbacUserAccounts -Verbose
