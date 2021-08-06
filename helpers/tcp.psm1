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
        ("bps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) / 8}
    }

    $ClientLinkSpeed = $Sender.LinkSpeed.split(" ")
    Switch($ClientLinkSpeed[1]) {
        ("Gbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps")  {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) / 8}
    }

    $ServerRecvCounter = Start-Job -ScriptBlock {
        param ([string] $ServerName , [string] $ServerInterfaceDescription)

        $ServerInterfaceDescription = (((($ServerInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_'

        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param([string]$ServerInterfaceDescription)
            Get-Counter -Counter "\Network Adapter($ServerInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 -ErrorAction Ignore
         } -ArgumentList $ServerInterfaceDescription

    } -ArgumentList $Receiver.NodeName,$Receiver.InterfaceDescription

    $ServerOutput = Start-Job -ScriptBlock {
        param ([string] $ServerName, [string] $ServerIP, $ModuleBase)

        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param ([string] $ServerIP, [string] $ModuleBase)

            & "$ModuleBase\tools\CTS-Traffic\ctsTraffic.exe" -listen:$ServerIP -consoleverbosity:1 -verify:connection -buffer:4194304 -transfer:0xffffffffffffffff -msgwaitall:on -io:rioiocp -TimeLimit:30000
         } -ArgumentList $ServerIP, $ModuleBase

    } -ArgumentList $Receiver.NodeName, $Receiver.IPAddress, $ModuleBase

    $ClientSendCounter = Start-Job -ScriptBlock {
        param([string] $ClientName, [string] $ClientInterfaceDescription)
        $ClientInterfaceDescription = (((($ClientInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_'

        Invoke-Command -ComputerName $ClientName -ScriptBlock {
            param ([string] $ClientInterfaceDescription)

            Get-Counter -Counter "\Network Adapter($ClientInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20
         } -ArgumentList $ClientInterfaceDescription

    } -ArgumentList $Sender.NodeName,$Sender.InterfaceDescription

    $ClientOutput = Start-Job -ScriptBlock {
        param ([string] $ClientName, [string] $ServerIP, [string] $ClientIP, [string] $ModuleBase)

        Invoke-Command -ComputerName $ClientName -ScriptBlock {
            param ([string] $ServerIP, [string] $ClientIP, $ModuleBase)

            & "$ModuleBase\tools\CTS-Traffic\ctsTraffic.exe" -bind:$ClientIP -target:$ServerIP -consoleverbosity:1 -verify:connection -buffer:4194304 -transfer:0xffffffffffffffff -msgwaitall:on -io:rioiocp -connections:32
         } -ArgumentList $ServerIP, $ClientIP, $ModuleBase

    } -ArgumentList $Sender.NodeName, $Receiver.IPAddress, $Sender.IPAddress, $ModuleBase

    #TODO: We should track the job state or listen for an event rather than a simplistic timer like this.
    Start-Sleep 30

    $ServerRecv = Receive-Job $ServerRecvCounter
    $ClientSend = Receive-Job $ClientSendCounter

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

    $ServerOutput = Receive-Job $ServerOutput
    $ClientOutput = Receive-Job $ClientOutput

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