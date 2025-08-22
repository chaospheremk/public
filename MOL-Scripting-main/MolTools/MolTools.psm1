function Get-TMMachineInfo {

    <#
    .SYNOPSIS
        Retrieves specific information about one or more computers using WMI or CIM.

    .DESCRIPTION
        This command uses either WMI or CIM to retrieve specific information about one or more
        computers. You must run this command as a user with permission to query CIM or WMI on the
        machines involved remotely. You can specify a starting protocol (CIM by default), and specify
        that the other protocol be used on a per-machine basis in the event of a failure.

    .PARAMETER ComputerName
        One or more computer names. When using WMI, this can also be IP addresses. IP addresses may
        not work for CIM.

    .PARAMETER Credential
        A PS credential to specify if connecting with a different user account.

    .PARAMETER LogFailuresToPath
        A path and filename to write failed computer names to. If omitted, no
        log will be written.

    .PARAMETER Protocol
        Valid values: Wsman (uses CIM) or Dcom (uses WMI). It will be used for all machines. "Wsman"
        is the default.

    .PARAMETER ProtocolFallback
        Specify this to try the other protocol if a machine fails automatically.

    .INPUTS
        System.String
        You can pipe a string that contains a computer name to this cmdlet.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        The cmdlet outputs a custom PSObject for reporting results.

    .EXAMPLE
        PS> Get-TMMachineInfo -ComputerName ONE,TWO,THREE
        This example will query three machines when multiple computer names are specified directly in
        the ComputerName parameter.

    .EXAMPLE
        PS> ONE,TWO,THREE | Get-TMMachineInfo
        This example will query three machines when multiple computer names are passed through the
        pipeline to Get-TMMachineInfo.

    .EXAMPLE
        PS> Get-ADComputer -Filter * | Select -ExpandProperty Name | Get-TMMachineInfo
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
        $paramsNewCimSession = @{
            SessionOption = $sessionOption
            Verbose       = $false
            ErrorAction   = 'Stop'
        }

        if ($PSBoundParameters.ContainsKey('Credential')) { $paramsNewCimSession.Credential = $Credential }

        $propsCompSys = @(
            'Name', 'Manufacturer', 'Model', 'TotalPhysicalMemory', 'SystemType',
            'NumberOfProcessors', 'NumberOfLogicalProcessors'
        )

        $propsOS = @( 'Version', 'BuildNumber', 'ServicePackMajorVersion', 'SystemDrive' )

        $paramsGetCS = @{
            ClassName = 'Win32_ComputerSystem'
            Property  = $propsCompSys
        }

        $paramsGetProc = @{
            ClassName = 'Win32_Processor'
            Property  = 'AddressWidth'
        }

        $paramsGetOS = @{
            ClassName = 'Win32_OperatingSystem'
            Property  = $propsOS
        }
    } # begin

    process {

        foreach ($computer in $ComputerName) {

            Write-Verbose "Connecting to $computer over $protocol"

            $paramsNewCimSession.ComputerName = $computer

            try {

                $cimSession = New-CimSession @paramsNewCimSession

                $paramsGetCS.CimSession = $cimSession
                $computerInfo = Get-CimInstance @paramsGetCS | Select-Object -Property $propsCompSys

                $paramsGetProc.CimSession = $cimSession
                $procArch = Get-CimInstance @paramsGetProc | Select-Object -First 1 -ExpandProperty 'AddressWidth'

                $paramsGetOS.CimSession = $cimSession
                $osInfo = Get-CimInstance @paramsGetOS | Select-Object -Property $propsOS

                $paramsGetFreeSpace = @{
                    Query      = "SELECT FreeSpace FROM Win32_LogicalDisk WHERE DeviceID='$($osInfo.SystemDrive)'"
                    CimSession = $cimSession
                }

                $freeSpace = Get-CimInstance @paramsGetFreeSpace | Select-Object -ExpandProperty 'FreeSpace'

                $cimSession | Remove-CimSession

                [PSCustomObject] @{
                    ComputerName      = $computerInfo.Name
                    OSVersion         = $osInfo.Version
                    SPVersion         = $osInfo.ServicePackMajorVersion
                    OSBuild           = $osInfo.BuildNumber
                    Manufacturer      = $computerInfo.Manufacturer
                    Model             = $computerInfo.Model
                    Procs             = $computerInfo.NumberOfProcessors
                    Cores             = $computerInfo.NumberOfLogicalProcessors
                    RAM               = [math]::Round(($computerInfo.TotalPhysicalMemory / 1GB), 2)
                    Arch              = $procArch
                    SysDriveFreeSpace = [math]::Round(($freeSpace / 1GB), 2)
                }
            }
            catch {

                Write-Warning "FAILED $computer on $protocol"

                if ($ProtocolFallback) {

                    if ($Protocol -eq 'Wsman') { $newProtocol = 'Dcom' }
                    else { $newProtocol = 'Wsman' }

                    Write-Verbose "Trying again with $newProtocol"

                    $paramsFallbackRun = @{
                        ComputerName     = $computer
                        Protocol         = $newProtocol
                        ProtocolFallback = $false
                    }

                    if ($PSBoundParameters.ContainsKey('LogFailuresToPath')) {
                        
                        $paramsFallbackRun.LogFailuresToPath = $LogFailuresToPath
                    }

                    Get-TMMachineInfo @paramsFallbackRun
                }

                if (-not $ProtocolFallback -and $PSBoundParameters.ContainsKey('LogFailuresToPath')) {

                    Write-Verbose "Logging to $LogFailuresToPath"

                    $computer | Out-File $LogFailuresToPath -Append
                }
            } # try/catch
        } # foreach ($computer in $ComputerName)
    } # process

    end { <# no content #> } # end
}

