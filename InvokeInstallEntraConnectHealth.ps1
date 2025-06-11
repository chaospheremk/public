function Copy-FileFromShare {

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]
        $FileName,

        [Parameter(Mandatory)]
        [string]
        $SharePath,

        [Parameter(Mandatory)]
        [string]
        $Destination,

        [PSCredential]
        $Credential
    )

    begin {
        # make sure source file exists
        $filePath = "$SharePath\$FileName"

        Write-Verbose -Message "Checking for existence of file '$filePath'."

        $psDriveName = 'FileDrive'
        $testDriveFilePath = "$psDriveName`:$fileName"

        $paramsNewPSDrive = @{
            Name = $psDriveName
            PSProvider = 'FileSystem'
            Root = $SharePath
            ErrorAction = 'Stop'
        }

        if ($Credential) { $paramsNewPSDrive.Add('Credential', $Credential) }

        try {

            Write-Verbose -Message "Creating PSDrive '$psDriveName'."

            $null = New-PSDrive @paramsNewPSDrive
        }
        catch { $_ }

        Write-Verbose -Message "PSDrive '$psDriveName' was created successfully."

        if ($PSCmdlet.ShouldProcess($testDriveFilePath, 'Check path')) {

            if (Test-Path -Path $testDriveFilePath) { Write-Verbose -Message "File '$filePath' exists." }
            else { throw "Source file $filePath does not exist." }
        }
    } # begin

    process {

        # make sure destination folder exists
        Write-Verbose -Message "Checking for existence of path '$Destination'."

        if (-not (Test-Path -Path $Destination)) {

            Write-Verbose -Message "Path '$Destination' does not exist."
            Write-Verbose -Message "Creating folder path '$Destination'."

            try { $null = New-Item -Path 'C:\' -Name 'temp' -ItemType Directory -Force }
            catch { $_ }

            Write-Verbose -Message "Folder path '$destination' was created successfully."
        }
        else { Write-Verbose -Message "Path '$Destination' already exists."}
        
        Write-Verbose -Message ("Copying file '$FileName' from share path '$SharePath' to destination" +
                                " '$Destination'")

        $paramsCopyItem = @{
            Path = $testDriveFilePath
            Destination = $Destination
            ErrorAction = 'Stop'
        }

        try {
            
            if ($PSCmdlet.ShouldProcess($testDriveFilePath, 'Copy file')) {
                
                Copy-Item @paramsCopyItem

                Write-Verbose -Message ("File '$FileName' from share path '$SharePath' was copied to destination" +
                                        " '$Destination' successfully.")
            }
        }
        catch { $_ }
    } # process

    end { 
        
        Write-Verbose -Message "Removing PSDrive '$psDriveName'."

        if ($PSCmdlet.ShouldProcess($psDriveName, 'Remove PSDrive')) {

            try { Remove-PSDrive -Name $psDriveName -ErrorAction 'Stop' }
            catch { $_ }

            Write-Verbose -Message "PSDrive '$psDriveName' was removed successfully."
        }
    } # end
}

function Invoke-CommandLine {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param(

        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]
        $ExePath,

        [Parameter(Mandatory)]
        [System.Array]
        $ExeArgs
    )

    begin { $command = $ExePath + ' ' + $ExeArgs -join ' ' }

    process {

        Write-Verbose -Message "Running command '$command'."

        if ($PSCmdlet.ShouldProcess($command, 'Run command')) {

            $output = & $ExePath @ExeArgs 2>&1

            if ($LASTEXITCODE -ne 0) {

                $tempOutput = foreach ($line in $output) {
                    
                    $lineIsEmpty = [string]::IsNullOrWhiteSpace($line)

                    if (-not $lineIsEmpty) { $line }
                }

                $formattedOutput = $tempOutput -join "`n"

                throw $formattedOutput
            }

            $output
        }

        Write-Verbose -Message "Command '$command' ran successfully."
    }
}

function Confirm-EntraConnectHealthAgentInstalled {

    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $HealthRegPath = 'HKLM:\SOFTWARE\Microsoft\Azure AD Connect Health Agent',

        [Parameter()]
        [string]
        $UpdaterRegPath = 'HKLM:\SOFTWARE\Microsoft\Azure AD Connect Agent Updater'
    )

    begin {

        Write-Verbose -Message "Checking if Entra Connect Health Agent is installed."

        $errorAction = @{ ErrorAction = 'SilentlyContinue' }
    } # begin

    process {

        try {

            $healthServiceExists = if (Get-Service -Name 'AzureADConnectHealthAgent' @errorAction) { $true }
                                   else { $false }

            $healthRegExists = if (Get-Item -Path $HealthRegPath @errorAction) { $true }
                               else { $false }

            $updaterSvcExists = if (Get-Service -Name 'AzureADConnectAgentUpdater' @errorAction) { $true }
                                else { $false}

            $updaterRegExists = if (Get-Item -Path $UpdaterRegPath @errorAction) { $true }
                                else { $false }

            $agentInstalled = $healthServiceExists -and $updaterSvcExists -and
                              $updaterRegExists -and $healthRegExists

            if ($agentInstalled) {

                Write-Verbose -Message "Entra Connect Health Agent is installed."
                $true
            }
            else {

                Write-Verbose -Message "Entra Connect Health Agent is not installed."
                $false
            }
        }
        catch { $_ }
    } # process

    end { <# no content #> } # end
}

