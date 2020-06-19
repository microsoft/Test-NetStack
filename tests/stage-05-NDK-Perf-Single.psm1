function Init-StageNDKPerfSingle {

    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [HashTable] $RetryStageSuccessList,
        [PSCredential] $Credentials = $null
    )

    Context "VERBOSE: Testing Connectivity Stage 5: NDK Perf`r`n" {
    
        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 5: NDK Perf`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 5: NDK Perf`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
        Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

        Write-Host "Time: $endTime`r`n"
        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        $Results["STAGE 5: NDK Perf"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE| CLIENT NIC`t`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
        $Failures["STAGE 5: NDK Perf"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE| CLIENT NIC`t`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
        $ResultInformationList["STAGE 5: NDK Perf"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 5: NDK Perf"] = [Boolean[]]@()
        $RetryStageSuccessList["STAGE 5: NDK Perf"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {

            Write-Host "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)"
            "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

            $ServerNetworkNode = $_
            $ServerName = $_.Name
            $ServerCimSession = New-CimSession -ComputerName $ServerName -Credential $Credentials
            $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled

            $ServerRdmaInterfaceList | ForEach-Object {

                $ServerStatus = $_.Status

                if($ServerStatus) {
                    
                    Write-Host "VERBOSE: Testing NDK Perf Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                    "VERBOSE: Testing NDK Perf Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
                    $ServerIP = $_.IpAddress
                    $ServerIF = $_.IfIndex
                    $ServerSubnet = $_.Subnet
                    $ServerVLAN = $_.VLAN
                    $ServerLinkSpeed = $_.LinkSpeed
                    $ServerInterfaceDescription = $_.Description

                    $TestNetwork | ForEach-Object {
    
                        $ClientNetworkNode = $_
                        $ClientName = $_.Name
                        $ClientCimSession = New-CimSession -ComputerName $ClientName -Credential $Credentials
                        $ClientRdmaInterfaceList = $ClientNetworkNode.InterfaceListStruct.Values | where Name -In $ClientNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled
    
                        $ClientRdmaInterfaceList | ForEach-Object {
    
                            $ClientIP = $_.IpAddress
                            $ClientIF = $_.IfIndex
                            $ClientSubnet = $_.Subnet
                            $ClientVLAN = $_.VLAN
                            $ClientStatus = $_.Status
                            $ClientLinkSpeed = $_.LinkSpeed
                            $ClientInterfaceDescription = $_.Description
    
                            if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And $ClientStatus) {
    
                                Write-Host "`r`n##################################################`r`n"
                                "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                                Write-Host "Time: $endTime`r`n"
                                "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                $Success = $False
                                $Retries = 3

                                while ((-not $Success) -and ($Retries -gt 0)) {

                                    It "1:1 RDMA Congestion Test -- Stress RDMA Transaction Between Two Singular NICs: Client $ClientIP to Server $ServerIP" {
                                        
                                        $Success = $False
                                        $ServerSuccess = $False
                                        $ClientSuccess = $False
                                        Start-Sleep -Seconds 1
                                        
                                        $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rperf -W 5"
                                        $ClientCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rperf"
                                        Write-Host $ServerCommand
                                        $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        Write-Host $ClientCommand
                                        $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $NewResultInformation = [ResultInformationData]::new()

                                        $ServerCounter = Start-Job -ScriptBlock {
                                            $ServerName = $Using:ServerName
                                            $ServerInterfaceDescription = $Using:ServerInterfaceDescription
                                            Invoke-Command -ComputerName $ServerName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\RDMA Activity($Using:ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 5 -ErrorAction Ignore }
                                        }

                                        Start-Sleep -Seconds 1 

                                        $ServerOutput = Start-Job -ScriptBlock {
                                            $ServerIP = $Using:ServerIP
                                            $ServerIF = $Using:ServerIF
                                            Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($Using:ServerIP):9000  -ServerIf $Using:ServerIF -TestType rperf -W 5 2>&1" }
                                        }

                                        Start-Sleep -Seconds 1
                                        
                                        $ClientCounter = Start-Job -ScriptBlock {
                                            $ClientName = $Using:ClientName
                                            $ClientInterfaceDescription = $Using:ClientInterfaceDescription
                                            Invoke-Command -ComputerName $ClientName -Credential $Using:Credentials -ScriptBlock { Get-Counter -Counter "\RDMA Activity($Using:ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 5 }
                                        }
                                        
                                        $ClientOutput = Invoke-Command -ComputerName $ClientName -Credential $Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):9000 -ClientAddr $Using:ClientIP -ClientIf $Using:ClientIF -TestType rperf 2>&1" }
                                        
                                        $read = Receive-Job $ServerCounter
                                        $written = Receive-Job $ClientCounter

                                        $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
                                            try {[uint64]($_) * 8} catch{}
                                        }
                                        $FlatClientOutput = $written.Readings.split(":") | ForEach-Object {
                                            try {[uint64]($_) * 8} catch{}
                                        }
                                        $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
                                        $ClientBytesPerSecond = ($FlatClientOutput | Measure-Object -Maximum).Maximum

                                        Start-Sleep -Seconds 5
                                        
                                        $ServerOutput = Receive-Job $ServerOutput
                                        
                                        Write-Host "NDK Perf Server Output: "
                                        $ServerOutput | ForEach-Object {$ServerSuccess = $_ -match 'completes';Write-Host $_}
                                        Write-Host "`r`n"
                                        "NDK Perf Server Output: "| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $ServerOutput | ForEach-Object {$_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8}
                                        "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
                                        Write-Host "NDK Perf Client Output: "
                                        $ClientOutput[0..($ClientOutput.Count-4)] | ForEach-Object {$ClientSuccess = $_ -match 'completes';Write-Host $_}
                                        "NDK Perf Client Output: "| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $ClientOutput | ForEach-Object {$_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8}
                                        Write-Host "`r`n##################################################`r`n"
                                        "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        
                                        $Success = ($ServerBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8) -and ($ClientBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)


                                        if (($Success) -or ($Retries -eq 1)) {
                                            $Results["STAGE 5: NDK Perf"] += "|($ServerName)`t`t| ($ServerIP)`t| $ServerBytesPerSecond bps `t| ($ClientName)`t| ($ClientIP)`t| $ClientBytesPerSecond bps`t| $SUCCESS |"
                                        }
                                        if ((-not $Success) -and ($Retries -eq 1)) {
                                            $Failures["STAGE 5: NDK Perf"] += "|($ServerName)`t`t| ($ServerIP)`t| $ServerBytesPerSecond bps `t| ($ClientName)`t| ($ClientIP)`t| $ClientBytesPerSecond bps`t| $SUCCESS |"
                                        }

                                        if (($Success) -or ($retries -eq 1)) {

                                            $NewResultInformation.SourceMachine = $ClientName
                                            $NewResultInformation.TargetMachine = $ServerName
                                            $NewResultInformation.SourceIp = $ClientIP
                                            $NewResultInformation.TargetIp = $ServerIP
                                            $NewResultInformation.Success = $Success
                                            $NewResultInformation.ReproCommand = "`r`n`t`tServer: $ServerCommand`r`n`t`tClient: $ClientCommand"
                                            $ResultInformationList["STAGE 5: NDK Perf"] += $NewResultInformation
                                            $StageSuccessList["STAGE 5: NDK Perf"] += $Success

                                        }
                                        
                                        $RetryStageSuccessList["STAGE 5: NDK Perf"] += $Success

                                        $Success | Should Be $True
                                    }

                                    $Retries--
                                    $SuccessCount = $RetryStageSuccessList["STAGE 5: NDK Perf"].Count
                                    $Success = $RetryStageSuccessList["STAGE 5: NDK Perf"][$SuccessCount - 1]

                                    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                                    Write-Host "Time: $endTime`r`n"
                                    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                    
                                }
                            } 
                        }
                    }
                }
            }
        }
    }
    
    Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 5: NDK Perf"

    Write-Host "RESULTS Stage 5: NDK Perf`r`n"
    "RESULTS Stage 5: NDK Perf`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    ($Results["STAGE 5: NDK Perf"]) | ForEach-Object {

        Write-Host $_ 
        $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    }
    if ($StageSuccessList["STAGE 5: NDK Perf"] -contains $false) {
        Write-Host "`r`nSTAGE 5: NDK PERF (1:1) FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
        "`r`nSTAGE 5: NDK PERF (1:1) FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        # $StageNumber = 0
    }

    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Time: $endTime`r`n"
    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
}