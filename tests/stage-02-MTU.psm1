function Init-StageMTU {

    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [PSCredential] $Credentials = $null
    )

    Context "VERBOSE: Testing Connectivity Stage 2: PING -L -F`r`n" {
            
        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 2: PING -L -F`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 2: PING -L -F`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
        Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

        Write-Host "Time: $endTime`r`n"
        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
        $Results["STAGE 2: PING -L -F"] = @("| SOURCE MACHINE`t| SOURCE NIC`t`t| TARGET MACHINE`t|TARGET NIC`t`t| REPORTED MTU`t| ACTUAL MTU | SUCCESS`t|")
        $Failures["STAGE 2: PING -L -F"] = @("| SOURCE MACHINE`t| SOURCE NIC`t`t| TARGET MACHINE`t|TARGET NIC`t`t| REPORTED MTU`t| ACTUAL MTU | SUCCESS`t|")
        $ResultInformationList["STAGE 2: PING -L -F"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 2: PING -L -F"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing Ping -L -F Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

            $hostName = $_.Name
            $HostCimSession = New-CimSession -ComputerName $hostName -Credential $Credentials
            $ValidInterfaceList = $_.InterfaceListStruct.Values | where IPAddress -ne "" 

            $ValidInterfaceList | ForEach-Object {
                
                $SourceStatus = $_.Status

                if ($SourceStatus) {

                    Write-Host "VERBOSE: Testing Ping -L -F Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                    "VERBOSE: Testing Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    
                    $TestInterface = $_

                    $InterfaceName = $TestInterface.Name

                    $InterfaceIfIndex = $TestInterface.IfIndex

                    $SubNetTable = $_.SubNetMembers

                    $SourceIp = $SubNetTable.Keys[0]

                    $PeerNetList = $SubNetTable[$SourceIp] | where $_.IpAddress -notlike $SourceIp 
                    
                    $PeerNetList | ForEach-Object {
                        
                        $NewResultInformation = [ResultInformationData]::new()
                        $TargetMachine = $_.MachineName
                        $TargetIP = $_.IpAddress

                        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                        Write-Host "Time: $endTime`r`n"
                        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        
                        if ($SourceIp -NotLike $TargetIp) {
                            
                            It "MTU Connectivity -- Verify Connectivity and Discover MTU: Between Target $($TargetIP) and Source $($SourceIP)" {
                                
                                $PacketSize = 0
                                $ReportedMTU
                                try {
                                    $PacketSize = [Int](Get-NetAdapterAdvancedProperty -CimSession $HostCimSession | where Name -eq $InterfaceName | where DisplayName -eq "Jumbo Packet").RegistryValue[0]
                                } catch {
                                    $PacketSize = [Int](Get-NetIPInterface -CimSession $HostCimSession | where ifIndex -eq $InterfaceIfIndex | where AddressFamily -eq "IPv4").nlMtu
                                    $ReportedMTU = $PacketSize
                                }

                                if ($PacketSize -eq 1514 -or $PacketSize -eq 9014) {
                                    $PacketSize -= 42
                                } elseif ($PacketSize -eq 1500 -or $PacketSize -eq 9000) {
                                    $PacketSize -= 28
                                }
                                $ReportedMTU = $PacketSize

                                $Success = $False
                                $Failure = $False

                                if ($PacketSize -eq 0) {

                                    $PacketSize = 1000
                                    $Success = $True

                                    while($Success) {
                                    
                                        Write-Host "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f -n 1`r`n"
                                        "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f -n 1`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                        $Output = Invoke-Command -ComputerName $hostName -Credential $Credentials -ScriptBlock { cmd /c "ping $Using:TargetIP -S $Using:SourceIP -l $Using:PacketSize -f -n 1" } | Out-String
                                        $Success = ("$Output" -match "Reply from $TargetIP") -and ("$Output" -match "(0% loss)") # -and (("$Output" -notmatch "General Failure") -or ("$Output" -notmatch "Destination host unreachable"))
                                        $Failure = ("$Output" -match "General Failure") -or ("$Output" -match "Destination host unreachable")
                                        $Success = $Success -and -not $Failure
                                        Write-Host "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}) FOR MTU: $PacketSize`r`n"
                                        "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}) FOR MTU: $PacketSize`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        
                                        if ($Success) {
                                            $PacketSize *= 2
                                        } 
                                        if ($Failure) {
                                            Write-Host "PING STATUS: General FAILURE - Host May Be Unreachable`r`n"
                                            "PING STATUS: General FAILURE - Host May Be Unreachable`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                            $PacketSize = 0
                                        } else {
                                            Write-Host "Upper Bound of $PacketSize found. Working to find specific value.`r`n"
                                            "Upper Bound of $PacketSize found. Working to find specific value.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        }
                                    }
                                }

                                while((-not $Success) -and (-not $Failure)) {

                                    Write-Host "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f -n 1`r`n"
                                    "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f -n 1`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                    $Output = Invoke-Command -ComputerName $hostName -Credential $Credentials -ScriptBlock { cmd /c "ping $Using:TargetIP -S $Using:SourceIP -l $Using:PacketSize -f -n 1" }
                                    $Success = ("$Output" -match "Reply from $TargetIP") -and ("$Output" -match "(0% loss)")
                                    $Failure = ("$Output" -match "General Failure") -or ("$Output" -match "Destination host unreachable")
                                    $Success = $Success -and -not $Failure

                                    if (-not $Success) {
                                        Write-Host "Attempting to find MTU Estimate. Iterating on 05% MTU decreases.`r`n"
                                        "Attempting to find MTU Estimate. Iterating on 05% MTU decreases.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $PacketSize = [math]::Round($PacketSize - ($PacketSize * .05))
                                    } 
                                    if ($Failure) {
                                        Write-Host "PING STATUS: General FAILURE - Host May Be Unreachable`r`n"
                                        "PING STATUS: General FAILURE - Host May Be Unreachable`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $PacketSize = 0
                                    } else {
                                        Write-Host "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}). Estimated MTU Found: ~$PacketSize`r`n"
                                        "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}). Estimated MTU Found: ~$PacketSize`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                        $TestInterface.ConnectionMTU["$TargetIP"] = $PacketSize
                                    }
                                }
                                
                                $ActualMTU = $PacketSize

                                # VERIFY REPORTED = ~ACTUAL MTU. FAIL IF RANGE > 500 BYTES.
                                if ([Math]::Abs($ReportedMTU - $ActualMTU) -gt 500) { 
                                    $Success = $False   
                                }

                                $Results["STAGE 2: PING -L -F"] += "| ($hostName)`t`t| ($SourceIP)`t| ($TargetMachine)`t`t| ($TargetIP)`t| $ReportedMTU Bytes`t| $ActualMTU Bytes | $Success`t|"
                                if (-not $Success) {
                                    $Failures["STAGE 1: PING"] += "| ($hostName)`t`t| ($SourceIP)`t| ($TargetMachine)`t`t| ($TargetIP)`t| $ReportedMTU Bytes`t| $ActualMTU Bytes | $Success`t|"
                                }

                                $NewResultInformation.SourceMachine = $hostName
                                $NewResultInformation.TargetMachine = $TargetMachine
                                $NewResultInformation.SourceIp = $SourceIp
                                $NewResultInformation.TargetIp = $TargetIp
                                $NewResultInformation.Success = $Success
                                $NewResultInformation.ReportedMTU = $ReportedMTU
                                $NewResultInformation.ActualMTU = $ActualMTU
                                $NewResultInformation.ReproCommand = "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f -n 1"
                                $ResultInformationList["STAGE 2: PING -L -F"] += $NewResultInformation
                                $StageSuccessList["STAGE 2: PING -L -F"] += $Success

                                $Success | Should Be $True
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
    
    Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 2: PING -L -F"

    Write-Host "RESULTS Stage 2: PING -L -F`r`n"
    "RESULTS Stage 2: PING -L -F`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    ($Results["STAGE 2: PING -L -F"]) | ForEach-Object {

        Write-Host $_ 
        $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    }
    if ($StageSuccessList["STAGE 2: PING -L -F"] -contains $false) {
        Write-Host "`r`nSTAGE 2: MTU TEST FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
        "`r`nSTAGE 2: MTU TEST FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        $StageNumber = @(0)
    }

    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Time: $endTime`r`n"
    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
}