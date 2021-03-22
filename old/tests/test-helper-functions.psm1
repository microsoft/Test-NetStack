
########################################################################
# Helper Functions
########################################################################
function ConvertTo-IPv4MaskString {

    param(
      [Parameter(Mandatory = $true)]
      [ValidateRange(0, 32)]
      [Int] $MaskBits
    )
    $mask = ([Math]::Pow(2, $MaskBits) - 1) * [Math]::Pow(2, (32 - $MaskBits))
    $bytes = [BitConverter]::GetBytes([UInt32] $mask)
    (($bytes.Count - 1)..0 | ForEach-Object { [String] $bytes[$_] }) -join "."

}

function Connect-Network {

    param(
      [Parameter(Mandatory = $true)]
      [NodeNetworkData[]] $NetworkData,
      [Parameter(Mandatory = $true)]
      [HashTable] $TestSubNetworks
    )

    $NetworkConnectivityTemp = @{}

    $NetworkData | ForEach-Object {
        
        $hostName = $_.Name

        $_.InterfaceListStruct.Values | ForEach-Object {

            if ($_.Status -eq $true) {

                $MaskVlanTuple = "$($_.Subnet), $($_.VLAN)" 
                $SubnetTuple = [SubnetTuple]::new()
                $SubnetTuple.IpAddress = $_.IpAddress
                $SubnetTuple.MachineName = $hostName
                $NetworkConnectivityTemp[$MaskVlanTuple] +=  @($SubnetTuple)
                $TestSubNetworks[$MaskVlanTuple] += @("$($_.IpAddress)")
            }

        }
        
    }

    $NetworkData | ForEach-Object {
        
        $_.InterfaceListStruct.Values | ForEach-Object {
            
            $MaskVlanTuple = "$($_.Subnet), $($_.VLAN)"

            if ($_.IpAddress -ne "" -and $_.IpAddress -notlike $NetworkConnectivityTemp[$MaskVlanTuple].IpAdress) {
                
                $MaskVlanTuple = "$($_.Subnet), $($_.VLAN)"

                $_.SubNetMembers[$_.IpAddress] = $NetworkConnectivityTemp[$MaskVlanTuple]
            }

        }
        
    }

}

########################################################################
# Test-NetStack Result Walker Functions For Recommendation Functionality 
#####################################################################

# Server connectivity and functionality check for a given NIC (with outlier checks).
# This test outputs whether or not TARGET machines succeed.

