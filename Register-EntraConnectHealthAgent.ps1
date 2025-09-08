# Invoke-RestMethod : {"error":"invalid_client","error_description":"AADSTS7000215: Invalid client secret provided.
# Ensure the secret being sent in the request is the client secret value, not the client secret ID, for a secret added
# to app ''. Trace ID: '' Correlation ID:
# '' Timestamp: 2025-06-10 12:13:37Z","error_codes":[7000215],"timestamp":"2025-06-10 1
# 2:13:37Z","trace_id":"","correlation_id":"","er
# ror_uri":"https://login.microsoftonline.us/error?code=7000215"}
# At line:1 char:1
# + Invoke-RestMethod @paramsInvokeRestMethod
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#     + CategoryInfo          : InvalidOperation: (System.Net.HttpWebRequest:HttpWebRequest) [Invoke-RestMethod], WebExc
#    eption
#     + FullyQualifiedErrorId : WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand


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

        try {

            $moduleName = 'C:\Program Files\Microsoft Azure AD Connect Health Agent\Modules\AdHealthConfiguration'

            Import-Module -Name $moduleName -ErrorAction 'Stop'
        }
        catch { $_ }

        $uri = "https://login.microsoftonline.us/$TenantId/oauth2/v2.0/token"

        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
        $clientSecretPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

        $body = [Ordered]@{
            client_id = $ClientId
            client_secret = $clientSecretPlain
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

            if ($PSCmdlet.ShouldProcess('Entra ID', 'Get access token')) {

                $paramsConvertToSecureString = @{
                    String = (Invoke-RestMethod @paramsInvokeRestMethod).access_token
                    AsPlainText = $true
                    Force = $true
                }
            }

            if ($PSCmdlet.ShouldProcess('Entra Connect Health agent', 'Register')) {

                $paramsRegisterECHAgent = @{
                    UserPrincipalName = $userName
                    AadToken = ConvertTo-SecureString @paramsConvertToSecureString
                }

                Register-MicrosoftEntraConnectHealthAgent @paramsRegisterECHAgent
            }            
        }
        catch { $_ }
    } # process

    end { <# no content #> } # end
}
