function Get-FullSharePermissionsReport {
    [CmdletBinding()]
    param (
        [switch]$IncludeSubfolders
    )

    $results = [System.Collections.Generic.List[PSObject]]::new()

    # Get all shared folders
    $shares = Get-CimInstance -ClassName Win32_Share | Where-Object { $_.Type -eq 0 }

    foreach ($share in $shares) {
        
        $shareName = $share.Name
        $sharePath = $share.Path

        # Get share permissions
        try {
            $shareSddl = (Get-SmbShareAccess -Name $shareName -ErrorAction Stop)
        }
        catch {
            Write-Warning "Failed to get share permissions for $shareName: $_"
            continue
        }

        foreach ($access in $shareSddl) {
            $results.Add([pscustomobject]@{
                    ShareName     = $shareName
                    Path          = $sharePath
                    Type          = 'Share'
                    Identity      = $access.AccountName
                    AccessControl = $access.AccessControlType
                    AccessRight   = $access.AccessRight
                    Inherited     = $false
                    Source        = $env:COMPUTERNAME
                })
        }

        # Get NTFS permissions on the share root and subfolders
        try {
            $dirs = if ($IncludeSubfolders) {
                Get-ChildItem -Path $sharePath -Recurse -Directory -Force -ErrorAction SilentlyContinue
            }
            else {
                @()
            }

            $dirs = , (Get-Item -Path $sharePath -Force) + $dirs

            foreach ($dir in $dirs) {
                try {
                    $acl = Get-Acl -Path $dir.FullName
                    foreach ($ace in $acl.Access) {
                        $results.Add([pscustomobject]@{
                                ShareName     = $shareName
                                Path          = $dir.FullName
                                Type          = 'NTFS'
                                Identity      = $ace.IdentityReference.ToString()
                                AccessControl = $ace.AccessControlType
                                AccessRight   = $ace.FileSystemRights
                                Inherited     = $ace.IsInherited
                                Source        = $env:COMPUTERNAME
                            })
                    }
                }
                catch {
                    Write-Warning "Failed to get ACL for $($dir.FullName): $_"
                }
            }
        }
        catch {
            Write-Warning "Failed to recurse $sharePath: $_"
        }
    }

    return $results
}



#### runspaces
function Get-NTFSPermissionsUsingRunspacePool {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$RootPath,

        [switch]$IncludeSubfolders = $true,

        [int]$ThrottleLimit = 8
    )

    # Validate root path
    if (-not (Test-Path $RootPath)) {
        Write-Error "Path not found: $RootPath"
        return
    }

    # Collect folders to scan
    $folders = try {
        $folders = if ($IncludeSubfolders) {
            Get-ChildItem -Path $RootPath -Recurse -Directory -Force -ErrorAction Stop
        }
        else {
            @()
        }
        , (Get-Item -Path $RootPath -Force) + $folders
    }
    catch {
        Write-Error "Error enumerating folders: $_"
        return
    }

    # Setup runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
    $runspacePool.ThreadOptions = 'ReuseThread'
    $runspacePool.Open()

    # Thread-safe result collector
    $syncHash = [hashtable]::Synchronized(@{
            Results = [System.Collections.Generic.List[object]]::new()
        })

    $runspaces = foreach ($folder in $folders) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $runspacePool

        [void]$ps.AddScript({
                param ($Path)

                $results = @()
                try {
                    $acl = Get-Acl -Path $Path
                    $inheritanceEnabled = -not $acl.AreAccessRulesProtected

                    foreach ($ace in $acl.Access) {
                        $results += [pscustomobject]@{
                            Path               = $Path
                            Identity           = $ace.IdentityReference.Value
                            AccessControl      = $ace.AccessControlType
                            AccessRight        = $ace.FileSystemRights
                            Inherited          = $ace.IsInherited
                            InheritanceFlag    = $ace.InheritanceFlags
                            PropagationFlag    = $ace.PropagationFlags
                            InheritanceEnabled = $inheritanceEnabled
                            Source             = $env:COMPUTERNAME
                        }
                    }
                }
                catch {
                    $results += [pscustomobject]@{
                        Path               = $Path
                        Identity           = '<ERROR>'
                        AccessControl      = 'N/A'
                        AccessRight        = 'N/A'
                        Inherited          = $false
                        InheritanceFlag    = 'N/A'
                        PropagationFlag    = 'N/A'
                        InheritanceEnabled = 'N/A'
                        Source             = $env:COMPUTERNAME
                        Error              = $_.Exception.Message
                    }
                }

                return $results
            }).AddArgument($folder.FullName)

        [pscustomobject]@{
            Pipe  = $ps
            Async = $ps.BeginInvoke()
        }
    }

    # Collect results
    foreach ($r in $runspaces) {
        $objects = $r.Pipe.EndInvoke($r.Async)
        $objects | ForEach-Object { $syncHash.Results.Add($_) }
        $r.Pipe.Dispose()
    }

    $runspacePool.Close()
    $runspacePool.Dispose()

    return $syncHash.Results
}