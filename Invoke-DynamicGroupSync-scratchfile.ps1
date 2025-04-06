$credential = Get-Credential

$paramsAD = @{
    Server = 'dougjohnson.me'
    Credential = $credential
}

$test = Get-ADUser -Filter * @paramsAD

$ous = Get-ADOrganizationalUnit -Filter * @paramsAD

$allGroups = Get-ADGroup -Filter * -SearchBase $ouMyGroups -Properties 'CanonicalName' @paramsAD

$ouMyGroups = 'OU=MyGroups,DC=dougjohnson,DC=me'

$groupName = 'DJM_ACL_AD_Dyn_City_Farmington'

$paramsNewAdGroup = @{
    Name = $groupName
    SamAccountName = $groupName
    GroupCategory = 'Security'
    GroupScope = 'DomainLocal'
    DisplayName = $groupName
    Path = $ouMyGroups
}

New-ADGroup @paramsNewAdGroup @paramsAD -PassThru

New-ADOrganizationalUnit -Name "TestDynComputers" -Path 'OU=MyComputers,DC=dougjohnson,DC=me' @paramsAD

'OU=TestDynUsers,OU=MyUsers,DC=dougjohnson,DC=me'

'OU=TestDynComputers,OU=MyComputers,DC=dougjohnson,DC=me'

$testComputerNames = @(
    [PSCustomObject] @{ Name = 'USER01-WRK01'; Location = 'Heaven'},
    [PSCustomObject] @{ Name = 'USER02-WRK02'; Location = 'Heaven'},
    [PSCustomObject] @{ Name = 'USER03-WRK03'; Location = 'Closet'},
    [PSCustomObject] @{ Name = 'USER04-WRK04'; Location = 'Heaven'},
    [PSCustomObject] @{ Name = 'USER05-WRK05'; Location = 'Closet'},
    [PSCustomObject] @{ Name = 'USER06-WRK06'; Location = 'Heaven'},
    [PSCustomObject] @{ Name = 'USER07-WRK07'; Location = 'Heaven'},
    [PSCustomObject] @{ Name = 'USER08-WRK08'; Location = 'Closet'},
    [PSCustomObject] @{ Name = 'USER09-WRK09'; Location = 'Closet'},
    [PSCustomObject] @{ Name = 'USER10-WRK10'; Location = 'Heaven'}
)

$path = 'OU=TestDynComputers,OU=MyComputers,DC=dougjohnson,DC=me'

foreach ($computer in (1..1000)) {

    $computerName = "computer$computer"

    New-ADComputer -Name $computerName -SamAccountName $computerName -Path $path @paramsAD
}


New-ADComputer -Name "USER02-SRV2" -SamAccountName "USER02-SRV2" -Path "OU=ApplicationServers,OU=ComputerAccounts,OU=Managed,DC=USER02,DC=COM"


<#
    .SYNOPSIS
    Add-NewUsersRandomPasswords.ps1

    .DESCRIPTION
    Create Active Directory users with a random password using PowerShell.

    .LINK
    www.alitajran.com/bulk-create-ad-users-with-random-passwords/

    .NOTES
    Written by: ALI TAJRAN
    Website:    www.alitajran.com
    LinkedIn:   linkedin.com/in/alitajran

    .CHANGELOG
    V1.00, 03/16/2020 - Initial version
    V2.00, 01/28/2024 - Added try/catch and changed to splatting
#>

# Import active directory module for running AD cmdlets
Import-Module ActiveDirectory

$LogDate = Get-Date -f dd-MM-yyyy_HHmmffff

# Location of CSV file that contains the users information
$ImportPath = "C:\Temp\NewUsersRP.csv"

# Location of CSV file that will be exported to including random passwords
$ExportPath = "C:\Temp\Passwords_$LogDate.csv"

# Define UPN
$UPN = "dougjohnson.me"

# Set the password length characters
$PasswordLength = 14

# Store the data from NewUsersRP.csv in the $ADUsers variable
$ADUsers = Import-Csv $ImportPath

# Initialize a List to store the data
$Report = [System.Collections.Generic.List[Object]]::new()

