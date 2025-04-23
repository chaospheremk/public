function Select-CustomObjectList {

    [CmdletBinding()]
    param (

        $ObjectList,

        $WhereBlock,

        $ForEachBlock
    )

    begin {}

    process {

        if ($WhereBlock) { $ObjectList.Where($WhereBlock).ForEach($ForEachBlock) }
        else { $ObjectList.ForEach($ForEachBlock) }
    }

    end {}
}

[List[PSObject]]$test3 = $testObjectList.ForEach({

    [PSCustomObject]@{

        Name = $_.Name
        GivenName = $_.GivenName
        Surname = $_.Surname
        UserPrincipalName = $_.UserPrincipalName
        SamAccountName = $_.SamAccountName
        ExternalEmailAddress = $_.'msDS-cloudExtensionAttribute12'.ToLower().Trim()
    }
})
