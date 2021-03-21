# basic ping, max mtu, reliability 90% or better, heartbeat

Function Invoke-UDPPMTUD {
    [CmdletBinding(DefaultParameterSetName = 'PMTUD')]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [Alias("Sender","SourceIP")]
        [IPAddress] $Source,

        [Parameter(Mandatory=$true, Position=1)]
        [Alias("Receiver", "DestinationIP", "RemoteIP", "Target")]
        [IPAddress] $Destination,

        [Parameter(Mandatory=$false, Position=2)]
        [Switch] $Reliability = $false,

        [parameter(Mandatory = $false)]
        [int] $port = 135,

        [parameter(Mandatory = $false)]
        [ValidateRange(800,10000)]
        [int] $StartBytes = 800, 

        [Parameter(Mandatory=$false, Position=5)]
        [int] $Count = 1000
    )
    
    $remoteEP = New-Object System.Net.IPEndPoint($Destination, $port)
    $localEP = New-Object System.Net.IPEndPoint($Source, 0)

    $udpClient = New-Object System.Net.Sockets.udpClient($localEP)
    $udpClient.Client.DontFragment = $true
    $udpClient.Connect($remoteEP)

    $obj = New-Object -TypeName psobject
    $obj | Add-Member -MemberType NoteProperty -Name SourceAddress      -Value $SourceAddress
    $obj | Add-Member -MemberType NoteProperty -Name DestinationAddress -Value $DestinationAddress

    if ($Reliability.IsPresent -eq $false) {
        1..$StartBytes | ForEach-Object { $data = $data + 'a' }

        :IncrementalMTU while ($true) {
            [byte[]] $buffer = [System.Text.Encoding]::ASCII.GetBytes($data)

            try {
                $MaxPathMTU = $udpClient.Send($buffer, $buffer.Length)
                $data = $data + 'a'
            }
            Catch { break IncrementalMTU }    
        }

        if (-not($MaxPathMTU)) { $MaxPathMTU = 'Error' }

        $obj | Add-Member -MemberType NoteProperty -Name UDPMSS             -Value $MaxPathMTU
        $obj | Add-Member -MemberType NoteProperty -Name UDPMTU             -Value $($MaxPathMTU + 42)

        return $obj
    }
    else {
        1..$StartBytes | ForEach-Object { $data = $data + 'a' }
        [byte[]] $buffer = [System.Text.Encoding]::ASCII.GetBytes($data)

        $UDPResponse = @()
        $timer = [System.DateTime]::Now

        do {
            $UDPResponse += $udpClient.Send($buffer, $buffer.Length)
        } until([System.DateTime]::Now -ge $timer.AddSeconds(15))


        $UDPReliability = @{
            Total  = $UDPResponse.Count
            Failed = $UDPResponse.Where({$_ -ne $true}).Count
        }
    }

    return $UDPReliability
}
