<#
.SYNOPSIS
    Transforms a KeePass 2.x XML export into Bitwarden's importable JSON format.
.DESCRIPTION
    Reads the full KeePass XML (including credentials), maps entry types, normalizes
    TOTP values, maps custom fields with appropriate hidden/text types, and appends
    expiry dates, tags, and attachment stubs to item notes for post-import remediation.
    Password history is intentionally dropped. Auto-Type sequences are dropped.
.PARAMETER KeePassXmlPath
    Path to the KeePass XML export file.
.PARAMETER OutputPath
    Path for the Bitwarden-format JSON output.
.PARAMETER CollectionId
    Bitwarden collection ID to assign to all items. Optional — can be injected
    automatically by Import-BitwardenVault if not known at transform time.
.EXAMPLE
    Convert-KeePassToBitwarden -KeePassXmlPath '.\vault.xml' -OutputPath '.\vault-import.json'
.EXAMPLE
    Convert-KeePassToBitwarden -KeePassXmlPath '.\vault.xml' -OutputPath '.\vault-import.json' -CollectionId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
#>
function Convert-KeePassToBitwarden {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$KeePassXmlPath,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$CollectionId = ''
    )

    $totpKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @('otp', 'TOTP Seed', 'TimeOtp-Secret-Base32', 'TimeOtp-Secret-Hex',
                     'TOTP', '_TOTP_', 'HmacOtp-Secret-Base32')) {
        [void]$totpKeys.Add($k)
    }

    $standardKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in @('Title', 'UserName', 'Password', 'URL', 'Notes')) {
        [void]$standardKeys.Add($k)
    }

    function Get-StringField {
        param ([System.Xml.XmlElement]$Entry, [string]$Key)
        $Entry.SelectSingleNode("String[Key='$Key']/Value")?.InnerText
    }

    # Normalizes TOTP values from various KeePass plugin formats to a value
    # Bitwarden accepts (otpauth URI or bare base32 secret).
    function ConvertTo-BitwardenTotp {
        param ([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        if ($Value.StartsWith('otpauth://')) { return $Value }
        # KeeOTP format: key=BASE32SECRET&step=30&size=6&type=totp
        if ($Value -match '^key=([A-Z2-7a-z0-9=]+)') { return $Matches[1] }
        # Bare base32 secret (Tray TOTP, KeePass native)
        return $Value
    }

    # Traverse all groups and assign a stable GUID to each path.
    function Build-FolderMap {
        param ([System.Xml.XmlElement]$RootGroup)

        $folders  = [System.Collections.Generic.List[PSObject]]::new()
        $pathToId = [System.Collections.Generic.Dictionary[string, string]]::new()

        function Traverse {
            param ([System.Xml.XmlElement]$Group, [string]$ParentPath)

            $name = $Group.SelectSingleNode('Name')?.InnerText
            $path = if ($ParentPath) { "$ParentPath/$name" } else { $name }
            $id   = [guid]::NewGuid().ToString()

            $folders.Add([PSCustomObject]@{ id = $id; name = $path })
            $pathToId[$path] = $id

            foreach ($sub in $Group.SelectNodes('Group')) {
                Traverse -Group $sub -ParentPath $path
            }
        }

        Traverse -Group $RootGroup -ParentPath ''
        return [PSCustomObject]@{ Folders = $folders; PathToId = $pathToId }
    }

    function ConvertTo-BitwardenItem {
        param (
            [System.Xml.XmlElement]$Entry,
            [string]$GroupPath,
            [string]$FolderId,
            [string]$CollectionId
        )

        $title    = Get-StringField -Entry $Entry -Key 'Title'
        $username = Get-StringField -Entry $Entry -Key 'UserName'
        $password = Get-StringField -Entry $Entry -Key 'Password'
        $url      = Get-StringField -Entry $Entry -Key 'URL'
        $notes    = Get-StringField -Entry $Entry -Key 'Notes'

        # SecureNote if no credentials present; Login otherwise
        $hasCredentials = (-not [string]::IsNullOrWhiteSpace($username)) -or
                          (-not [string]::IsNullOrWhiteSpace($password))
        $itemType = if ($hasCredentials) { 1 } else { 2 }

        # Build notes — append metadata markers for post-import remediation
        $noteLines = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($notes)) { $noteLines.Add($notes) }

        $expiresNode = $Entry.SelectSingleNode('Times/Expires')
        $expiryNode  = $Entry.SelectSingleNode('Times/ExpiryTime')
        if ($expiresNode?.InnerText -eq 'True' -and $null -ne $expiryNode) {
            $noteLines.Add("[EXPIRES: $($expiryNode.InnerText)]")
        }

        $tagsNode = $Entry.SelectSingleNode('Tags')
        if (-not [string]::IsNullOrWhiteSpace($tagsNode?.InnerText)) {
            $noteLines.Add("[TAGS: $($tagsNode.InnerText)]")
        }

        foreach ($binKey in $Entry.SelectNodes('Binary/Key')) {
            $noteLines.Add("[ATTACHMENT PENDING: $($binKey.InnerText)]")
        }

        $finalNotes = if ($noteLines.Count -gt 0) { $noteLines -join "`n" } else { $null }

        # Custom fields — skip standard keys and TOTP keys (handled separately)
        $bwFields  = [System.Collections.Generic.List[PSObject]]::new()
        $totpValue = $null

        foreach ($field in $Entry.SelectNodes('String')) {
            $key   = $field.SelectSingleNode('Key')?.InnerText
            $value = $field.SelectSingleNode('Value')?.InnerText

            if ($standardKeys.Contains($key)) { continue }

            if ($totpKeys.Contains($key)) {
                $totpValue = ConvertTo-BitwardenTotp -Value $value
                continue
            }

            # KeePass marks memory-protected fields with Protected="True" on the Value node
            $isProtected = $field.SelectSingleNode('Value')?.GetAttribute('Protected') -eq 'True'
            $fieldType   = if ($isProtected -or $key -imatch 'password|secret|token|key') { 1 } else { 0 }

            $bwFields.Add([PSCustomObject]@{
                name  = $key
                value = $value
                type  = $fieldType
            })
        }

        $collectionIds = if ($CollectionId) { @($CollectionId) } else { @() }

        $item = [ordered]@{
            id             = [guid]::NewGuid().ToString()
            organizationId = $null
            folderId       = $FolderId
            type           = $itemType
            reprompt       = 0
            name           = $title
            notes          = $finalNotes
            favorite       = $false
            fields         = $bwFields.ToArray()
            collectionIds  = $collectionIds
            creationDate   = $Entry.SelectSingleNode('Times/CreationTime')?.InnerText
            revisionDate   = $Entry.SelectSingleNode('Times/LastModificationTime')?.InnerText
        }

        if ($itemType -eq 1) {
            $uris = [System.Collections.Generic.List[PSObject]]::new()
            if (-not [string]::IsNullOrWhiteSpace($url)) {
                $uris.Add([PSCustomObject]@{ match = $null; uri = $url })
            }
            $item['login'] = [ordered]@{
                uris     = $uris.ToArray()
                username = $username
                password = $password
                totp     = $totpValue
            }
        }
        elseif ($itemType -eq 2) {
            $item['secureNote'] = @{ type = 0 }
        }

        return [PSCustomObject]$item
    }

    function Get-GroupItems {
        param (
            [System.Xml.XmlElement]$Group,
            [string]$ParentPath,
            [System.Collections.Generic.Dictionary[string, string]]$PathToId,
            [string]$CollectionId
        )

        $name  = $Group.SelectSingleNode('Name')?.InnerText
        $path  = if ($ParentPath) { "$ParentPath/$name" } else { $name }
        $items = [System.Collections.Generic.List[PSObject]]::new()

        foreach ($entry in $Group.SelectNodes('Entry')) {
            $folderId = $PathToId[$path]
            $items.Add((ConvertTo-BitwardenItem -Entry $entry -GroupPath $path -FolderId $folderId -CollectionId $CollectionId))
        }

        foreach ($sub in $Group.SelectNodes('Group')) {
            $items.AddRange((Get-GroupItems -Group $sub -ParentPath $path -PathToId $PathToId -CollectionId $CollectionId))
        }

        return $items
    }

    [xml]$xml  = Get-Content -Path $KeePassXmlPath -Encoding UTF8 -Raw
    $rootGroup = $xml.KeePassFile.Root.Group
    $folderMap = Build-FolderMap -RootGroup $rootGroup
    $allItems  = Get-GroupItems -Group $rootGroup -ParentPath '' -PathToId $folderMap.PathToId -CollectionId $CollectionId

    $bwExport = [ordered]@{
        encrypted = $false
        folders   = $folderMap.Folders.ToArray()
        items     = $allItems.ToArray()
    }

    $bwExport | ConvertTo-Json -Depth 20 | Set-Content -Path $OutputPath -Encoding UTF8
    Write-Host "Bitwarden import JSON → $OutputPath ($($allItems.Count) items)"
}
