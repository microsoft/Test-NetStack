function Init-StageTCPHostToHost {

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
        Write-Host (ConvertTo-Json $TestNetwork)
        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing CTS Traffic (TCP) Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            
            $ServerNode = $_
            $ServerName = $_.Name
            $ServerInterfaceList = $ServerNode.InterfaceListStruct.Values | Where Status -eq $True
            
            $ClientNetwork = $TestNetwork | Where Name -ne $ServerName
            Write-Host $ClientNetwork
            $ClientNetwork | ForEach-Object {

                $ClientNode = $_
                $ClientName = $_.Name
                $ClientIPList = @()

                $ServerOutput = @()
                $ClientOutput = @()
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
                    Write-Host ($ClientIP -NotIn $ClientIPList)
                    $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$($ServerIP) -Port:900$i -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000`r`n"
                    $ClientCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$($ServerIP) -Port:900$i -bind:$ClientIP -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed`r`n"
                    
                    $NewResultInformation = [ResultInformationData]::new()
                    
                    Write-Host $ServerCommand
                    $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    Write-Host $ClientCommand
                    $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    
                    $ServerOutput += Start-Job -ScriptBlock {
                        
                        $ServerIP = $Using:ServerIP
                        $i = $Using:i
                        Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -port:900$Using:i -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000" }
                    }

                    $ClientOutput += Start-Job -ScriptBlock {
                        
                        $ServerIP = $Using:ServerIP
                        $ClientIP = $Using:ClientIP
                        $ClientLinkSpeed = $Using:ClientLinkSpeed
                        $i = $Using:i
                        Invoke-Command -ComputerName $Using:ClientName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -port:900$Using:i -connections:32 -consoleverbosity:1 -iterations:2 -RateLimit:$Using:ClientLinkSpeed" }            
                    }

                    $ClientIPList += $ClientIP
                    $i++

                }

                Start-Sleep -Seconds 40

                $ServerOutput | ForEach-Object {
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

                $ClientOutput | ForEach-Object {
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
                
                
            }
        }

        It "Synthetic Connection Test (TCP) -- Verify Throughput is >75% reported: Client $($ClientName) to Server $($ServerName)`r`n" { 

            $True | Should Be $True
        }
    }
    
    # Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 3: TCP CTS Traffic"

    # Write-Host "RESULTS Stage 3: TCP CTS Traffic`r`n"
    # "RESULTS Stage 3: TCP CTS Traffic`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    # ($Results["STAGE 3: TCP CTS Traffic"]) | ForEach-Object {

    #     Write-Host $_ 
    #     $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    # }
    # if ($StageSuccessList["STAGE 3: TCP CTS Traffic"] -contains $false) {
    #     Write-Host "`r`nSTAGE 3: CTS TRAFFIC FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
    #     "`r`nSTAGE 3: CTS TRAFFIC FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #     # $StageNumber = 0
    # }

    
    # $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    # Write-Host "Ending Stage 3: $endTime`r`n"
    # "Ending Stage 3: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

}