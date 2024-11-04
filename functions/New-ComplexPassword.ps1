function New-ComplexPassword {
    [CmdletBinding()]
    param ( [int]$Length = 16 )

    Begin {

        $upperCase = [char[]]"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        $lowerCase = [char[]]"abcdefghijklmnopqrstuvwxyz"
        $digits = [char[]]"0123456789"
        $specialChars = [char[]]"!@#$%^&*()-_=+[]{}|;:,.<>?/"

        # Combine all character sets
        [char[]]$allChars = $upperCase + $lowerCase + $digits + $specialChars
    }

    Process {

        $passwordList = [System.Collections.Generic.List[PSObject]]::new()
        $passwordList.Add(($upperCase | Get-SecureRandom))
        $passwordList.Add(($lowerCase | Get-SecureRandom))
        $passwordList.Add(($digits | Get-SecureRandom))
        $passwordList.Add(($specialChars | Get-SecureRandom))

        # Generate the remaining characters randomly
        for ($i = $passwordList.count; $i -lt $Length; $i++) { $passwordList.Add(( $allChars | Get-SecureRandom )) }

        # Convert the password array to a string and return
        [string]$passwordString = ($passwordList | Get-SecureRandom -Shuffle) -join ''

        $passwordString
    }
}