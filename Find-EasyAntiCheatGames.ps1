function Find-EasyAntiCheatGames {

    [CmdletBinding()]
    param (

        [string[]]
        $IncludeExtensions = @('exe', 'dll', 'sys'),

        [string[]]
        $EACIndicators = @(
            'EasyAntiCheat', 'EACLauncher', 'EAC',
            'EasyAntiCheat_x64.dll', 'EasyAntiCheat.sys', 'EasyAntiCheat_launcher.exe'
        ),

        [switch]
        $Detailed
    )

    $results = [System.Collections.Concurrent.ConcurrentBag[PSCustomObject]]::new()

    $enumerationOptions = [System.IO.EnumerationOptions]@{
        RecurseSubdirectories = $true
        IgnoreInaccessible    = $true
        AttributesToSkip      = [System.IO.FileAttributes]::ReparsePoint -bor [System.IO.FileAttributes]::System
    }

    $scriptBlock = {
        param ($root, $eacIndicators, $includeExtensions, $options, $resultsBag)

        try {

            foreach ($file in [System.IO.Directory]::EnumerateFiles($root, '*', $options)) {

                $name = [System.IO.Path]::GetFileName($file)

                foreach ($indicator in $eacIndicators) {

                    if ($name -like "*$indicator*") {

                        $ext = [System.IO.Path]::GetExtension($file).TrimStart('.').ToLowerInvariant()

                        if ($includeExtensions -contains $ext) {

                            $resultsBag.Add(

                                [PSCustomObject]@{
                                    GamePath = [System.IO.Path]::GetDirectoryName($file)
                                    File     = $name
                                    FullPath = $file
                                }
                            )

                            break
                        }
                    }
                }
            }
        }
        catch {}
    }

    $runspaces = [System.Collections.Generic.List[System.Management.Automation.PowerShell]]::new()
    $jobs = [System.Collections.Generic.List[System.IAsyncResult]]::new()

    $paramsGetCI = @{
        Path        = 'C:\'
        Directory   = $true
        ErrorAction = 'SilentlyContinue'
    }

    $notMatchString = 'Windows|System Volume Information|ProgramData'

    $topDirs = (Get-ChildItem @paramsGetCI).Where({ $_.FullName -notmatch $notMatchString })

    foreach ($dir in $topDirs) {

        $ps = [powershell]::Create()
        $runspaces.Add($ps)

        $job = $ps.AddScript($scriptBlock).
                   AddArgument($dir.FullName).
                   AddArgument($EACIndicators).
                   AddArgument($IncludeExtensions).
                   AddArgument($enumerationOptions).
                   AddArgument($results).
                   BeginInvoke()

        $jobs.Add($job)
    }

    # Wait for all runspaces to finish
    for ($i = 0; $i -lt $jobs.Count; $i++) { $runspaces[$i].EndInvoke($jobs[$i]); $runspaces[$i].Dispose() }

    $grouped = $results | Group-Object -Property 'GamePath' | Sort-Object -Property 'Name'

    if ($Detailed) {

        $detailedResults = [System.Collections.Generic.List[PSCustomObject]]::new()

        foreach ($result in $grouped) {

            $detailedResults.Add(

                [PSCustomObject]@{
                    GamePath = $result.Name
                    EACFiles = $result.Group.File
                }
            )
        }

        $detailedResults
    }
    else { $grouped.Name }
}