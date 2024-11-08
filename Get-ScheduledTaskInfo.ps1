function Get-ScheduledTaskRunHistory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0)]
        [string]$TaskName,

        [Parameter()]
        [string]$ComputerName = $env:COMPUTERNAME,

        [Parameter()]
        [int]$MaxResults = 10
    )

    # Ensure the required module is available
    if (!(Get-Module -ListAvailable -Name ScheduledTasks)) {
        Write-Error "The ScheduledTasks module is not available. Please make sure it is installed."
        return
    }

    # Query the Scheduled Task
    $task = Get-ScheduledTask -TaskName $TaskName -CimSession $ComputerName -ErrorAction Stop

    if (-not $task) {
        Write-Error "Scheduled task '$TaskName' not found on computer '$ComputerName'."
        return
    }

    # Using WMI to get detailed task history
    $query = "SELECT * FROM Win32_ScheduledJob WHERE Name = '$TaskName'"
    $runHistory = Get-CimInstance -Query $query -ComputerName $ComputerName -ErrorAction Stop |
                  Sort-Object -Property @{ Expression = { $_.StartTime }; Descending = $true } |
                  Select-Object -First $MaxResults

    if (-not $runHistory) {
        Write-Output "No run history found for task '$TaskName' on computer '$ComputerName'."
        return
    }

    # Parse and output the history in a user-friendly format
    $runHistory | ForEach-Object {
        [PSCustomObject]@{
            TaskName    = $TaskName
            Computer    = $ComputerName
            StartTime   = $_.StartTime
            EndTime     = $_.EndTime
            Status      = if ($_.ExitCode -eq 0) { "Success" } else { "Failed (Exit Code: $($_.ExitCode))" }
            RunDuration = ($_.EndTime - $_.StartTime).TotalMinutes
        }
    }
}

# Example usage:
# Get-ScheduledTaskRunHistory -TaskName "YourTaskName" -MaxResults 5