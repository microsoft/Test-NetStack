function Test-StageTCPSingle {

    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [HashTable] $RetryStageSuccessList,
        [PSCredential] $Credentials = $null
    )
    
    Context "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        
        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
        Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

        Write-Host "Stage 3 Start Time: $endTime`r`n"
        "Stage 3 start Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        $Results["STAGE 3: TCP CTS Traffic"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER RECEIVE Gbps `t| SERVER SEND Gbps `t| CLIENT MACHINE`t| CLIENT NIC`t`t| CLIENT RECEIVE Gbps `t| CLIENT SEND Gbps `t| THRESHOLD (>65%) `t|")
        $Failures["STAGE 3: TCP CTS Traffic"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER RECEIVE Gbps `t| SERVER SEND Gbps `t| CLIENT MACHINE`t| CLIENT NIC`t`t| CLIENT RECEIVE Gbps `t| CLIENT SEND Gbps `t| THRESHOLD (>65%) `t|")
        $ResultInformationList["STAGE 3: TCP CTS Traffic"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 3: TCP CTS Traffic"] = [Boolean[]]@()
        $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {

            Write-Host "VERBOSE: Testing CTS Traffic (TCP) Connectivity on Machine: $($_.Name)"
            "VERBOSE: Testing CTS Traffic (TCP) Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

            $ServerNetworkNode = $_
            $ServerName = $_.Name
            $ServerCimSession = New-CimSession -ComputerName $ServerName -Credential $Credentials
            $ServerInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | Where Status -eq $True

            $ClientNetwork = $TestNetwork | Where Name -ne $ServerName

            $ClientNetwork | ForEach-Object {

                $ClientNode = $_
                $ClientName = $_.Name
                $ClientIPList = @()

                $ServerOutput = @()
                $ClientOutput = @()
                $i = 0

                $ServerInterfaceList | ForEach-Object { 

                    $ServerInterface = $_ 
                    $ClientInterface = ($ClientNode.InterfaceListStruct.Values | Where Subnet -eq $ServerInterface.Subnet | Where VLAN -eq $ServerInterface.VLAN | Where Name -eq $ServerInterface.Name)

                    $ServerIP = $ServerInterface.IpAddress
                    $ServerSubnet = $ServerInterface.Subnet
                    $ServerVLAN = $ServerInterface.VLAN
                    $ServerLinkSpeed = $ServerInterface.LinkSpeed
                    $ServerInterfaceDescription = $ServerInterface.Description
                    
                    $ClientIP = $ClientInterface.IpAddress
                    $ClientSubnet = $ClientInterface.Subnet
                    $ClientVLAN = $ClientInterface.VLAN
                    $ClientLinkSpeed = $ClientInterface.LinkSpeed
                    $ClientInterfaceDescription = $ClientInterface.Description

                    It "Synthetic Connection Test (TCP) -- Verify Throughput is >75% reported: Client $($ClientIP) to Server $($ServerIP)`r`n" {

                        $Success = $False

                        $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$($ServerIP) -consoleverbosity:1 -ServerExitLimit:64 -TimeLimit:20000 -pattern:duplex"
                        $ClientCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$($ServerIP) -bind:$ClientIP -connections:64 -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed -pattern:duplex"
                        $NewResultInformation = [ResultInformationData]::new()
                        
                        Write-Host $ServerCommand
                        $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        Write-Host $ClientCommand
                        $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        
                        $ServerRecvCounter = Start-Job -ScriptBlock {
                            $ServerName = $Using:ServerName
                            $ServerInterfaceDescription = (((($Using:ServerInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
                            Invoke-Command -ComputerName $ServerName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\Network Adapter($Using:ServerInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 -ErrorAction Ignore }
                        }
                        
                        $ServerSendCounter = Start-Job -ScriptBlock {
                            $ServerName = $Using:ServerName
                            $ServerInterfaceDescription = (((($Using:ServerInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
                            Invoke-Command -ComputerName $ServerName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\Network Adapter($Using:ServerInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20 -ErrorAction Ignore }
                        }

                        $ServerOutput = Start-Job -ScriptBlock {
                            $ServerIP = $Using:ServerIP
                            $ServerLinkSpeed = $Using:ServerLinkSpeed
                            Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -consoleverbosity:1 -ServerExitLimit:64 -TimeLimit:20000 -pattern:duplex" }
                        }

                        $ClientRecvCounter = Start-Job -ScriptBlock {
                            $ClientName = $Using:ClientName
                            $ClientInterfaceDescription = (((($Using:ClientInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']' ) -replace '/', '_' 
                            Invoke-Command -ComputerName $ClientName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\Network Adapter($Using:ClientInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 }
                        }

                        $ClientSendCounter = Start-Job -ScriptBlock {
                            $ClientName = $Using:ClientName
                            $ClientInterfaceDescription = (((($Using:ClientInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']' ) -replace '/', '_' 
                            Invoke-Command -ComputerName $ClientName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\Network Adapter($Using:ClientInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20 }
                        }

                        $ClientOutput = Start-Job -ScriptBlock {
                            $ServerIP = $Using:ServerIP
                            $ClientIP = $Using:ClientIP
                            $ClientLinkSpeed = $Using:ClientLinkSpeed
                            Invoke-Command -ComputerName $Using:ClientName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -connections:64 -consoleverbosity:1 -iterations:2 -RateLimit:$Using:ClientLinkSpeed -pattern:duplex" }
                        }
                        
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
                        
                        $ServerRecvBitsPerSecond = '{0:00.00}' -f [Math]::Round(($FlatServerRecvOutput | Measure-Object -Maximum).Maximum * [Math]::Pow(10, -9), 2)
                        $ServerSendBitsPerSecond = '{0:00.00}' -f [Math]::Round(($FlatServerSendOutput | Measure-Object -Maximum).Maximum * [Math]::Pow(10, -9), 2)
                        $ClientRecvBitsPerSecond = '{0:00.00}' -f [Math]::Round(($FlatClientRecvOutput | Measure-Object -Maximum).Maximum * [Math]::Pow(10, -9), 2)
                        $ClientSendBitsPerSecond = '{0:00.00}' -f [Math]::Round(($FlatClientSendOutput | Measure-Object -Maximum).Maximum * [Math]::Pow(10, -9), 2)
                        
                        Write-Host "New Server Recv bps: $ServerRecvBitsPerSecond"
                        Write-Host "New Server Send bps: $ServerSendBitsPerSecond"
                        Write-Host "New Client Recv bps: $ClientRecvBitsPerSecond"
                        Write-Host "New Client Send bps: $ClientSendBitsPerSecond"
                        
                        $ServerOutput = Receive-Job $ServerOutput
                        $ClientOutput = Receive-Job $ClientOutput
                        $ServerLinkSpeed = [Math]::Round(($ServerLinkSpeed) * [Math]::Pow(10, -9), 2)
                        $ClientLinkSpeed =[Math]::Round(($ClientLinkSpeed) * [Math]::Pow(10, -9), 2)
                        $Success = ($ServerRecvBitsPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .65) -and ($ServerSendBitsPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .65) -and ($ClientRecvBitsPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .65) -and ($ClientSendBitsPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .65)

                        Write-Host "Success: $Success"
                        Write-Host "TCP CTS Traffic Server Output: "
                        
                        Write-Host "TCP CTS Traffic Client Output: "
                        
                        if (($Success)) {
                            $Results["STAGE 3: TCP CTS Traffic"] += "|($ServerName)`t| ($ServerIP)`t| $ServerRecvBitsPerSecond Gbps `t`t| $ServerSendBitsPerSecond Gbps `t`t| ($ClientName)`t| ($ClientIP)`t| $ClientRecvBitsPerSecond Gbps `t`t| $ClientSendBitsPerSecond Gbps`t`t| $SUCCESS `t`t`t|"
                        }
                        if ((-not $Success)) {
                            $Failures["STAGE 3: TCP CTS Traffic"] += "|($ServerName)`t| ($ServerIP)`t| $ServerRecvBitsPerSecond Gbps `t`t| $ServerSendBitsPerSecond Gbps `t`t| ($ClientName)`t| ($ClientIP)`t| $ClientRecvBitsPerSecond Gbps `t`t| $ClientSendBitsPerSecond Gbps`t`t| $SUCCESS `t`t`t|"
                        }

                        if (($Success)) {

                            $NewResultInformation.SourceMachine = $ClientName
                            $NewResultInformation.TargetMachine = $ServerName
                            $NewResultInformation.SourceIp = $ClientIP
                            $NewResultInformation.TargetIp = $ServerIP
                            $NewResultInformation.Success = $Success
                            $NewResultInformation.ReportedSendBps = $ClientLinkSpeed
                            $NewResultInformation.ReportedReceiveBps = $ServerLinkSpeed
                            $NewResultInformation.ActualSendBps = $ClientSendBitsPerSecond
                            $NewResultInformation.ActualReceiveBps = $ServerRecvBitsPerSecond
                            $NewResultInformation.ReproCommand = "`r`n`t`tServer: $ServerCommand`r`n`t`tClient: $ClientCommand"
                            $ResultInformationList["STAGE 3: TCP CTS Traffic"] += $NewResultInformation
                            $StageSuccessList["STAGE 3: TCP CTS Traffic"] += $Success
                        }

                        $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"] += $Success

                        $Success | Should Be $True
                    }

                    $SuccessCount = $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"].Count
                    $Success = $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"][$SuccessCount - 1]
            
                    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                    Write-Host "Time: $endTime`r`n"
                    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    
                    Write-Host "`r`n####################################`r`n"
                    "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                }
            }

            $TestNetwork = $TestNetwork | where Name -ne $ServerName
        }
        
        Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 3: TCP CTS Traffic"

        Write-Host "RESULTS Stage 3: TCP CTS Traffic`r`n"
        "RESULTS Stage 3: TCP CTS Traffic`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        ($Results["STAGE 3: TCP CTS Traffic"]) | ForEach-Object {

            Write-Host $_ 
            $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

        }
        if ($StageSuccessList["STAGE 3: TCP CTS Traffic"] -contains $false) {
            Write-Host "`r`nSTAGE 3: CTS TRAFFIC FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
            "`r`nSTAGE 3: CTS TRAFFIC FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            # $StageNumber = 0
        }

        
        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

        Write-Host "Ending Stage 3: $endTime`r`n"
        "Ending Stage 3: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
    }
}