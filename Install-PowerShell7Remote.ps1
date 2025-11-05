function Install-PowerShell7Remote {
    <#
    .SYNOPSIS
        Installs PowerShell 7 and enables PS7 remoting on remote servers running PowerShell 5.1.

    .DESCRIPTION
        Copies a local PowerShell 7 MSI installer to remote servers, executes a silent installation,
        and configures PowerShell 7 remoting. Uses existing PS 5.1 remoting to bootstrap the process.
        
        Performance notes:
        - Processes servers sequentially to avoid overwhelming network or remote resources
        - Copies installer once per server, removes after installation
        - Uses WinRM sessions directly rather than Invoke-Command wrapper overhead

    .PARAMETER ComputerName
        One or more remote computer names or IP addresses. Must have PS 5.1 remoting enabled.

    .PARAMETER InstallerPath
        Local path to the PowerShell 7 MSI installer (e.g., PowerShell-7.x.x-win-x64.msi).

    .PARAMETER Credential
        Credential for authenticating to remote computers. If omitted, uses current user context.

    .PARAMETER AddToPath
        Adds PowerShell 7 to the system PATH during installation. Default: $true

    .PARAMETER EnableRemoting
        Enables PowerShell 7 remoting after installation. Default: $true

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for installation completion on each server. Default: 300

    .EXAMPLE
        Install-PowerShell7Remote -ComputerName 'Server01','Server02' -InstallerPath 'C:\Installers\PowerShell-7.4.6-win-x64.msi'
        
        Installs PowerShell 7 on Server01 and Server02 using the specified installer.

    .EXAMPLE
        $cred = Get-Credential
        Install-PowerShell7Remote -ComputerName (Get-Content servers.txt) -InstallerPath '.\PS7.msi' -Credential $cred
        
        Installs PowerShell 7 on all servers listed in servers.txt using specified credentials.

    .OUTPUTS
        PSCustomObject with properties: ComputerName, Success, InstalledVersion, RemotingEnabled, ErrorMessage

    .NOTES
        Requires:
        - PowerShell 5.1 remoting enabled on target servers
        - Administrative privileges on target servers
        - Network access to target servers on WinRM ports (5985/5986)
        - MSI installer file accessible locally
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateScript({

            if (-not (Test-Path -Path $_ -PathType 'Leaf')) { throw "Installer file not found: $_" }

            if ($_ -notmatch '\.msi$') { throw "Installer must be an MSI file: $_" }

            $true
        })]
        [string]$InstallerPath,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter()]
        [bool]$ExplorerContext = $true,

        [Parameter()]
        [bool]$FileContext = $true,

        [Parameter()]
        [bool]$EnableRemoting = $true,

        [Parameter()]
        [bool]$RegisterManifest = $true,

        [Parameter()]
        [bool]$AddToPath = $true,

        [Parameter()]
        [bool]$DisableTelemetry = $true,

        [Parameter()]
        [bool]$UseMU = $true,

        [Parameter()]
        [bool]$EnableMU = $true,

        [Parameter()]
        [ValidateRange(60, 1800)]
        [int]$TimeoutSeconds = 300
    )

    begin {
        $installerFile = Get-Item -Path $InstallerPath
        $installerFileName = $installerFile.Name
        $results = [System.Collections.Generic.List[PSObject]]::new()

        Write-Verbose "Installer: $($installerFile.FullName) ($([math]::Round($installerFile.Length / 1MB, 2)) MB)"
    } # begin

    process {

        foreach ($computer in $ComputerName) {

            $result = [PSCustomObject]@{
                ComputerName     = $computer
                Success          = $false
                InstalledVersion = $null
                RemotingEnabled  = $false
                ErrorMessage     = $null
                DurationSeconds  = 0
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {

                if ($PSCmdlet.ShouldProcess($computer, "Install PowerShell 7 and enable remoting")) {

                    Write-Verbose "[$computer] Establishing PS 5.1 session..."

                    $sessionParams = @{
                        ComputerName = $computer
                        ErrorAction  = 'Stop'
                    }

                    if ($Credential) { $sessionParams.Credential = $Credential }

                    $session = New-PSSession @sessionParams

                    try {
                        # Copy installer to remote temp directory
                        $remoteTempPath = "C:\temp\$installerFileName"
                        Write-Verbose "[$computer] Copying installer to $remoteTempPath..."
                        
                        $paramsCopyItem = @{
                            Path        = $installerFile.FullName
                            Destination = $remoteTempPath
                            ToSession   = $session
                            Force       = $true
                            ErrorAction = 'Stop'
                        }

                        Copy-Item @paramsCopyItem

                        # Build installation arguments
                        $msiArgs = [System.Collections.Generic.List[string]]::new()
                        $msiArgs.Add('/package')
                        $msiArgs.Add($remoteTempPath)
                        $msiArgs.Add('/quiet')
                        #$msiArgs.Add('/norestart')
                        
                        if ($ExplorerContext) { $msiArgs.Add('ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1') }

                        if ($FileContext) { $msiArgs.Add('ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1') }
                        
                        if ($EnableRemoting) { $msiArgs.Add('ENABLE_PSREMOTING=1') }

                        if ($RegisterManifest) { $msiArgs.Add('REGISTER_MANIFEST=1') }

                        if ($AddToPath) { $msiArgs.Add('ADD_PATH=1') }

                        if ($DisableTelemetry) { $msiArgs.Add('DISABLE_TELEMETRY=1') }

                        if ($UseMU) { $msiArgs.Add('USE_MU=1') }

                        if ($EnableMU) { $msiArgs.Add('ENABLE_MU=1') }

                        $msiArgString = $msiArgs -join ' '
                        Write-Verbose "[$computer] Installing PowerShell 7..."
                        Write-Verbose "[$computer] MSI arguments: $msiArgString"

                        # Execute installation
                        $installScript = {
                            param($Arguments, $TimeoutSec)
                            
                            $paramsStartProcess = @{
                                FilePath     = 'msiexec.exe'
                                ArgumentList = $Arguments
                                Wait         = $true
                                PassThru     = $true
                                NoNewWindow  = $true
                            }

                            $process = Start-Process @paramsStartProcess
                            
                            $waitTime = 0
                            while (-not $process.HasExited -and $waitTime -lt $TimeoutSec) {

                                Start-Sleep -Seconds 2
                                $waitTime += 2
                            }

                            if (-not $process.HasExited) {

                                $process.Kill()
                                throw "Installation timed out after $TimeoutSec seconds"
                            }

                            return @{
                                ExitCode = $process.ExitCode
                                TimedOut = $false
                            }
                        }

                        $paramsInvokeCommandInstall = @{
                            Session      = $session
                            ScriptBlock  = $installScript
                            ArgumentList = $msiArgString, $TimeoutSeconds
                            ErrorAction  = 'Stop'
                        }
                        
                        $installResult = Invoke-Command @paramsInvokeCommandInstall

                        if ($installResult.ExitCode -ne 0 -and $installResult.ExitCode -ne 3010) {

                            throw "MSI installation failed with exit code: $($installResult.ExitCode)"
                        }

                        Write-Verbose "[$computer] Installation completed (exit code: $($installResult.ExitCode))"

                        # Verify installation and get version
                        $verifyScript = {

                            $pwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'

                            if (Test-Path $pwshPath) {

                                $versionOutput = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'

                                return @{
                                    Installed = $true
                                    Version   = $versionOutput
                                }
                            }

                            return @{
                                Installed = $false
                                Version   = $null
                            }
                        }

                        $paramsInvokeCommandVerification = @{
                            Session = $session
                            ScriptBlock = $verifyScript
                            ErrorAction = 'Stop'
                        }

                        $verification = Invoke-Command @paramsInvokeCommandVerification

                        if (-not $verification.Installed) {

                            throw "PowerShell 7 executable not found after installation"
                        }

                        $result.InstalledVersion = $verification.Version
                        Write-Verbose "[$computer] PowerShell 7 version: $($verification.Version)"

                        # Verify remoting if enabled
                        if ($EnableRemoting) {

                            Write-Verbose "[$computer] Verifying PowerShell 7 remoting..."
                            
                            $remotingScript = {

                                try {

                                    $endpoints = Get-PSSessionConfiguration -ErrorAction 'Stop'
                                    $ps7Endpoint = $endpoints.Where({ $_.Name -like 'PowerShell.7*' }, 'First')

                                    return @{
                                        Enabled  = $null -ne $ps7Endpoint
                                        Endpoint = $ps7Endpoint.Name
                                    }
                                }
                                catch {

                                    return @{
                                        Enabled  = $false
                                        Endpoint = $null
                                    }
                                }
                            }

                            $paramsInvokeCommandRemoting = @{
                                Session = $session
                                ScriptBlock = $remotingScript
                                ErrorAction = 'Stop'
                            }

                            $remotingCheck = Invoke-Command @paramsInvokeCommandRemoting
                            $result.RemotingEnabled = $remotingCheck.Enabled

                            if ($remotingCheck.Enabled) {

                                Write-Verbose "[$computer] PowerShell 7 remoting enabled: $($remotingCheck.Endpoint)"
                            }
                            else {

                                Write-Warning "[$computer] PowerShell 7 remoting verification failed"
                            }
                        }

                        # Cleanup installer
                        Write-Verbose "[$computer] Cleaning up installer file..."

                        $cleanupScript = {
                            param($Path)

                            Remove-Item -Path $Path -Force -ErrorAction 'SilentlyContinue'
                        }

                        $paramsInvokeCommandCleanup = @{
                            Session = $session
                            ScriptBlock = $cleanupScript
                            ArgumentList = $remoteTempPath
                            ErrorAction = 'SilentlyContinue'
                        }

                        Invoke-Command @paramsInvokeCommandCleanup

                        $result.Success = $true
                    }
                    finally {

                        if ($session) { Remove-PSSession -Session $session -ErrorAction 'SilentlyContinue' }
                    }
                }
            }
            catch {

                $result.ErrorMessage = $_.Exception.Message
                Write-Warning "[$computer] Failed: $($_.Exception.Message)"
            }
            finally {

                $stopwatch.Stop()
                $result.DurationSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
                $results.Add($result)
            }
        }
    } # process

    end {
        # Return results
        $results

        # Summary
        $successCount = $results.Where({ $_.Success }).Count
        $totalCount = $results.Count
        
        Write-Verbose "Installation summary: $successCount of $totalCount succeeded"
    } # end
}
