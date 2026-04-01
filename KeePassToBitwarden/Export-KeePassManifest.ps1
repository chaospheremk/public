<#
.SYNOPSIS
    Generates a sanitized structural manifest from a KeePass 2.x XML export.
.DESCRIPTION
    Parses KeePass XML and produces a JSON manifest containing group hierarchy,
    entry metadata, and structural flags — with all credential values stripped.
    Safe for use with GitHub Copilot Chat for vault analysis and design decisions.
.PARAMETER KeePassXmlPath
    Path to the KeePass XML export file.
.PARAMETER OutputPath
    Path for the sanitized JSON manifest output.
.EXAMPLE
    Export-KeePassManifest -KeePassXmlPath '.\vault.xml' -OutputPath '.\vault-manifest.json'
#>
function Export-KeePassManifest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$KeePassXmlPath,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    function Get-UrlHostname {
        param ([string]$Url)
        if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
        try {
            $uri = [System.Uri]::new($Url)
            return $uri.Host
        }
        catch {
            return $null
        }
    }

    function Get-FieldValue {
        param (
            [System.Xml.XmlElement]$Entry,
            [string]$FieldName
        )
        $node = $Entry.SelectSingleNode("String[Key='$FieldName']/Value")
        return $node?.InnerText
    }

    function ConvertTo-EntryManifest {
        param (
            [System.Xml.XmlElement]$Entry,
            [string]$GroupPath
        )

        $title    = Get-FieldValue -Entry $Entry -FieldName 'Title'
        $url      = Get-FieldValue -Entry $Entry -FieldName 'URL'
        $username = Get-FieldValue -Entry $Entry -FieldName 'UserName'
        $notes    = Get-FieldValue -Entry $Entry -FieldName 'Notes'

        # Custom fields — names only, no values
        $customFieldNames = [System.Collections.Generic.List[string]]::new()
        foreach ($field in $Entry.SelectNodes("String[Key!='Title' and Key!='Password' and Key!='UserName' and Key!='URL' and Key!='Notes']")) {
            $customFieldNames.Add($field.Key)
        }

        # Attachments — filenames only, no content
        $attachmentNames = [System.Collections.Generic.List[string]]::new()
        foreach ($binary in $Entry.SelectNodes('Binary/Key')) {
            $attachmentNames.Add($binary.InnerText)
        }

        [PSCustomObject]@{
            GroupPath       = $GroupPath
            Title           = $title
            UrlHostname     = Get-UrlHostname -Url $url
            HasUsername     = -not [string]::IsNullOrWhiteSpace($username)
            HasPassword     = $true
            HasNotes        = -not [string]::IsNullOrWhiteSpace($notes)
            HasTotp         = ($null -ne $Entry.SelectSingleNode("String[Key='otp' or Key='TOTP Seed' or Key='TimeOtp-Secret-Base32']"))
            HasCustomFields = ($customFieldNames.Count -gt 0)
            CustomFieldNames = $customFieldNames.ToArray()
            HasAttachments  = ($attachmentNames.Count -gt 0)
            AttachmentNames = $attachmentNames.ToArray()
            CreatedDate     = $Entry.SelectSingleNode('Times/CreationTime')?.InnerText
            ModifiedDate    = $Entry.SelectSingleNode('Times/LastModificationTime')?.InnerText
        }
    }

    function Get-GroupEntries {
        param (
            [System.Xml.XmlElement]$Group,
            [string]$ParentPath = ''
        )

        $groupName = $Group.SelectSingleNode('Name')?.InnerText
        $groupPath = if ($ParentPath) { "$ParentPath/$groupName" } else { $groupName }
        $entries   = [System.Collections.Generic.List[PSObject]]::new()

        foreach ($entry in $Group.SelectNodes('Entry')) {
            $entries.Add((ConvertTo-EntryManifest -Entry $entry -GroupPath $groupPath))
        }

        foreach ($subGroup in $Group.SelectNodes('Group')) {
            $entries.AddRange((Get-GroupEntries -Group $subGroup -ParentPath $groupPath))
        }

        return $entries
    }

    [xml]$xml  = Get-Content -Path $KeePassXmlPath -Encoding UTF8 -Raw
    $rootGroup = $xml.KeePassFile.Root.Group

    $allEntries = Get-GroupEntries -Group $rootGroup
    $manifest   = [PSCustomObject]@{
        GeneratedAt  = (Get-Date -Format 'o')
        TotalEntries = $allEntries.Count
        Entries      = $allEntries
    }

    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Manifest written to $OutputPath — $($allEntries.Count) entries, zero credential values."
}
