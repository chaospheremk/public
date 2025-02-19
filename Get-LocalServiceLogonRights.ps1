function Get-LocalServiceLogonRights {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true,
                   ValueFromPipeline = $true,
                   ValueFromPipelineByPropertyName = $true,
                   HelpMessage = "Enter one or more target computer names.")]
        [string[]]$ComputerName,

        [Parameter(HelpMessage = "Specify credentials if needed to access the remote computer(s).")]
        [System.Management.Automation.PSCredential]$Credential
    )

    # Initialize an array to hold the results
    $results = @()

    foreach ($server in $ComputerName) {
        try {
            # Establish a remote PowerShell session to the target server.
            $sessionParams = @{
                ComputerName = $server
                ErrorAction  = 'Stop'
            }
            if ($Credential) {
                $sessionParams.Credential = $Credential
            }
            $session = New-PSSession @sessionParams

            # ScriptBlock to run on the remote machine.
            # It exports the security policy (USER_RIGHTS area) and then extracts the account(s)
            # assigned the "Log on as a service" right (SeServiceLogonRight).
            $scriptBlock = {
                # Create a temporary file path for the export
                $tempPath = [System.IO.Path]::Combine($env:TEMP, [System.IO.Path]::GetRandomFileName() + ".inf")

                try {
                    # Export the local security policy for user rights assignments.
                    secedit.exe /export /cfg $tempPath /areas USER_RIGHTS | Out-Null

                    # Read the content of the exported file.
                    $content = Get-Content -Path $tempPath -ErrorAction Stop

                    # Find the line that starts with "SeServiceLogonRight"
                    $line = $content | Where-Object { $_ -match '^SeServiceLogonRight\s*=' }
                    if ($line) {
                        # The expected format: SeServiceLogonRight = [Account1],[Account2],...
                        $splitLine = $line -split '=', 2
                        if ($splitLine.Count -eq 2) {
                            $accounts = $splitLine[1].Trim() -split ','
                            # Clean up the account names by trimming whitespace.
                            $accounts = $accounts | ForEach-Object { $_.Trim() } | Where-Object { $_ }
                            return $accounts
                        }
                    }
                    return @()
                }
                finally {
                    # Ensure that the temporary file is removed even if errors occur.
                    if (Test-Path -Path $tempPath) {
                        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }

            # Run the script block on the remote server.
            $assignedAccounts = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ErrorAction Stop

            # Add the result to the collection.
            $results += [pscustomobject]@{
                ComputerName           = $server
                LogOnAsServiceAccounts = if ($assignedAccounts) { $assignedAccounts } else { @("None Assigned") }
            }
        }
        catch {
            Write-Warning "An error occurred processing '$server': $_"
            $results += [pscustomobject]@{
                ComputerName           = $server
                LogOnAsServiceAccounts = @("Error encountered")
            }
        }
        finally {
            # Clean up the session.
            if ($session) { Remove-PSSession -Session $session }
        }
    }

    # Output the aggregated results.
    return $results
}

<# 
.EXAMPLE
    # Check a single server:
    Get-LocalServiceLogonRights -ComputerName "Server01"

.EXAMPLE
    # Check multiple servers with credentials:
    $cred = Get-Credential
    Get-LocalServiceLogonRights -ComputerName "Server01","Server02" -Credential $cred

.DESCRIPTION
    This function uses remote PowerShell sessions to connect to one or more target servers, 
    exports the local security policy regarding user rights assignments, and parses out the 
    accounts that have the "Log on as a service" (SeServiceLogonRight) right. It follows 
    best practices including advanced function design, error handling, and session cleanup.
#>
