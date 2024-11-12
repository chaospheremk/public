# Install Microsoft.Graph module if not already installed
if (!(Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Install-Module Microsoft.Graph -Scope CurrentUser -Force -AllowClobber
}

# Import Microsoft.Graph
Import-Module Microsoft.Graph

# Function to connect to Microsoft Graph using an app registration or interactive login
function Connect-ToGraph {
    param(
        [Parameter(Mandatory = $false)]
        [string]$ClientId,
        [Parameter(Mandatory = $false)]
        [string]$TenantId,
        [Parameter(Mandatory = $false)]
        [string]$ClientSecret
    )
    
    if ($ClientId -and $TenantId -and $ClientSecret) {
        # Connect using app credentials
        $secureClientSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
        $tokenRequestBody = @{
            client_id     = $ClientId
            scope         = "https://graph.microsoft.com/.default"
            client_secret = $secureClientSecret
            grant_type    = "client_credentials"
        }
        $tokenResponse = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method Post -ContentType "application/x-www-form-urlencoded" -Body $tokenRequestBody
        Connect-MgGraph -AccessToken $tokenResponse.access_token
    } else {
        # Interactive login
        Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All AuditLog.Read.All Device.Read.All"
    }
}

# Function to get the last Cloud PC sign-in activity using sign-in logs
function Get-CloudPCSignInActivity {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$UserPrincipalNames
    )

    $signInData = @()

    foreach ($user in $UserPrincipalNames) {
        try {
            # Get last sign-in data for the user specifically for Windows 365 Cloud PC
            $signIn = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$user' and appDisplayName eq 'Windows 365'" -Top 1 | Sort-Object -Property createdDateTime -Descending | Select-Object -First 1

            if ($signIn) {
                $signInData += [pscustomobject]@{
                    UserPrincipalName = $user
                    LastSignInDateTime = $signIn.CreatedDateTime
                    Status            = $signIn.Status.ErrorCode -eq 0 ? 'Success' : 'Failure'
                }
            }
            else {
                $signInData += [pscustomobject]@{
                    UserPrincipalName = $user
                    LastSignInDateTime = "No recent sign-ins"
                    Status             = "N/A"
                }
            }
        }
        catch {
            Write-Error "Failed to retrieve sign-in data for user $user. Error: $_"
        }
    }

    return $signInData
}

# Connect to Microsoft Graph interactively
Connect-ToGraph

# List of Cloud PC users' UPNs
$userList = (Get-MgDeviceManagementManagedDevice -Filter "contains(operatingSystem, 'Windows') and contains(managementAgent, 'Microsoft Managed Desktop')" -All).UserPrincipalName | Where-Object { $_ -ne $null }

# Get Cloud PC sign-in activity
$cloudPCSignInData = Get-CloudPCSignInActivity -UserPrincipalNames $userList

# Display Cloud PC sign-in data
$cloudPCSignInData | Format-Table -AutoSize

# Disconnect Microsoft Graph session
Disconnect-MgGraph