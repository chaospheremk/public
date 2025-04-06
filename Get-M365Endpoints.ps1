#### dependency functions
function Import-HtmlAgilityPack {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not ([AppDomain]::CurrentDomain.GetAssemblies().GetName()).Where( { $_.Name -eq "HtmlAgilityPack" })) {

        Add-Type -Path $Path
        Write-Verbose "HtmlAgilityPack loaded from $Path."
        #Write-Host "HtmlAgilityPack loaded from $Path." -ForegroundColor 'Green'
    }
    else {
        Write-Verbose "HtmlAgilityPack already loaded."
        #Write-Host "HtmlAgilityPack already loaded." -ForegroundColor 'Yellow'
    }
}

function Get-IPAddressType {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$IPString
    )

    Begin { [System.Net.IPAddress]$parsedIP = $null } # begin

    Process {

        if ([System.Net.IPAddress]::TryParse($IPString, [ref]$parsedIP)) {

            switch ($parsedIP.AddressFamily) {
                'InterNetwork'   { return 'IPv4' }
                'InterNetworkV6' { return 'IPv6' }
                default          { return 'Unknown' }
            }
        }
        else { return 'Invalid' }
    } # process
}

function Get-IPSubnetType {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$IPSubnetString
    )

    Begin { [System.Net.IPAddress]$parsedIP = $null } # begin

    Process {

        $ipString = $IPSubnetString.Split('/')[0]

        if ([System.Net.IPAddress]::TryParse($ipString, [ref]$parsedIP)) {

            switch ($parsedIP.AddressFamily) {
                'InterNetwork'   { return 'IPv4' }
                'InterNetworkV6' { return 'IPv6' }
                default          { return 'Unknown' }
            }
        }
        else { return 'Invalid' }
    } # process
}


# primary functions
function Get-M365Endpoints {
    
    [CmdletBinding()]
    param (
        [ValidateSet("Commercial", "GCC", "GCCHigh", "DOD")]
        [string]$ServiceInstance = "Commercial"
    )

    # Mapping of instance to API endpoint query
    $instanceMap = @{
        "Commercial" = "worldwide"
        "GCC"       = "usgovgcc"
        "GCCHigh"   = "usgovgcchigh"
        "DOD"       = "usgovdod"
    }

    $clientRequestId = [guid]::NewGuid().Guid
    $endpointUrl = "https://endpoints.office.com/endpoints/$($instanceMap[$ServiceInstance])?clientrequestid=$clientRequestId"

    try {
        $endpoints = Invoke-RestMethod -Uri $endpointUrl -Method Get
    }
    catch {
        Write-Error "Failed to retrieve Microsoft 365 endpoint data: $_"
        return
    }

    $resultsList = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($endpoint in $endpoints) {

        $serviceAreaDisplayName = $endpoint.serviceAreaDisplayName
        $urls = $endpoint.urls
        $ipSubnets = $endpoint.ips

        foreach ($url in $urls) {

            if ($endpoint.tcpPorts) {
                
                $ports = $endpoint.tcpPorts -split ','

                foreach ($port in $ports) {

                    $resultsList.Add(
                        
                        [PSCustomObject]@{

                            EndpointType = 'URL'
                            Endpoint         = $url
                            Protocol = 'TCP'
                            Port    = $port
                            ServiceAreaDisplayName = $serviceAreaDisplayName
                            Instance    = $ServiceInstance
                        }
                    )
                }
            }

            if ($endpoint.udpPorts) {
                
                $ports = $endpoint.udpPorts -split ','

                foreach ($port in $ports) {

                    $resultsList.Add(
                        
                        [PSCustomObject]@{

                            EndpointType = 'URL'
                            Endpoint         = $url
                            Protocol = 'UDP'
                            Port    = $port
                            ServiceAreaDisplayName = $serviceAreaDisplayName
                            Instance    = $ServiceInstance
                        }
                    )
                }
            }
        }

        foreach ($ipSubnet in $ipSubnets) {
            
            $endpointType = Get-IPSubnetType -IPSubnetString $ipSubnet

            if ($endpoint.tcpPorts) {
                
                $ports = $endpoint.tcpPorts -split ','

                foreach ($port in $ports) {

                    $resultsList.Add(
                        
                        [PSCustomObject]@{

                            EndpointType = $endpointType
                            Endpoint         = $ipSubnet
                            Protocol = 'TCP'
                            Port    = $port
                            ServiceAreaDisplayName = $serviceAreaDisplayName
                            Instance    = $ServiceInstance
                        }
                    )
                }
            }

            if ($endpoint.udpPorts) {
                
                $ports = $endpoint.udpPorts -split ','

                foreach ($port in $ports) {

                    $resultsList.Add(
                        
                        [PSCustomObject]@{

                            EndpointType = $endpointType
                            Endpoint         = $ipSubnet
                            Protocol = 'UDP'
                            Port    = $port
                            ServiceAreaDisplayName = $serviceAreaDisplayName
                            Instance    = $ServiceInstance
                        }
                    )
                }
            }
        }
    }


    return $resultsList
}