function Install-EntraConnectHealthAgent {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (

        [ValidateScript({ Test-Path -Path $_ })]
        [string]
        $InstallerPath = 'C:\temp\MicrosoftEntraConnectHealthAgentSetup.exe'
    )

    begin { $exeArgs = @( '/quiet', 'AddsMonitoringEnabled=1', 'SkipRegistration=1') } # begin

    process {

        Write-Verbose -Message 'Installing Entra Connect Health agent.'

        if ($PSCmdlet.ShouldProcess($InstallerPath, 'Install agent')) {

            try {

                $null = Invoke-CommandLine -ExePath $InstallerPath -ExeArgs $exeArgs -ErrorAction 'Stop'

                Start-Sleep -Seconds 15

                if (-not (Confirm-EntraConnectHealthAgentInstalled)) {
                    
                    throw "Entra Connect Health agent was not installed successfully."
                }
            }
            catch { $_ }
        }

        Write-Verbose -Message "Entra Connect Health agent was installed successfully."
    } # process

    end { <# no content #> } # end
}

function Set-EntraConnectHealthRegistry {

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter()]
        [string]
        $HealthRegPath = 'HKLM:\SOFTWARE\Microsoft\Azure AD Connect Health Agent',

        [Parameter()]
        [string]
        $UpdaterRegPath = 'HKLM:\SOFTWARE\Microsoft\Azure AD Connect Agent Updater'
    )

    begin {

        # Registry configuration for Azure US Government
        $registryConfig = @{
            EnvironmentName = 'AzureUSGovernment'
            UpdaterServiceHost = 'autoupdate.msappproxy.us'
            HealthServiceHost = 'frontend.aadconnecthealth.microsoftazure.us'
        }

        # Define registry operations using parameter values
        $registryOperations = @(
            @{
                Path = $UpdaterRegPath
                Property = 'EnvironmentName'
                Value = $registryConfig.EnvironmentName
                Description = 'Azure AD Connect Agent Updater environment'
            },
            @{
                Path = $UpdaterRegPath
                Property = 'UpdaterServiceHost'
                Value = $registryConfig.UpdaterServiceHost
                Description = 'Azure AD Connect Agent Updater service host'
            },
            @{
                Path = $HealthRegPath
                Property = 'EnvironmentName'
                Value = $registryConfig.EnvironmentName
                Description = 'Entra Connect Health Agent environment'
            },
            @{
                Path = $HealthRegPath
                Property = 'HealthServiceHost'
                Value = $registryConfig.HealthServiceHost
                Description = 'Entra Connect Health Agent service host'
            }
        )

        $services = @('AzureADConnectHealthAgent', 'AzureADConnectAgentUpdater')
    } # begin

    process {

        Write-Verbose -Message "Stopping Entra Connect Health related services."

        if ($PSCmdlet.ShouldProcess('Services', 'Stop services')) {

            try {

                foreach ($service in $services) {

                    if ((Get-Service -Name $service).Status -eq 'Running') {
                        
                        Stop-Service -Name $service -ErrorAction 'Stop'
                    }
                }
            }
            catch { $_ }
        }

        Write-Verbose -Message "Stopped running Entra Connect Health related services successfully."

        foreach ($operation in $registryOperations) {

            Write-Verbose -Message "Checking registry setting: $($operation.Description)"

            # Get current value (handle non-existent paths gracefully)
            $currentValue = $null
            $pathExists = Test-Path -Path $operation.Path

            if ($pathExists) {

                $getParams = @{
                    Path = $operation.Path
                    Name = $operation.Property
                    ErrorAction = 'SilentlyContinue'
                }

                $currentValue = (Get-ItemProperty @getParams).($operation.Property)
            }

            # Check if update is needed
            if ($currentValue -ne $operation.Value) {

                $whatIfMessage = ("Set registry value '$($operation.Property)' to '$($operation.Value)'" +
                                  " at path '$($operation.Path)'")
                
                if (-not $pathExists) {

                    Write-Verbose -Message "Registry path '$($operation.Path)' does not exist"
                    $whatIfMessage = ("Create registry path '$($operation.Path)' and set" +
                                      " '$($operation.Property)' to '$($operation.Value)'")
                }
                else {

                    Write-Verbose -Message ("Property '$($operation.Property)' current value: '$currentValue'," +
                                            " required value: '$($operation.Value)'")
                }

                if ($PSCmdlet.ShouldProcess($operation.Path, $whatIfMessage)) {

                    try {
                        # Ensure registry path exists
                        if (-not $pathExists) {

                            Write-Verbose "Creating registry path: $($operation.Path)"

                            $null = New-Item -Path $operation.Path -Force -ErrorAction 'Stop'

                            Write-Verbose "Created registry path: $($operation.Path)"
                        }

                        # Set the registry value

                        Write-Verbose -Message ("Setting '$($operation.Property)' to '$($operation.Value)' at" +
                                                " '$($operation.Path)'")

                        $setParams = @{
                            Path = $operation.Path
                            Name = $operation.Property
                            Value = $operation.Value
                            ErrorAction = 'Stop'
                        }
                        
                        Set-ItemProperty @setParams

                        Write-Verbose -Message ("Successfully set '$($operation.Property)' to" +
                                                " '$($operation.Value)' at '$($operation.Path)'")
                    }
                    catch {

                        Write-Error -Message ("Failed to set registry value '$($operation.Property)' at" +
                                              " '$($operation.Path)': $($_.Exception.Message)")
                        continue
                    }
                }
            }
            else {
                
                Write-Verbose -Message "Registry setting '$($operation.Property)' already configured correctly"
            }
        }
    } # process

    end { <# no content #> } # end
}

