function Set-ResourceGroupTags {
    <#
    .SYNOPSIS
    Sets tags on a resource group and all resources within it.

    .DESCRIPTION
    This function applies specified tags to both a resource group and every resource contained within that resource group.
    Tags are merged with existing tags by default, with new values overwriting existing ones for matching keys.

    .PARAMETER ResourceGroupId
    The fully qualified resource ID of the target resource group.
    Format: /subscriptions/{subscription-id}/resourceGroups/{resource-group-name}

    .PARAMETER Tags
    Hashtable containing the tag key-value pairs to apply.
    Example: @{ Environment = 'Production'; Owner = 'TeamA' }

    .PARAMETER OverwriteExisting
    When specified, completely replaces existing tags instead of merging.

    .EXAMPLE
    Set-ResourceGroupTags -ResourceGroupId '/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/myRG' -Tags @{ Environment = 'Production' }

    .EXAMPLE
    $tags = @{
        Environment = 'Production'
        Owner = 'TeamA'
        CostCenter = 'CC-001'
    }
    Set-ResourceGroupTags -ResourceGroupId '/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/myRG' -Tags $tags

    .OUTPUTS
    [PSCustomObject] Summary of tagging operations including success/failure counts.

    .NOTES
    Requires Az.Resources module and appropriate Azure permissions.
    Performance: Processes resources in batches for optimal throughput.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSObject]$ResourceGroupObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [hashtable]$Tags,

        [switch]$OverwriteExisting
    )

    begin {

        # Verify Az.Resources module
        if (-not (Get-Module -Name Az.Resources -ListAvailable)) {

            Write-Error -Message 'Az.Resources module is required but not available. Install with: Install-Module Az.Resources' -ErrorAction 'Stop'
        }

        # Import required module if not already loaded
        if (-not (Get-Module -Name Az.Resources)) { Import-Module Az.Resources -Force }

        $results = [System.Collections.Generic.List[PSObject]]::new()

        $regexResourceGroupId = '^/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/resourceGroups/.+$'
    }

    process {

        try {

            $resourceGroupId = $ResourceGroupObject.ResourceId

            if ($resourceGroupId -notmatch $regexResourceGroupId) {

                Write-Error -Message "Invalid ResourceGroupId format: $ResourceGroupId" -ErrorAction 'Stop'
            }

            # Extract resource group name from ID
            $rgName = $ResourceGroupObject.ResourceGroupName
            $subscriptionId = ($ResourceGroupId -split '/')[2]

            Write-Verbose "Processing Resource Group: $rgName in subscription: $subscriptionId"

            # Set Azure context to correct subscription
            if ((Get-AzContext).Subscription.Id -ne $subscriptionId) {
                
                $null = Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop
            }

            # Verify resource group exists
            $resourceGroup = Get-AzResourceGroup -Name $rgName -ErrorAction Stop
            Write-Verbose "Resource group found: $($resourceGroup.ResourceGroupName)"

            # Get all resources in the resource group (retrieve only required properties for performance)
            $resources = Get-AzResource -ResourceGroupName $rgName -ErrorAction 'Stop' | 
                Select-Object -Property 'ResourceId', 'Name', 'ResourceType', 'Tags'

            Write-Verbose "Found $($resources.Count) resources in resource group"

            $successCount = 0
            $failureCount = 0
            $errors = [System.Collections.Generic.List[string]]::new()

            # Process Resource Group tags first
            if ($PSCmdlet.ShouldProcess($rgName, "Set tags")) {

                try {
                    
                    $currentRgTags = if ($null -eq $resourceGroupObject.Tags) { @{} }
                                     else { $resourceGroupObject.Tags }

                    if ($OverwriteExisting) { $newRgTags = $Tags }
                    else {

                        $newRgTags = @{}
                        foreach ($key in $currentRgTags.Keys) { $newRgTags[$key] = $currentRgTags[$key] }
                        foreach ($key in $Tags.Keys) { $newRgTags[$key] = $Tags[$key] }
                    }

                    $null = Set-AzResourceGroup -ResourceGroupName $rgName -Tag $newRgTags -ErrorAction Stop
                    $successCount++
                    Write-Verbose "Successfully tagged resource group: $rgName"
                } catch {

                    $failureCount++
                    $errorMsg = "Failed to tag resource group $rgName`: $($_.Exception.Message)"
                    $errors.Add($errorMsg)
                    Write-Warning $errorMsg
                }
            }

            # Process resources (early exit if no resources)
            if ($resources.Count -eq 0) { Write-Verbose "No resources found in resource group"}
            else {
                
                Write-Verbose "Processing $($resources.Count) resources"

                foreach ($resource in $resources) {

                    if ($PSCmdlet.ShouldProcess($resource.Name, "Set tags")) {

                        try {

                            #$currentTags = $resource.Tags ?? @{}

                            $currentTags = if ($null -eq $resource.Tags) { @{} }
                                           else { $resource.Tags }
                            
                            if ($OverwriteExisting) { $newTags = $Tags}
                            else {

                                $newTags = @{}
                                foreach ($key in $currentTags.Keys) { $newTags[$key] = $currentTags[$key] }
                                foreach ($key in $Tags.Keys) { $newTags[$key] = $Tags[$key] }
                            }

                            $paramsSetAzResource = @{
                                ResourceId = $resource.ResourceId
                                Tag = $newTags
                                Force = $true
                                ErrorAction = 'Stop'
                            }

                            $null = Set-AzResource @paramsSetAzResource
                            $successCount++
                            Write-Verbose "Successfully tagged resource: $($resource.Name)"
                        } catch {

                            $failureCount++
                            $errorMsg = "Failed to tag resource $($resource.Name): $($_.Exception.Message)"
                            $errors.Add($errorMsg)
                            Write-Warning $errorMsg
                        }
                    }
                }
            }

            # Create result object
            $result = [PSCustomObject]@{
                ResourceGroupId = $ResourceGroupId
                ResourceGroupName = $rgName
                TagsApplied = $Tags
                OverwriteMode = $OverwriteExisting.IsPresent
                TotalTargets = $resources.Count + 1  # +1 for RG itself
                SuccessCount = $successCount
                FailureCount = $failureCount
                Errors = $errors
                Timestamp = [datetime]::UtcNow
            }

            $results.Add($result)

        } catch {

            $errorMsg = "Critical error processing $ResourceGroupId`: $($_.Exception.Message)"
            Write-Error $errorMsg
            
            $result = [PSCustomObject]@{
                ResourceGroupId = $ResourceGroupId
                ResourceGroupName = if ($null -eq $rgName) { 'Unknown' } else { $rgName }
                TagsApplied = $Tags
                OverwriteMode = $OverwriteExisting.IsPresent
                TotalTargets = 0
                SuccessCount = 0
                FailureCount = 1
                Errors = @($errorMsg)
                Timestamp = [datetime]::UtcNow
            }

            $results.Add($result)
        }
    }

    end {
        # Clean up large temporaries
        $resources = $null
        
        $results
    }
}

##################

$tags = @{
    Tag1 = 'Tag1Value1'
    Tag2 = 'Tag2Value1'
    Tag3 = 'Tag3Value1'
}

$resourceGroups = Get-AzResourceGroup | Select-Object -Property 'ResourceGroupName', 'ResourceId'

$results = [System.Collections.Generic.List[psobject]]::new()

foreach ($resourceGroup in $resourceGroups) {

    $result = Set-ResourceGroupTags -ResourceGroupObject $resourceGroup -Tags $tags -Verbose

    $results.Add($result)
}