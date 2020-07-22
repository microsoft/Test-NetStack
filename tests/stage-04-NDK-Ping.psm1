function Test-StageNDKPing {

    param(
        [NodeNetworkData[]] $TestNetwork,
        [HashTable] $Results,
        [HashTable] $Failures,
        [HashTable] $ResultInformationList,
        [HashTable] $StageSuccessList,
        [PSCredential] $Credentials = $null
    )

    Context "VERBOSE: Testing Connectivity Stage 4: NDK Ping`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 4: NDK Ping`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 4: NDK Ping`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        
        $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'
        Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

        Write-Host "Time: $endTime`r`n"
        "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        $Results["STAGE 4: NDK Ping"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| CLIENT MACHINE`t| CLIENT NIC`t`t| CONNECTIVITY`t|")
        $Failures["STAGE 4: NDK Ping"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| CLIENT MACHINE`t| CLIENT NIC`t`t| CONNECTIVITY`t|")
        $ResultInformationList["STAGE 4: NDK Ping"] = [ResultInformationData[]]@()
        $StageSuccessList["STAGE 4: NDK Ping"] = [Boolean[]]@()

        $TestNetwork | ForEach-Object {
    
            Write-Host "VERBOSE: Testing NDK Ping Connectivity on Machine: $($_.Name)"
            "VERBOSE: Testing NDK Ping Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            $ServerNetworkNode = $_
            $ServerName = $_.Name
            $ServerCimSession = New-CimSession -ComputerName $ServerName -Credential $Credentials
            $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled
    
            $ServerRdmaInterfaceList | ForEach-Object {
                
                $ServerStatus = $_.Status

                if ($ServerStatus) {
                    
                    Write-Host "VERBOSE: Testing NDK Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                    "VERBOSE: Testing NDK Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    
                    $ServerIP = $_.IpAddress
                    $ServerIF = $_.IfIndex
                    $ServerSubnet = $_.Subnet
                    $ServerVLAN = $_.VLAN
        
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
        
                            if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And $ClientStatus) {
                                
                                Write-Host "`r`n##################################################`r`n"
                                "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                                Write-Host "Time: $endTime`r`n"
                                "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                
                                It "Basic RDMA Connectivity Test -- Verify Basic Rdma Connectivity: Client $ClientIP to Server $ServerIP" {
                                    
                                    $ServerSuccess = $False
                                    $ClientSuccess = $False
                                    $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5"
                                    $ClientCommand = "Client $ClientName CMD: C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping"
                                    Write-Host $ServerCommand
                                    $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                    Write-Host $ClientCommand
                                    $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                    $NewResultInformation = [ResultInformationData]::new()

                                    $ServerOutput = Start-Job -ScriptBlock {
                                        $ServerIP = $Using:ServerIP
                                        $ServerIF = $Using:ServerIF
                                        Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -S -ServerAddr $($Using:ServerIP):9000  -ServerIf $Using:ServerIF -TestType rping -W 5 2>&1" }
                                    }
                                    Start-Sleep -Seconds 1
                                    $ClientOutput = Invoke-Command -ComputerName $ClientName -Credential $Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):9000 -ClientAddr $Using:ClientIP -ClientIf $Using:ClientIF -TestType rping 2>&1" }
                                    Start-Sleep -Seconds 5
            
                                    $ServerOutput = Receive-Job $ServerOutput
                                
                                    Write-Host "NDK Ping Server Output: "
                                    $ServerOutput | ForEach-Object {$ServerSuccess = $_ -match 'completes'; Write-Host $_}
                                    Write-Host "`r`n"

                                    "NDK Ping Server Output: "| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                    $ServerOutput | ForEach-Object {$_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8}
                                    "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            
                                    Write-Host "NDK Ping Client Output: "
                                    $ClientOutput[0..($ClientOutput.Count-4)] | ForEach-Object {$ClientSuccess = $_ -match 'completes';Write-Host $_}
                                    "NDK Ping Client Output: "| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                    $ClientOutput | ForEach-Object {$_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8}


                                    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

                                    Write-Host "Time: $endTime`r`n"
                                    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                                    
                                    Write-Host "`r`n##################################################`r`n"
                                    "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

                                    $Success = $ServerSuccess -and $ClientSuccess

                                    $Results["STAGE 4: NDK Ping"] += "| ($ServerName)`t`t| ($ServerIP)`t| ($ClientName)`t`t| ($ClientIP)`t| $Success`t`t|"

                                    if ((-not $Success)) {
                                        $Failures["STAGE 4: NDK Ping"] += "| ($ServerName)`t`t| ($ServerIP)`t| ($ClientName)`t`t| ($ClientIP)`t| $Success`t`t|"
                                    }
                                    
                                    $NewResultInformation.SourceMachine = $ClientName
                                    $NewResultInformation.TargetMachine = $ServerName
                                    $NewResultInformation.SourceIp = $ClientIP
                                    $NewResultInformation.TargetIp = $ServerIP
                                    $NewResultInformation.Success = $Success
                                    $NewResultInformation.ReproCommand = "`r`n`t`tServer: $ServerCommand`r`n`t`tClient: $ClientCommand"
                                    $ResultInformationList["STAGE 4: NDK Ping"] += $NewResultInformation
                                    $StageSuccessList["STAGE 4: NDK Ping"] += $Success

                                    $Success | Should Be $True
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Assert-ServerClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 4: NDK Ping"

    Write-Host "RESULTS Stage 4: NDK Ping`r`n"
    "RESULTS Stage 4: NDK Ping`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    ($Results["STAGE 4: NDK Ping"]) | ForEach-Object {

        Write-Host $_ 
        $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    }
    if ($StageSuccessList["STAGE 4: NDK Ping"] -contains $false) {
        Write-Host "`r`nSTAGE 4: NDK PING FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
        "`r`nSTAGE 4: NDK PING FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        $StageNumber = @(0)
    }

    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Time: $endTime`r`n"
    "Time: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
}