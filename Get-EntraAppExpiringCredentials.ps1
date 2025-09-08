function Get-EntraAppExpiringCredentials {
    <#
    .SYNOPSIS
    Retrieves Entra ID app registrations with client secrets or certificates expiring within a specified timeframe.

    .DESCRIPTION
    This function connects to Microsoft Graph and examines all app registrations in the tenant
    to identify those with client secrets (password credentials) or certificates (key credentials)
    that will expire within the specified number of days. Returns structured objects containing
    detailed information about each expiring credential.

    .PARAMETER DaysToExpiry
    Number of days from today to check for expiring credentials. Default is 30 days.

    .PARAMETER IncludeExpired
    Include credentials that have already expired in the results.

    .PARAMETER SecretsOnly
    Check only client secrets (password credentials). Cannot be used with -CertsOnly.

    .PARAMETER CertsOnly
    Check only certificates (key credentials). Cannot be used with -SecretsOnly.

    .PARAMETER AppId
    Limit check to specific application(s) by Application ID (Client ID).

    .EXAMPLE
    Get-EntraAppExpiringCredentials
    
    Retrieves all app registrations with credentials expiring in the next 30 days.

    .EXAMPLE
    Get-EntraAppExpiringCredentials -DaysToExpiry 7 -IncludeExpired
    
    Retrieves apps with credentials expiring in 7 days, including already expired ones.

    .EXAMPLE
    Get-EntraAppExpiringCredentials -SecretsOnly -DaysToExpiry 14
    
    Checks only client secrets expiring within 14 days.

    .EXAMPLE
    Get-EntraAppExpiringCredentials -AppId "12345678-1234-1234-1234-123456789012"
    
    Checks credentials for a specific application.

    .OUTPUTS
    PSCustomObject with properties:
    - ApplicationId: The app registration's Application (Client) ID
    - DisplayName: The app registration's display name
    - CredentialType: 'ClientSecret' or 'Certificate'
    - CredentialId: Unique identifier for the credential
    - Description: Description for the credential
    - SecretHint: Hint for the client secret
    - StartDate: When the credential becomes valid
    - EndDate: When the credential expires
    - DaysUntilExpiry: Number of days until expiration (negative if expired)
    - IsExpired: Boolean indicating if credential has expired

    .NOTES
    Requires the Microsoft.Graph.Applications module and appropriate permissions:
    - Application.Read.All (least privilege)
    
    Performance optimized for large tenants by retrieving only required properties
    and using early filtering to minimize processing overhead.
    #>

    [CmdletBinding(DefaultParameterSetName = 'All')]
    param(
        [Parameter()]
        [ValidateRange(1, 365)]
        [int]$DaysToExpiry = 30,

        [Parameter()]
        [switch]$IncludeExpired,

        [Parameter(ParameterSetName = 'SecretsOnly')]
        [switch]$SecretsOnly,

        [Parameter(ParameterSetName = 'CertsOnly')]
        [switch]$CertsOnly,

        [Parameter()]
        [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
        [string[]]$AppId
    )

    begin {
        # Require PowerShell 7.3 or higher
        $requiredVersion = [Version]'7.3.0'
        $currentVersion = $PSVersionTable.PSVersion
        
        if ($currentVersion -lt $requiredVersion) {

            $errorMessage = "PowerShell 7.3 or higher is required. Current version: $currentVersion"

            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.NotSupportedException]::new($errorMessage), 'PowerShellVersionNotSupported',
                    [System.Management.Automation.ErrorCategory]::NotInstalled, $currentVersion
                )
            )
        }

        # Verify Microsoft Graph module availability
        if (-not (Get-Module -Name Microsoft.Graph.Applications -ListAvailable)) {

            $errorMessage = 'Microsoft.Graph.Applications module is required.' +
                            ' Install with: Install-Module Microsoft.Graph.Applications'

            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new($errorMessage), 'ModuleNotFound',
                    [System.Management.Automation.ErrorCategory]::NotInstalled, 'Microsoft.Graph.Applications'
                )
            )
        }

        # Import required module
        if (-not (Get-Module -Name Microsoft.Graph.Applications)) { Import-Module Microsoft.Graph.Applications }

        # Calculate date thresholds
        $today = Get-Date
        $expiryThreshold = $today.AddDays($DaysToExpiry)
        
        # Initialize results collection
        $results = [System.Collections.Generic.List[PSObject]]::new()

        if ($PSBoundParameters.ContainsKey('Verbose')) {

            $includeDateString = if ($IncludeExpired) { 'any date' } else { $today.ToString('yyyy-MM-dd') }
            $verboseMessage = "Checking for credentials expiring between $includeDateString" +
                             " and $($expiryThreshold.ToString('yyyy-MM-dd'))"

            Write-Verbose -Message $verboseMessage
        }
    }

    process {
        try {
            # Verify Graph connection
            $context = Get-MgContext

            if (-not $context) {

                $errorMessage = 'Not connected to Microsoft Graph. Run Connect-MgGraph first.'

                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.InvalidOperationException]::new($errorMessage), 'GraphNotConnected',
                        [System.Management.Automation.ErrorCategory]::ConnectionError, $null
                    )
                )
            }

            if ($PSBoundParameters.ContainsKey('Verbose')) {

                $contextAccount = $context.Account
                $tenantId = $context.TenantId

                Write-Verbose -Message "Connected to Microsoft Graph as $contextAccount in tenant $tenantId"
            }

            # Build application filter
            $filter = if ($AppId) {

                $filterStrings = foreach ($id in $AppId) { "appId eq '$id'" }
                $appIdFilter = $filterStrings -join ' or '

                "($appIdFilter)"
            }
            else { $null }

            # Retrieve applications with only required properties for performance
            $paramsGetMgApplication = @{
                Property = @('Id', 'AppId', 'DisplayName', 'PasswordCredentials', 'KeyCredentials')
                All = $true
            }
            
            if ($filter) { $paramsGetMgApplication.Filter = $filter }

            Write-Verbose -Message "Retrieving application registrations..."
            $applications = Get-MgApplication @paramsGetMgApplication

            if (-not $applications) {

                Write-Warning -Messsage "No applications found matching the specified criteria."
                return
            }

            Write-Verbose -Message "Processing $($applications.Count) application(s)..."

            # Process each application
            foreach ($app in $applications) {
                # Process client secrets unless certificates-only specified
                if ($PSCmdlet.ParameterSetName -ne 'CertsOnly' -and $app.PasswordCredentials) {

                    foreach ($secret in $app.PasswordCredentials) {

                        $daysUntil = ($secret.EndDateTime - $today).Days
                        $isExpired = $secret.EndDateTime -lt $today
                        
                        # Apply filtering logic
                        if (($IncludeExpired -or -not $isExpired) -and
                            ($secret.EndDateTime -le $expiryThreshold)) {
                            
                            $description = $secret.DisplayName ?? 'No description'

                            if ($description -eq 'CWAP_AuthSecret') {
                                
                                $description = $description + ' (Do not delete. App Proxy)'
                            }

                            $results.Add(
                                [PSCustomObject]@{
                                    ApplicationId = $app.AppId
                                    DisplayName = $app.DisplayName
                                    CredentialType = 'ClientSecret'
                                    CredentialId = $secret.KeyId
                                    Description = $description
                                    SecretHint = $secret.Hint
                                    StartDate = $secret.StartDateTime
                                    EndDate = $secret.EndDateTime
                                    DaysUntilExpiry = $daysUntil
                                    IsExpired = $isExpired
                                }
                            )
                        }
                    }
                }

                # Process certificates unless secrets-only specified
                if ($PSCmdlet.ParameterSetName -ne 'SecretsOnly' -and $app.KeyCredentials) {

                    foreach ($cert in $app.KeyCredentials) {

                        $daysUntil = ($cert.EndDateTime - $today).Days
                        $isExpired = $cert.EndDateTime -lt $today
                        
                        # Apply filtering logic
                        if (($IncludeExpired -or -not $isExpired) -and $cert.EndDateTime -le $expiryThreshold) {

                            $results.Add(
                                [PSCustomObject]@{
                                    ApplicationId = $app.AppId
                                    DisplayName = $app.DisplayName
                                    CredentialType = 'Certificate'
                                    CredentialId = $cert.KeyId
                                    Description = $cert.DisplayName ?? 'No description'
                                    SecretHint = $null
                                    StartDate = $cert.StartDateTime
                                    EndDate = $cert.EndDateTime
                                    DaysUntilExpiry = $daysUntil
                                    IsExpired = $isExpired
                                }
                            )
                        }
                    }
                }
            }

            # Sort results by expiry date (most urgent first)
            if ($results) { Write-Verbose -Message "Found $($results.Count) credential(s) matching criteria" }

            $results | Sort-Object -Property 'EndDate'
        }
        catch {
            
            Write-Error -Message "Failed to retrieve application credentials: $($_.Exception.Message)"

            $PSCmdlet.ThrowTerminatingError($_.ErrorRecord)
        }
        finally {

            # Cleanup large temporary collections
            $applications = $null
            $results = $null
        }
    }
}

$appId = '6aaf813d-fe9f-4bd7-8177-1b567dd44597', 'd594948e-8432-4981-a8de-93cabbac34e2', '73cd4e68-b823-4fde-b76f-56643cbd35d1'

$paramsGetEntraAppExpCreds = @{
    DaysToExpiry = 30
    IncludeExpired = $true
    #SecretsOnly = $true
    #CertsOnly = $true
    #AppId = $appId
    Verbose = $true
}

Get-EntraAppExpiringCredentials @paramsGetEntraAppExpCreds