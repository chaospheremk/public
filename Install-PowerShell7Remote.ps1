function Install-PowerShell7Remote {
    <#
    .SYNOPSIS
        Installs PowerShell 7 and enables PS7 remoting on remote servers running PowerShell 5.1.

    .DESCRIPTION
        Copies a local PowerShell 7 MSI installer to remote servers, executes a silent installation,
        and configures PowerShell 7 remoting. Uses existing PS 5.1 remoting to bootstrap the process.
        
        Uses fire-and-forget installation method with external polling to handle WinRM service
        restart that occurs when enabling PSRemoting.
        
        Performance notes:
        - Processes servers sequentially to avoid overwhelming network or remote resources
        - Copies installer once per server, removes after installation
        - Polls for completion every 5 seconds during installation

    .PARAMETER ComputerName
        One or more remote computer names or IP addresses. Must have PS 5.1 remoting enabled.

    .PARAMETER InstallerPath
        Local path to the PowerShell 7 MSI installer (e.g., PowerShell-7.x.x-win-x64.msi).

    .PARAMETER Credential
        Credential for authenticating to remote computers. If omitted, uses current user context.

    .PARAMETER ExplorerContext
        Adds 'Open PowerShell here' context menu in Explorer. Default: $true

    .PARAMETER FileContext
        Adds 'Run with PowerShell' context menu for files. Default: $true

    .PARAMETER EnableRemoting
        Enables PowerShell 7 remoting after installation. Default: $true

    .PARAMETER RegisterManifest
        Registers PowerShell manifest for event logging. Default: $true

    .PARAMETER AddToPath
        Adds PowerShell 7 to the system PATH during installation. Default: $true

    .PARAMETER DisableTelemetry
        Disables PowerShell telemetry. Default: $true

    .PARAMETER UseMU
        Uses Microsoft Update for updates. Default: $true

    .PARAMETER EnableMU
        Enables Microsoft Update. Default: $true

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
        
        The function uses a fire-and-forget approach because ENABLE_PSREMOTING restarts WinRM,
        which would kill the active remoting session. It polls externally for completion.
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
    }

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
                        # Ensure C:\temp exists and copy installer
                        $remoteTempPath = "C:\temp\$installerFileName"
                        Write-Verbose "[$computer] Ensuring temp directory exists..."
                        
                        Invoke-Command -Session $session -ScriptBlock {
                            if (-not (Test-Path 'C:\temp')) {
                                New-Item -Path 'C:\temp' -ItemType Directory -Force | Out-Null
                            }
                        } -ErrorAction Stop

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
                        $msiArgs.Add('/i')
                        $msiArgs.Add($remoteTempPath)
                        $msiArgs.Add('/quiet')
                        $msiArgs.Add('/norestart')
                        
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

                        # Execute installation (fire-and-forget because ENABLE_PSREMOTING restarts WinRM)
                        $installScript = {
                            param($Arguments)
                            
                            # Start installation without waiting (session will die when WinRM restarts)
                            $paramsStartProcess = @{
                                FilePath     = 'msiexec.exe'
                                ArgumentList = $Arguments
                                WindowStyle  = 'Hidden'
                                PassThru     = $true
                            }

                            $process = Start-Process @paramsStartProcess
                            
                            return @{
                                ProcessId = $process.Id
                                Started   = $true
                            }
                        }

                        $paramsInvokeCommandInstall = @{
                            Session      = $session
                            ScriptBlock  = $installScript
                            ArgumentList = $msiArgString
                            ErrorAction  = 'Stop'
                        }
                        
                        $installResult = Invoke-Command @paramsInvokeCommandInstall
                        Write-Verbose "[$computer] Installation started (PID: $($installResult.ProcessId))"

                        # Close the session before WinRM restarts
                        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
                        $session = $null

                        # Poll for installation completion
                        Write-Verbose "[$computer] Waiting for installation to complete (polling every 5s)..."
                        $pollStartTime = Get-Date
                        $installed = $false
                        $pollInterval = 5

                        while (((Get-Date) - $pollStartTime).TotalSeconds -lt $TimeoutSeconds) {
                            Start-Sleep -Seconds $pollInterval

                            try {
                                # Attempt to create new PS 5.1 session to check status
                                $checkSession = New-PSSession @sessionParams -ErrorAction Stop

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

                                $verification = Invoke-Command -Session $checkSession -ScriptBlock $verifyScript -ErrorAction Stop

                                if ($verification.Installed) {
                                    $installed = $true
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

                                        $remotingCheck = Invoke-Command -Session $checkSession -ScriptBlock $remotingScript -ErrorAction Stop
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
                                    Invoke-Command -Session $checkSession -ScriptBlock {
                                        param($Path)
                                        Remove-Item -Path $Path -Force -ErrorAction 'SilentlyContinue'
                                    } -ArgumentList $remoteTempPath -ErrorAction SilentlyContinue

                                    Remove-PSSession -Session $checkSession -ErrorAction SilentlyContinue
                                    break
                                }

                                Remove-PSSession -Session $checkSession -ErrorAction SilentlyContinue
                            }
                            catch {
                                # WinRM may still be restarting or installation still running
                                $elapsed = [math]::Round(((Get-Date) - $pollStartTime).TotalSeconds, 0)
                                Write-Verbose "[$computer] Still waiting... (${elapsed}s elapsed)"
                            }
                        }

                        if (-not $installed) {
                            throw "Installation verification timed out after $TimeoutSeconds seconds"
                        }

                        Write-Verbose "[$computer] Installation completed successfully"
                        $result.Success = $true
                    }
                    finally {
                        if ($session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
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
    }

    end {
        # Return results
        $results

        # Summary
        $successCount = $results.Where({ $_.Success }).Count
        $totalCount = $results.Count
        
        Write-Verbose "Installation summary: $successCount of $totalCount succeeded"
    }
}
