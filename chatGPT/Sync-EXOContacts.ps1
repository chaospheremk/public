# find and replace _PROJECT_ with name of project

param (
    [string]$TenantId,
    [string]$ClientId,
    [string]$Thumbprint,
    [switch]$DryRun,
    [string]$SenderUPN,
    [string]$NotifyEmail,
    [string]$LogFile = ".\_PROJECT_ContactSync.log",
    [string]$ExchangeOnlineAppId = '00000002-0000-0ff1-ce00-000000000000'
)



function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("s")
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Connect-ExchangeOnlineApp {
    Connect-ExchangeOnline `
        -CertificateThumbprint $Thumbprint `
        -AppId $ClientId `
        -Organization "$TenantId"
}

function Get-ExistingContacts {
    Get-MailContact -Filter "CustomAttribute1 -eq '_PROJECT_'" -ResultSize Unlimited |
    Select-Object Name, ExternalEmailAddress, Identity
}

function Send-LogNotification {
    param (
        [string]$SenderUPN,
        [string]$ToAddress,
        [string]$Subject,
        [string]$LogFile
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Mail)) {
        Import-Module Microsoft.Graph -ErrorAction Stop
    }

    Connect-MgGraph -Scopes "Mail.Send" -NoWelcome

    $logContent = Get-Content -Path $LogFile -Raw
    $base64Content = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($logContent))

    $message = @{
        subject      = $Subject
        body         = @{
            contentType = "Text"
            content     = "_PROJECT_ Contact Sync Log attached. See below for details."
        }
        toRecipients = @(
            @{
                emailAddress = @{
                    address = $ToAddress
                }
            }
        )
        attachments  = @(
            @{
                "@odata.type" = "#microsoft.graph.fileAttachment"
                name          = [System.IO.Path]::GetFileName($LogFile)
                contentBytes  = $base64Content
                contentType   = "text/plain"
            }
        )
    }

    Send-MgUserMail -UserId $SenderUPN -Message $message -SaveToSentItems:$false
    Write-Log "Graph email sent to $ToAddress from $SenderUPN"
}

function Sync-_PROJECT_Contacts {
    Write-Log "Getting AD users with msDS-cloudExtensionAttribute13 = _PROJECT_..."
    $adUsers = Get-ADUser -Filter 'msDS-cloudExtensionAttribute13 -eq "_PROJECT_"' -Properties 'msDS-cloudExtensionAttribute9', sAMAccountName, GivenName, Surname

    $currentEmails = [System.Collections.Generic.List[string]]::new()
    foreach ($user in $adUsers) {
        $email = $user.'msDS-cloudExtensionAttribute9'.Trim().ToLower()
        if (-not [string]::IsNullOrWhiteSpace($email)) {
            $currentEmails.Add($email)
        }
    }

    $existingContacts = [System.Collections.Generic.Dictionary[string, bool]]::new()
    $contactLookup = [System.Collections.Generic.Dictionary[string, Microsoft.Exchange.Data.Directory.Management.MailContact]]::new()

    foreach ($contact in Get-ExistingContacts) {
        $email = $contact.ExternalEmailAddress.ToString().Trim().ToLower()
        if (-not $existingContacts.ContainsKey($email)) {
            $existingContacts.Add($email, $true)
            $contactLookup.Add($email, $contact)
        }
    }

    $createdContacts = [System.Collections.Generic.List[string]]::new()

    foreach ($user in $adUsers) {
        $email = $user.'msDS-cloudExtensionAttribute9'.Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($email) -or $existingContacts.ContainsKey($email)) {
            continue
        }

        $contactName = "_PROJECT__$($user.sAMAccountName)"
        if ($DryRun) {
            Write-Log "[DryRun] Would create contact: $contactName <$email>"
        }
        else {
            try {
                New-MailContact -Name $contactName `
                    -ExternalEmailAddress $email `
                    -FirstName $user.GivenName `
                    -LastName $user.Surname `
                    -CustomAttribute1 "_PROJECT_" `
                    -OrganizationalUnit "Contacts"
                $createdContacts.Add($email)
                Write-Log "Created contact: $contactName <$email>"
            }
            catch {
                Write-Log "ERROR creating contact $contactName <$email>: $_"
            }
        }
    }

    Write-Log "Total contacts created: $($createdContacts.Count)"

    $removedContacts = [System.Collections.Generic.List[string]]::new()
    foreach ($email in $existingContacts.Keys) {
        if (-not $currentEmails.Contains($email)) {
            $contact = $contactLookup[$email]
            if ($DryRun) {
                Write-Log "[DryRun] Would remove orphaned contact: $($contact.Name) <$email>"
            }
            else {
                try {
                    Remove-MailContact -Identity $contact.Identity -Confirm:$false
                    $removedContacts.Add($email)
                    Write-Log "Removed orphaned contact: $($contact.Name) <$email>"
                }
                catch {
                    Write-Log "ERROR removing contact $($contact.Name) <$email>: $_"
                }
            }
        }
    }

    Write-Log "Total orphaned contacts removed: $($removedContacts.Count)"
}

# Main
if (Test-Path $LogFile) { Remove-Item -Path $LogFile -Force }
Write-Log "===== _PROJECT_ Contact Sync Starting ====="

Connect-ExchangeOnlineApp
Sync-_PROJECT_Contacts
Disconnect-ExchangeOnline

if ($NotifyEmail -and $SenderUPN) {
    Send-LogNotification -SenderUPN $SenderUPN -ToAddress $NotifyEmail -Subject "_PROJECT_ Contact Sync Log" -LogFile $LogFile
}

Write-Log "===== _PROJECT_ Contact Sync Completed ====="