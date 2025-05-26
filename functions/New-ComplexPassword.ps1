function New-ComplexPassword {

    <#
    .SYNOPSIS
        Generates a complex password with a specified length.

    .DESCRIPTION
        This function generates a complex password that includes at least one lowercase letter,
        one uppercase letter, one digit, and one special character. The password is shuffled to
        ensure randomness.

    .INPUTS
        [int]$Length - The length of the password to be generated. The default is 16 characters.

    .OUTPUTS
        [string] - A complex password string.

    .PARAMETER Length
        The length of the password to be generated. The default is 16 characters.

    .EXAMPLE
        New-ComplexPassword
        Generates a complex password with the default length of 16 characters.

    .EXAMPLE
        New-ComplexPassword -Length 20
        Generates a complex password with a length of 20 characters.
    #>

    [CmdletBinding()]
    [OutputType([string])]
    param (
        [ValidateScript({ $_ -ge 8 })]
        [int]$Length = 16
    )

    begin {

        # Define the character sets for password generation
        # Lowercase letters, uppercase letters, digits, and special characters
        $charSet = @{

            Digits    = [char[]](48..57)
            UpperCase = [char[]](65..90)
            LowerCase = [char[]](97..122)
            Special   = [char[]]( (33..47) + (58..64) + 91 + (93..95) + (123..126) )
            All       = [char[]]( (33..90) + 91 + (93..95) + (97..126) )
        }
    } # begin

    process {

        # Generate a random password with at least one character from each set
        # This ensures that the password meets complexity requirements
        $pwList = [System.Collections.Generic.List[psobject]]::new()
        $pwList.Add( ($charSet.LowerCase | Get-SecureRandom) )
        $pwList.Add( ($charSet.UpperCase | Get-SecureRandom) )
        $pwList.Add( ($charSet.Digits | Get-SecureRandom) )
        $pwList.Add( ($charSet.Special | Get-SecureRandom) )

        # Generate the remaining characters randomly
        for ($i = $pwList.count; $i -lt $Length; $i++) { 
            
            $pwList.Add( ($charSet.All | Get-SecureRandom) )
        }

        # Shuffle the password list to ensure randomness
        # Convert the list to a string and return it
        ($pwList | Get-SecureRandom -Shuffle) -join ''
    } # process
}