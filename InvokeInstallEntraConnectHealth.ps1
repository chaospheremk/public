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

    begin { <# no content #> } # begin

    process {

        $verboseMessage = "Copying file [$FileName] from share path [$SharePath] to destination [$Destination]"

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

        $envProp = 'EnvironmentName'
        $envVal = 'AzureUSGovernment'
        $updSvcHostProp = 'UpdaterServiceHost'
        $updSvcHostVal = 'autoupdate.msappproxy.us'
        $hlthSvcHostProp = 'HealthServiceHost'
        $hlthSvcHostVal = 'frontend.aadconnecthealth.microsoftazure.us'
    } # begin

    process {

        try {

            Write-Verbose -Message "Checking Azure AD Connect Agent Updater registry settings."

            $paramsGetUpdaterEnvProperty = @{
                Path = $UpdaterRegPath
                Name = $envProp
                ErrorAction = 'SilentlyContinue'
            }

            $updaterEnvName = (Get-ItemProperty @paramsGetUpdaterEnvProperty).$envProp

            if ($updaterEnvName -ne $envVal) {
                
                Write-Verbose -Message "Property [$envProp] not set at path [$UpdaterRegPath]."

                $paramsSetUpdaterEnvProperty = @{
                    Path = $UpdaterRegPath
                    Name = $envProp
                    Value = $envVal
                    ErrorAction = 'Stop'
                }

                Write-Verbose -Message "Setting property [$envProp] to value [$envVal]."

                try {

                    Set-ItemProperty @paramsSetUpdaterEnvProperty

                    Write-Verbose -Message "Set property [$envProp] to value [$envVal] successfully."
                }
                catch { $_ }
            }

            $paramsGetUpdaterSvcProperty = @{
                Path = $UpdaterRegPath
                Name = $updSvcHostProp
                ErrorAction = 'SilentlyContinue'
            }

            $updaterSvcHost = (Get-ItemProperty @paramsGetUpdaterSvcProperty).$updSvcHostProp

            if ($updaterSvcHost -ne $updSvcHostVal) {
                
                Write-Verbose -Message "Property [$updSvcHostProp] not set at path [$UpdaterRegPath]."

                $paramsSetUpdaterSvcProperty = @{
                    Path = $UpdaterRegPath
                    Name = $updSvcHostProp
                    Value = $updSvcHostVal
                    ErrorAction = 'Stop'
                }

                Write-Verbose -Message "Setting property [$updSvcHostProp] to value [$updSvcHostVal]."

                try {

                    Set-ItemProperty @paramsSetUpdaterSvcProperty
                    Write-Verbose -Message "Set property [$updSvcHostProp] to value [$updSvcHostVal] successfully."
                }
                catch { $_ }
            }

            Write-Verbose -Message "Checking Entra Connect Agent Updater registry settings."

            $paramsGetHealthEnvProperty = @{
                Path = $HealthRegPath
                Name = $envProp
                ErrorAction = 'SilentlyContinue'
            }

            $healthEnvName = (Get-ItemProperty @paramsGetHealthEnvProperty).$envProp

            if ($healthEnvName -ne $envVal) {
                
                Write-Verbose -Message "Property [$envProp] not set at path [$HealthRegPath]."

                $paramsSetHealthEnvProperty = @{
                    Path = $HealthRegPath
                    Name = $envProp
                    Value = $envVal
                    ErrorAction = 'Stop'
                }

                Write-Verbose -Message "Setting property [$envProp] to value [$envVal]."

                try {

                    Set-ItemProperty @paramsSetHealthEnvProperty

                    Write-Verbose -Message "Set property [$envProp] to value [$envVal] successfully."
                }
                catch { $_ }
            }

            $paramsGetHealthSvcProperty = @{
                Path = $HealthRegPath
                Name = $hlthSvcHostProp
                ErrorAction = 'SilentlyContinue'
            }

            $healthSvcHost = (Get-ItemProperty @paramsGetHealthSvcProperty).$hlthSvcHostProp

            if ($healthSvcHost -ne $hlthSvcHostVal) {

                Write-Verbose -Message "Property [$hlthSvcHostProp] not set at path [$HealthRegPath]."

                $paramsSetHealthSvcProperty = @{
                    Path = $HealthRegPath
                    Name = $hlthSvcHostProp
                    Value = $hlthSvcHostVal
                    ErrorAction = 'Stop'
                }

                Write-Verbose -Message "Setting property [$hlthSvcHostProp] to value [$hlthSvcHostVal]."

                try {

                    Set-ItemProperty @paramsSetHealthSvcProperty

                    Write-Verbose -Message "Set property [$hlthSvcHostProp] to value [$hlthSvcHostVal] successfully."
                }
                catch { $_ }
            }
        }
        catch { $_ }
    } # process

    end { <# no content #> } # end
}

# make sure C:\temp folder exists
Write-Verbose -Message "Checking for existence of path [$destination]."

$fileName = 'MicrosoftEntraConnectHealthAgentSetup.exe'
$sharePath = ''
$destination = 'C:\temp'

if (-not (Test-Path -Path $destination)) {

    Write-Verbose -Message "Path [$destination] does not exist."
    Write-Verbose -Message "Creating folder path [$destination]."

    try {

        $null = New-Item -Path 'C:\' -Name 'temp' -ItemType Directory -Force

        Write-Verbose -Message "Folder path [$destination] was created successfully."
    }
    catch { $_ }
}
else { Write-Verbose -Message "Path [$destination] already exists."}

## download installer to C:\temp folder
$installerPath = "$destination\$fileName"

Write-Verbose -Message "Checking for existence of file [$installerPath]."

if (-not (Test-Path -Path "$installerPath")) {

    Write-Verbose -Message "File [$installerPath] does not exist."
    Write-Verbose -Message "Downloading file [$fileName] from share [$sharePath]."

    $paramsCopyFile = @{
        FileName = $fileName
        SharePath = $sharePath
        Destination = $destination
        ErrorAction = 'Stop'
    }

    try {

        Copy-FileFromShare @paramsCopyFile

        Write-Verbose -Message "File [$fileName] was downloaded successfully."
    }
    catch { $_ }
}

###########################################################################################################################
## install silently with no registration
Write-Verbose -Message "Running installer [$fileName]."

$exeArgs = @( '/quiet', 'AddsMonitoringEnabled=1', 'SkipRegistration=1')

try {

    $null = Invoke-CommandLine -ExePath $installerPath -ExeArgs $exeArgs -ErrorAction 'Stop'

    Write-Verbose -Message "Installer [$fileName] ran successfully."
}
catch { $_ }

# verify that Entra Connect Health is installed

$healthAgentInstalled = Confirm-EntraConnectHealthAgentInstalled

## make registry changes
Write-Verbose -Message "Making required registry changes."

Set-EntraConnectHealthRegistry





## create access token
## run registration command