function Set-TMServiceLogon {

    <#
    .SYNOPSIS
        Sets service login name and password.

    .DESCRIPTION
        This command uses either CIM (default) or WMI to set the service password, and optionally the
        logon user name, for a service, which can be running on one or more remote machines. You must
        run this command as a user who has permission to perform this task, remotely, on the computers
        involved.
        
    .PARAMETER ServiceName
        The name of the service. Query the Win32_Service class to verify that you know the correct
        name.

    .PARAMETER ComputerName
        One or more computer names. Using IP addresses will fail with CIM; they will work with WMI.
        CIM is always attempted first.

    .PARAMETER NewPassword
        A plain-text string of the new password.

    .PARAMETER NewUser
        Optional; the new logon user name, in DOMAIN\USER format.

    .PARAMETER ErrorLogFilePath
        If provided, this is a path and filename of a text file where failed computer names will be
        logged.

    .PARAMETER Credential
        A PS credential to specify if connecting to remote machines with a different user account.

    .INPUTS
        System.String
        You can pipe a string that contains a computer name to this cmdlet.

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        The cmdlet outputs a custom PSObject for reporting results.

    .EXAMPLE
        PS> Set-TMServiceLogon -ServiceName 'BITS' -ComputerName ONE,TWO,THREE -NewPassword 'abc123'
        This example will update the service authentication password for the specified service on
        three machines when multiple computer names are specified directly in the ComputerName
        parameter.

    .EXAMPLE
        PS> ONE,TWO,THREE | Set-TMServiceLogon -ServiceName 'BITS' -NewPassword 'abc123'
        This example will update the service authentication password on three machines when multiple
        computer names are passed through the pipeline to Set-TMServiceLogon.

    .EXAMPLE
        PS> Set-TMServiceLogon -ServiceName 'BITS' -ComputerName computer1 -NewPassword 'abc123' `
        PS>                    -NewUser 'DOMAIN\username'
        This example will update the service authentication username and password for the specified
        service on specified computers.
#>

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
        $protocol = 'Wsman'
        $sessionOption = New-CimSessionOption -Protocol $protocol
        $paramsNewCimSession = @{
            SessionOption = $sessionOption
            Verbose       = $false
            ErrorAction   = 'Stop'
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

            Do {

                try {

                    if ($PSCmdlet.ShouldProcess($computer)) {

                        Write-Verbose "Connect to $computer on $protocol"

                        # create Cim session, add CimSession to Invoke-CimMethod params
                        $paramsNewCimSession.ComputerName = $computer

                        $cimSession = New-CimSession @paramsNewCimSession
                        $paramsInvokeCimMethod.CimSession = $cimSession

                        Write-Verbose "Setting $serviceName on $computer"
                        
                        $result = Invoke-CimMethod @paramsInvokeCimMethod | Select-Object -Property 'ReturnValue'

                        $status = switch ($result.ReturnValue) {
                            0 { 'Success' }
                            22 { 'Invalid Account' }
                            default { "Failed: $($result.ReturnValue)" }
                        }

                        Write-Verbose "Closing connection to $computer"

                        # remove Cim session
                        $cimSession | Remove-CimSession
                    }
                    else { $status = 'WhatIf: Skipped' }

                    # output result
                    [PSCustomObject]@{
                        ComputerName = $computer
                        Status       = $status
                    }

                    $protocol = 'Stop'
                }
                catch {

                    switch ($protocol) {
                        'Wsman' {
                            $protocol = 'Dcom'

                            Write-Warning "$computer failed on WS-MAN. Attempting Dcom."
                        }
                        'Dcom' {
                            $protocol = 'Stop'

                            if ($PSBoundParameters.ContainsKey('ErrorLogFilePath')) {

                                Write-Warning "$computer failed; logged to $ErrorLogFilePath"
                                $computer | Out-File $ErrorLogFilePath -Append
                            }
                        }
                    }
                }
            } Until ($protocol -eq 'Stop')
        }
    } # process

    end { <# no content #> } # end
} # function Set-TMServiceLogon