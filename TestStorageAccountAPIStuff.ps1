$secVaultFilePath = Join-Path "$env:USERPROFILE\SecretStore" SecretStore.Vault.Credential
Unlock-SecretStore -Password (Import-CliXml -Path $secVaultFilePath)

$tenantId = '092ec6d1-91bb-41cc-a354-90068582d5c8'
$clientId = '1d05e425-28d8-4219-8e15-e5c8d7054b6b'
$clientSecret = Get-Secret -Name 'teststorageaccount' | ConvertFrom-SecureString -AsPlainText
$scope = 'https://storage.azure.com/.default'

$body = @{
    grant_type    = 'client_credentials'
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = $scope
}


$tokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" -Body $body
$accessToken = $tokenResponse.access_token





$storageAccountName = 'sadjmteststorage'
$containerName = 'testcontainer'
$blobName = 'example.txt'

$uri = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

Invoke-RestMethod -Method Put -Uri $uri -Headers @{ Authorization = "Bearer $accessToken" } -Body "File contents" -ContentType 'text/plain'


########################

$storageAccountName = 'sadjmteststorage'
$containerName = 'testcontainer'
$blobName = 'example.txt'
$blobContent = 'File contents'
$uri = "https://$storageAccountName.blob.core.windows.net/$containerName/$blobName"

$headers = @{
    Authorization    = "Bearer $accessToken"
    'x-ms-blob-type' = 'BlockBlob'
    'x-ms-version'   = '2023-11-03'  # Use a supported API version
    'x-ms-date'      = (Get-Date).ToUniversalTime().ToString("R")
    'Content-Type'   = 'text/plain'
}

Invoke-RestMethod -Method Put -Uri $uri -Headers $headers -Body $blobContent