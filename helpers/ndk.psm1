function Invoke-NDKPing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Server,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $Client
    )

    $NDKPingResults = New-Object -TypeName psobject

    $ServerOutput = Start-Job -ScriptBlock {
        param ([string] $ServerName, [string] $ServerIP, [string] $ServerIF)

        Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param([string] $ServerIP, [string] $ServerIF)
            cmd /c "NdkPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 15 2>&1"
        } -ArgumentList $ServerIP, $ServerIF
    } -ArgumentList $Server.NodeName, $Server.IPAddress, $Server.InterfaceIndex

    $ClientOutput = Invoke-Command -ComputerName $Client.NodeName -ScriptBlock {
        param ([string] $ServerIP, [string] $ClientIP, [string] $ClientIF)

        cmd /c "NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping 2>&1"
    } -ArgumentList $Server.IPAddress, $Client.IPAddress, $Client.InterfaceIndex

    $ServerOutput = Receive-Job $ServerOutput -Wait -AutoRemoveJob

    Write-Verbose "NDK Ping Server Output: "
    $ServerOutput | ForEach-Object {
        $ServerSuccess = $_ -match 'completes'
        if ($_) { Write-Verbose $_ }
    }

    $NDKPingResults | Add-Member -MemberType NoteProperty -Name ServerSuccess -Value $ServerSuccess
    Return $NDKPingResults
}

function Invoke-NDKPerf1to1 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Server,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $Client,

        [Parameter(Mandatory=$true, Position=2)]
        [int] $ExpectedTPUT
    )

    $NDKPerf1to1Results = New-Object -TypeName psobject

    $ServerLinkSpeed = $Server.LinkSpeed.split(" ")
    Switch($ServerLinkSpeed[1]) {
        ("Gbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps") {$ServerLinkSpeedBps = [Int]::Parse($ServerLinkSpeed[0]) / 8}
    }

    $ClientLinkSpeed = $Client.LinkSpeed.split(" ")
    Switch($ClientLinkSpeed[1]) {
        ("Gbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 9) / 8}
        ("Mbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 6) / 8}
        ("Kbps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) * [Math]::Pow(10, 3) / 8}
        ("bps") {$ClientLinkSpeedBps = [Int]::Parse($ClientLinkSpeed[0]) / 8}
    }

    $ExpectedTPUTDec = $ExpectedTPUT / 100

    $Success = $False
    $Retries = 3

    while ((-not $Success) -and ($Retries -gt 0)) {
        $Success = $False
        $ServerSuccess = $False
        $ClientSuccess = $False

        $ServerCounter = Start-Job -ScriptBlock {
            param ([string] $ServerName, [string] $ServerInterfaceDescription )

            Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param( [string] $ServerInterfaceDescription )

                Get-Counter -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 20 -ErrorAction Ignore
            } -ArgumentList $ServerInterfaceDescription
        } -ArgumentList $Server.NodeName, $Server.InterfaceDescription

        $ServerOutput = Start-Job -ScriptBlock {
            param ([string] $ServerName, [string] $ServerIP, [string] $ServerIF)

            Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param ([string] $ServerIP, [string] $ServerIF)

                cmd /c "NDKPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rperf -W 20 2>&1"
            } -ArgumentList $ServerIP,$ServerIF
        } -ArgumentList $Server.NodeName, $Server.IPAddress, $Server.InterfaceIndex

        $ClientCounter = Start-Job -ScriptBlock {
            param ([string] $ClientName, [string] $ClientInterfaceDescription)

            Invoke-Command -ComputerName $ClientName -ScriptBlock {
                param ([string] $ClientInterfaceDescription)

                Get-Counter -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 20
            } -ArgumentList $ClientInterfaceDescription

        } -ArgumentList $Client.NodeName, $Client.InterfaceDescription

        $ClientOutput = Invoke-Command -ComputerName $Client.NodeName -ScriptBlock {
            param ([string] $ServerIP, [string] $ClientIP, [string] $ClientIF)
            cmd /c "NDKPerfCmd.exe -C -ServerAddr $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rperf 2>&1"
        } -ArgumentList $Server.IPAddress,$Client.IPAddress,$Client.InterfaceIndex

        $read = Receive-Job $ServerCounter -Wait -AutoRemoveJob
        $written = Receive-Job $ClientCounter -Wait -AutoRemoveJob

        $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
            try {[uint64]($_)} catch{}
        }
        $FlatClientOutput = $written.Readings.split(":") | ForEach-Object {
            try {[uint64]($_)} catch{}
        }
        $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
        $ClientBytesPerSecond = ($FlatClientOutput | Measure-Object -Maximum).Maximum

        $ServerOutput = Receive-Job $ServerOutput -Wait -AutoRemoveJob

        $MinLinkSpeedBps = ($ServerLinkSpeedBps, $ClientLinkSpeedBps | Measure-Object -Minimum).Minimum
        $Success = ($ServerBytesPerSecond -gt $MinLinkSpeedBps * $ExpectedTPUTDec) -and ($ClientBytesPerSecond -gt $MinLinkSpeedBps * $ExpectedTPUTDec)
        $Retries--
    }

    $RawData = New-Object -TypeName psobject
    $RawData | Add-Member -MemberType NoteProperty -Name ServerBytesPerSecond -Value $ServerBytesPerSecond
    $RawData | Add-Member -MemberType NoteProperty -Name ClientBytesPerSecond -Value $ClientBytesPerSecond
    $RawData | Add-Member -MemberType NoteProperty -Name MinLinkSpeedBps -Value $MinLinkSpeedBps

    $ReceiverLinkSpeedGbps = [Math]::Round(($ServerLinkSpeedBps * 8) * [Math]::Pow(10, -9), 2)
    $ReceivedGbps = [Math]::Round(($ServerBytesPerSecond * 8) * [Math]::Pow(10, -9), 2)
    $ReceivedPctgOfLinkSpeed = [Math]::Round(($ReceivedGbps / $ReceiverLinkSpeedGbps) * 100, 2)

    $NDKPerf1to1Results | Add-Member -MemberType NoteProperty -Name ReceiverLinkSpeedGbps -Value $ReceiverLinkSpeedGbps
    $NDKPerf1to1Results | Add-Member -MemberType NoteProperty -Name ReceivedGbps -Value $ReceivedGbps
    $NDKPerf1to1Results | Add-Member -MemberType NoteProperty -Name ReceivedPctgOfLinkSpeed -Value $ReceivedPctgOfLinkSpeed
    $NDKPerf1to1Results | Add-Member -MemberType NoteProperty -Name RawData -Value $RawData

    Return $NDKPerf1to1Results
}

