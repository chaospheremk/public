function Select-ProjectedObjectList {

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [OutputType([System.Collections.Generic.List[PSObject]], ParameterSetName = 'Default')]
    [OutputType([System.Collections.Generic.Dictionary[string, PSObject]], ParameterSetName = 'AsDictionary')]

    param (

        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Parameter(Mandatory, ParameterSetName = 'AsDictionary')]
        [ValidateNotNullOrEmpty()]
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
    } # begin

    process {

        if ($AsDictionary) {

            $paramsConvertToDictionary = @{

                ObjectList = [System.Collections.Generic.List[PSObject]]$list
                KeyProperty = $KeyProperty
            }
        
            ConvertTo-Dictionary @paramsConvertToDictionary
        }
        else { ,[System.Collections.Generic.List[PSObject]]$list }
    } # process
}

function ConvertTo-Dictionary {

    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, PSObject]])]
    param (

        [Parameter(Mandatory)]
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
            catch { Write-Error -Message $_ }
        }

        $dictionary
    } # process
}