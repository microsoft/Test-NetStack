function Invoke-NDKPing {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, Position=0)]
        [PSObject] $Server,

        [Parameter(Mandatory=$true, Position=1)]
        [PSObject] $Client
    )

    Write-Host ":: $([System.DateTime]::Now) :: $($Client.NodeName) [$($Client.IPaddress)] -> $($Server.NodeName) [$($Server.IPAddress)] [NDK Ping]"

    $NDKPingResults = New-Object -TypeName psobject

    $ServerOutput = Start-Job `
    -ScriptBlock {
        param([string]$ServerName,[string]$ServerIP,[string]$ServerIF)
        Invoke-Command -ComputerName $ServerName `
        -ScriptBlock {
            param([string]$ServerIP,[string]$ServerIF)
            cmd /c "NdkPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5 2>&1"
        } `
        -ArgumentList $ServerIP,$ServerIF
    } `
    -ArgumentList $Server.NodeName,$Server.IPAddress,$Server.InterfaceIndex

    Start-Sleep -Seconds 1

    $ClientOutput = Invoke-Command -ComputerName $Client.NodeName `
    -ScriptBlock { 
        param([string]$ServerIP,[string]$ClientIP,[string]$ClientIF)
        cmd /c "NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping 2>&1" 
    } `
    -ArgumentList $Server.IPAddress,$Client.IPAddress,$Client.InterfaceIndex

    Start-Sleep -Seconds 5
            
    $ServerOutput = Receive-Job $ServerOutput
                                
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

    Write-Host ":: $([System.DateTime]::Now) :: $($Client.NodeName) [$($Client.IPaddress)] -> $($Server.NodeName) [$($Server.IPAddress)] [NDK Perf 1:1]"

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
        Start-Sleep -Seconds 1

        $ServerCounter = Start-Job `
        -ScriptBlock {
            param([string]$ServerName,[string]$ServerInterfaceDescription)
            Invoke-Command -ComputerName $ServerName `
            -ScriptBlock { 
                param([string]$ServerInterfaceDescription)
                Get-Counter -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 20 -ErrorAction Ignore 
            } `
            -ArgumentList $ServerInterfaceDescription
        } `
        -ArgumentList $Server.NodeName,$Server.InterfaceDescription
        Start-Sleep -Seconds 1 

        $ServerOutput = Start-Job `
        -ScriptBlock {
            param([string]$ServerName,[string]$ServerIP,[string]$ServerIF)
            Invoke-Command -ComputerName $ServerName `
            -ScriptBlock {
                param([string]$ServerIP,[string]$ServerIF)
                cmd /c "NDKPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rperf -W 20 2>&1" 
            } `
            -ArgumentList $ServerIP,$ServerIF
        } `
        -ArgumentList $Server.NodeName,$Server.IPAddress,$Server.InterfaceIndex
        Start-Sleep -Seconds 1
                                        
        $ClientCounter = Start-Job `
        -ScriptBlock {
            param([string]$ClientName,[string]$ClientInterfaceDescription)
            Invoke-Command -ComputerName $ClientName `
            -ScriptBlock {
                param([string]$ClientInterfaceDescription)
                Get-Counter -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 20 
            } `
            -ArgumentList $ClientInterfaceDescription
        } `
        -ArgumentList $Client.NodeName,$Client.InterfaceDescription
                                        
        $ClientOutput = Invoke-Command -ComputerName $Client.NodeName `
        -ScriptBlock {
            param([string]$ServerIP,[string]$ClientIP,[string]$ClientIF)
            cmd /c "NDKPerfCmd.exe -C -ServerAddr $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rperf 2>&1" 
        } `
        -ArgumentList $Server.IPAddress,$Client.IPAddress,$Client.InterfaceIndex
                                        
        $read = Receive-Job $ServerCounter
        $written = Receive-Job $ClientCounter

        $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
            try {[uint64]($_)} catch{}
        }
        $FlatClientOutput = $written.Readings.split(":") | ForEach-Object {
            try {[uint64]($_)} catch{}
        }
        $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
        $ClientBytesPerSecond = ($FlatClientOutput | Measure-Object -Maximum).Maximum

        Start-Sleep -Seconds 5
                                        
        $ServerOutput = Receive-Job $ServerOutput
                                        
        Write-Verbose "NDK Perf Server Output: "
        $ServerOutput | ForEach-Object {
            $ServerSuccess = $_ -match 'completes'
            if ($_) { Write-Verbose $_ }
        }
        Write-Verbose "`r`n"
        
        Write-Verbose "NDK Perf Client Output: "
        $ClientOutput | ForEach-Object {
            $ClientSuccess = $_ -match 'completes'
            if ($_) { Write-Verbose $_ }
        }
        Write-Verbose "`r`n##################################################`r`n"
            
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
    #$ReceivedPctgOfLinkSpeed = [Math]::Round(($ServerBytesPerSecond / $ServerLinkSpeedBps) * 100, 2)
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
        [PSObject] $ClientNetwork
    )

    $NDKPerfNto1Results = New-Object -TypeName psobject
    $ClientNetworksTested = @()
    $NClientResults = @()
    $ResultString = ""

    # Increment number of client nodes sending at once
    for ($i = 1; $i -le $ClientNetwork.Count; $i++) {

        $RandomClientNodes = If ($ClientNetwork.Count -eq 1) { $ClientNetwork[0] } Else { $ClientNetwork[0..$i] }
        $N = $RandomClientNodes.Count
        if ($ClientNetworksTested) { $ClientNetworksTested = $ClientNetworksTested, $RandomClientNodes.IPAddress }
        else { $ClientNetworksTested = $RandomClientNodes.IPAddress }
        
        # To append as last digit of port number
        #$j = 0
        $j = 9000

        $ServerOutput = @()
        $ClientOutput = @()
        $ServerCounter = @()
        $ClientCounter = @()
        $ServerSuccess = $True
        $MultiClientSuccess = $True
        #$ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):900$j  -ServerIf $ServerIF -TestType rping -W 5`r`n"
        #$NewResultInformation = [ResultInformationData]::new()
        #$NewResultInformation.ReproCommand = "`r`n`t`t$ServerCommand"

        $RandomClientNodes | ForEach-Object {
            Start-Sleep -Seconds 1
                        
            $ClientName = $_.NodeName
            #$ClientInterface = $_.InterfaceListStruct.Values | where Name -In $_.RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
            $ClientIP = $_.IPAddress
            $ClientIF = $_.InterfaceIndex
            $ClientInterfaceDescription = $_.InterfaceDescription
            $ClientLinkSpeed = [Int]::Parse($_.LinkSpeed.Split()[0]) * [Math]::Pow(10, 9) / 8
            $ServerLinkSpeed = [Int]::Parse($Server.LinkSpeed.Split()[0]) * [Math]::Pow(10, 9) / 8

            <#                
            $ClientCommand = "Client $($_.Name) CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
            Write-Host $ServerCommand
            $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            Write-Host $ClientCommand
            $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            #>


            $ServerCounter += Start-Job `
            -ScriptBlock {
                param([string]$ServerName,[string]$ServerInterfaceDescription)
                #$ServerName = $Using:ServerName
                #$ServerInterfaceDescription = $Using:ServerInterfaceDescription
                Get-Counter -ComputerName $ServerName -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 20 #-ErrorAction Ignore
            } `
            -ArgumentList $Server.NodeName,$Server.InterfaceDescription


            $ServerOutput += Start-Job `
            -ScriptBlock {
                param([string]$ServerName,[string]$ServerIP,[string]$ServerIF,[int]$j)
                #$ServerIP = $Using:ServerIP
                #$ServerIF = $Using:ServerIF
                #$j = $Using:j
                Invoke-Command -ComputerName $ServerName `
                -ScriptBlock {
                    param([string]$ServerIP,[string]$ServerIF,[int]$j)
                    cmd /c "NdkPerfCmd.exe -S -ServerAddr $($ServerIP):$j  -ServerIf $ServerIF -TestType rperf -W 20 2>&1" 
                } `
                -ArgumentList $ServerIP,$ServerIF,$j
            } `
            -ArgumentList $Server.NodeName,$Server.IPAddress,$Server.InterfaceIndex,$j

            $ClientCounter += Start-Job `
            -ScriptBlock {
                param([string]$ClientName,[string]$ClientInterfaceDescription)
                #$ClientName = $Using:ClientName
                #$ClientInterfaceDescription = $Using:ClientInterfaceDescription
                Get-Counter -ComputerName $ClientName -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 20
            } `
            -ArgumentList $ClientName,$ClientInterfaceDescription

            $ClientOutput += Start-Job `
            -ScriptBlock {
                param([string]$ClientName,[string]$ServerIP,[string]$ClientIP,[string]$ClientIF,[int]$j)
                #$ServerIP = $Using:ServerIP
                #$ClientIP = $Using:ClientIP
                #$ClientIF = $Using:ClientIF
                #$j = $Using:j
                Invoke-Command -Computername $ClientName `
                -ScriptBlock {
                    param([string]$ServerIP,[string]$ClientIP,[string]$ClientIF,[int]$j)
                    cmd /c "NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):$j -ClientAddr $($ClientIP) -ClientIf $($ClientIF) -TestType rperf 2>&1" 
                } `
                -ArgumentList $ServerIP,$ClientIP,$ClientIF,$j
            } `
            -ArgumentList $ClientName,$Server.IPAddress,$ClientIP,$ClientIF,$j

            Start-Sleep -Seconds 1
            $j++
        }
                        
        Start-Sleep -Seconds 20
        Write-Host "##################################################`r`n"
        #"##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        $ServerBytesPerSecond = 0
        $k = 0
        $ServerCounter | ForEach-Object {
                            
            $read = Receive-Job $_

            $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
                try {[uint64]($_) * 8} catch{}
            }
            #$ClientInterface = $RandomClientNodes[$k].InterfaceListStruct.Values | where Name -In $RandomClientNodes[$k].RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
            #$ClientLinkSpeed = $ClientInterface.LinkSpeed
            $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
            $ServerSuccess = $ServerSuccess -and ($ServerBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)
                            
            $k++
        }
        $ResultString += "| ($Server.NodeName)`t`t| ($Server.IPAddress)`t| $ServerBytesPerSecond `t`t|" 

        $ServerOutput | ForEach-Object {
            $job = Receive-Job $_
            Write-Host $job
            #$job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        }
        Write-Host "`r`n##################################################`r`n"
        #"`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

        $k = 0
        $ClientCounter | ForEach-Object {
                            
            $written = Receive-Job $_
            $FlatClientOutput = $written.Readings.split(":") | ForEach-Object {
                try {[uint64]($_) * 8} catch{}
            }
            $ClientName = $RandomClientNodes[$k].NodeName
            #$ClientInterface = $RandomClientNodes[$k].InterfaceListStruct.Values | where Name -In $RandomClientNodes[$k].RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
            #$ClientIP = $ClientInterface.IpAddress
            #$ClientIF = $ClientInterface.IfIndex
            #$ClientLinkSpeed = $ClientInterface.LinkSpeed
            $ClientBytesPerSecond = ($FlatClientOutput | Measure-Object -Maximum).Maximum
            $IndividualClientSuccess = ($ClientBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)
            $MultiClientSuccess = $MultiClientSuccess -and $IndividualClientSuccess
            #$NewResultInformation.SourceMachineNameList += $ClientName
            #$NewResultInformation.SourceMachineIPList += $ClientIP
            #$NewResultInformation.SourceMachineActualBpsList += $ClientBytesPerSecond
            #$NewResultInformation.SourceMachineSuccessList += $IndividualClientSuccess
            #$NewResultInformation.ReproCommand += "`r`n`t`tClient $($_.ClientName) CMD:  C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
                            
            #$StageSuccessList["STAGE 6: NDK Perf (N : 1)"] = [Boolean[]]@()
                            
            $ResultString +=  "`r|`t`t`t`t`t`t`t`t`t| $($ClientName)`t`t| $($ClientIP)`t|"
            $ResultString += " $ClientBytesPerSecond bps`t| $IndividualClientSuccess`t|"
            $k++
        }

        $k = 0
        $ClientOutput | ForEach-Object {
            $job = Receive-Job $_
            Write-Host $job
            #$job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        }
        Write-Host "`r`n##################################################`r`n"
        #"`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

        $Success = $ServerSuccess -and $MultiClientSuccess
        if ($Success) { $NClientResults += "N = $($N): Pass" }
        else { $NClientResults += "N = $($N): Fail" }
        
        #$NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name ReceivedGbps -Value $ReceivedGbps
        

        <#                
        $Results["STAGE 6: NDK Perf (N : 1)"] += $ResultString
        if (-not $Success) {
            $Failures["STAGE 6: NDK Perf (N : 1)"] += $ResultString
        }

                        
        $NewResultInformation.TargetMachine = $ServerName
        $NewResultInformation.TargetIp = $ServerIP
        $NewResultInformation.NumSources = $MachineCluster.Count - 1
        $NewResultInformation.Success = $Success
        $ResultInformationList["STAGE 6: NDK Perf (N : 1)"] += $NewResultInformation
        $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] += $Success  
        #>
    }
    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name ClientNetworksTested -Value $ClientNetworksTested
    $NDKPerfNto1Results | Add-Member -MemberType NoteProperty -Name NClientResults -Value $NClientResults
    Return $NDKPerfNto1Results
}