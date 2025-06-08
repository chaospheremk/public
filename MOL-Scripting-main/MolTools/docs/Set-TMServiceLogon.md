---
external help file: MolTools-help.xml
Module Name: MolTools
online version:
schema: 2.0.0
---

# Set-TMServiceLogon

## SYNOPSIS
Sets service login name and password.

## SYNTAX

```
Set-TMServiceLogon [-ServiceName] <String> [-ComputerName] <String[]> [-NewPassword] <String>
 [[-NewUser] <String>] [[-ErrorLogFilePath] <String>] [[-Credential] <PSCredential>]
 [-ProgressAction <ActionPreference>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## DESCRIPTION
This command uses either CIM (default) or WMI to set the service password, and optionally the
logon user name, for a service, which can be running on one or more remote machines.
You must
run this command as a user who has permission to perform this task, remotely, on the computers
involved.

## EXAMPLES

### EXAMPLE 1
```
Set-TMServiceLogon -ServiceName 'BITS' -ComputerName ONE,TWO,THREE -NewPassword 'abc123'
This example will update the service authentication password for the specified service on
three machines when multiple computer names are specified directly in the ComputerName
parameter.
```

### EXAMPLE 2
```
ONE,TWO,THREE | Set-TMServiceLogon -ServiceName 'BITS' -NewPassword 'abc123'
This example will update the service authentication password on three machines when multiple
computer names are passed through the pipeline to Set-TMServiceLogon.
```

### EXAMPLE 3
```
Set-TMServiceLogon -ServiceName 'BITS' -ComputerName computer1 -NewPassword 'abc123' `
PS>                    -NewUser 'DOMAIN\username'
This example will update the service authentication username and password for the specified
service on specified computers.
```

## PARAMETERS

### -ComputerName
One or more computer names.
Using IP addresses will fail with CIM; they will work with WMI.
CIM is always attempted first.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: True (ByPropertyName, ByValue)
Accept wildcard characters: False
```

### -Credential
A PS credential to specify if connecting to remote machines with a different user account.

```yaml
Type: PSCredential
Parameter Sets: (All)
Aliases:

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ErrorLogFilePath
If provided, this is a path and filename of a text file where failed computer names will be
logged.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -NewPassword
A plain-text string of the new password.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -NewUser
Optional; the new logon user name, in DOMAIN\USER format.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -ProgressAction
{{ Fill ProgressAction Description }}

```yaml
Type: ActionPreference
Parameter Sets: (All)
Aliases: proga

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -ServiceName
The name of the service.
Query the Win32_Service class to verify that you know the correct
name.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: False
```

### -Confirm
Prompts you for confirmation before running the cmdlet.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf
Shows what would happen if the cmdlet runs.
The cmdlet is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters
This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String
### You can pipe a string that contains a computer name to this cmdlet.
## OUTPUTS

### System.Management.Automation.PSCustomObject
### The cmdlet outputs a custom PSObject for reporting results.
## NOTES

## RELATED LINKS
