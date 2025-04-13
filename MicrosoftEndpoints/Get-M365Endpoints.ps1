#### dependency functions
function Import-HtmlAgilityPack {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ })]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $loadedBinaries = [AppDomain]::CurrentDomain.GetAssemblies().GetName()

    if (-not $loadedBinaries.Where({ $_.Name -eq "HtmlAgilityPack" })) {

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

    begin { [System.Net.IPAddress]$parsedIP = $null } # begin

    process {

        if ([System.Net.IPAddress]::TryParse($IPString, [ref]$parsedIP)) {

            switch ($parsedIP.AddressFamily) {

                'InterNetwork' { 'IPv4' }
                'InterNetworkV6' { 'IPv6' }
                default { 'Unknown' }
            }
        }
        else { 'Invalid' }
    } # process
}

function Get-IPSubnetType {

    [CmdletBinding()]
    param (

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$IPSubnetString
    )

    begin { [System.Net.IPAddress]$parsedIP = $null } # begin

    process {

        $ipString = $IPSubnetString.Split('/')[0]

        if ([System.Net.IPAddress]::TryParse($ipString, [ref]$parsedIP)) {

            switch ($parsedIP.AddressFamily) {

                'InterNetwork' { 'IPv4' }
                'InterNetworkV6' { 'IPv6' }
                default { 'Unknown' }
            }
        }
        else { 'Invalid' }
    } # process
}


# primary functions
function Get-M365Endpoints {
    
    [CmdletBinding()]
    param (

        [ValidateSet("Commercial", "GCC", "GCCHigh", "DOD")]
        [string]$ServiceInstance = "Commercial"
    )

    begin {

        # Mapping of instance to API endpoint query
        $instanceMap = @{
            "Commercial" = "worldwide"
            "GCC"        = "usgovgcc"
            "GCCHigh"    = "usgovgcchigh"
            "DOD"        = "usgovdod"
        }

        $clientRequestId = [guid]::NewGuid().Guid
        $endpointUrl = "https://endpoints.office.com/endpoints/$($instanceMap[$ServiceInstance])?clientrequestid=$clientRequestId"
    } # begin

    process {

        try { $allEndpoints = Invoke-RestMethod -Uri $endpointUrl -Method 'Get' }
        catch {

            Write-Error "Failed to retrieve Microsoft 365 endpoint data: $_"
            return
        }

        $resultsList = [System.Collections.Generic.List[PSObject]]::new()

        foreach ($endpoint in $allEndpoints) {

            $serviceAreaDisplayName = $endpoint.serviceAreaDisplayName

            foreach ($url in $endpoint.urls) {

                if ($endpoint.tcpPorts) {

                    foreach ($port in ($endpoint.tcpPorts -split ',')) {

                        $resultsList.Add(
                            
                            [PSCustomObject]@{

                                EndpointType           = 'URL'
                                Endpoint               = $url
                                Protocol               = 'TCP'
                                Port                   = $port
                                ServiceAreaDisplayName = $serviceAreaDisplayName
                                Instance               = $ServiceInstance
                            }
                        )
                    }
                }

                if ($endpoint.udpPorts) {

                    foreach ($port in ($endpoint.udpPorts -split ',')) {

                        $resultsList.Add(
                            
                            [PSCustomObject]@{

                                EndpointType           = 'URL'
                                Endpoint               = $url
                                Protocol               = 'UDP'
                                Port                   = $port
                                ServiceAreaDisplayName = $serviceAreaDisplayName
                                Instance               = $ServiceInstance
                            }
                        )
                    }
                }
            }

            foreach ($ipSubnet in $endpoint.ips) {
                
                $endpointType = Get-IPSubnetType -IPSubnetString $ipSubnet

                if ($endpoint.tcpPorts) {

                    foreach ($port in ($endpoint.tcpPorts -split ',')) {

                        $resultsList.Add(
                            
                            [PSCustomObject]@{

                                EndpointType           = $endpointType
                                Endpoint               = $ipSubnet
                                Protocol               = 'TCP'
                                Port                   = $port
                                ServiceAreaDisplayName = $serviceAreaDisplayName
                                Instance               = $ServiceInstance
                            }
                        )
                    }
                }

                if ($endpoint.udpPorts) {

                    foreach ($port in ($endpoint.udpPorts -split ',')) {

                        $resultsList.Add(
                            
                            [PSCustomObject]@{

                                EndpointType           = $endpointType
                                Endpoint               = $ipSubnet
                                Protocol               = 'UDP'
                                Port                   = $port
                                ServiceAreaDisplayName = $serviceAreaDisplayName
                                Instance               = $ServiceInstance
                            }
                        )
                    }
                }
            }
        }

        $resultsList
    } # process
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
            'GCC' { $headerIdQuery = "//h3[@id='network-connectivity-requirements']/following-sibling::ul[1]" }
            'GCCHigh' { $headerIdQuery = "//h3[@id='us-government-cloud-inclusive-of-gcchigh-and-dod']/following-sibling::ul[1]" }
            'DOD' { $headerIdQuery = "//h3[@id='us-government-cloud-inclusive-of-gcchigh-and-dod']/following-sibling::ul[1]" }
        }

        # using SelectSingleNode to only grab the one unordered list XPath query grabs the unordered list after
        # h3 header id 'us-government-cloud-inclusive-of-gcchigh-and-dod'
        $ulNode = $htmlDoc.DocumentNode.SelectSingleNode($headerIdQuery)

        # select all URLs from the list
        foreach ($liNode in $ulNode.SelectNodes("li")) {

            # Extract the actual URL inside <code> if present
            foreach ($codeNode in $liNode.SelectNodes(".//code")) {
                
                $resultList.Add( [PSCustomObject]@{ URL = $codeNode.InnerText.Trim() } )
            }
        }

        $resultList
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
