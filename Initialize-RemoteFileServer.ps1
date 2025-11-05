function Initialize-RemoteFileServer {
    <#
    .SYNOPSIS
        Prepares remote file servers with PowerShell 7 and required modules.

    .DESCRIPTION
        Uses Invoke-Command to remotely install PowerShell 7, register a custom
        repository, and install required modules (NTFSSecurity and COMPANYPSTools).
        
        Designed for bulk preparation of file servers before running additional
        automation scripts. Each step is executed sequentially with validation.

    .PARAMETER ComputerName
        One or more remote computer names to configure.

    .PARAMETER RepositoryName
        Name for the custom PowerShell repository (e.g., 'CompanyRepo').

    .PARAMETER RepositoryUri
        URI of the self-hosted PowerShell repository (e.g., 'https://psrepo.company.com/nuget').

    .PARAMETER Credential
        PSCredential object for remote authentication. If not provided, uses current context.

    .PARAMETER PS7InstallerUri
        URI to PowerShell 7 MSI installer. Defaults to latest stable release from GitHub.

    .PARAMETER SkipPS7Install
        Skip PowerShell 7 installation if already present and version is acceptable.

    .EXAMPLE
        $cred = Get-Credential
        $servers = 'FS01', 'FS02', 'FS03'
        $results = Initialize-RemoteFileServer -ComputerName $servers -RepositoryName 'CompanyRepo' -RepositoryUri 'https://psrepo.company.com/nuget' -Credential $cred
        $results | Where-Object { -not $_.Success } | Format-Table

    .EXAMPLE
        Initialize-RemoteFileServer -ComputerName 'FS01' -RepositoryName 'CompanyRepo' -RepositoryUri 'https://psrepo.company.com/nuget' -SkipPS7Install

    .NOTES
        Performance: Processes servers in parallel via Invoke-Command.
        Requirements: WinRM enabled on target servers, administrative access.
        PowerShell 7 installation requires reboot in rare cases; function does not force reboot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryName,

        [Parameter(Mandatory)]
        [ValidatePattern('^https?://')]
        [string]$RepositoryUri,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter()]
        [ValidatePattern('^https?://')]
        [string]$PS7InstallerUri = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7-win-x64.msi',

        [Parameter()]
        [switch]$SkipPS7Install
    )

    begin {
        $computerList = [System.Collections.Generic.List[string]]::new()
        
        $scriptBlock = {
            param(
                [string]$RepoName,
                [string]$RepoUri,
                [string]$InstallerUri,
                [bool]$SkipInstall
            )

            $result = [PSCustomObject]@{
                ComputerName       = $env:COMPUTERNAME
                PS7Installed       = $false
                PS7Version         = $null
                RepositoryAdded    = $false
                NTFSSecurityAdded  = $false
                COMPANYPSToolsAdded = $false
                Success            = $false
                Errors             = [System.Collections.Generic.List[string]]::new()
                ExecutionTime      = $null
            }

            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                # Step 1: Install PowerShell 7
                $pwshPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
                
                if ($SkipInstall -and (Test-Path $pwshPath)) {
                    $result.PS7Installed = $true
                    $versionCheck = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
                    $result.PS7Version = $versionCheck
                } else {
                    $tempMsi = Join-Path $env:TEMP "pwsh7_$(Get-Random).msi"
                    
                    try {
                        $webClient = [System.Net.WebClient]::new()
                        $webClient.DownloadFile($InstallerUri, $tempMsi)
                        
                        $msiArgs = @(
                            '/i'
                            $tempMsi
                            '/quiet'
                            '/norestart'
                            'ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1'
                            'ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1'
                            'ENABLE_PSREMOTING=1'
                            'REGISTER_MANIFEST=1'
                        )
                        
                        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -PassThru -NoNewWindow
                        
                        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
                            $result.PS7Installed = $true
                            if (Test-Path $pwshPath) {
                                $versionCheck = & $pwshPath -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
                                $result.PS7Version = $versionCheck
                            }
                        } else {
                            $result.Errors.Add("PowerShell 7 installation failed with exit code: $($process.ExitCode)")
                            return $result
                        }
                    } finally {
                        if (Test-Path $tempMsi) {
                            Remove-Item $tempMsi -Force -ErrorAction SilentlyContinue
                        }
                    }
                }

                if (-not $result.PS7Installed) {
                    $result.Errors.Add('PowerShell 7 installation verification failed')
                    return $result
                }

                # Step 2-4: Execute remaining steps in PowerShell 7 context
                $ps7Script = @"
`$ErrorActionPreference = 'Stop'
`$results = @{
    RepositoryAdded = `$false
    NTFSSecurityAdded = `$false
    COMPANYPSToolsAdded = `$false
    Errors = @()
}

try {
    # Step 2: Register custom repository
    if (-not (Get-PSRepository -Name '$RepoName' -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Name '$RepoName' -SourceLocation '$RepoUri' -InstallationPolicy Trusted
    }
    `$results.RepositoryAdded = `$true
} catch {
    `$results.Errors += "Repository registration failed: `$(`$_.Exception.Message)"
}

try {
    # Step 3: Install NTFSSecurity module
    if (-not (Get-Module -Name NTFSSecurity -ListAvailable)) {
        Install-Module -Name NTFSSecurity -Force -AllowClobber -Scope AllUsers
    }
    `$results.NTFSSecurityAdded = `$true
} catch {
    `$results.Errors += "NTFSSecurity installation failed: `$(`$_.Exception.Message)"
}

try {
    # Step 4: Install COMPANYPSTools from custom repository
    if (-not (Get-Module -Name COMPANYPSTools -ListAvailable)) {
        Install-Module -Name COMPANYPSTools -Repository '$RepoName' -Force -AllowClobber -Scope AllUsers
    }
    `$results.COMPANYPSToolsAdded = `$true
} catch {
    `$results.Errors += "COMPANYPSTools installation failed: `$(`$_.Exception.Message)"
}

`$results | ConvertTo-Json -Compress
"@

                $ps7Result = & $pwshPath -NoProfile -Command $ps7Script
                $ps7Data = $ps7Result | ConvertFrom-Json

                $result.RepositoryAdded = $ps7Data.RepositoryAdded
                $result.NTFSSecurityAdded = $ps7Data.NTFSSecurityAdded
                $result.COMPANYPSToolsAdded = $ps7Data.COMPANYPSToolsAdded
                
                foreach ($err in $ps7Data.Errors) {
                    $result.Errors.Add($err)
                }

                $result.Success = $result.PS7Installed -and 
                                  $result.RepositoryAdded -and 
                                  $result.NTFSSecurityAdded -and 
                                  $result.COMPANYPSToolsAdded

            } catch {
                $result.Errors.Add("Unexpected error: $($_.Exception.Message)")
            } finally {
                $stopwatch.Stop()
                $result.ExecutionTime = $stopwatch.Elapsed.ToString()
            }

            return $result
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            $computerList.Add($computer)
        }
    }

    end {
        if ($computerList.Count -eq 0) {
            Write-Warning 'No computers specified'
            return
        }

        $invokeParams = @{
            ComputerName = $computerList.ToArray()
            ScriptBlock  = $scriptBlock
            ArgumentList = @(
                $RepositoryName,
                $RepositoryUri,
                $PS7InstallerUri,
                $SkipPS7Install.IsPresent
            )
            ErrorAction  = 'Stop'
        }

        if ($PSBoundParameters.ContainsKey('Credential')) {
            $invokeParams.Credential = $Credential
        }

        try {
            $results = Invoke-Command @invokeParams
            
            # Return clean results without PS remoting metadata
            foreach ($result in $results) {
                [PSCustomObject]@{
                    ComputerName        = $result.ComputerName
                    PS7Installed        = $result.PS7Installed
                    PS7Version          = $result.PS7Version
                    RepositoryAdded     = $result.RepositoryAdded
                    NTFSSecurityAdded   = $result.NTFSSecurityAdded
                    COMPANYPSToolsAdded = $result.COMPANYPSToolsAdded
                    Success             = $result.Success
                    Errors              = $result.Errors
                    ExecutionTime       = $result.ExecutionTime
                }
            }
        } catch {
            Write-Error "Failed to execute remote commands: $($_.Exception.Message)"
        }
    }
}