function Invoke-NDKPerfNto1 {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Server,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $ClientNetwork,

        [Parameter(Mandatory=$true, Position=2)]
        [int] $ExpectedTPUT
    )

    $NDKPerfNto1Results = New-Object -TypeName psobject
    $ClientNetworksTested = @()
    $NClientResults = @()
    $ResultString = ""
    $ExpectedTPUTDec = $ExpectedTPUT / 100

    $j = 9000

    $ServerOutput = @()
    $ClientOutput = @()
    $ServerCounter = @()
    $ClientCounter = @()
    $ServerSuccess = $True
    $MultiClientSuccess = $True

    $ClientNetwork | ForEach-Object {
        $ClientName = $_.NodeName
        $ClientIP = $_.IPAddress
        $ClientIF = $_.InterfaceIndex
        $ClientInterfaceDescription = $_.InterfaceDescription
        $ClientLinkSpeedBps = [Int]::Parse($_.LinkSpeed.Split()[0]) * [Math]::Pow(10, 9) / 8
        $ServerLinkSpeedBps = [Int]::Parse($Server.LinkSpeed.Split()[0]) * [Math]::Pow(10, 9) / 8

        $ServerCounter += Start-Job -ScriptBlock {
            param ([string] $ServerName, [string] $ServerInterfaceDescription)

            Get-Counter -ComputerName $ServerName -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 20 #-ErrorAction Ignore
        } -ArgumentList $Server.NodeName,$Server.InterfaceDescription

        $ServerOutput += Start-Job -ScriptBlock {
            param ([string] $ServerName, [string] $ServerIP, [string] $ServerIF, [int]$j)
            Invoke-Command -ComputerName $ServerName -ScriptBlock {
                param([string]$ServerIP,[string]$ServerIF,[int]$j)
                cmd /c "NdkPerfCmd.exe -S -ServerAddr $($ServerIP):$j  -ServerIf $ServerIF -TestType rperf -W 20 2>&1"
            } -ArgumentList $ServerIP, $ServerIF, $j
        } -ArgumentList $Server.NodeName, $Server.IPAddress, $Server.InterfaceIndex, $j

        $ClientCounter += Start-Job -ScriptBlock {
            param ([string] $ClientName, [string] $ClientInterfaceDescription)

            Get-Counter -ComputerName $ClientName -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 20
        } -ArgumentList $ClientName,$ClientInterfaceDescription

        $ClientOutput += Start-Job -ScriptBlock {
            param ([string] $ClientName, [string] $ServerIP, [string] $ClientIP, [string] $ClientIF, [int]$j)

            Invoke-Command -Computername $ClientName -ScriptBlock {
                param ([string] $ServerIP, [string] $ClientIP, [string] $ClientIF, [int] $j)
                cmd /c "NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):$j -ClientAddr $($ClientIP) -ClientIf $($ClientIF) -TestType rperf 2>&1"
            } -ArgumentList $ServerIP,$ClientIP,$ClientIF,$j
        } -ArgumentList $ClientName,$Server.IPAddress,$ClientIP,$ClientIF,$j

        $j++
    }

    $ServerBytesPerSecond = 0
    $ServerBpsArray = @()
    $ServerGbpsArray = @()
    $MinAcceptableLinkSpeedBps = ($ServerLinkSpeedBps, $ClientLinkSpeedBps | Measure-Object -Minimum).Minimum * $ExpectedTPUTDec
    $ServerCounter | ForEach-Object {
        $read = Receive-Job $_ -Wait -AutoRemoveJob

        if ($read.Readings) {
            $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
                try {[uint64]($_)} catch{}
            }
        }

        $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
        $ServerBpsArray += $ServerBytesPerSecond
        $ServerGbpsArray += [Math]::Round(($ServerBytesPerSecond * 8) * [Math]::Pow(10, -9), 2)
        $ServerSuccess = $ServerSuccess -and ($ServerBytesPerSecond -gt $MinAcceptableLinkSpeedBps)
    }

    $RawData = New-Object -TypeName psobject
    $RawData | Add-Member -MemberType NoteProperty -Name ServerBytesPerSecond -Value $ServerBpsArray
    $RawData | Add-Member -MemberType NoteProperty -Name MinLinkSpeedBps -Value $MinAcceptableLinkSpeedBps

    $ReceiverLinkSpeedGbps = [Math]::Round(($ServerLinkSpeedBps * 8) * [Math]::Pow(10, -9), 2)

    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name ReceiverLinkSpeedGbps -Value $ReceiverLinkSpeedGbps
    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name RxGbps -Value $ServerGbpsArray
    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name ClientNetworkTested -Value $ClientNetwork.IPAddress
    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name ServerSuccess -Value $ServerSuccess
    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name RawData -Value $RawData

    Return $NDKPerfNto1Results
}

