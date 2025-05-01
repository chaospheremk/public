function Select-ProjectedObjectList {

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([System.Collections.Generic.List[PSObject]], ParameterSetName = 'Default')]
    [OutputType([System.Collections.Generic.Dictionary[string, PSObject]], ParameterSetName = 'AsDictionary')]

    param (

        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(Mandatory, ParameterSetName = 'AsDictionary')]
        [AllowNull()]
        [System.Collections.Generic.List[PSObject]]
        $ObjectList,

        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'AsDictionary')]
        [ScriptBlock]
        $FilterBlock = { $_ },

        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(Mandatory, ParameterSetName = 'AsDictionary')]
        [ValidateNotNullOrEmpty()]
        [ScriptBlock]
        $ForEachBlock,

        [Parameter(ParameterSetName = 'AsDictionary')]
        [switch]
        $AsDictionary,

        [Parameter(Mandatory, ParameterSetName = 'AsDictionary')]
        [string]
        $KeyProperty
    )

    begin {

        $list = [System.Collections.Generic.List[PSObject]]$ObjectList.Where($FilterBlock).ForEach($ForEachBlock)

        if ($AsDictionary) {

            $paramsConvertToDictionary = @{

                ObjectList = $list
                KeyProperty = $KeyProperty
            }
        }
    } # begin

    end {

        if ($AsDictionary) { ConvertTo-Dictionary @paramsConvertToDictionary }
        else { ,$list }
    }
}

function ConvertTo-Dictionary {

    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, PSObject]])]
    param (

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[PSObject]]
        $ObjectList,

        [Parameter(Mandatory)]
        [string]
        $KeyProperty
    )

    begin { $dictionary = [System.Collections.Generic.Dictionary[string, PSObject]]::new() }

    process {

        foreach ($object in $ObjectList) {

            $key = $object.$KeyProperty.ToString().Trim().ToLower()

            try { $dictionary.Add($key, $object) }
            catch { Write-Error -Message $_.Exception.Message }
        }

    } # process

    end { $dictionary }
}

function Get-DictionaryDelta {

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, PSObject]]
        $Source,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, PSObject]]
        $Target
    )

    begin {

        $adds    = [System.Collections.Generic.List[PSObject]]::new()
        $removes = [System.Collections.Generic.List[PSObject]]::new()
    }

    process {

        # Keys to Add (in Source but not in Target)
        foreach ($key in $Source.Keys) { if (-not $Target.ContainsKey($key)) { $adds.Add($Source[$key]) } }

        # Keys to Remove (in Target but not in Source)
        foreach ($key in $Target.Keys) { if (-not $Source.ContainsKey($key)) { $removes.Add($Target[$key]) } }
    }

    end {
        
        [PSCustomObject]@{
            Adds    = $adds
            Removes = $removes
        }
    }
}

function Invoke-DeclarativeReconciliation {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Collections.Generic.List[PSObject]]
        $SourceObjectList,

        [ScriptBlock]
        $SourceFilterBlock = { $_ },

        [ValidateNotNullOrEmpty()]
        [ScriptBlock]
        $SourceForEachBlock,

        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Collections.Generic.List[PSObject]]
        $TargetObjectList,

        [ScriptBlock]
        $TargetFilterBlock = { $_ },

        [ValidateNotNullOrEmpty()]
        [ScriptBlock]
        $TargetForEachBlock,

        [Parameter(Mandatory)]
        [string]
        $KeyProperty,

        [Parameter(Mandatory)]
        [ScriptBlock]
        $AddBlock,

        [Parameter(Mandatory)]
        [ScriptBlock]
        $RemoveBlock
    )

    begin {

        $paramsSourceProjectedObjectList = @{

            ObjectList = $SourceObjectList
            FilterBlock = $SourceFilterBlock
            ForEachBlock = $SourceForEachBlock
            AsDictionary = $true
            KeyProperty = $KeyProperty
        }

        $paramsTargetProjectedObjectList = @{

            ObjectList = $TargetObjectList
            FilterBlock = $TargetFilterBlock
            ForEachBlock = $TargetForEachBlock
            AsDictionary = $true
            KeyProperty = $KeyProperty
        }
    }
    # get the source and target dictionaries

    process {

        $sourceDict = Select-ProjectedObjectList @paramsSourceProjectedObjectList

        $targetDict = Select-ProjectedObjectList @paramsTargetProjectedObjectList

        # get the delta between the source and target dictionaries
        $delta = Get-DictionaryDelta -Source $sourceDict -Target $targetDict

        # if the delta is empty, return
        if ($delta.Adds) { & $AddBlock -Objects $delta.Adds }

        if ($delta.Removes) { & $RemoveBlock -Objects $delta.Removes }
    }
}