function Assert-ServerClientInterfaceSuccess {

    param(
      [Parameter(Mandatory = $true)]
      [HashTable] $ResultInformationList,
      [Parameter(Mandatory = $true)]
      [String] $StageString
    )
    
    $ResultData = $ResultInformationList[$StageString]
    $InterfaceList = @()
    $MachineList = @()

    $OutlierServerRecommendations = @{}
    $OutlierClientRecommendations = @{}
    $InterfaceServerRecommendations = ""
    $InterfaceClientRecommendations = ""
    $MachineServerRecommendations = ""
    $MachineClientRecommendations = ""
    $InterfaceServerSuccesses = @{}
    $InterfaceClientSuccesses = @{}
    $MachineServerSuccesses = @{}
    $MachineClientSuccesses = @{}

    $ResultData | ForEach-Object {

        $SourceMachine = $_.SourceMachine
        $TargetMachine = $_.TargetMachine
        $SourceIp = $_.SourceIp
        $TargetIp = $_.TargetIp
        $Success = $_.Success
        $ActualMTU = $_.ActualMTU
        $ReportedMTU = $_.ReportedMTU
        $ReportedSourceBps = $_.ReportedSendBps
        $ReportedTargetBps = $_.ReportedReceiveBps
        $ActualSourceBps = $_.ActualSendBps
        $ActualReceiveBps = $_.ActualReceiveBps
        $ReproCommands = $_.ReproCommand
        
        if ($InterfaceList -notcontains $SourceIp) {$InterfaceList += $SourceIp}
        if ($MachineList -notcontains $SourceMachine) {$MachineList += $SourceMachine}

        $InterfaceServerSuccesses[$TargetIp] += @($Success)
        $InterfaceClientSuccesses[$SourceIp] += @($Success)
        $MachineServerSuccesses[$TargetMachine] += @($Success)
        $MachineClientSuccesses[$SourceMachine] += @($Success)
        
        $IndividualServerRecommendation = ""
        $IndividualClientRecommendation = ""
        $InterfaceServerRecommendation = ""
        $InterfaceClientRecommendation = ""
        $MachineServerRecommendation = ""
        $MachineClientRecommendation = ""

        switch ($StageString) {
            ("STAGE 1: PING") {
                $IndividualServerRecommendation = "INDIVIDUAL FAILURE: Ping Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Verify Subnet And VLAN Settings For Relevant NICs.`r`n"
                $IndividualClientRecommendation = "INDIVIDUAL FAILURE: Ping Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Verify Subnet And VLAN Settings For Relevant NICs.`r`n"
                $InterfaceServerRecommendation = "INTERFACE FAILURE: Ping Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify subnet and VLAN settings for relevant NICs. If the problem persists, consider checking NIC cabling.`r`n"
                $InterfaceClientRecommendation = "INTERFACE FAILURE: Ping Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify subnet and VLAN settings for relevant NICs. If the problem persists, consider checking NIC cabling.`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: Ping Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify firewall settings for the erring machine. If the problem persists, consider checking Machine cabling.`r`n"
                $MachineClientRecommendation = "MACHINE FAILURE: Ping Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify firewall settings for the erring machine. If the problem persists, consider checking Machine cabling.`r`n"
            }
            ("STAGE 2: PING -L -F") {
                $IndividualServerRecommendation = "INDIVIDUAL FAILURE: MTU Check Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine). Reported MTU was ($ReportedMTU), Actual MTU was ($ActualMTU).`r`n`tRECOMMENDATION: Verify MTU Settings.`r`n"
                $IndividualClientRecommendation = "INDIVIDUAL FAILURE: MTU Check Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine). Reported MTU was ($ReportedMTU), Actual MTU was ($ActualMTU).`r`n`tRECOMMENDATION: Verify MTU Settings.`r`n"
                $InterfaceServerRecommendation= "INTERFACE FAILURE: MTU Check Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceClientRecommendation = "INTERFACE FAILURE: MTU Check Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: MTU Check Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineClientRecommendation = "MACHINE FAILURE: MTU Check Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            }
            ("STAGE 3: TCP CTS Traffic") {
                $IndividualServerRecommendation = "INDIVIDUAL FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.65) From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Retry TCP transaction with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $IndividualClientRecommendation = "INDIVIDUAL FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.65) From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Retry TCP transaction with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $InterfaceServerRecommendation = "INTERFACE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.65) Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. Verify firewall settings for the erring machine. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceClientRecommendation = "INTERFACE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.65) Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. Verify firewall settings for the erring machine. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.65) Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineClientRecommendation = "MACHINE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.65) Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            
            }
            ("STAGE 4: NDK Ping") {
                $IndividualServerRecommendation = "INDIVIDUAL FAILURE: NDK Ping Failed From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Retry NDK Ping with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $IndividualClientRecommendation = "INDIVIDUAL FAILURE: NDK Ping Failed From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine). `r`n`tRECOMMENDATION: Retry NDK Ping with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $InterfaceServerRecommendation = "INTERFACE FAILURE: NDK Ping Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceClientRecommendation = "INTERFACE FAILURE: NDK Ping Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: NDK Ping Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineClientRecommendation = "MACHINE FAILURE: NDK Ping Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            
            }
            ("STAGE 5: NDK Perf") {
                $IndividualServerRecommendation = "INDIVIDUAL FAILURE: NDK Perf (1:1) Failed From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Retry NDK Perf (1:1) with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $IndividualClientRecommendation = "INDIVIDUAL FAILURE: NDK Perf (1:1) Failed From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine). `r`n`tRECOMMENDATION: Retry NDK Perf (1:1) with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $InterfaceServerRecommendation = "INTERFACE FAILURE: NDK Perf (1:1) Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceClientRecommendation = "INTERFACE FAILURE: NDK Perf (1:1) Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: NDK Perf (1:1) Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineClientRecommendation = "MACHINE FAILURE: NDK Perf (1:1) Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            
            }
            ("STAGE 6: NDK Perf (N : 1)") {
                $IndividualServerRecommendation = "INDIVIDUAL FAILURE: NDK Perf (1:1) Failed From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Retry NDK Perf (1:1) with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $IndividualClientRecommendation = "INDIVIDUAL FAILURE: NDK Perf (1:1) Failed From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine). `r`n`tRECOMMENDATION: Retry NDK Perf (1:1) with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $InterfaceServerRecommendation = "INTERFACE FAILURE: NDK Perf (1:1) Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceClientRecommendation = "INTERFACE FAILURE: NDK Perf (1:1) Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: NDK Perf (1:1) Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineClientRecommendation = "MACHINE FAILURE: NDK Perf (1:1) Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            
            }
            
        }
        if (-not $Success) {
            $OutlierServerRecommendations[$TargetIp] += $IndividualServerRecommendation
            $OutlierClientRecommendations[$SourceIp] += $IndividualClientRecommendation
        }
        
    }

    $InterfaceList | ForEach-Object {
        
        $InterfaceServerSuccess = $InterfaceServerSuccesses[$_]
        $InterfaceClientSuccess = $InterfaceClientSuccesses[$_]

        # Server
        if ($InterfaceServerSuccess -notcontains $true) {
            # Add Interface-Wide Failure Rec
            $InterfaceServerRecommendations += ($InterfaceServerRecommendation -f $_)
        } elseif ($InterfaceServerSuccess -notcontains $false) {
            $InterfaceServerRecommendations += "INTERFACE Success: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $InterfaceServerRecommendations += $OutlierServerRecommendations[$_]
        }
        

        # Client
        if ($InterfaceClientSuccess -notcontains $true) {
            # Add Interface-Wide Failure Rec
            $InterfaceClientRecommendations += ($InterfaceClientRecommendation -f $_)
        } elseif ($InterfaceClientSuccess -notcontains $false) {
            $InterfaceClientRecommendations += "INTERFACE Success: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $InterfaceClientRecommendations += $OutlierClientRecommendations[$_]
        }
        
    }

    $MachineList | ForEach-Object {

        $MachineServerSuccess = $MachineServerSuccesses[$_]
        $MachineClientSuccess = $MachineClientSuccesses[$_]

        # Server
        if ($MachineServerSuccess -notcontains $true) {
            # Add Machine-Wide Failure Rec
            $MachineServerRecommendations += ($MachineServerRecommendation -f $_)
        } elseif ($MachineServerSuccess -notcontains $false) {
            $MachineServerRecommendations += "MACHINE SUCCESS: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $MachineServerRecommendations += ($OutlierServerRecommendations[$_])
        }
        

        # Client
        if ($MachineClientSuccess -notcontains $true) {
            # Add Machine-Wide Failure Rec
            $MachineClientRecommendations += ($MachineClientRecommendation -f $_)
        } elseif ($MachineClientSuccess -notcontains $false) {
            $MachineClientRecommendations += "MACHINE SUCCESS: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $MachineClientRecommendations += $OutlierClientRecommendations[$_]
        }
        
    }
    Write-Host "`r`nINDIVIDUAL AND INTERFACE Server RECOMMENDATIONS`r`n"
    "`r`nINDIVIDUAL AND INTERFACE Server RECOMMENDATIONS`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host $InterfaceServerRecommendations
    $InterfaceServerRecommendations | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host "`r`nINDIVIDUAL AND INTERFACE Client RECOMMENDATIONS`r`n"
    "`r`nINDIVIDUAL AND INTERFACE Client RECOMMENDATIONS`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host $InterfaceClientRecommendations
    $InterfaceClientRecommendations | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host "`r`nMACHINE AND INTERFACE Server RECOMMENDATIONS`r`n"
    "`r`nMACHINE AND INTERFACE Server RECOMMENDATIONS`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host $MachineServerRecommendations
    $MachineServerRecommendations | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host "`r`nMACHINE AND INTERFACE Client RECOMMENDATIONS`r`n"
    "`r`nMACHINE AND INTERFACE Client RECOMMENDATIONS`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host $MachineClientRecommendations
    $MachineClientRecommendations | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

}

