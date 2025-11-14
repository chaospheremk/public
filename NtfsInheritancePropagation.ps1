function Test-NtfsInheritancePropagation {
    <#
    .SYNOPSIS
    Detects folders where NTFS inheritance is enabled but parent ACEs do not properly propagate.

    .DESCRIPTION
    Test-NtfsInheritancePropagation walks a directory tree and compares each child folder's
    ACL to its parent's ACL.

    A folder is reported when:
      - The parent ACL has inheritance enabled, AND
      - The child ACL has inheritance enabled, AND
      - The parent has one or more inheritable ACEs (OI and/or CI), AND
      - The child is missing matching inherited ACEs for one or more of those parent rules.

    This helps detect "non-propagating inheritance" scenarios, which are often caused by:
      - Missing OI/CI flags on parent ACEs,
      - ACL canonical-order issues on the parent,
      - Complex DENY / CREATOR OWNER interactions or ACL corruption.

    The function returns objects describing each problematic child and which parent ACEs
    failed to propagate.

    .PARAMETER Path
    Root folder to analyze. Must be a directory.

    .PARAMETER Recurse
    When specified, recursively scans all subfolders beneath the root. If omitted, only
    the direct child folders of Path are analyzed.

    .PARAMETER MaxDepth
    Maximum recursion depth beneath the root when -Recurse is used. The root folder is
    depth 0. Defaults to 15.

    .PARAMETER VerifyParent
    When specified, runs "icacls <Parent> /verify" for each parent folder that has at least
    one non-propagating child. This can help identify invalid or non-canonical ACLs that
    often cause inheritance bugs. This adds overhead and should be used selectively.

    .EXAMPLE
    Test-NtfsInheritancePropagation -Path 'D:\Data' -Recurse

    Scans D:\Data and all subfolders for folders where inheritance is enabled but at least
    one inheritable ACE from the parent does not show up as an inherited ACE on the child.

    .EXAMPLE
    Test-NtfsInheritancePropagation -Path '\\FileServer01\Share' -Recurse -MaxDepth 5 -VerifyParent |
        Format-Table Path, ParentPath, MissingInheritedAceCount, ParentAclInvalid

    Scans up to 5 levels deep under the UNC path and shows any folders with non-propagating
    inheritance, along with whether the parent ACL failed icacls /verify.

    .NOTES
    Performance:
      - Uses Get-Acl once per folder and walks the tree with an internal queue.
      - Avoids ForEach-Object / Where-Object pipelines in performance-sensitive sections.
      - Only directories are examined; file ACLs are ignored.

    Returned object properties:
      - Path                     : Child folder path
      - ParentPath               : Parent folder path
      - Depth                    : Depth under the root
      - MissingInheritedAceCount : Number of parent ACEs that did not appear on the child
      - MissingIdentities        : List of identity names for the missing ACEs
      - ParentInheritanceEnabled : Whether parent has inheritance enabled
      - ChildInheritanceEnabled  : Whether child has inheritance enabled
      - ParentAclInvalid         : $true if icacls /verify reported "Invalid ACL" (when -VerifyParent)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName')]
        [string]$Path,

        [Parameter()]
        [switch]$Recurse,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int]$MaxDepth = 15,

        [Parameter()]
        [switch]$VerifyParent
    )

    begin {
        # Queue for breadth-first traversal
        $queueType = [System.Collections.Generic.Queue[psobject]]
        $queue = [Activator]::CreateInstance($queueType)
    }

    process {
        # Resolve and validate the root item
        $rootItem = Get-Item -LiteralPath $Path -ErrorAction Stop

        if (-not $rootItem.PSIsContainer) {
            throw "Path '$Path' is not a directory. Test-NtfsInheritancePropagation expects a folder path."
        }

        $rootAcl = Get-Acl -LiteralPath $rootItem.FullName -ErrorAction Stop

        # Enqueue root frame
        $rootFrame = [pscustomobject]@{
            Item  = $rootItem
            Acl   = $rootAcl
            Depth = 0
        }
        $queue.Enqueue($rootFrame)

        while ($queue.Count -gt 0) {
            $frame   = $queue.Dequeue()
            $parent  = $frame.Item
            $parentAcl = $frame.Acl
            $depth   = $frame.Depth

            $parentInheritanceEnabled = -not $parentAcl.AreAccessRulesProtected

            # Only bother looking at children if the parent actually has inheritance enabled.
            if ($Recurse -or $depth -eq 0) {
                # For the root, we always inspect its immediate children even without -Recurse.
                $enumerateChildren = $true
            }
            else {
                $enumerateChildren = $false
            }

            if ($enumerateChildren) {
                if ($Recurse -and $depth -ge $MaxDepth) {
                    # Respect MaxDepth
                    continue
                }

                # Enumerate child directories using .NET for performance
                try {
                    $childDirs = $parent.GetDirectories()
                }
                catch {
                    # If we can't enumerate (access denied, etc.), skip this branch.
                    continue
                }

                foreach ($child in $childDirs) {
                    # Get child ACL safely
                    try {
                        $childAcl = Get-Acl -LiteralPath $child.FullName -ErrorAction Stop
                    }
                    catch {
                        # Skip problematic child but continue scanning others
                        continue
                    }

                    $childInheritanceEnabled = -not $childAcl.AreAccessRulesProtected

                    # Only analyze propagation when both parent and child have inheritance enabled
                    if ($parentInheritanceEnabled -and $childInheritanceEnabled) {

                        # Build list of inheritable parent ACEs (anything with non-None inheritance flags)
                        $parentAccess = $parentAcl.Access
                        $inheritableParentRules =
                            $parentAccess.Where({
                                $_.InheritanceFlags -ne [System.Security.AccessControl.InheritanceFlags]::None
                            })

                        if ($inheritableParentRules.Count -gt 0) {
                            # Compare to child's inherited ACEs
                            $childAccess = $childAcl.Access

                            $missingRulesType = [System.Collections.Generic.List[System.Security.AccessControl.FileSystemAccessRule]]
                            $missingRules = [Activator]::CreateInstance($missingRulesType)

                            foreach ($parentRule in $inheritableParentRules) {
                                # Find matching inherited ACE on the child
                                $matches =
                                    $childAccess.Where({
                                        $_.IsInherited -and
                                        $_.IdentityReference -eq $parentRule.IdentityReference -and
                                        $_.FileSystemRights -eq $parentRule.FileSystemRights -and
                                        $_.AccessControlType -eq $parentRule.AccessControlType -and
                                        $_.InheritanceFlags -eq $parentRule.InheritanceFlags -and
                                        $_.PropagationFlags -eq $parentRule.PropagationFlags
                                    })

                                if ($matches.Count -eq 0) {
                                    $null = $missingRules.Add($parentRule)
                                }
                            }

                            if ($missingRules.Count -gt 0) {
                                # Collect identity names for reporting
                                $missingIdentitiesType = [System.Collections.Generic.List[string]]
                                $missingIdentities = [Activator]::CreateInstance($missingIdentitiesType)

                                foreach ($rule in $missingRules) {
                                    $null = $missingIdentities.Add($rule.IdentityReference.ToString())
                                }

                                # Optional ACL verification for the parent
                                $parentAclInvalid = $false
                                if ($VerifyParent) {
                                    try {
                                        $verifyOutput = & icacls $parent.FullName /verify 2>&1
                                        foreach ($line in $verifyOutput) {
                                            if ($line -match 'Invalid ACL') {
                                                $parentAclInvalid = $true
                                                break
                                            }
                                        }
                                    }
                                    catch {
                                        # If icacls fails, we just leave ParentAclInvalid as $false
                                        # and let the consumer decide how to handle it.
                                    }
                                }

                                $result = [pscustomobject]@{
                                    Path                     = $child.FullName
                                    ParentPath               = $parent.FullName
                                    Depth                    = $depth + 1
                                    MissingInheritedAceCount = $missingRules.Count
                                    MissingIdentities        = $missingIdentities.ToArray()
                                    ParentInheritanceEnabled = $parentInheritanceEnabled
                                    ChildInheritanceEnabled  = $childInheritanceEnabled
                                    ParentAclInvalid         = $parentAclInvalid
                                }

                                Write-Output $result
                            }
                        }
                    }

                    # Enqueue the child for further traversal if -Recurse is set
                    if ($Recurse) {
                        $childFrame = [pscustomobject]@{
                            Item  = $child
                            Acl   = $childAcl
                            Depth = $depth + 1
                        }
                        $queue.Enqueue($childFrame)
                    }
                }
            }
        }
    }
}