# www.alitajran.com/generate-secure-random-passwords-powershell/
function Get-RandomPassword {
    param (
        # The length of each password which should be created.
        [Parameter(Mandatory = $true)]
        [ValidateRange(8, 255)]
        [Int32]$Length,

        # The number of passwords to generate.
        [Parameter(Mandatory = $false)]
        [Int32]$Count = 1,

        # The character sets the password may contain.
        # A password will contain at least one of each of the characters.
        [String[]]$CharacterSet = @(
            'abcdefghijklmnopqrstuvwxyz',
            'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
            '0123456789',
            '!$%&^.#;'
        )
    )

    # Generate a cryptographically secure seed
    $bytes = [Byte[]]::new(4)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $seed = [System.BitConverter]::ToInt32($bytes, 0)
    $rnd = [Random]::new($seed)

    # Combine all character sets for random selection
    $allCharacterSets = [String]::Concat($CharacterSet)

    try {
        for ($i = 0; $i -lt $Count; $i++) {
            $password = [Char[]]::new($Length)
            $index = 0

            # Ensure at least one character from each set
            foreach ($set in $CharacterSet) {
                $password[$index++] = $set[$rnd.Next($set.Length)]
            }

            # Fill remaining characters randomly from all sets
            for ($j = $index; $j -lt $Length; $j++) {
                $password[$index++] = $allCharacterSets[$rnd.Next($allCharacterSets.Length)]
            }

            # Fisher-Yates shuffle for randomness
            for ($j = $Length - 1; $j -gt 0; $j--) {
                $m = $rnd.Next($j + 1)
                $t = $password[$j]
                $password[$j] = $password[$m]
                $password[$m] = $t
            }

            # Output each password
            Write-Output ([String]::new($password))
        }
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

$ou = 'OU=TestDynUsers,OU=MyUsers,DC=dougjohnson,DC=me'
# Loop through each row containing user details in the CSV file
foreach ($User in $ADUsers) {

    $password = Get-RandomPassword -Length $PasswordLength

    $userName = $user.FirstName + "." + $user.LastName
    $displayName = "$($User.FirstName) $($User.LastName)"
    $userPrincipalName = "$userName@$UPN"

    try {
        $userParams = @{
            SamAccountName        = $userName
            UserPrincipalName     = $userPrincipalName
            Name                  = $displayName
            GivenName             = $User.FirstName
            Surname               = $User.LastName
            Enabled               = $true
            DisplayName           = $displayName
            Path                  = $ou
            EmailAddress          = $userPrincipalName
            AccountPassword       = (ConvertTo-SecureString $password -AsPlainText -Force)
            ChangePasswordAtLogon = $True
        }


        # User does not exist then proceed to create the new user account
        # Account will be created in the OU provided by the $OU variable read from the CSV file
        New-ADUser @userParams @paramsAD

        # If the user is created, add the data to the export report
        $ReportLine = $User | Add-Member -MemberType NoteProperty -Name "Initial Password" -Value $password -PassThru
        $Report.Add($ReportLine)
        # If the user is created, show a message
        Write-Host "The user $($User.username) is created." -ForegroundColor Green
    }
    catch {
        # If an exception occurs during user creation, handle it here
        Write-Host "Failed to create user $($User.username) - $_" -ForegroundColor Red
    }
}

# Export the data to CSV file
if ($Report.Count -gt 0) {
    $Report | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding utf8
    Write-Host "CSV file is exported to $ExportPath." -ForegroundColor Cyan
}
else {
    Write-Host "No users were created. CSV file will not be exported." -ForegroundColor Cyan
}



$peoriaUsers = Get-ADUser -LDAPFilter '(l=Peoria)' -SearchBase "OU=MyUsers,DC=dougjohnson,DC=me" -Properties * @paramsAD

$basementComputers = Get-ADComputer -LDAPFilter '(location=Basement)' -SearchBase "OU=MyComputers,DC=dougjohnson,DC=me" -Properties 'Location' @paramsAD


$ConfigPath = 'C:\temp\DynamicGroups.json'
$schemaPath = 'C:\temp\DynamicGroupsSchema.json'

$rawJson = Get-Content -Raw -Path $ConfigPath
$rawJson | Test-Json -SchemaFile $schemaPath

$ou = 'OU=TestDynUsers,OU=MyUsers,DC=dougjohnson,DC=me'

# change user properties
$peoriaUsers = Get-ADUser -Filter "City -eq 'Peoria'" -SearchBase $ou @paramsAD

$hellUsers = Get-ADUser -Filter "City -eq 'Hell'" -SearchBase $ou @paramsAD

$roanokeUsers = Get-ADUser -Filter "City -eq 'Roanoke'" -SearchBase $ou @paramsAD

$allTestUsers = $peoriaUsers + $hellUsers + $roanokeUsers

$newPeoriaUsers = $allTestUsers | Get-Random -Count ([int]($allTestUsers.count / 3))

$newHellUsers = $allTestUsers.Where({$group1Users.objectGUID -notcontains $_.objectGUID}) | Get-Random -Count ([int]($allTestUsers.count / 3))

$newRoanokeUsers = $allTestUsers.Where({$group1Users.objectGUID -notcontains $_.objectGUID -and $group2Users.objectGUID -notcontains $_.objectGUID})

$newPeoriaUsers | Set-ADUser -City 'Peoria' @paramsAD
$newHellUsers | Set-ADUser -City 'Hell' @paramsAD
$newRoanokeUsers | Set-ADUser -City 'Roanoke' @paramsAD

###### assign computers to random location
$path = 'OU=TestDynComputers,OU=MyComputers,DC=dougjohnson,DC=me'
$allTestComputers = Get-ADComputer -Filter * -SearchBase $path @paramsAD

$group1Computers = $allTestComputers | Get-Random -Count ([int]($allTestComputers.count / 4))

$group2Computers = $allTestComputers.Where({$group1Computers.objectGUID -notcontains $_.objectGUID}) | Get-Random -Count ([int]($allTestComputers.count / 4))

$group3Computers = $allTestComputers.Where({$group1Computers.objectGUID -notcontains $_.objectGUID -and $group2Computers.objectGUID -notcontains $_.objectGUID}) | Get-Random -Count ([int]($allTestComputers.count / 4))

$group4Computers = $allTestComputers.Where({$group1Computers.objectGUID -notcontains $_.objectGUID -and $group2Computers.objectGUID -notcontains $_.objectGUID -and $group3Computers.objectGUID -notcontains $_.objectGUID})


$group1Computers | Set-ADComputer -Location 'First Floor' @paramsAD

$group2Computers | Set-ADComputer -Location 'Basement' @paramsAD

$group3Computers | Set-ADComputer -Location 'Closet' @paramsAD

$group4Computers | Set-ADComputer -Location 'Heaven' @paramsAD

###### assign users to random city
$ou = 'OU=TestDynUsers,OU=MyUsers,DC=dougjohnson,DC=me'
$allTestUsers = Get-ADUser -Filter * -SearchBase $ou @paramsAD

$group1Users = $allTestUsers | Get-Random -Count ([int]($allTestUsers.count / 4))

$group2Users = $allTestUsers.Where({$group1Users.objectGUID -notcontains $_.objectGUID}) | Get-Random -Count ([int]($allTestUsers.count / 4))

$group3Users = $allTestUsers.Where({$group1Users.objectGUID -notcontains $_.objectGUID -and $group2Users.objectGUID -notcontains $_.objectGUID}) | Get-Random -Count ([int]($allTestUsers.count / 4))

$group4Users = $allTestUsers.Where({$group1Users.objectGUID -notcontains $_.objectGUID -and $group2Users.objectGUID -notcontains $_.objectGUID -and $group3Users.objectGUID -notcontains $_.objectGUID})

$group1Users | Set-ADUser -City 'Peoria' @paramsAD

$group2Users | Set-ADUser -City 'Hell' @paramsAD

$group3Users | Set-ADUser -City 'Roanoke' @paramsAD

$group4Users | Set-ADUser -City 'Farmington' @paramsAD

######

$groups = $rules.Name

$userGroups = @(
    'DJM_ACL_AD_Dyn_City_Peoria',
    'DJM_ACL_AD_Dyn_City_Hell',
    'DJM_ACL_AD_Dyn_City_Roanoke',
    'DJM_ACL_AD_Dyn_City_Farmington'
)

$ou = 'OU=TestDynUsers,OU=MyUsers,DC=dougjohnson,DC=me'
$groupName = 'DJM_ACL_AD_Dyn_City_Farmington'
$memberCount = (Get-ADGroupMember -Identity $groupName @paramsAD).count

$targetUsersCount = (Get-ADUser -Filter "City -eq 'Farmington'" -SearchBase $ou @paramsAD).count

if ($memberCount -eq $targetUsersCount) {

    Write-Host "$groupName count is good" -ForegroundColor 'Green'
}
else {

    Write-Host "$groupName count is not good" -ForegroundColor 'Red'
}
