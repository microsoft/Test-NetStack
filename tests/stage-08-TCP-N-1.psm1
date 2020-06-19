function Init-StageTCPMulti {

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

                    $ResultString = ""
                    $ClientNetwork = $TestNetwork | where Name -ne $ServerName

                    for($i = 1; $i -lt $MachineCluster.Count - 1; $i++) {

                        It "(N:1) TCP Congestion Test (Client $ClientIP to Server $ServerIP)" {
                            
                            $RandomClientNodes = If ($ClientNetwork.Count -eq 1) { $ClientNetwork[0] } Else { $ClientNetwork[0..$i] }
                            # $RandomClientNodes = $RandomClientNodes | where Status
                            $j = 0
                            $ServerOutput = @()
                            $ClientOutput = @()
                            $ServerCounter = @()
                            $ClientCounter = @()
                            $ServerSuccess = $True
                            $MultiClientSuccess = $True
                            $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -port:900$j -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000 2>&1`r`n"
                            $NewResultInformation = [ResultInformationData]::new()
                            $NewResultInformation.ReproCommand = "`r`n`t`t$ServerCommand"

                            $RandomClientNodes | ForEach-Object {
                                
                                Start-Sleep -Seconds 1
                            
                                $ClientName = $_.Name
                                $ClientInterface = ($_.InterfaceListStruct.Values | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN)[0]
                                $ClientIP = $ClientInterface.IpAddress
                                $ClientIF = $ClientInterface.IfIndex
                                $ClientInterfaceDescription = $ClientInterface.Description  
                                
                                $ClientCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -port:900$j -connections:32 -consoleverbosity:1 -iterations:2 2>&1`r`n"
                                Write-Host $ServerCommand
                                $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                Write-Host $ClientCommand
                                $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                $ServerOutput += Start-Job -ScriptBlock {
                                    $ServerIP = $Using:ServerIP
                                    $j = $Using:j
                                    Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -port:900$Using:j -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000 2>&1" }
                                }

                                $ClientOutput += Start-Job -ScriptBlock {
                                    $ServerIP = $Using:ServerIP
                                    $ClientIP = $Using:ClientIP
                                    $j = $Using:j
                                    Invoke-Command -Computername $Using:ClientName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -port:900$Using:j -connections:32 -consoleverbosity:1 -iterations:2 2>&1" }
                                }

                                Start-Sleep -seconds 1
                                $j++
                            }
                            Start-Sleep -Seconds 10
                            $ServerOutput | ForEach-Object {
                                $job = Receive-Job $_
                                Write-Host $job
                                $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                            }

                            $k = 0
                            $ClientOutput | ForEach-Object {
                                $job = Receive-Job $_
                                Write-Host $job
                                $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                            }

                            
                            Write-Host "##################################################`r`n"
                            "##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                            
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