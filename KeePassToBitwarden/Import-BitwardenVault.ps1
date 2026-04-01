<#
.SYNOPSIS
    Imports a transformed Bitwarden JSON file into an org vault via the BW CLI.
.DESCRIPTION
    Resolves the target collection ID from the org, injects it into all items in the
    JSON (overwriting any collectionIds already present), then runs bw import.
    Requires $env:BW_SESSION to be set via 'bw unlock' before calling.
.PARAMETER JsonPath
    Path to the Bitwarden-format JSON file produced by Convert-KeePassToBitwarden.
.PARAMETER OrganizationId
    Bitwarden organization ID. Retrieve via: bw list organizations | ConvertFrom-Json.
.EXAMPLE
    Import-BitwardenVault -JsonPath '.\vault-import.json' -OrganizationId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'
.EXAMPLE
    Import-BitwardenVault -JsonPath '.\vault-import.json' -OrganizationId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' -WhatIf
#>
function Import-BitwardenVault {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$JsonPath,

        [Parameter(Mandatory)]
        [string]$OrganizationId
    )

    if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
        throw "Bitwarden CLI (bw) not found in PATH. Install from https://bitwarden.com/help/cli/"
    }

    if ([string]::IsNullOrWhiteSpace($env:BW_SESSION)) {
        throw "BW_SESSION is not set. Run 'bw unlock' and set the session key first:`n  `$env:BW_SESSION = (bw unlock --raw)"
    }

    # Resolve the single collection ID from the org
    Write-Host "Resolving collection ID for org $OrganizationId..."
    $collectionsJson = bw list org-collections --organizationid $OrganizationId 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list org collections: $collectionsJson"
    }

    $collections = $collectionsJson | ConvertFrom-Json
    if ($collections.Count -eq 0) {
        throw "No collections found in org $OrganizationId. Verify the org ID and your permissions."
    }
    if ($collections.Count -gt 1) {
        Write-Warning "Multiple collections found — using the first one: '$($collections[0].name)' ($($collections[0].id))"
    }

    $collectionId = $collections[0].id
    Write-Host "Target collection: '$($collections[0].name)' ($collectionId)"

    # Load the export JSON and inject the collection ID into every item
    Write-Host "Patching collectionIds in import JSON..."
    $export = Get-Content -Path $JsonPath -Encoding UTF8 -Raw | ConvertFrom-Json -Depth 20

    foreach ($item in $export.items) {
        $item.collectionIds = @($collectionId)
    }

    $tempPath = [System.IO.Path]::Combine(
        [System.IO.Path]::GetTempPath(),
        "bw-import-$([guid]::NewGuid()).json"
    )

    try {
        $export | ConvertTo-Json -Depth 20 | Set-Content -Path $tempPath -Encoding UTF8

        if ($PSCmdlet.ShouldProcess(
            "$($export.items.Count) items → org $OrganizationId / collection $collectionId",
            'bw import'
        )) {
            Write-Host "Running bw import ($($export.items.Count) items)..."
            bw import bitwardenjson $tempPath --organizationid $OrganizationId

            if ($LASTEXITCODE -ne 0) {
                throw "bw import exited with code $LASTEXITCODE"
            }

            Write-Host "Import complete."
        }
    }
    finally {
        if (Test-Path $tempPath) {
            Remove-Item $tempPath -Force
        }
    }
}
