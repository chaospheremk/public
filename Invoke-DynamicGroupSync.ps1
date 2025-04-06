<#


$domain = 'dougjohnson.me'
$credential = Get-Credential

$ConfigPath = 'C:\temp\DynamicGroups.json'
$SchemaPath = 'C:\temp\DynamicGroupsSchema.json'

$paramsInvokeDynamicGroupSync = @{
    ConfigPath = $ConfigPath
    SchemaPath = $SchemaPath
    Domain     = $Domain
    Credential = $Credential
}
FilterType = 'LDAPFilter'

$paramsInvokeDynamicGroupSync = @{
    ConfigPath = $ConfigPath
    SchemaPath = $SchemaPath
}

Invoke-DynamicGroupSync @paramsInvokeDynamicGroupSync
sds
#>

function Invoke-DynamicGroupSync {

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (

        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(Mandatory, ParameterSetName = 'Authenticated')]
        [ValidateNotNullOrEmpty()]
        [string]$ConfigPath,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Authenticated')]
        [string]$SchemaPath,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'Authenticated')]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Filter','LDAPFilter')]
        [string]$FilterType = 'Filter',
        
        [Parameter(Mandatory, ParameterSetName = 'Authenticated')]
        [ValidateNotNullOrEmpty()]
        [string]$Domain,

        [Parameter(Mandatory, ParameterSetName = 'Authenticated')]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential
    )

    Begin {

        $paramsAD = @{ ErrorAction = 'Stop' }

        if ($PSCmdlet.ParameterSetName -eq 'Authenticated') {

            $paramsAD['Server'] = $Domain
            $paramsAD['Credential'] = $Credential
        }

        $paramsGetObjects = @{ Properties = 'ObjectGUID'}
    } # begin

    Process {

        # import dynamic group rules from json config file
        $rawJson = Get-Content -Raw -Path $ConfigPath -ErrorAction 'Stop'

        # validate json schema if provided
        if ($SchemaPath) { $null = $rawJson | Test-Json -SchemaFile $SchemaPath -ErrorAction 'Stop' }
        else { $null = $rawJson | Test-Json -ErrorAction 'Stop' }

        $rules = $rawJson | ConvertFrom-Json -ErrorAction 'Stop'

        # process each dynamic group rule
        foreach ($rule in $rules) {

            # establish variables
            $objectType = $rule.ObjectType
            $groupObjectGUID = $rule.GroupObjectGUID
            $toAddList = [System.Collections.Generic.List[object]]::new()
            $toRemoveList = [System.Collections.Generic.List[object]]::new()
            
            Write-Host "Processing dynamic group: $($rule.Name)" -ForegroundColor 'Cyan'

            # get target objects
            $paramsGetObjects = @{ SearchBase = $rule.SearchBase }
            
            switch ($FilterType) {

                'Filter' { $paramsGetObjects['Filter'] = $rule.Filter }
                'LDAPFilter' { $paramsGetObjects['LDAPFilter'] = $rule.LDAPFilter }
                default { throw "Unsupported filter type: $FilterType" }
            }

            $targetObjects = switch ($objectType) {

                'User' { Get-ADUser @paramsGetObjects @paramsAD }
                'Computer' { Get-ADComputer @paramsGetObjects @paramsAD }
                default { throw "Unsupported object type: $objectType" }
            }
            
            # get current group members
            $paramsGetMember = @{
                
                Identity = $groupObjectGUID
                Properties = 'Members'
            }
            #$currentMembers = Get-ADGroupMember @paramsGetMember @paramsAD | Select-Object -Property 'ObjectGUID'

            $currentMembers = Get-ADGroup @paramsGetMember @paramsAD | Select-Object -ExpandProperty 'Members'

            # build hashtables
            $targetMap = @{}
            foreach ($object in $targetObjects) { $targetMap[$object.'DistinguishedName'] = $object }

            $memberMap = @{}
            foreach ($member in $currentMembers) { $memberMap[$member] = $member }

            # get users to add
            foreach ($dn in $targetMap.Keys) {

                $memberMapContainsDn = $memberMap.ContainsKey($dn)

                if (-not $memberMapContainsDn) { $toAddList.Add($targetMap[$dn].'DistinguishedName') }
            }

            # get users to remove
            foreach ($dn in $memberMap.Keys) {

                $targetMapContainsDn = $targetMap.ContainsKey($dn)

                if (-not $targetMapContainsDn) { $toRemoveList.Add($memberMap[$dn]) }
            }

            $paramsAdGroupMember = @{
                Identity = $groupObjectGUID
                Confirm  = $false
            }

            if ($toAddList.Count -gt 0) {

                $paramsAdGroupMember['Members'] = $toAddList

                Write-Host "Adding members to group: $($rule.Name)" -ForegroundColor 'Green'
                Write-Host "Members to add: $($toAddList.Count)" -ForegroundColor 'Green'
                Add-ADGroupMember @paramsAdGroupMember @paramsAD
            }
            else {

                Write-Host "No members to add to group: $($rule.Name)"
            }

            if ($toRemoveList.Count -gt 0) {

                $paramsAdGroupMember['Members'] = $toRemoveList

                Write-Host "Removing members from group: $($rule.Name)" -ForegroundColor 'Yellow'
                Write-Host "Members to remove: $($toRemoveList.Count)" -ForegroundColor 'Yellow'
                Remove-ADGroupMember @paramsAdGroupMember @paramsAD
            }
            else {

                Write-Host "No members to remove from group: $($rule.Name)"
            }
        }
    } # process
}