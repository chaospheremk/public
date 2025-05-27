function Get-TMMachineInfo {
<#
    .SYNOPSIS
        Retrieves specific information about one or more computers using WMI or
        CIM.

    .DESCRIPTION
        This command uses either WMI or CIM to retrieve specific information about
        one or more computers. You must run this command as a user with
        permission to query CIM or WMI on the machines involved remotely. You can
        specify a starting protocol (CIM by default), and specify
        that the other protocol be used on a per-machine basis in the event of a
        failure

    .PARAMETER ComputerName
        One or more computer names. When using WMI, this can also be IP addresses.
        IP addresses may not work for CIM.

    .PARAMETER Credential
        A PS credential to specify if connecting with a different user account.

    .PARAMETER LogFailuresToPath
        A path and filename to write failed computer names to. If omitted, no log
        will be written.

    .PARAMETER Protocol
        Valid values: Wsman (uses CIM) or Dcom (uses WMI). It will be used for all
        machines. "Wsman" is the default.

    .PARAMETER ProtocolFallback
        Specify this to try the other protocol if a machine fails automatically.

    .EXAMPLE
        Get-TMMachineInfo -ComputerName ONE,TWO,THREE
        This example will query three machines when multiple computer names are
        specified directly in the ComputerName parameter.

    .EXAMPLE
        ONE,TWO,THREE | Get-TMMachineInfo
        This example will query three machines when multiple computer names are
        passed through the pipeline to Get-TMMachineInfo.

    .EXAMPLE
        Get-ADComputer -Filter * | Select -ExpandProperty Name | Get-TMMachineInfo
        This example will attempt to query all machines in AD.
#>
    [CmdletBinding()]
    param (

        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('CN', 'MachineName', 'Name')]
        [string[]]
        $ComputerName,

        [PSCredential]
        $Credential,

        [string]
        $LogFailuresToPath,

        [ValidateSet('Wsman', 'Dcom')]
        [string]
        $Protocol = 'Wsman',

        [switch]
        $ProtocolFallback
    )

    begin {

        $sessionOption = New-CimSessionOption -Protocol $Protocol
        $paramsNewCimSession = @{ SessionOption = $sessionOption }

        if ($PSBoundParameters.ContainsKey('Credential')) { $paramsNewCimSession.Credential = $Credential }

        $propsCompSys = @(
            'Name', 'Manufacturer', 'Model', 'TotalPhysicalMemory', 'SystemType',
            'NumberOfProcessors', 'NumberOfLogicalProcessors'
        )

        $propsOS = @(
            'Version', 'BuildNumber', 'ServicePackMajorVersion',
            'ServicePackMinorVersion', 'SystemDrive'
        )

        $paramsGetCimCompSys = @{
            ClassName = 'Win32_ComputerSystem'
            Property  = $propsCompSys
        }

        $paramsGetCimProc = @{
            ClassName = 'Win32_Processor'
            Property  = 'AddressWidth'
        }

        $paramsGetCimOS = @{
            ClassName = 'Win32_OperatingSystem'
            Property  = $propsOS
        }
    } # begin

    process {

        foreach ($computer in $ComputerName) {

            $paramsNewCimSession.ComputerName = $computer
            $cimSession = New-CimSession @paramsNewCimSession

            $paramsGetCimCompSys.CimSession = $cimSession
            $computerInfo = Get-CimInstance @paramsGetCimCompSys | Select-Object -Property $propsCompSys

            $totalRamGB = [math]::Round(($computerInfo.TotalPhysicalMemory / 1GB), 2)

            $paramsGetCimProc.CimSession = $cimSession
            $cpuType = Get-CimInstance @paramsGetCimProc | Select-Object -First 1 -ExpandProperty 'AddressWidth'

            $paramsGetCimOS.CimSession = $cimSession
            $osInfo = Get-CimInstance @paramsGetCimOS | Select-Object -Property $propsOS

            $paramsGetCimFreeSpace = @{
                Query      = "SELECT FreeSpace FROM Win32_LogicalDisk WHERE DeviceID='$($osInfo.SystemDrive)'"
                CimSession = $cimSession
            }

            $freeSpace = Get-CimInstance @paramsGetCimFreeSpace | Select-Object -ExpandProperty 'FreeSpace'
            $freeSpaceGB = [math]::Round(($freeSpace / 1GB), 2)

            $cimSession | Remove-CimSession

            [PSCustomObject] @{
                ComputerName              = $computerInfo.Name
                ComputerManufacturer      = $computerInfo.Manufacturer
                ComputerModel             = $computerInfo.Model
                'ComputerTotalRAM(GB)'    = $totalRamGB
                ComputerCPUType           = $cpuType
                ComputerCPUSocketCount    = $computerInfo.NumberOfProcessors
                ComputerCPUCoreCount      = $computerInfo.NumberOfLogicalProcessors
                OSVersion                 = $osInfo.Version
                OSBuildNumber             = $osInfo.BuildNumber
                OSServicePackMajorVersion = $osInfo.ServicePackMajorVersion
                OSServicePackMinorVersion = $osInfo.ServicePackMinorVersion
                OSSystemDrive             = $osInfo.SystemDrive
                'DiskFreeSpace(GB)'       = $freeSpaceGB
            }
        }
    } # process

    end { <# no content #> } # end
}

function Set-TMServiceLogon {

    [CmdletBinding(SupportsShouldProcess)]
    param (

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $ServiceName,

        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string[]]
        $ComputerName,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]
        $NewPassword,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]
        $NewUser,

        [string]
        $ErrorLogFilePath,

        [PSCredential]
        $Credential
    )

    begin { 

        # initialize CimSession params
        $sessionOption = New-CimSessionOption -Protocol 'Wsman'
        $paramsNewCimSession = @{
            SessionOption = $sessionOption
            Verbose       = $false
        }
        if ($PSBoundParameters.ContainsKey('Credential')) { $paramsNewCimSession.Credential = $Credential }

        # initialize Change method arguments
        $arguments = @{ 'StartPassword' = $NewPassword }
        if ($PSBoundParameters.ContainsKey('NewUser')) { $arguments.'StartName' = $NewUser }
        else { Write-Warning "Not setting a new user name" }

        # initialize Invoke-CimMethod params
        $paramsInvokeCimMethod = @{
            Query      = "SELECT * FROM Win32_Service WHERE Name='$ServiceName'"
            MethodName = 'Change'
            Arguments  = $arguments
        }
    } # begin

    process {

        foreach ($computer in $ComputerName) {

            Write-Verbose "Connect to $computer on WS-MAN"

            # create Cim session, add CimSession to Invoke-CimMethod params
            $paramsNewCimSession.ComputerName = $computer
            $cimSession = New-CimSession @paramsNewCimSession
            $paramsInvokeCimMethod.CimSession = $cimSession

            Write-Verbose "Setting $serviceName on $computer"

            if ($PSCmdlet.ShouldProcess($computer)) {

                $result = Invoke-CimMethod @paramsInvokeCimMethod | Select-Object -Property 'ReturnValue'

                $status = switch ($result.ReturnValue) {
                    0 { 'Success' }
                    22 { 'Invalid Account' }
                    default { "Failed: $($result.ReturnValue)" }
                }
            }
            else { $status = 'WhatIf: Skipped' }

            Write-Verbose "Closing connection to $computer"

            # remove Cim session
            $cimSession | Remove-CimSession -WhatIf:$false

            # output result
            [PSCustomObject]@{
                ComputerName = $computer
                Status       = $status
            }
        }
    } # process

    end { <# no content #> } # end
} # function Set-TMServiceLogon