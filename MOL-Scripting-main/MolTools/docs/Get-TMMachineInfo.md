---
external help file: MolTools-help.xml
Module Name: MolTools
online version:
schema: 2.0.0
---

# Get-TMMachineInfo

## SYNOPSIS
Retrieves specific information about one or more computers using WMI or CIM.

## SYNTAX

```
Get-TMMachineInfo [-ComputerName] <String[]> [[-Credential] <PSCredential>] [[-LogFailuresToPath] <String>]
 [[-Protocol] <String>] [-ProtocolFallback] [-ProgressAction <ActionPreference>] [<CommonParameters>]
```

## DESCRIPTION
This command uses either WMI or CIM to retrieve specific information about one or more
computers.
You must run this command as a user with permission to query CIM or WMI on the
machines involved remotely.
You can specify a starting protocol (CIM by default), and specify
that the other protocol be used on a per-machine basis in the event of a failure.

## EXAMPLES

### EXAMPLE 1
```
Get-TMMachineInfo -ComputerName ONE,TWO,THREE
This example will query three machines when multiple computer names are specified directly in
the ComputerName parameter.
```

### EXAMPLE 2
```
ONE,TWO,THREE | Get-TMMachineInfo
This example will query three machines when multiple computer names are passed through the
pipeline to Get-TMMachineInfo.
```

### EXAMPLE 3
```
Get-ADComputer -Filter * | Select -ExpandProperty Name | Get-TMMachineInfo
This example will attempt to query all machines in AD.
```

## PARAMETERS

### -ComputerName
One or more computer names.
When using WMI, this can also be IP addresses.
IP addresses may
not work for CIM.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases: CN, MachineName, Name

Required: True
Position: 1
Default value: None
Accept pipeline input: True (ByValue)
Accept wildcard characters: False
```

### -Credential
A PS credential to specify if connecting with a different user account.

```yaml
Type: PSCredential
Parameter Sets: (All)
Aliases:

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -LogFailuresToPath
A path and filename to write failed computer names to.
If omitted, no
log will be written.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
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

### -Protocol
Valid values: Wsman (uses CIM) or Dcom (uses WMI).
It will be used for all machines.
"Wsman"
is the default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: Wsman
Accept pipeline input: False
Accept wildcard characters: False
```

### -ProtocolFallback
Specify this to try the other protocol if a machine fails automatically.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
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
