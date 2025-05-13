function Get-EntraRolesReport {

    [CmdletBinding()]
    Param()

    # Get all Entra users, store in dictionary
    $propsMgUsers = @(
        'DisplayName',
        'GivenName',
        'Id',
        'JobTitle',
        'Surname',
        'UserPrincipalName'
    )

    $paramsConvertToDictionary = @{
        ObjectList = Get-MgUser -All -Property $propsMgUsers | Select-Object -Property $propsMgUsers
        KeyProperty = 'Id'
    }

    $allMgUsersDict = ConvertTo-Dictionary @paramsConvertToDictionary

    # Get all Entra service principals, store in dictionary
    $propsMgServicePrincipals = @(
        'AppId',
        'DisplayName',
        'Id',
        'ServicePrincipalType'
    )

    $paramsConvertToDictionary = @{
        ObjectList = Get-MgServicePrincipal -All -Property $propsMgServicePrincipals |
            Select-Object -Property $propsMgServicePrincipals
        KeyProperty = 'Id'
    }

    $allMgServicePrincipalsDict = ConvertTo-Dictionary @paramsConvertToDictionary

    # Get all Entra groups, store in dictionary
    $propsMgGroups = @(
        'Description',
        'DisplayName',
        'Id'
    )

    $paramsConvertToDictionary = @{
        ObjectList = Get-MgGroup -All -Property $propsMgGroups | Select-Object -Property $propsMgGroups
        KeyProperty = 'Id'
    }

    $allMgGroupsDict = ConvertTo-Dictionary @paramsConvertToDictionary

    # Get all Entra Role assignments, store in dictionary
    $propsRoleAssignments = @(
        'DirectoryScopeId',
        'Id',
        'PrincipalId',
        'RoleDefinitionId'
    )

    $paramsConvertToDictionary = @{
        ObjectList = Get-MgRoleManagementDirectoryRoleAssignment -All -Property $propsRoleAssignments |
            Select-Object -Property $propsRoleAssignments
        KeyProperty = 'Id'
    }

    $allRoleAssignmentsDict = ConvertTo-Dictionary @paramsConvertToDictionary

    # Get all Entra Role definitions, store in dictionary
    $propsRoleDefinitions = @(
        'Description',
        'DisplayName',
        'Id',
        'IsBuiltIn',
        'IsEnabled',
        'ResourceScopes'
    )

    $paramsConvertToDictionary = @{
        ObjectList = Get-MgRoleManagementDirectoryRoleDefinition -All -Property $propsRoleDefinitions |
            Select-Object -Property $propsRoleDefinitions
        KeyProperty = 'Id'
    }

    $allRoleDefinitionsDict = ConvertTo-Dictionary @paramsConvertToDictionary

    # Get all Entra Administrative Units, store in dictionary
    $propsAdminUnits = @(
        'Description',
        'DisplayName',
        'Id',
        'IsMemberManagementRestricted'
    )

    $paramsConvertToDictionary = @{
        ObjectList = Get-MgDirectoryAdministrativeUnit -All -Property $propsAdminUnits |
            Select-Object -Property $propsAdminUnits
        KeyProperty = 'Id'
    }

    $allAdminUnitsDict = ConvertTo-Dictionary @paramsConvertToDictionary


    # start logic
    $resultsList = [System.Collections.Generic.List[PSObject]]::new()
    $assignedGroupsDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()
    $groupMembersDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()

    foreach ($key in $allRoleAssignmentsDict.Keys) {

        $roleAssignment = $allRoleAssignmentsDict[$key]
        $roleAssignmentDirectoryScopeId = $roleAssignment.DirectoryScopeId
        $principalId = $roleAssignment.PrincipalId
        $roleDefinitionId = $roleAssignment.RoleDefinitionId
        $roleDefinition = $allRoleDefinitionsDict[$roleDefinitionId]

        $roleDescription = $roleDefinition.Description
        $roleDisplayName = $roleDefinition.DisplayName
        $roleId = $roleDefinition.Id
        $roleIsBuiltIn = $roleDefinition.IsBuiltIn
        $roleIsEnabled = $roleDefinition.IsEnabled
        $roleResourceScopes = $roleDefinition.ResourceScopes

        $directoryScope = switch ($roleAssignmentDirectoryScopeId) {

            { $_ -eq '/' } { 'Root Directory' }

            { $_ -match '/administrativeUnits/'} {

                $adminUnitId = $_ -replace '/administrativeUnits/'

                "Administrative Unit: $($allAdminUnitsDict[$adminUnitId].DisplayName)"
            }
        }

        switch ($principalId) {

            {$allMgUsersDict.ContainsKey($_)} {

                $object = $allMgUsersDict[$_]

                $objectType = 'User'
                $userGivenName = $object.GivenName
                $userJobTitle = $object.JobTitle
                $userSurname = $object.Surname
                $userUserPrincipalName = $object.UserPrincipalName
                $groupDescription = $null
                $spAppId = $null
                $spServicePrincipalType = $null
            }

            {$allMgServicePrincipalsDict.ContainsKey($_)} {

                $object = $allMgServicePrincipalsDict[$_]

                $objectType = 'ServicePrincipal'
                $userGivenName = $null
                $userJobTitle = $null
                $userSurname = $null
                $userUserPrincipalName = $null
                $groupDescription = $null
                $spAppId = $object.AppId
                $spServicePrincipalType = $object.ServicePrincipalType
            }

            {$allMgGroupsDict.ContainsKey($_)} {

                $object = $allMgGroupsDict[$_]
                $objectId = $object.Id
                $objectDisplayName = $object.DisplayName

                if (-not $assignedGroupsDict.ContainsKey($_)) {
                    
                    #$assignedGroupsDict.Add($_, $object)
                    $groupMemberIds = (Get-MgGroupMember -All -GroupId $_ -Property 'Id').Id

                    $assignedGroupsDict.Add($_, $groupMemberIds)
                }

                $groupMembersDict = [System.Collections.Generic.Dictionary[string, string]]::new()
                
                foreach ($id in $assignedGroupsDict[$_]) {

                    $groupMemberType = switch ($id) {

                        {$allMgUsersDict.ContainsKey($_)} { 'User' }
                        {$allMgServicePrincipalsDict.ContainsKey($_)} { 'ServicePrincipal' }
                        {$allMgGroupsDict.ContainsKey($_)} { 'Group' }
                        default { 'Unknown' }
                    }

                    $groupMembersDict.Add($id, $groupMemberType)
                }

                foreach ($key in $groupMembersDict.Keys) {

                    $objectType = $groupMembersDict[$key]

                    switch ($groupMembersDict[$key]) {
                        
                        {'User'} { 

                            $memberObject = $allMgUsersDict[$key]

                            $memberObjectId = $memberObject.Id
                            $memberObjectDisplayName = $memberObject.DisplayName
                            $objectType = $_
                            $userGivenName = $memberObject.GivenName
                            $userJobTitle = $memberObject.JobTitle
                            $userSurname = $memberObject.Surname
                            $userUserPrincipalName = $memberObject.UserPrincipalName
                            $groupDescription = $null
                            $spAppId = $null
                            $spServicePrincipalType = $null
                        
                        }

                        {'ServicePrincipal'} {

                            $memberObject = $allMgServicePrincipalsDict[$key]

                            $memberObjectId = $memberObject.Id
                            $memberObjectDisplayName = $memberObject.DisplayName
                            $objectType = $_
                            $userGivenName = $null
                            $userJobTitle = $null
                            $userSurname = $null
                            $userUserPrincipalName = $null
                            $groupDescription = $null
                            $spAppId = $memberObject.AppId
                            $spServicePrincipalType = $memberObject.ServicePrincipalType
                        }

                        {'Group'} {
                            
                            $memberObject = $allMgGroupsDict[$key]
                            
                            $memberObjectId = $memberObject.Id
                            $memberObjectDisplayName = $memberObject.DisplayName
                            $objectType = $_
                            $userGivenName = $null
                            $userJobTitle = $null
                            $userSurname = $null
                            $userUserPrincipalName = $null
                            $groupDescription = $memberObject.Description
                            $spAppId = $null
                            $spServicePrincipalType = $null
                        }
                    }

                    $assignmentGroup = $allMgGroupsDict[$objectId]

                    $resultsList.Add(

                        [PSCustomObject]@{
                            ObjectId = $memberObjectId
                            ObjectDisplayName = $memberObjectDisplayName
                            ObjectType = $objectType
                            AssignmentDirectoryScopeId = $roleAssignmentDirectoryScopeId
                            AssignmentDirectoryScope = $directoryScope
                            AssignmentType = 'Group Inherited'
                            AssignmentGroupDisplayName = $assignmentGroup.DisplayName
                            AssignmentGroupId = $assignmentGroup.Id
                            RoleDescription = $roleDescription
                            RoleDisplayName = $roleDisplayName
                            RoleId = $roleId
                            RoleIsBuiltIn = $roleIsBuiltIn
                            RoleIsEnabled = $roleIsEnabled
                            RoleResourceScopes = $roleResourceScopes
                            UserGivenName = $userGivenName
                            UserJobTitle = $userJobTitle
                            UserSurname = $userSurname
                            UserUserPrincipalName = $userUserPrincipalName
                            GroupDescription = $groupDescription
                            SpAppId = $spAppId
                            SpServicePrincipalType = $spServicePrincipalType
                        }
                    )
                }

                $objectType = 'Group'
                $userGivenName = $null
                $userJobTitle = $null
                $userSurname = $null
                $userUserPrincipalName = $null
                $groupDescription = $object.Description
                $spAppId = $null
                $spServicePrincipalType = $null
            }
        }

        $resultsList.Add(

            [PSCustomObject]@{
                ObjectId = $objectId
                ObjectDisplayName = $objectDisplayName
                ObjectType = $objectType
                AssignmentDirectoryScopeId = $roleAssignmentDirectoryScopeId
                AssignmentDirectoryScope = $directoryScope
                AssignmentType = 'Direct'
                AssignmentGroupDisplayName = $null
                AssignmentGroupId = $null
                RoleDescription = $roleDescription
                RoleDisplayName = $roleDisplayName
                RoleId = $roleId
                RoleIsBuiltIn = $roleIsBuiltIn
                RoleIsEnabled = $roleIsEnabled
                RoleResourceScopes = $roleResourceScopes
                UserGivenName = $userGivenName
                UserJobTitle = $userJobTitle
                UserSurname = $userSurname
                UserUserPrincipalName = $userUserPrincipalName
                GroupDescription = $groupDescription
                SpAppId = $spAppId
                SpServicePrincipalType = $spServicePrincipalType
            }
        )
    }
}
