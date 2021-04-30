function Invoke-TCP {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Source,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $Destination
    )

    Write-Host ":: $([System.DateTime]::Now) :: $($Source.NodeName) [$($Source.IPAddress)] <-> $($Destination.NodeName) [$($Destination.IPaddress)] [CTS Traffic]"

    $TCPResults = New-Object -TypeName psobject

    if (!($Source.IPAddress -in $global:localIPs) -and !(Invoke-Command -ComputerName $Source.NodeName -ScriptBlock { Test-Path -Path "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe" })) {
        $DestinationSession = New-PSSession -ComputerName $Source.NodeName
        Invoke-Command -ComputerName $Source.NodeName -ScriptBlock {cmd /c "mkdir C:\Test-NetStack\tools\CTS-Traffic"} -ErrorAction SilentlyContinue
        Copy-Item C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\Test-NetStack\tools\CTS-Traffic -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue
    }
    if (!($Destination.IPAddress -in $global:localIPs) -and !(Invoke-Command -ComputerName $Destination.NodeName -ScriptBlock { Test-Path -Path "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe" })) {
        $DestinationSession = New-PSSession -ComputerName $Destination.NodeName
        Invoke-Command -ComputerName $Destination.NodeName -ScriptBlock {cmd /c "mkdir C:\Test-NetStack\tools\CTS-Traffic"} -ErrorAction SilentlyContinue
        Copy-Item C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -Destination C:\Test-NetStack\tools\CTS-Traffic -Force -ToSession $DestinationSession -ErrorAction SilentlyContinue
    }
    

    # CTS Traffic Rate Limit is specified in bytes/second
    $ServerLinkSpeed = $Source.LinkSpeed.split(" ")
    Switch($ServerLinkSpeed[1]) {            
        ("Gbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) / 8}
    }

    $ClientLinkSpeed = $Destination.LinkSpeed.split(" ")
    Switch($ClientLinkSpeed[1]) {              
        ("Gbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) / 8}
    }

    Invoke-Command -ComputerName $Source.NodeName, $Destination.NodeName -ScriptBlock { New-NetFirewallRule -DisplayName "CtsTraffic" -Direction Inbound -Protocol TCP -LocalPort 4444 -Action Allow | Out-Null }
    
    $ServerRecvCounter = Start-Job `
    -ScriptBlock {
        param([string]$ServerName,[string]$ServerInterfaceDescription)
        $ServerInterfaceDescription = (((($ServerInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
        Invoke-Command -ComputerName $ServerName `
        -ScriptBlock { 
            param([string]$ServerInterfaceDescription)
            Get-Counter -Counter "\Network Adapter($ServerInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 -ErrorAction Ignore 
         } `
         -ArgumentList $ServerInterfaceDescription
    } `
    -ArgumentList $Source.NodeName,$Source.InterfaceDescription
    
    $ServerSendCounter = Start-Job `
    -ScriptBlock {
        param([string]$ServerName,[string]$ServerInterfaceDescription)
        $ServerInterfaceDescription = (((($ServerInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
        Invoke-Command -ComputerName $ServerName `
        -ScriptBlock { 
            param([string]$ServerInterfaceDescription)
            Get-Counter -Counter "\Network Adapter($ServerInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20 -ErrorAction Ignore 
         } `
         -ArgumentList $ServerInterfaceDescription
    } `
    -ArgumentList $Source.NodeName,$Source.InterfaceDescription

    $ServerOutput = Start-Job `
    -ScriptBlock {
        param([string]$ServerName,[string]$ServerIP,[string]$ServerLinkSpeed)
        Invoke-Command -ComputerName $ServerName `
        -ScriptBlock { 
            param([string]$ServerIP)
            cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -consoleverbosity:1 -ServerExitLimit:64 -TimeLimit:20000 -pattern:duplex" 
         } `
         -ArgumentList $ServerIP
    } `
    -ArgumentList $Source.NodeName,$Source.IPAddress,$Source.LinkSpeed

    $ClientRecvCounter = Start-Job `
    -ScriptBlock {
        param([string]$ClientName,[string]$ClientInterfaceDescription) 
        $ClientInterfaceDescription = (((($ClientInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
        Invoke-Command -ComputerName $ClientName `
        -ScriptBlock { 
            param([string]$ClientInterfaceDescription)
            Get-Counter -Counter "\Network Adapter($ClientInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 
         } `
         -ArgumentList $ClientInterfaceDescription
    } `
    -ArgumentList $Destination.NodeName,$Destination.InterfaceDescription

    $ClientSendCounter = Start-Job `
    -ScriptBlock {
        param([string]$ClientName,[string]$ClientInterfaceDescription)
        $ClientInterfaceDescription = (((($ClientInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
        Invoke-Command -ComputerName $ClientName `
        -ScriptBlock { 
            param([string]$ClientInterfaceDescription)
            Get-Counter -Counter "\Network Adapter($ClientInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20
         } `
         -ArgumentList $ClientInterfaceDescription
    } `
    -ArgumentList $Destination.NodeName,$Destination.InterfaceDescription
    
    $ClientOutput = Start-Job `
    -ScriptBlock {
        param([string]$ClientName,[string]$ServerIP,[string]$ClientIP,[string]$ClientLinkSpeed)
        Invoke-Command -ComputerName $ClientName `
        -ScriptBlock { 
            param([string]$ServerIP,[string]$ClientIP,[string]$ClientLinkSpeed)
            cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -connections:64 -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed -pattern:duplex"  
         } `
         -ArgumentList $ServerIP,$ClientIP,$ClientLinkSpeed
    } `
    -ArgumentList $Destination.NodeName,$Source.IPAddress,$Destination.IPAddress,$ClientLinkSpeedBps
    

    Start-Sleep 20
                       
    $ServerRecv = Receive-Job $ServerRecvCounter
    $ServerSend = Receive-Job $ServerSendCounter
    $ClientRecv = Receive-Job $ClientRecvCounter
    $ClientSend = Receive-Job $ClientSendCounter

    $FlatServerRecvOutput = $ServerRecv.Readings.split(":") | ForEach-Object {
        try {[uint64]($_) * 8} catch{}
    }
    $FlatServerSendOutput = $ServerSend.Readings.split(":") | ForEach-Object {
        try {[uint64]($_) * 8} catch{}
    }
    $FlatClientRecvOutput = $ClientRecv.Readings.split(":") | ForEach-Object {
        try {[uint64]($_) * 8} catch{}
    }
    $FlatClientSendOutput = $ClientSend.Readings.split(":") | ForEach-Object {
        try {[uint64]($_) * 8} catch{}
    }

    $ServerRecvBitsPerSecond = [Math]::Round(($FlatServerRecvOutput | Measure-Object -Maximum).Maximum, 2)
    $ServerSendBitsPerSecond = [Math]::Round(($FlatServerSendOutput | Measure-Object -Maximum).Maximum, 2)
    $ClientRecvBitsPerSecond = [Math]::Round(($FlatClientRecvOutput | Measure-Object -Maximum).Maximum, 2)
    $ClientSendBitsPerSecond = [Math]::Round(($FlatClientSendOutput | Measure-Object -Maximum).Maximum, 2)
                      
    Write-Verbose "Server Recv bps: $ServerRecvBitsPerSecond"
    Write-Verbose "Server Send bps: $ServerSendBitsPerSecond"
    Write-Verbose "Client Recv bps: $ClientRecvBitsPerSecond"
    Write-Verbose "Client Send bps: $ClientSendBitsPerSecond"
                        
    $ServerOutput = Receive-Job $ServerOutput
    $ClientOutput = Receive-Job $ClientOutput

    $ServerLinkSpeedBitsPerSecond = $ServerLinkSpeedBps * 8
    $ClientLinkSpeedBitsPerSecond = $ClientLinkSpeedBps * 8

    $MinLinkSpeed = ($ServerLinkSpeedBitsPerSecond, $ClientLinkSpeedBitsPerSecond | Measure-Object -Minimum).Minimum
    Write-Verbose "Minimum Link Speed bps: $MinLinkSpeed"


    $TCPResults | Add-Member -MemberType NoteProperty -Name ServerRecvBitsPerSecond -Value $ServerRecvBitsPerSecond
    $TCPResults | Add-Member -MemberType NoteProperty -Name ServerSendBitsPerSecond -Value $ServerSendBitsPerSecond
    $TCPResults | Add-Member -MemberType NoteProperty -Name ClientRecvBitsPerSecond -Value $ClientRecvBitsPerSecond
    $TCPResults | Add-Member -MemberType NoteProperty -Name ClientSendBitsPerSecond -Value $ClientSendBitsPerSecond
    $TCPResults | Add-Member -MemberType NoteProperty -Name MinLinkSpeed -Value $MinLinkSpeed


    Return $TCPResults
}