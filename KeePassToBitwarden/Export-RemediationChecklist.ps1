<#
.SYNOPSIS
    Generates a sanitized remediation checklist from a KeePass 2.x XML export.
.DESCRIPTION
    Scans the KeePass XML and outputs a JSON file identifying entries that require
    manual post-import action in Bitwarden: TOTP re-wiring, attachment re-upload,
    SecureNote type conversion candidates, and expired entries.
    No credential values are written to the output.
.PARAMETER KeePassXmlPath
    Path to the KeePass XML export file.
.PARAMETER OutputPath
    Path for the sanitized remediation checklist JSON.
.EXAMPLE
    Export-RemediationChecklist -KeePassXmlPath '.\vault.xml' -OutputPath '.\remediation.json'
#>
function Export-RemediationChecklist {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$KeePassXmlPath,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $totpKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @('otp', 'TOTP Seed', 'TimeOtp-Secret-Base32', 'TimeOtp-Secret-Hex',
                     'TOTP', '_TOTP_', 'HmacOtp-Secret-Base32')) {
        [void]$totpKeys.Add($k)
    }

    $totp            = [System.Collections.Generic.List[PSObject]]::new()
    $attachments     = [System.Collections.Generic.List[PSObject]]::new()
    $notesCandidates = [System.Collections.Generic.List[PSObject]]::new()
    $expired         = [System.Collections.Generic.List[PSObject]]::new()

    function Get-StringField {
        param ([System.Xml.XmlElement]$Entry, [string]$Key)
        $Entry.SelectSingleNode("String[Key='$Key']/Value")?.InnerText
    }

    function Scan-Group {
        param ([System.Xml.XmlElement]$Group, [string]$ParentPath = '')

        $name = $Group.SelectSingleNode('Name')?.InnerText
        $path = if ($ParentPath) { "$ParentPath/$name" } else { $name }

        foreach ($entry in $Group.SelectNodes('Entry')) {
            $title    = Get-StringField -Entry $entry -Key 'Title'
            $username = Get-StringField -Entry $entry -Key 'UserName'
            $password = Get-StringField -Entry $entry -Key 'Password'
            $notes    = Get-StringField -Entry $entry -Key 'Notes'
            $stub     = [PSCustomObject]@{ Title = $title; GroupPath = $path }

            # TOTP
            foreach ($field in $entry.SelectNodes('String')) {
                if ($totpKeys.Contains($field.SelectSingleNode('Key')?.InnerText)) {
                    $totp.Add($stub)
                    break
                }
            }

            # Attachments
            foreach ($binKey in $entry.SelectNodes('Binary/Key')) {
                $attachments.Add([PSCustomObject]@{
                    Title          = $title
                    GroupPath      = $path
                    AttachmentName = $binKey.InnerText
                })
            }

            # SecureNote candidates — no credentials, has notes content
            if ([string]::IsNullOrWhiteSpace($username) -and
                [string]::IsNullOrWhiteSpace($password) -and
                -not [string]::IsNullOrWhiteSpace($notes)) {
                $notesCandidates.Add($stub)
            }

            # Expired
            $expiresNode = $entry.SelectSingleNode('Times/Expires')
            $expiryNode  = $entry.SelectSingleNode('Times/ExpiryTime')
            if ($expiresNode?.InnerText -eq 'True' -and $null -ne $expiryNode) {
                $expired.Add([PSCustomObject]@{
                    Title      = $title
                    GroupPath  = $path
                    ExpiryDate = $expiryNode.InnerText
                })
            }
        }

        foreach ($sub in $Group.SelectNodes('Group')) {
            Scan-Group -Group $sub -ParentPath $path
        }
    }

    [xml]$xml = Get-Content -Path $KeePassXmlPath -Encoding UTF8 -Raw
    Scan-Group -Group $xml.KeePassFile.Root.Group

    [PSCustomObject]@{
        GeneratedAt          = (Get-Date -Format 'o')
        Summary              = [PSCustomObject]@{
            TotpEntries          = $totp.Count
            AttachmentEntries    = $attachments.Count
            SecureNoteCandidates = $notesCandidates.Count
            ExpiredEntries       = $expired.Count
        }
        TotpEntries          = $totp
        AttachmentEntries    = $attachments
        SecureNoteCandidates = $notesCandidates
        ExpiredEntries       = $expired
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

    Write-Host "Remediation checklist → $OutputPath"
    Write-Host "  TOTP entries:           $($totp.Count)"
    Write-Host "  Attachment entries:     $($attachments.Count)"
    Write-Host "  SecureNote candidates:  $($notesCandidates.Count)"
    Write-Host "  Expired entries:        $($expired.Count)"
}
