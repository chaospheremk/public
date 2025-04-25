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

    process {

        if ($AsDictionary) {

            $paramsConvertToDictionary = @{

                ObjectList = [System.Collections.Generic.List[PSObject]]$ObjectList.Where($FilterBlock).ForEach($ForEachBlock)
                KeyProperty = $KeyProperty
            }
        
            $dictionary = ConvertTo-Dictionary @paramsConvertToDictionary

            return $dictionary
        }
        else {
            
            $result = $ObjectList.Where($FilterBlock).ForEach($ForEachBlock)
            return (,$result)
        }
    }
}

function ConvertTo-Dictionary {

    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Dictionary[string, PSObject]])]
    param (

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSObject]]
        $ObjectList,

        [Parameter(Mandatory = $true)]
        [string]
        $KeyProperty
    )

    begin { $dictionary = [System.Collections.Generic.Dictionary[string, PSObject]]::new() } # begin

    process {

        foreach ($object in $ObjectList) { $dictionary.Add($object.$KeyProperty, $object) }

        $dictionary
    } # process
}
