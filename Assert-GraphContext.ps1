function Test-GraphAuthentication {
    <#
    .SYNOPSIS
    Validates that Microsoft Graph is authenticated.

    .DESCRIPTION
    Checks for an existing Microsoft Graph context. If none is found,
    it throws a terminating error with structured metadata to ensure proper error handling.

    .EXAMPLE
    Test-GraphAuthentication

    Use at the beginning of an advanced function to ensure the user is authenticated to Microsoft Graph.

    .NOTES
    ErrorID: MissingGraphContext
    ErrorCategory: ResourceUnavailable
    #>
    [CmdletBinding()]
    param ()

    if (-not (Get-MgContext)) {
        $message = "Microsoft Graph authentication context not found. Use Connect-MgGraph before running this command."
        $exception = New-Object System.InvalidOperationException($message)
        $errorRecord = New-Object System.Management.Automation.ErrorRecord (
            $exception,
            "MissingGraphContext",
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            $null
        )

        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
}