function Register-EntraConnectHealthAgent {

    [CmdletBinding(SupportsShouldProcess = $true)]
    param (

        [Parameter(Mandatory = $true)]
        [string]
        $UserName,

        [Parameter(Mandatory = $true)]
        [string]
        $TenantId,

        [Parameter(Mandatory = $true)]
        [string]
        $ClientId,

        [SecureString]
        $ClientSecret = (Read-Host -AsSecureString -Prompt "Please enter the Client Secret")
    )

    begin {

        Write-Verbose -Message "Importing AdHealthConfiguration module."

        try {

            $moduleName = 'C:\Program Files\Microsoft Azure AD Connect Health Agent\Modules\AdHealthConfiguration'

            Import-Module -Name $moduleName -ErrorAction 'Stop'
        }
        catch { $_ }

        Write-Verbose -Message "AdHealthConfiguration module was imported successfully."

        $uri = "https://login.microsoftonline.us/$TenantId/oauth2/v2.0/token"

        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)

        $body = [Ordered]@{
            client_id = $ClientId
            client_secret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            grant_type = 'client_credentials'
            scope = "https://management.usgovcloudapi.net/.default"
        }

        $paramsInvokeRestMethod = @{
            Method = 'Post'
            Uri = $uri
            Body = $body
            ContentType = 'application/x-www-form-urlencoded'
            ErrorAction = 'Stop'
        }
    } # begin

    process {

        try {

            Write-Verbose -Message "Generating AadToken"

            if ($PSCmdlet.ShouldProcess('Entra ID', 'Get access token')) {

                $paramsConvertToSecureString = @{
                    String = (Invoke-RestMethod @paramsInvokeRestMethod).access_token
                    AsPlainText = $true
                    Force = $true
                }
            }

            Write-Verbose -Message "AadToken was generated successfully."

            Write-Verbose -Message "Registering Entra Connect Health agent."

            if ($PSCmdlet.ShouldProcess('Entra Connect Health agent', 'Register')) {

                $paramsRegisterECHAgent = @{
                    UserPrincipalName = $userName
                    AadToken = ConvertTo-SecureString @paramsConvertToSecureString
                }

                try {

                    Register-MicrosoftEntraConnectHealthAgent @paramsRegisterECHAgent

                    $loopCount = 0

                    do {

                        Start-Sleep -Seconds 1

                        $status = (Get-Service -Name 'AzureADConnectHealthAgent').Status

                        $loopCount++
                    } while (($status -ne 'Running') -or ($loopCount -gt 5))
                }
                catch { $_ }
            }

            Write-Verbose -Message 'Entra Connect Health agent was registered successfully.'

            Write-Verbose -Message 'Starting AzureADConnectAgentUpdater service.'

            if ($PSCmdlet.ShouldProcess('AzureADConnectAgentUpdater', 'Start service')) {

                try { Start-Service -Name 'AzureADConnectAgentUpdater' -ErrorAction 'Stop' }
                catch { $_ }
            }

            Write-Verbose -Message 'AzureADConnectAgentUpdater was started successfully.'
        }
        catch { $_ }
    } # process

    end { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } # end
}
