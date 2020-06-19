function Init-StageNDKPerfMulti {
    
    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [PSCredential] $Credentials = $null
    )

    Context "VERBOSE: Testing Connectivity Stage 6: NDK Perf (N : 1)`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 6: NDK Perf (N : 1)`r`n"
        Write-Host "####################################"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 6: NDK Perf (N : 1)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
        Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

        Write-Host "Time: $endTime`r`n"
        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        $Results["STAGE 6: NDK Perf (N : 1)"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
        $ResultString = ""
        $Failures["STAGE 6: NDK Perf (N : 1)"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
        $ResultInformationList["STAGE 6: NDK Perf (N : 1)"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            $ServerNetworkNode = $_
            $ServerName = $_.Name

            $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where Status | where RdmaEnabled

            $ServerRdmaInterfaceList | ForEach-Object {
                
                # $ServerStatus = $_.Status
                # if ($ServerStatus) {

                # }
                Write-Host "VERBOSE: Testing NDK Perf N:1 Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                "VERBOSE: Testing NDK Perf N:1 Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                $ServerIP = $_.IpAddress
                $ServerIF = $_.IfIndex
                $ServerSubnet = $_.Subnet
                $ServerVLAN = $_.VLAN
                $ServerLinkSpeed = $_.LinkSpeed
                $ServerInterfaceDescription = $_.Description
                
                $ResultString = ""
                
                $ClientNetwork = $TestNetwork | where Name -ne $ServerName

                for ($i = 1; $i -lt $MachineCluster.Count - 1; $i++) {
                    
                    It "(N:1) RDMA Congestion Test (Client $ClientIP to Server $ServerIP)" {

                        $RandomClientNodes = If ($ClientNetwork.Count -eq 1) { $ClientNetwork[0] } Else { $ClientNetwork[0..$i] }
                        # $RandomClientNodes = $RandomClientNodes | where Status
                        $j = 0

                        $ServerOutput = @()
                        $ClientOutput = @()
                        $ServerCounter = @()
                        $ClientCounter = @()
                        $ServerSuccess = $True
                        $MultiClientSuccess = $True
                        $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):900$j  -ServerIf $ServerIF -TestType rping -W 5`r`n"
                        $NewResultInformation = [ResultInformationData]::new()
                        $NewResultInformation.ReproCommand = "`r`n`t`t$ServerCommand"

                        $RandomClientNodes | ForEach-Object {
                            Start-Sleep -Seconds 1
                        
                            $ClientName = $_.Name
                            $ClientInterface = $_.InterfaceListStruct.Values | where Name -In $_.RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
                            $ClientIP = $ClientInterface.IpAddress
                            $ClientIF = $ClientInterface.IfIndex
                            $ClientInterfaceDescription = $ClientInterface.Description  

                            
                            $ClientCommand = "Client $($_.Name) CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
                            Write-Host $ServerCommand
                            $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                            Write-Host $ClientCommand
                            $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                            $ServerCounter += Start-Job -ScriptBlock {
                                $ServerName = $Using:ServerName
                                $ServerInterfaceDescription = $Using:ServerInterfaceDescription
                                Get-Counter -ComputerName $ServerName -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 5 #-ErrorAction Ignore
                            }

                            $ServerOutput += Start-Job -ScriptBlock {
                                $ServerIP = $Using:ServerIP
                                $ServerIF = $Using:ServerIF
                                $j = $Using:j
                                Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -S -ServerAddr $($Using:ServerIP):900$Using:j  -ServerIf $Using:ServerIF -TestType rping -W 5 2>&1" }
                            }

                            $ClientCounter += Start-Job -ScriptBlock {
                                $ClientName = $Using:ClientName
                                $ClientInterfaceDescription = $Using:ClientInterfaceDescription
                                Get-Counter -ComputerName $ClientName -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 5
                            }

                            $ClientOutput += Start-Job -ScriptBlock {
                                $ServerIP = $Using:ServerIP
                                $ClientIP = $Using:ClientIP
                                $ClientIF = $Using:ClientIF
                                $j = $Using:j
                                Invoke-Command -Computername $Using:ClientName -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):900$Using:j -ClientAddr $($Using:ClientIP) -ClientIf $($Using:ClientIF) -TestType rping 2>&1" }
                            }
                            Start-Sleep -Seconds 1
                            $j++
                        }
                        
                        Start-Sleep -Seconds 10
                        Write-Host "##################################################`r`n"
                        "##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        $ServerBytesPerSecond = 0
                        $k = 0
                        $ServerCounter | ForEach-Object {
                            
                            $read = Receive-Job $_

                            $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
                                try {[uint64]($_) * 8} catch{}
                            }
                            $ClientInterface = $RandomClientNodes[$k].InterfaceListStruct.Values | where Name -In $RandomClientNodes[$k].RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
                            $ClientLinkSpeed = $ClientInterface.LinkSpeed
                            $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
                            $ServerSuccess = $ServerSuccess -and ($ServerBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)
                            
                            $k++
                        }
                        $ResultString += "| ($ServerName)`t`t| ($ServerIP)`t| $ServerBytesPerSecond `t`t|" 

                        $ServerOutput | ForEach-Object {
                            $job = Receive-Job $_
                            Write-Host $job
                            $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        }
                        Write-Host "`r`n##################################################`r`n"
                        "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                        $k = 0
                        $ClientCounter | ForEach-Object {
                            
                            $written = Receive-Job $_
                            $FlatClientOutput = $written.Readings.split(":") | ForEach-Object {
                                try {[uint64]($_) * 8} catch{}
                            }
                            $ClientName = $RandomClientNodes[$k].Name
                            $ClientInterface = $RandomClientNodes[$k].InterfaceListStruct.Values | where Name -In $RandomClientNodes[$k].RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
                            $ClientIP = $ClientInterface.IpAddress
                            $ClientIF = $ClientInterface.IfIndex
                            $ClientLinkSpeed = $ClientInterface.LinkSpeed
                            $ClientBytesPerSecond = ($FlatClientOutput | Measure-Object -Maximum).Maximum
                            $IndividualClientSuccess = ($ClientBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)
                            $MultiClientSuccess = $MultiClientSuccess -and $IndividualClientSuccess
                            $NewResultInformation.SourceMachineNameList += $ClientName
                            $NewResultInformation.SourceMachineIPList += $ClientIP
                            $NewResultInformation.SourceMachineActualBpsList += $ClientBytesPerSecond
                            $NewResultInformation.SourceMachineSuccessList += $IndividualClientSuccess
                            $NewResultInformation.ReproCommand += "`r`n`t`tClient $($_.ClientName) CMD:  C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
                            
                            $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] = [Boolean[]]@()
                            
                            $ResultString +=  "`r|`t`t`t`t`t`t`t`t`t| $($ClientName)`t`t| $($ClientIP)`t|"
                            $ResultString += " $ClientBytesPerSecond bps`t| $IndividualClientSuccess`t|"
                            $k++
                        }

                        $k = 0
                        $ClientOutput | ForEach-Object {
                            $job = Receive-Job $_
                            Write-Host $job
                            $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        }
                        Write-Host "`r`n##################################################`r`n"
                        "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                        $Success = $ServerSuccess -and $MultiClientSuccess
                        
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

                        $Success | Should Be $True    
                    }

                }

            }

        }
    }

    Assert-ServerMultiClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 6: NDK Perf (N : 1)"

    Write-Host "RESULTS Stage 6: NDK Perf (N : 1)`r`n"
    "RESULTS Stage 6: NDK Perf (N : 1)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    $ResultString += "| ($ServerName)`t`t| ($ServerIP)`t|"
    ($Results["STAGE 6: NDK Perf (N : 1)"]) | ForEach-Object {

        Write-Host $_ 
        $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    }
    if ($StageSuccessList["STAGE 6: NDK Perf (N : 1)"] -contains $false) {
        Write-Host "`r`nSTAGE 6: NDK PERF (N:1) FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
        "`r`nSTAGE 6: NDK PERF (N:1) FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'CTest-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        $StageNumber = 0
    }
}