function Assert-ServerMultiClientInterfaceSuccess {

    param(
      [Parameter(Mandatory = $true)]
      [HashTable] $ResultInformationList,
      [Parameter(Mandatory = $true)]
      [String] $StageString
    )
    
    $ResultData = $ResultInformationList[$StageString]
    $InterfaceList = @()
    $MachineList = @()

    $OutlierServerRecommendations = @{}
    $InterfaceServerRecommendations = ""
    $MachineServerRecommendations = ""
    $InterfaceServerSuccesses = @{}
    $MachineServerSuccesses = @{}

    $ResultData | ForEach-Object {

        $SourceMachines = $_.SourceMachineNameList
        $SourceIps = $_.SourceMachineIPList
        $SourceSuccesses = $_.SourceMachineSuccessList
        $SourceCount = $_.NumSources
        $TargetMachine = $_.TargetMachine
        $TargetIp = $_.TargetIp
        $Success = $_.Success
        $ReproCommands = $_.ReproCommand
        
        if ($InterfaceList -notcontains $TargetIp) {$InterfaceList += $TargetIp}
        if ($MachineList -notcontains $TargetMachine) {$MachineList += $TargetMachine}

        $InterfaceServerSuccesses[$TargetIp] += @($Success)
        $MachineServerSuccesses[$TargetMachine] += @($Success)
        
        $IndividualServerRecommendation = ""
        $InterfaceServerRecommendation = ""
        $MachineServerRecommendation = ""

        switch ($StageString) {
            ("STAGE 6: NDK Perf (N : 1)") {
                $InterfaceServerRecommendation = "INTERFACE FAILURE: At Least One NDK Perf (N:1) Congestion Test Failed When ($SourceCount) Source Machines ($SourceMachines) With IPs ($SourceIps) Congested Their Connection With Target ($TargetIP) On Machine ($TargetMachine). Success rate was ($SourceSuccesses), respectively.`r`n`tRECOMMENDATION: Retry NDK Perf (N:1) with relevant interfaces. Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $MachineServerRecommendation = "MACHINE FAILURE: NDK Perf (N:1) Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            
            }
            
        }
        if (-not $Success) {
            $OutlierServerRecommendations[$TargetIp] += $InterfaceServerRecommendation
        }
        
    }


    $InterfaceList | ForEach-Object {
        
        $InterfaceServerSuccess = $InterfaceServerSuccesses[$_]

        # Server
        if ($InterfaceServerSuccess -notcontains $false) {
            $InterfaceServerRecommendations += "INTERFACE Success: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $InterfaceServerRecommendations += $OutlierServerRecommendations[$_]
        }
        
    }

    $MachineList | ForEach-Object {

        $MachineServerSuccess = $MachineServerSuccesses[$_]

        # Server
        if ($MachineServerSuccess -notcontains $true) {
            # Add Machine-Wide Failure Rec
            $MachineServerRecommendations += ($MachineServerRecommendation -f $_)
        } elseif ($MachineServerSuccess -notcontains $false) {
            $MachineServerRecommendations += "MACHINE SUCCESS: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $MachineServerRecommendations += ($OutlierServerRecommendations[$_])
        }
        
    }
    Write-Host "`r`nINDIVIDUAL AND INTERFACE Server RECOMMENDATIONS`r`n"
    "`r`nINDIVIDUAL AND INTERFACE Server RECOMMENDATIONS`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host $InterfaceServerRecommendations
    $InterfaceServerRecommendations | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host "`r`nMACHINE AND INTERFACE Server RECOMMENDATIONS`r`n"
    "`r`nMACHINE AND INTERFACE Server RECOMMENDATIONS`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    Write-Host $MachineServerRecommendations
    $MachineServerRecommendations | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

}