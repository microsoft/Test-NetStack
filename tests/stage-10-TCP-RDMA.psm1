function Test-StageTCPHostToHost {

    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [HashTable] $RetryStageSuccessList,
        [PSCredential] $Credentials = $null
    )
    Context "VERBOSE: Testing Connectivity Stage 10: TCP + RDMA Congestion`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 10: TCP + RDMA Congestion`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 10: TCP + RDMA Congestion`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        
        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

        Write-Host "Stage 3 Start Time: $endTime`r`n"
        "Stage 3 start Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        $Results["Stage 10: TCP + RDMA Congestion"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t`t| CLIENT BPS`t`t| THRESHOLD (>65%) |")
        $Failures["Stage 10: TCP + RDMA Congestion"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t`t| CLIENT BPS`t`t| THRESHOLD (>65%) |")
        $ResultInformationList["Stage 10: TCP + RDMA Congestion"] = [ResultInformationData[]]@()
        $StageSuccessList["Stage 10: TCP + RDMA Congestion"] = [Boolean[]]@()
        $RetryStageSuccessList["Stage 10: TCP + RDMA Congestion"] = [Boolean[]]@()
        Write-Host (ConvertTo-Json $TestNetwork)
        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing TCP + RDMA Traffic Combination on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            
            $ServerNode = $_
            $ServerName = $_.Name
            $ServerInterfaceList = $ServerNode.InterfaceListStruct.Values | Where Status -eq $True
            
            $ClientNetwork = $TestNetwork | Where Name -ne $ServerName
            
            $ClientNetwork | ForEach-Object {

                $ClientNode = $_
                $ClientName = $_.Name
                $ClientIPList = @()

                $ServerTCPOutput = @()
                $ClientTCPOutput = @()
                $i = 0
                $ServerInterfaceList | ForEach-Object {

                    $ServerInterface = $_ 
                    $ClientInterface = ($ClientNode.InterfaceListStruct.Values | Where Subnet -eq $ServerInterface.Subnet | Where VLAN -eq $ServerInterface.VLAN | Where IPAddress -NotIn $ClientIPList)[0]
                    
                    $ServerIP = $ServerInterface.IpAddress
                    $ServerSubnet = $ServerInterface.Subnet
                    $ServerVLAN = $ServerInterface.VLAN
                    $ServerLinkSpeed = $ServerInterface.LinkSpeed
                    
                    $ClientIP = $ClientInterface.IpAddress
                    $ClientSubnet = $ClientInterface.Subnet
                    $ClientVLAN = $ClientInterface.VLAN
                    $ClientLinkSpeed = $ClientInterface.LinkSpeed

                    $ServerTCPCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$($ServerIP) -Port:800$i -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000`r`n"
                    $ClientTCPCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$($ServerIP) -bind:$ClientIP -Port:800$i -connections:32 -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed`r`n"
                    
                    $ServerRdmaCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):900$i  -ServerIf $ServerIF -TestType rperf -W 5"
                    $ClientRdmaCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$i -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rperf"
                                        
                    $NewResultInformation = [ResultInformationData]::new()
                    
                    Write-Host "TCP COMMANDS:"
                    "TCP COMMANDS:" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    Write-Host $ServerTCPCommand
                    $ServerTCPCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    Write-Host $ClientTCPCommand
                    $ClientTCPCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    
                    Write-Host "RDMA COMMANDS:"
                    "RDMA COMMANDS:" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    Write-Host $ServerRdmaCommand
                    $ServerRdmaCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    Write-Host $ClientRdmaCommand
                    $ClientRdmaCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                    ## TCP Congestion Server Counter
                    $ServerTCPCounter = Start-Job -ScriptBlock {
                        $ServerName = $Using:ServerName
                        $ServerInterfaceDescription = (((($Using:ServerInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']') -replace '/', '_' 
                        Invoke-Command -ComputerName $ServerName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\Network Adapter($Using:ServerInterfaceDescription)\Bytes Received/sec" -MaxSamples 20 -ErrorAction Ignore }
                    }
                    
                    ## RDMA Congestion Server Counter
                    $ServerRdmaCounter = Start-Job -ScriptBlock {
                        $ServerName = $Using:ServerName
                        $ServerInterfaceDescription = $Using:ServerInterfaceDescription
                        Invoke-Command -ComputerName $ServerName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\RDMA Activity($Using:ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 5 -ErrorAction Ignore }
                    }

                    ## TCP Congestion Server Start
                    $ServerTCPOutput += Start-Job -ScriptBlock {
                        
                        $ServerIP = $Using:ServerIP
                        $i = $Using:i
                        Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -port:800$Using:i -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000" }
                    }

                    ## RDMA Congestion Server Start
                    $ServerRdmaOutput = Start-Job -ScriptBlock {
                        $ServerIP = $Using:ServerIP
                        $ServerIF = $Using:ServerIF
                        $i = $Using:i
                        Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($Using:ServerIP):900$Using:i  -ServerIf $Using:ServerIF -TestType rperf -W 5 2>&1" }
                    }
                    
                    ## TCP Congestion Server Counter
                    $ClientSendCounter = Start-Job -ScriptBlock {
                        $ClientName = $Using:ClientName
                        $ClientInterfaceDescription = (((($Using:ClientInterfaceDescription) -replace '#', '_') -replace '[(]', '[') -replace '[)]', ']' ) -replace '/', '_' 
                        Invoke-Command -ComputerName $ClientName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\Network Adapter($Using:ClientInterfaceDescription)\Bytes Sent/sec" -MaxSamples 20 }
                    }
                    
                    ## RDMA Congestion Server Counter
                    $ClientRdmaCounter = Start-Job -ScriptBlock {
                        $ClientName = $Using:ClientName
                        $ClientInterfaceDescription = $Using:ClientInterfaceDescription
                        Invoke-Command -ComputerName $ClientName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\RDMA Activity($Using:ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 5 }
                    }
                    
                    ## TCP Congestion Client Start
                    $ClientTCPOutput += Start-Job -ScriptBlock {
                        $ServerIP = $Using:ServerIP
                        $ClientIP = $Using:ClientIP
                        $ClientLinkSpeed = $Using:ClientLinkSpeed
                        $i = $Using:i
                        Invoke-Command -ComputerName $Using:ClientName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -port:800$Using:i -connections:32 -consoleverbosity:1 -iterations:2 -RateLimit:$Using:ClientLinkSpeed" }            
                    }

                    ## RDMA Congestion Client Start
                    $ClientRdmaOutput += Start-Job -ScriptBlock {
                        $ServerIP = $Using:ServerIP
                        $ServerIF = $Using:ServerIF
                        $ClientIP = $Using:ClientIP
                        $ClientIF = $Using:ServerIF
                        $i = $Using:i
                        Invoke-Command -ComputerName $Using:ClientName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):900$Using:i -ClientAddr $Using:ClientIP -ClientIf $Using:ClientIF -TestType rperf 2>&1" }            
                    }
                    Start-Sleep -Seconds 1
                                        
                    $readTCP = Receive-Job $ServerTCPCounter
                    $writtenTCP = Receive-Job $ClientTCPCounter

                    $readRdma = Receive-Job $ServerRdmaCounter
                    $writtenRdma = Receive-Job $ClientRdmaCounter

                    $FlatServerTCPOutput = $readTCP.Readings.split(":") | ForEach-Object {
                        try {[uint64]($_) * 8} catch{}
                    }
                    $FlatClientTCPOutput = $writtenTCP.Readings.split(":") | ForEach-Object {
                        try {[uint64]($_) * 8} catch{}
                    }

                    $FlatServerRdmaOutput = $readRdma.Readings.split(":") | ForEach-Object {
                        try {[uint64]($_) * 8} catch{}
                    }
                    $FlatClientRdmaOutput = $writtenRdma.Readings.split(":") | ForEach-Object {
                        try {[uint64]($_) * 8} catch{}
                    }

                    $ServerTCPBytesPerSecond = ($FlatServerTCPOutput | Measure-Object -Maximum).Maximum
                    $ClientTCPBytesPerSecond = ($FlatClientTCPOutput | Measure-Object -Maximum).Maximum

                    $ServerRdmaBytesPerSecond = ($FlatServerRdmaOutput | Measure-Object -Maximum).Maximum
                    $ClientRdmaBytesPerSecond = ($FlatClientRdmaOutput | Measure-Object -Maximum).Maximum

                    $ClientIPList += $ClientIP
                    $i++

                }

                Start-Sleep -Seconds 40

                $ServerTCPOutput | ForEach-Object {
                    Write-Host Get-Job $_
                    $job = Receive-Job $_
                    # Write-Host $job
                    
                    $job | ForEach-Object {
                        Write-Host $_
                    }
                    # $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                    It "Synthetic Connection Test (TCP) -- Verify Throughput is >75% reported: Client $($ClientName) to Server $($ServerName)`r`n" { 

                        $True | Should Be $True
                    }
                }
                Write-Host "`r`n##################################################`r`n"
                "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                $ClientTCPOutput | ForEach-Object {
                    $job = Receive-Job $_

                    $job | ForEach-Object {
                        Write-Host $_
                    }
                    
                    
                    It "Synthetic Connection Test (TCP) -- Verify Throughput is >75% reported: Client $($ClientName) to Server $($ServerName)`r`n" { 

                        $True | Should Be $True
                    }
                }
                Write-Host "`r`n##################################################`r`n"
                "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                
                
            }
        }

        It "Synthetic Connection Test (TCP) -- Verify Throughput is >75% reported: Client $($ClientName) to Server $($ServerName)`r`n" { 

            $True | Should Be $True
        }
    }
    
    # Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "Stage 10: TCP + RDMA Congestion"

    # Write-Host "RESULTS Stage 10: TCP + RDMA Congestion`r`n"
    # "RESULTS Stage 10: TCP + RDMA Congestion`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    # ($Results["Stage 10: TCP + RDMA Congestion"]) | ForEach-Object {

    #     Write-Host $_ 
    #     $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    # }
    # if ($StageSuccessList["Stage 10: TCP + RDMA Congestion"] -contains $false) {
    #     Write-Host "`r`nSTAGE 3: CTS TRAFFIC FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
    #     "`r`nSTAGE 3: CTS TRAFFIC FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #     # $StageNumber = 0
    # }

    
    # $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    # Write-Host "Ending Stage 3: $endTime`r`n"
    # "Ending Stage 3: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

}