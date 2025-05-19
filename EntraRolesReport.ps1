$secVaultFilePath = Join-Path "$env:USERPROFILE\SecretStore" SecretStore.Vault.Credential
Unlock-SecretStore -Password (Import-CliXml -Path $secVaultFilePath)

$paramsConnectMgGraph = @{
    ClientId = Get-Secret -Name 'ClientId - djm-powershellautomation' | ConvertFrom-SecureString -AsPlainText
    TenantId = Get-Secret -Name 'TenantId - dougjohnsonme.onmicrosoft.com' | ConvertFrom-SecureString -AsPlainText
    CertificateThumbprint = Get-Secret -Name 'CertificateThumbprint - djm-powershellautomation' | ConvertFrom-SecureString -AsPlainText
    NoWelcome = $true
}

Connect-MgGraph @paramsConnectMgGraph


function Get-EntraRolesReport {

    [CmdletBinding()]
    Param()

    # Get all Entra users, store in dictionary
    try {

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
    }
    finally { Remove-Variable -Name @('propsMgUsers', 'paramsConvertToDictionary') }

    # Get all Entra service principals, store in dictionary
    try {

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
    }
    finally { Remove-Variable -Name @('propsMgServicePrincipals', 'paramsConvertToDictionary') }

    # Get all Entra groups, store in dictionary
    $allRoleAssignedGroupsDict = [System.Collections.Generic.Dictionary[string, PSObject]]::new()

    try {

        $propsMgGroups = @('Description', 'DisplayName', 'Id')

        $paramsGetMgGroup = @{
            All = $true
            Filter = "IsAssignableToRole eq true"
            Property = $propsMgGroups
        }

        $paramsConvertToDictionary = @{
            ObjectList = Get-MgGroup @paramsGetMgGroup | Select-Object -Property $propsMgGroups
            KeyProperty = 'Id'
        }

        $roleAssignedGroupsDict = ConvertTo-Dictionary @paramsConvertToDictionary

        foreach ($key in $roleAssignedGroupsDict.Keys) {

            $group = $roleAssignedGroupsDict[$key]

            [System.Collections.Generic.HashSet[string]]$groupMemberIds = (Get-MgBetaGroupTransitiveMember -GroupId $group.Id).Id

            $groupObject = [PSCustomObject]@{
                Description = $group.Description
                DisplayName = $group.DisplayName
                Id = $group.Id
                Members = $groupMemberIds
            }

            $allRoleAssignedGroupsDict.Add($group.Id, $groupObject)
        }
    }
    finally {

        Remove-Variable -Name @(

            'propsMgGroups', 'paramsGetMgGroup', 'paramsConvertToDictionary', 'roleAssignedGroupsDict'
        )
    }                   

    # Get all Entra Role assignments, store in dictionary
    try {

        $propsRoleAssignments = @('DirectoryScopeId', 'Id', 'PrincipalId', 'RoleDefinitionId')

        $paramsConvertToDictionary = @{
            ObjectList = Get-MgRoleManagementDirectoryRoleAssignment -All -Property $propsRoleAssignments |
                Select-Object -Property $propsRoleAssignments
            KeyProperty = 'Id'
        }

        $allRoleAssignmentsDict = ConvertTo-Dictionary @paramsConvertToDictionary
    }
    finally { Remove-Variable -Name @('propsRoleAssignments', 'paramsConvertToDictionary') }

    # Get all Entra Role definitions, store in dictionary
    try {

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
    }
    finally { Remove-Variable -Name @('propsRoleDefinitions', 'paramsConvertToDictionary') }

    # Get all Entra Administrative Units, store in dictionary
    try {

        $propsAdminUnits = @('Description', 'DisplayName', 'Id', 'IsMemberManagementRestricted')

        $paramsConvertToDictionary = @{
            ObjectList = Get-MgDirectoryAdministrativeUnit -All -Property $propsAdminUnits |
                Select-Object -Property $propsAdminUnits
            KeyProperty = 'Id'
        }

        $allAdminUnitsDict = ConvertTo-Dictionary @paramsConvertToDictionary
    }
    finally { Remove-Variable -Name @('propsAdminUnits', 'paramsConvertToDictionary') }


    # start logic
    $resultsList = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($key in $allRoleAssignmentsDict.Keys) {

        $roleAssignment = $allRoleAssignmentsDict[$key]
        $roleAssignmentDirectoryScopeId = $roleAssignment.DirectoryScopeId
        $principalId = $roleAssignment.PrincipalId
        $roleDefinitionId = $roleAssignment.RoleDefinitionId

        if (-not $allRoleDefinitionsDict.ContainsKey($roleDefinitionId)) { 

            $paramsGetRoleDefinition = @{
                UnifiedRoleDefinitionId = $roleDefinitionId
                Property = $propsRoleDefinitions
            }

            $roleDefinitionObject = Get-MgRoleManagementDirectoryRoleDefinition @paramsGetRoleDefinition |
                Select-Object -Property $propsRoleDefinitions

            $allRoleDefinitionsDict.Add($roleDefinitionId, $roleDefinitionObject) 
        }

        $roleDefinition = $allRoleDefinitionsDict[$roleDefinitionId]
        $roleDescription = $roleDefinition.Description
        $roleDisplayName = $roleDefinition.DisplayName
        $roleId = $roleDefinition.Id
        $roleIsBuiltIn = $roleDefinition.IsBuiltIn
        $roleIsEnabled = $roleDefinition.IsEnabled
        $roleResourceScopes = ($roleDefinition.ResourceScopes -join ',')

        $directoryScope = switch ($roleAssignmentDirectoryScopeId) {

            { $_ -eq '/' } { 'Root Directory' }

            { $_ -match '/administrativeUnits/'} {

                $adminUnitId = $_ -replace '/administrativeUnits/'

                "Administrative Unit: $($allAdminUnitsDict[$adminUnitId].DisplayName)"
            }
        }

        switch ($principalId) {

            {$allMgUsersDict.ContainsKey($_)} {

                $object = $allMgUsersDict[$principalId]
                $objectId = $object.Id
                $objectDisplayName = $object.DisplayName
                $objectType = 'User'
                $userGivenName = $object.GivenName
                $userJobTitle = $object.JobTitle
                $userSurname = $object.Surname
                $userUserPrincipalName = $object.UserPrincipalName
                $spAppId = $null
                $spServicePrincipalType = $null
            }

            {$allMgServicePrincipalsDict.ContainsKey($_)} {

                $object = $allMgServicePrincipalsDict[$principalId]
                $objectId = $object.Id
                $objectDisplayName = $object.DisplayName
                $objectType = 'ServicePrincipal'
                $userGivenName = $null
                $userJobTitle = $null
                $userSurname = $null
                $userUserPrincipalName = $null
                $spAppId = $object.AppId
                $spServicePrincipalType = $object.ServicePrincipalType
            }

            {$allRoleAssignedGroupsDict.ContainsKey($_)} {

                $groupObject = $allRoleAssignedGroupsDict[$principalId]
                $groupObjectId = $groupObject.Id
                $groupObjectDisplayName = $groupObject.DisplayName
                $groupObjectDescription = $groupObject.Description

                foreach ($member in $groupObject.Members) {

                    switch ($member) {

                        {$allMgUsersDict.ContainsKey($_)} {

                            $memberObject = $allMgUsersDict[$member]
                            $memberObjectId = $memberObject.Id
                            $memberObjectDisplayName = $memberObject.DisplayName
                            $memberObjectType = 'User'
                            $userGivenName = $memberObject.GivenName
                            $userJobTitle = $memberObject.JobTitle
                            $userSurname = $memberObject.Surname
                            $userUserPrincipalName = $memberObject.UserPrincipalName
                            $spAppId = $null
                            $spServicePrincipalType = $null
                        }

                        {$allMgServicePrincipalsDict.ContainsKey($_)} {

                            $memberObject = $allMgServicePrincipalsDict[$member]
                            $memberObjectId = $memberObject.Id
                            $memberObjectDisplayName = $memberObject.DisplayName
                            $memberObjectType = 'ServicePrincipal'
                            $userGivenName = $null
                            $userJobTitle = $null
                            $userSurname = $null
                            $userUserPrincipalName = $null
                            $spAppId = $memberObject.AppId
                            $spServicePrincipalType = $memberObject.ServicePrincipalType
                        }
                    }

                    $resultsList.Add(

                        [PSCustomObject]@{
                            ObjectId = $memberObjectId
                            ObjectDisplayName = $memberObjectDisplayName
                            ObjectType = $memberObjectType
                            AssignmentDirectoryScopeId = $roleAssignmentDirectoryScopeId
                            AssignmentDirectoryScope = $directoryScope
                            AssignmentType = 'Group'
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
                            SpAppId = $spAppId
                            SpServicePrincipalType = $spServicePrincipalType
                            GroupDescription = $groupObjectDescription
                            GroupDisplayName = $groupObjectDisplayName
                            GroupId = $groupObjectId
                        }
                    )
                }
            }
        }

        if ($allRoleAssignedGroupsDict.ContainsKey($principalId)) { continue }

        $resultsList.Add(

            [PSCustomObject]@{
                ObjectId = $objectId
                ObjectDisplayName = $objectDisplayName
                ObjectType = $objectType
                AssignmentDirectoryScopeId = $roleAssignmentDirectoryScopeId
                AssignmentDirectoryScope = $directoryScope
                AssignmentType = 'Direct'
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
                SpAppId = $spAppId
                SpServicePrincipalType = $spServicePrincipalType
                GroupDescription = $null
                GroupDisplayName = $null
                GroupId = $null
            }
        )
    }

    $resultsList
}
