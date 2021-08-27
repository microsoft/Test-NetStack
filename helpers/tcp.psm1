function Invoke-TCP {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Receiver,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $Sender
    )

    $ModuleBase = (Get-Module Test-NetStack -ListAvailable | Select-Object -First 1).ModuleBase

    # CTS Traffic Rate Limit is specified in bytes/second
    $ServerLinkSpeed = $Receiver.LinkSpeed.split(" ")
    Switch($ServerLinkSpeed[1]) {
        ("Gbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps") {$ServerLinkSpeedBps  = [Int]::Parse($ServerLinkSpeed[0]) / 8}
    }

    $ClientLinkSpeed = $Sender.LinkSpeed.split(" ")
    Switch($ClientLinkSpeed[1]) {
        ("Gbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps")  {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) / 8}
    }

    $ServerRecvCounter = Invoke-Command -ComputerName $Receiver.NodeName -ScriptBlock {
        $ServerInterfaceDescription = ((($($using:Receiver).InterfaceDescription -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_'

        Get-Counter -Counter "\Network Adapter($ServerInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 -ErrorAction Ignore
    } -JobName "Svr.Counter.$($Receiver.NodeName)" -AsJob

    $ServerOutput = Invoke-Command -ComputerName $Receiver.NodeName -ScriptBlock {
        & "$($using:ModuleBase)\tools\CTS-Traffic\ctsTraffic.exe" -listen:$($using:Receiver).IPAddress -consoleverbosity:1 -verify:connection -buffer:4194304 -transfer:0xffffffffffffffff -msgwaitall:on -io:rioiocp -TimeLimit:20000
    } -JobName "Svr.Output.$($Receiver.NodeName)" -AsJob

    $ClientSendCounter = Invoke-Command -ComputerName $Sender.NodeName -ScriptBlock {
        $ClientInterfaceDescription = ((($($using:Sender).InterfaceDescription -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_'

        Get-Counter -Counter "\Network Adapter($ClientInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20
    } -JobName "Client.Counter.$($Sender.NodeName)" -AsJob

    $ClientOutput = Invoke-Command -ComputerName $Sender.NodeName -ScriptBlock {
        & "$($using:ModuleBase)\tools\CTS-Traffic\ctsTraffic.exe" -bind:$($using:Sender.IPAddress) -target:$($using:Receiver.IPAddress) -consoleverbosity:1 -verify:connection -buffer:4194304 -transfer:0xffffffffffffffff -msgwaitall:on -io:rioiocp -connections:32 -iterations:5
    } -JobName "Client.Output.$($Sender.NodeName)" -AsJob

    $ServerRecv = Receive-Job $ServerRecvCounter -Wait -AutoRemoveJob
    $ClientSend = Receive-Job $ClientSendCounter -Wait -AutoRemoveJob

    $FlatServerRecvOutput = $ServerRecv.Readings.split(":") | ForEach-Object {
        try {[uint64]($_) * 8} catch {}
    }
    $FlatClientSendOutput = $ClientSend.Readings.split(":") | ForEach-Object {
        try {[uint64]($_) * 8} catch {}
    }

    $ServerRecvBitsPerSecond = [Math]::Round(($FlatServerRecvOutput | Measure-Object -Maximum).Maximum, 2)
    $ClientSendBitsPerSecond = [Math]::Round(($FlatClientSendOutput | Measure-Object -Maximum).Maximum, 2)

    Write-Verbose "Server Recv bps: $ServerRecvBitsPerSecond"
    Write-Verbose "Client Send bps: $ClientSendBitsPerSecond"

    $ServerOutput = Receive-Job $ServerOutput -Wait -AutoRemoveJob
    $ClientOutput = Receive-Job $ClientOutput -Wait -AutoRemoveJob

    $ServerLinkSpeedBitsPerSecond = $ServerLinkSpeedBps * 8
    $ClientLinkSpeedBitsPerSecond = $ClientLinkSpeedBps * 8

    $MinLinkSpeedBitsPerSecond = ($ServerLinkSpeedBitsPerSecond, $ClientLinkSpeedBitsPerSecond | Measure-Object -Minimum).Minimum
    Write-Verbose "Minimum Link Speed bps: $MinLinkSpeedBitsPerSecond"

    $RawData = New-Object -TypeName psobject
    $RawData | Add-Member -MemberType NoteProperty -Name ServerRxbps -Value $ServerRecvBitsPerSecond
    $RawData | Add-Member -MemberType NoteProperty -Name ClientTxbps -Value $ClientSendBitsPerSecond
    $RawData | Add-Member -MemberType NoteProperty -Name MinLinkSpeedbps -Value $MinLinkSpeedBitsPerSecond

    $ReceiverLinkSpeedGbps = [Math]::Round($ServerLinkSpeedBitsPerSecond * [Math]::Pow(10, -9), 2)
    $ReceivedGbps = [Math]::Round($ServerRecvBitsPerSecond * [Math]::Pow(10, -9), 2)
    $ReceivedPercentageOfLinkSpeed = [Math]::Round(($ReceivedGbps / $ReceiverLinkSpeedGbps) * 100, 2)

    $TCPResults = New-Object -TypeName psobject
    $TCPResults | Add-Member -MemberType NoteProperty -Name ReceiverLinkSpeedGbps -Value $ReceiverLinkSpeedGbps
    $TCPResults | Add-Member -MemberType NoteProperty -Name ReceivedGbps -Value $ReceivedGbps
    $TCPResults | Add-Member -MemberType NoteProperty -Name ReceivedPctgOfLinkSpeed -Value $ReceivedPercentageOfLinkSpeed
    $TCPResults | Add-Member -MemberType NoteProperty -Name RawData -Value $RawData

    Return $TCPResults
}