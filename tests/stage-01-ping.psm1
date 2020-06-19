function Init-StagePing {

    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [PSCredential] $Credentials = $null
    )

    Context "VERBOSE: Testing Connectivity Stage 1: PING`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 1: PING`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 1: PING`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
        Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

        Write-Host "Time: $endTime`r`n"
        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        Write-Host "Hello"
        Write-Host $TestNetwork
        $Results["STAGE 1: PING"] = @("| SOURCE MACHINE`t| SOURCE NIC`t`t| TARGET NIC`t`t| CONNECTIVITY`t|")
        $Failures["STAGE 1: PING"] = @("| SOURCE MACHINE`t| SOURCE NIC`t`t| TARGET NIC`t`t| CONNECTIVITY`t|")
        $ResultInformationList["STAGE 1: PING"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 1: PING"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {
            
            Write-Host "VERBOSE: Testing Ping Connectivity on Machine: $($_.Name)`r`n"
            "VERBOSE: Testing Ping Connectivity on Machine: $($_.Name)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            
            $hostName = $_.Name
            $HostCimSession = New-CimSession -ComputerName $hostname -Credential $Credentials
            $ValidInterfaceList = $_.InterfaceListStruct.Values | where IPAddress -ne "" 

            $ValidInterfaceList | ForEach-Object {
                
                $SourceStatus = $_.Status

                if ($SourceStatus) {
                    
                    Write-Host "VERBOSE: Testing Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                    "VERBOSE: Testing Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    
                    $SubNetTable = $_.SubNetMembers
                    $SourceIp = $SubNetTable.Keys[0]
                    $PeerNetList = $SubNetTable[$SourceIp] | where $_.IpAddress -notlike $SourceIp

                    $PeerNetList | ForEach-Object {

                        $NewResultInformation = [ResultInformationData]::new()
                        $TargetName = $_.MachineName
                        $TargetIP = $_.IpAddress

                        $Success = $true

                        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                        Write-Host "Time: $endTime`r`n"
                        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                        
                        if ($SourceIp -NotLike $TargetIp -and $SourceStatus) {
                            
                            It "Basic Connectivity (ping) -- Verify Basic Connectivity: Between $($TargetIP) and $($SourceIP))" {
                                
                                Write-Host "ping $($TargetIP) -S $($SourceIP)`r`n"
                                "ping $($TargetIP) -S $($SourceIP)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                $ReproCommand = "ping $($TargetIP) -S $($SourceIP)"
                                    
                                $Output = Invoke-Command -ComputerName $hostName -Credential $Credentials -ScriptBlock { cmd /c "ping $Using:TargetIP -S $Using:SourceIP" } 
                                $Success = ("$Output" -match "Reply from $TargetIP") -and ($Output -match "(0% loss)") -and ("$Output" -notmatch "Destination host unreachable/") 

                                "PING STATUS SUCCESS: $Success`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                $Results["STAGE 1: PING"] += "| ($hostName)`t`t| ($SourceIP)`t| ($TargetIP)`t| $Success`t`t|"

                                if (-not $Success) {
                                    $Failures["STAGE 1: PING"] += "| ($hostName)`t`t| ($SourceIP)`t| ($TargetIP)`t| $Success`t`t|"
                                }

                                $NewResultInformation.SourceMachine = $hostName
                                $NewResultInformation.TargetMachine = $TargetName
                                $NewResultInformation.SourceIp = $SourceIp
                                $NewResultInformation.TargetIp = $TargetIp
                                $NewResultInformation.Success = $Success
                                $NewResultInformation.ReproCommand = $ReproCommand
                                $ResultInformationList["STAGE 1: PING"] += $NewResultInformation
                                
                                $StageSuccessList["STAGE 1: PING"] += $Success

                                $Success | Should Be $True
                            }

                            # $StageSuccess = $StageSuccess -and $Success
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
    
    Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 1: PING"

    Write-Host "RESULTS Stage 1: PING`r`n"
    "RESULTS Stage 1: PING`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    ($Results["STAGE 1: PING"]) | ForEach-Object {

        Write-Host $_ 
        $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    }
    if ($StageSuccessList["STAGE 1: PING"] -contains $false) {
        Write-Host "`r`nSTAGE 1: PING FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
        "`r`nSTAGE 1: PING FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        $StageNumber = @(0)
    }

    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Time: $endTime`r`n"
    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
}
