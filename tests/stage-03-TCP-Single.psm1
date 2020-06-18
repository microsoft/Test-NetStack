function stage-03-TCP-Single {

    Context "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        
        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

        Write-Host "Stage 3 Start Time: $endTime`r`n"
        "Stage 3 start Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        $Results["STAGE 3: TCP CTS Traffic"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t`t| CLIENT BPS`t`t| THRESHOLD (>65%) |")
        $Failures["STAGE 3: TCP CTS Traffic"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t`t| CLIENT BPS`t`t| THRESHOLD (>65%) |")
        $ResultInformationList["STAGE 3: TCP CTS Traffic"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 3: TCP CTS Traffic"] = [Boolean[]]@()
        $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing CTS Traffic (TCP) Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            $ServerNetworkNode = $_
            $ServerName = $_.Name
            $ServerCimSession = New-CimSession -ComputerName $ServerName -Credential $Credentials
            $ServerNetworkNode.InterfaceListStruct.Values | ForEach-Object {
                
                $ServerStatus = $_.Status

                if ($ServerStatus) {
                    Write-Host "VERBOSE: Testing CTS Traffic (TCP) Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                    "VERBOSE: Testing CTS Traffic (TCP) Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                    $ServerIP = $_.IpAddress
                    $ServerSubnet = $_.Subnet
                    $ServerVLAN = $_.VLAN
                    $ServerLinkSpeed = $_.LinkSpeed

                    $TestNetwork | ForEach-Object {

                        $ClientNetworkNode = $_
                        $ClientName = $_.Name
                        $ClientCimSession = New-CimSession -ComputerName $ClientName -Credential $Credentials
                        $ClientNetworkNode.InterfaceListStruct.Values | ForEach-Object {

                            $ClientIP = $_.IpAddress
                            $ClientSubnet = $_.Subnet
                            $ClientVLAN = $_.VLAN
                            $ClientLinkSpeed = $_.LinkSpeed
                            $ClientStatus = $_.Status

                            if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And ($ClientStatus)) {

                                $Success = $False
                                $Retries = 3
                                
                                $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                                Write-Host "Time: $endTime`r`n"
                                "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                while((-not $Success) -and ($Retries -gt 0)) {
                                    
                                    It "Synthetic Connection Test (TCP) -- Verify Throughput is >75% reported: Client $($ClientIP) to Server $($ServerIP)`r`n" {

                                        $Success = $False

                                        $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$($ServerIP) -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000"
                                        $ClientCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$($ServerIP) -bind:$ClientIP -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed"
                                        $NewResultInformation = [ResultInformationData]::new()
                                        
                                        Write-Host $ServerCommand
                                        $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        Write-Host $ClientCommand
                                        $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        
                                        $ServerOutput = Start-Job -ScriptBlock {
                                            $ServerIP = $Using:ServerIP
                                            $ServerLinkSpeed = $Using:ServerLinkSpeed
                                            Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000 2>&1" }
                                        }

                                        $ClientOutput = Invoke-Command -ComputerName $ClientName -Credential $Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -connections:32 -consoleverbosity:1 -iterations:2 2>&1" }
                                    
                                        Start-Sleep 1

                                        $ServerOutput = Receive-Job $ServerOutput

                                        $FlatServerOutput = @()
                                        $FlatClientOutput = @()
                                        $ServerOutput[20..($ServerOutput.Count-5)] | ForEach-Object {If ($_ -ne "") {$FlatServerOutput += ($_ -split '\D+' | Sort-Object -Unique)}}
                                        $ClientOutput[20..($ClientOutput.Count-5)] | ForEach-Object {If ($_ -ne "") {$FlatClientOutput += ($_ -split '\D+' | Sort-Object -Unique)}}
                                        $FlatServerOutput = ForEach($num in $FlatServerOutput) {if ($num -ne "") {[Long]::Parse($num)}} 
                                        $FlatClientOutput = ForEach($num in $FlatClientOutput) {if ($num -ne "") {[Long]::Parse($num)}}

                                        $ServerRecvBps = ($FlatServerOutput | Measure-Object -Maximum).Maximum * 8
                                        $ClientRecvBps = ($FlatClientOutput | Measure-Object -Maximum).Maximum * 8
                                        $Success = ($ServerRecvBps -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .65) -and ($ClientRecvBps -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .65)
                                        Write-Host "Server Bps $ServerRecvBps and Client Bps $ClientRecvBps`r`n"
                                        "Server Bps $ServerRecvBps and Client Bps $ClientRecvBps`r`n"| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                        Write-Host "TCP CTS Traffic Server Output: "
                                        # Write-Host ($ServerOutput -match "SuccessfulConnections")
                                        $ServerOutput[($ServerOutput.Count-3)..$ServerOutput.Count] | ForEach-Object {Write-Host $_}
                                        Write-Host "`r`n"
                                        "TCP CTS Traffic Server Output: "| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        ($ServerOutput -match "SuccessfulConnections") | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $ServerOutput[($ServerOutput.Count-3)..$ServerOutput.Count] | ForEach-Object {$_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8}
                                        "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                        Write-Host "TCP CTS Traffic Client Output: "
                                        Write-Host ($ClientOutput -match "SuccessfulConnections")
                                        $ClientOutput[($ClientOutput.Count-3)..$ClientOutput.Count] | ForEach-Object {Write-Host $_}
                                        Write-Host "`r`n"
                                        "TCP CTS Traffic Client Output: "| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        ($ClientOutput -match "SuccessfulConnections") | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $ClientOutput[($ClientOutput.Count-3)..$ClientOutput.Count] | ForEach-Object {$_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8}
                                        "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                        if (($Success) -or ($Retries -eq 1)) {
                                            $Results["STAGE 3: TCP CTS Traffic"] += "|($ServerName)`t`t| ($ServerIP)`t| $ServerRecvBps bps `t| ($ClientName)`t`t| ($ClientIP)`t| $ClientRecvBps bps`t| $SUCCESS |"
                                        }
                                        if ((-not $Success) -and ($Retries -eq 1)) {
                                            $Failures["STAGE 3: TCP CTS Traffic"] += "|($ServerName)`t`t| ($ServerIP)`t| $ServerRecvBps bps `t| ($ClientName)`t`t| ($ClientIP)`t| $ClientRecvBps bps`t| $SUCCESS |"
                                        }

                                        if (($Success) -or ($retries -eq 1)) {

                                            $NewResultInformation.SourceMachine = $ClientName
                                            $NewResultInformation.TargetMachine = $ServerName
                                            $NewResultInformation.SourceIp = $ClientIP
                                            $NewResultInformation.TargetIp = $ServerIP
                                            $NewResultInformation.Success = $Success
                                            $NewResultInformation.ReportedSendBps = $ClientLinkSpeed
                                            $NewResultInformation.ReportedReceiveBps = $ServerLinkSpeed
                                            $NewResultInformation.ActualSendBps = $ClientRecvBps
                                            $NewResultInformation.ActualReceiveBps = $ServerRecvBps
                                            $NewResultInformation.ReproCommand = "`r`n`t`tServer: $ServerCommand`r`n`t`tClient: $ClientCommand"
                                            $ResultInformationList["STAGE 3: TCP CTS Traffic"] += $NewResultInformation
                                            $StageSuccessList["STAGE 3: TCP CTS Traffic"] += $Success
                                        }
                                        $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"] += $Success

                                        $Success | Should Be $True
                                    }

                                    $Retries--
                                    $SuccessCount = $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"].Count
                                    $Success = $RetryStageSuccessList["STAGE 3: TCP CTS Traffic"][$SuccessCount - 1]
                                    
                                }
                                $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                                Write-Host "Time: $endTime`r`n"
                                "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                Write-Host "`r`n####################################`r`n"
                                "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                            } 
                        }
                    }
                } 
            }
        }
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