function Invoke-NDKPerfNtoN {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $ServerList,

        [Parameter(Mandatory=$true, Position=1)]
        [int] $ExpectedTPUT
    )

    $thisSubnet = ($ServerList | Select-Object -First 1).subnet
    $thisVLAN = ($ServerList | Select-Object -First 1).VLAN

    $NDKPerfNtoNResults = New-Object -TypeName psobject
    $ExpectedTPUTDec = $ExpectedTPUT / 100

    $j = 9000

    $ServerOutput = @()
    $ClientOutput = @()
    $ServerCounter = @()
    $ClientCounter = @()

    $ServerSuccess = $True

    $ServerList | ForEach-Object {
        $Server = $_
        $ServerLinkSpeedBps = [Int]::Parse($Server.LinkSpeed.Split()[0]) * [Math]::Pow(10, 9) / 8
        $ClientNetwork = $ServerList | Where-Object NodeName -ne $Server.NodeName

        $ClientNetwork | ForEach-Object {
            $ClientName = $_.NodeName
            $ClientIP = $_.IPAddress
            $ClientIF = $_.InterfaceIndex
            $ClientInterfaceDescription = $_.InterfaceDescription
            $ClientLinkSpeedBps = [Int]::Parse($_.LinkSpeed.Split()[0]) * [Math]::Pow(10, 9) / 8

            $ServerCounter += Start-Job -ScriptBlock {
                param ([string] $ServerName, [string] $ServerInterfaceDescription)

                Get-Counter -ComputerName $ServerName -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 20 #-ErrorAction Ignore
            } -ArgumentList $Server.NodeName,$Server.InterfaceDescription

            $ServerOutput += Start-Job -ScriptBlock {
                param ([string] $ServerName, [string] $ServerIP, [string] $ServerIF, [int] $j)

                Invoke-Command -ComputerName $ServerName -ScriptBlock {
                    param([string]$ServerIP,[string]$ServerIF,[int]$j)
                    cmd /c "NdkPerfCmd.exe -S -ServerAddr $($ServerIP):$j  -ServerIf $ServerIF -TestType rperf -W 20 2>&1"
                } -ArgumentList $ServerIP, $ServerIF, $j
            } -ArgumentList $Server.NodeName,$Server.IPAddress,$Server.InterfaceIndex,$j

            $ClientCounter += Start-Job `
            -ScriptBlock {
                param([string]$ClientName,[string]$ClientInterfaceDescription)
                Get-Counter -ComputerName $ClientName -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 20
            } -ArgumentList $ClientName,$ClientInterfaceDescription

            $ClientOutput += Start-Job -ScriptBlock {
                param ([string] $ClientName, [string] $ServerIP, [string] $ClientIP, [string] $ClientIF, [int]$j)

                Invoke-Command -Computername $ClientName -ScriptBlock {
                    param ([string] $ServerIP, [string] $ClientIP, [string] $ClientIF, [int]$j)
                    cmd /c "NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):$j -ClientAddr $($ClientIP) -ClientIf $($ClientIF) -TestType rperf 2>&1"
                } -ArgumentList $ServerIP,$ClientIP,$ClientIF,$j
            } -ArgumentList $ClientName,$Server.IPAddress,$ClientIP,$ClientIF,$j

            $j++
        }
    }


    $ServerBytesPerSecond = 0
    $ServerBpsArray = @()
    $ServerGbpsArray = @()
    $MinAcceptableLinkSpeedBps = ($ServerLinkSpeedBps, $ClientLinkSpeedBps | Measure-Object -Minimum).Minimum * $ExpectedTPUTDec
    $ServerCounter | ForEach-Object {

        $read = Receive-Job $_ -Wait -AutoRemoveJob

        $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
            try {[uint64]($_)} catch{}
        }
        $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
        $ServerBpsArray += $ServerBytesPerSecond
        $ServerGbpsArray += [Math]::Round(($ServerBytesPerSecond * 8) * [Math]::Pow(10, -9), 2)
        $ServerSuccess = $ServerSuccess -and ($ServerBytesPerSecond -gt $MinAcceptableLinkSpeedBps)
    }

    $RawData = New-Object -TypeName psobject
    $RawData | Add-Member -MemberType NoteProperty -Name ServerBytesPerSecond -Value $ServerBpsArray

    $NDKPerfNtoNResults | Add-Member -MemberType NoteProperty -Name RxGbps -Value $ServerGbpsArray
    $NDKPerfNtoNResults | Add-Member -MemberType NoteProperty -Name ServerSuccess -Value $ServerSuccess
    $NDKPerfNtoNResults | Add-Member -MemberType NoteProperty -Name RawData -Value $RawData

    Return $NDKPerfNtoNResults
}
