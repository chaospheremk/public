# install Entra Connect Health


##################################
# FUNCTIONS

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
        $Destination
    )

    begin {
        # make sure source file exists
        $filePath = "$SharePath\$FileName"

        Write-Verbose -Message "Checking for existence of file '$filePath'."

        if (-not (Test-Path -Path $filePath)) {
            throw "Source file $filePath does not exist."
        }
    } # begin

    process {

        # make sure destination folder exists
        Write-Verbose -Message "Checking for existence of path '$Destination'."

        if (-not (Test-Path -Path $Destination)) {

            Write-Verbose -Message "Path '$Destination' does not exist."
            Write-Verbose -Message "Creating folder path '$Destination'."

            try {

                $null = New-Item -Path 'C:\' -Name 'temp' -ItemType Directory -Force

                Write-Verbose -Message "Folder path '$destination' was created successfully."
            }
            catch { $_ }
        }
        else { Write-Verbose -Message "Path '$Destination' already exists."}

        $verboseMessage = "Copying file '$FileName' from share path '$SharePath' to destination '$Destination'"
        Write-Verbose -Message $verboseMessage

        try { Copy-Item -Path "$SharePath\$FileName" -Destination $Destination -ErrorAction 'Stop' }
        catch { $_ }
    } # process

    end { <# no content #> } # end
}

function Invoke-CommandLine {

    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        [string]
        $ExePath,

        [Parameter(Mandatory)]
        [System.Array]
        $ExeArgs
    )

    process {

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
    } # begin

    process {

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

                $whatIfMessage = "Set registry value '$($operation.Property)' to '$($operation.Value)'" +
                                 " at path '$($operation.Path)'"
                
                if (-not $pathExists) {

                    Write-Verbose -Message "Registry path '$($operation.Path)' does not exist"
                    $whatIfMessage = "Create registry path '$($operation.Path)' and set '$($operation.Property)'" +
                                     " to '$($operation.Value)'"
                }
                else {

                    Write-Verbose -Message "Property '$($operation.Property)' current value: '$currentValue'," +
                                           " required value: '$($operation.Value)'"
                }

                if ($PSCmdlet.ShouldProcess($operation.Path, $whatIfMessage)) {

                    try {
                        # Ensure registry path exists
                        if (-not $pathExists) {
                            Write-Verbose "Creating registry path: $($operation.Path)"
                            $null = New-Item -Path $operation.Path -Force -ErrorAction 'Stop'
                        }

                        # Set the registry value
                        $setParams = @{
                            Path = $operation.Path
                            Name = $operation.Property
                            Value = $operation.Value
                            ErrorAction = 'Stop'
                        }
                        
                        Set-ItemProperty @setParams

                        Write-Verbose -Message "Successfully set '$($operation.Property)' to" +
                                               " '$($operation.Value)' at '$($operation.Path)'"
                    }
                    catch {

                        Write-Error -Message "Failed to set registry value '$($operation.Property)' at" +
                                             " '$($operation.Path)': $($_.Exception.Message)"
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

## download installer to C:\temp folder
$installerPath = "$destination\$fileName"

Write-Verbose -Message "Checking for existence of file '$installerPath'."

if (-not (Test-Path -Path "$installerPath")) {

    Write-Verbose -Message "File '$installerPath' does not exist."
    Write-Verbose -Message "Downloading file '$fileName' from share '$sharePath'."

    $paramsCopyFile = @{
        FileName = $fileName
        SharePath = $sharePath
        Destination = $destination
        ErrorAction = 'Stop'
    }

    try {

        Copy-FileFromShare @paramsCopyFile

        Write-Verbose -Message "File '$fileName' was downloaded successfully."
    }
    catch { $_ }
}

###########################################################################################################################
## install silently with no registration
Write-Verbose -Message "Running installer '$fileName'."

$exeArgs = @( '/quiet', 'AddsMonitoringEnabled=1', 'SkipRegistration=1')

try {

    $null = Invoke-CommandLine -ExePath $installerPath -ExeArgs $exeArgs -ErrorAction 'Stop'

    Write-Verbose -Message "Installer '$fileName' ran successfully."
}
catch { $_ }

# verify that Entra Connect Health is installed

$healthAgentInstalled = Confirm-EntraConnectHealthAgentInstalled

## make registry changes
Write-Verbose -Message "Making required registry changes."

Set-EntraConnectHealthRegistry





## create access token
## run registration command