function Get-EntraHybridEndpoints {

    [CmdletBinding()]
    param (

        [ValidateSet("Commercial", "GCC", "GCCHigh", "DOD")]
        [string]$ServiceInstance = "Commercial"
    )

    Begin {

        # Load HTMLAgilityPack
        Import-HtmlAgilityPack -Path "C:\tools\HtmlAgilityPack.dll"

        # initialize List to hold the table data
        $resultList = [System.Collections.Generic.List[PSObject]]::new()

        # Mapping of instance to API endpoint query
        $url = 'https://learn.microsoft.com/en-us/entra/identity/devices/how-to-hybrid-join'
    } # begin

    Process {

        # Fetch HTML content
        $response = Invoke-WebRequest -Uri $url

        # Extract the HTML content
        $htmlContent = $response.Content

        # Create an HtmlDocument object
        $htmlDoc = New-Object HtmlAgilityPack.HtmlDocument

        # Load HTML content into the HtmlDocument
        $htmlDoc.LoadHtml($htmlContent)

        switch ($ServiceInstance) {

            'Worldwide' { $headerIdQuery = "//h3[@id='network-connectivity-requirements']/following-sibling::ul[1]" }
            'GCC'       { $headerIdQuery = "//h3[@id='network-connectivity-requirements']/following-sibling::ul[1]" }
            'GCCHigh'   { $headerIdQuery = "//h3[@id='us-government-cloud-inclusive-of-gcchigh-and-dod']/following-sibling::ul[1]" }
            'DOD'       { $headerIdQuery = "//h3[@id='us-government-cloud-inclusive-of-gcchigh-and-dod']/following-sibling::ul[1]" }
        }

        # using SelectSingleNode to only grab the one unordered list XPath query grabs the unordered list after
        # h3 header id 'us-government-cloud-inclusive-of-gcchigh-and-dod'
        $ulNode = $htmlDoc.DocumentNode.SelectSingleNode($headerIdQuery)

        # select all URLs from the list
        $liNodes = $ulNode.SelectNodes("li")
        
        foreach ($liNode in $liNodes) {

            # Extract the actual URL inside <code> if present
            $codeNodes = $liNode.SelectNodes(".//code")

            foreach ($codeNode in $codeNodes) { $resultList.Add( [PSCustomObject]@{ URL = $codeNode.InnerText.Trim() } ) }
        }

        return $resultList
    } # process
}

#####
# SCRATCHPAD

function Get-TeamsEndpoints {

    [CmdletBinding()]
    param (

        [ValidateSet("Worldwide", "GCC", "GCCHigh", "DOD")]
        [string]$ServiceInstance = "Worldwide"
    )

    Begin {

        # Load HTMLAgilityPack
        Import-HtmlAgilityPack -Path "C:\tools\HtmlAgilityPack.dll"

        # Mapping of instance to API endpoint query
        $url = @{

            'Worldwide' = 'https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges?view=o365-worldwide'
            'GCC'       = 'https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges?view=o365-worldwide'
            'GCCHigh'   = 'https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-u-s-government-gcc-high-endpoints?view=o365-worldwide'
            'DOD'       = 'https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-u-s-government-dod-endpoints?view=o365-worldwide'
        }
    } # begin

    Process {

        # Fetch HTML content
        $response = Invoke-WebRequest -Uri $url[$serviceInstance]

        # Extract the HTML content
        $htmlContent = $response.Content

        # Create an HtmlDocument object
        $htmlDoc = New-Object HtmlAgilityPack.HtmlDocument

        # Load HTML content into the HtmlDocument
        $htmlDoc.LoadHtml($htmlContent)

        # using SelectSingleNode to only grab the one table. XPath query grabs the table after h2 header id 'microsoft-teams'
        $tableNode = $htmlDoc.DocumentNode.SelectSingleNode("//h2[@id='microsoft-teams']/following-sibling::table[1]")

        # select all rows within the table
        $rows = $tableNode.SelectNodes(".//tr")

        # Get header cells (either <th> or <td>)
        $headerCells = $rows[0].SelectNodes(".//th")

        # Extract header names
        $headers = foreach ($headerCell in $headerCells) { $headerCell.InnerText.Trim() }

        # initialize List to hold the table data
        $tableList = [System.Collections.Generic.List[PSObject]]::new()

        # Loop over each row after the headers
        foreach ($row in $rows | Select-Object -Skip 1) {

            # Get all cells in the row (either <td> or <th>)
            $cells = $row.SelectNodes(".//td")

            # Create a hashtable to hold the row data
            $rowData = @{}

            # Loop through each cell and add to the hashtable
            for ($i = 0; $i -lt $cells.Count; $i++) {

                $header = $headers[$i]

                $cellValue = if ($cells[$i]) { $cells[$i].InnerText.Trim() } else { "" }

                $rowData[$header] = $cellValue
            }

            # Add the hashtable as a new PSObject to the list
            #$tableList.Add([PSCustomObject]$rowData)
            $tableList.Add([PSCustomObject]$rowData)
        }

        return $tableList
    } # process
}


### ipv4 regex

$ipv4Regex = '\b(?:(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(?:\.|$)){4}\b'

$ipv4Regex = '\b(?:(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(?:\.|$)){4}\b'


# ipv6 Regex
$ip = 'fe80::20d:3aff:fe1d:49e'
$ip = '192.168.1.1'


$isValidIP = [System.Net.IPAddress]::TryParse($ip, [ref]$null)
Write-Output $isValidIP # True



