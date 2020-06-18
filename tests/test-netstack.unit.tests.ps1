########################################################################
# Test-NetStack Network and Result Data Structures
########################################################################

class InterfaceData {
    [String]$Name
    [String]$SubNet
    [String]$IpAddress
    [String]$IfIndex
    [String]$Description
    [String]$RdmaImplementation
    [String]$vSwitch
    [String]$vSwitchDescription
    [String]$pSwitch
    [Int]$SubnetMask
    [Int]$Vlan
    [Long]$LinkSpeed
    [Boolean]$RdmaEnabled = $false
    [Boolean]$Status = $false
    [HashTable]$SubNetMembers = @{}
    [HashTable]$ConnectionMTU = @{}
}

class NodeNetworkData {
    [String]$Name
    [String]$RdmaProtocol
    [boolean]$IsRDMACapable
    [PSobject[]]$RdmaNetworkAdapters = @()
    [HashTable]$InterfaceListStruct = @{}
}

class SubnetTuple {
    [String]$MachineName
    [String]$IpAddress
}

class ResultInformationData {
    [String]$SourceMachine
    [String]$TargetMachine
    [String]$SourceIp
    [String]$TargetIp
    [String]$ReproCommand
    [Boolean]$Success
    [Int]$NumSources
    [Int]$ReportedMTU
    [Int]$ActualMTU
    [Long]$ReportedReceiveBps
    [Long]$ReportedSendBps
    [Long]$ActualReceiveBps
    [Long]$ActualSendBps
    [String[]] $SourceMachineNameList
    [String[]] $SourceMachineIPList
    [Boolean[]] $SourceMachineSuccessList
    [Long[]] $SourceMachineActualBpsList
}

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

########################################################################
# Begin Pester Test and Network Imaging
########################################################################

Describe "Test Network Stack`r`n" {
    
    [NodeNetworkData[]]$TestNetwork = [NodeNetworkData[]]@();
    [String[]]$MachineCluster = @()
    [HashTable]$TestSubNetworks = @{}
    [HashTable] $Results = @{}
    [HashTable] $Failures = @{}

    [HashTable]$ResultInformationList = @{}
    [HashTable]$StageSuccessList = @{}
    [HashTable]$RetryStageSuccessList = @{}

    Write-Host "Generating Test-NetStack-Output.txt"
    New-Item C:\Test-NetStack\Test-NetStack-Output.txt -ErrorAction SilentlyContinue
    $OutputFile = "Test-NetStack Output File"
    $OutputFile | Set-Content 'C:\Test-NetStack\Test-NetStack-Output.txt'

    $startTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Starting Test-NetStack: $startTime`r`n"
    "Starting Test-NetStack: $startTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    #TODO: Why are we declaring this since it's already available with $env:ComputerName?
    $machineName = $env:computername
    $sddcFlag = $false

    if (-not ($MachineList)) {
        try {
            
            Write-Host "VERBOSE: No list of machines passed to Test-NetStack. Assuming machine running in cluster.`r`n"
            "VERBOSE: No list of machines passed to Test-NetStack. Assuming machine running in cluster.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

            $MachineCluster = Get-ClusterNode
        
        } catch {
            
            #TODO: Exit will actually close the window if running in the shell. We should Write-Error to the screen.
            Write-Host "VERBOSE: An error has occurred. Machine $($machineName) is not running the cluster service. Exiting Test-NetStack.`r`n"
            "VERBOSE: An error has occurred. Machine $($machineName) is not running the cluster service. Exiting Test-NetStack.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        }
    }
    Else {
        $MachineCluster = $MachineList
    }

    Write-Host "The Following List of Machines will be tested: $MachineCluster`r`n"
    "The Following List of Machines will be tested: $MachineCluster`r`n"| Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    $equalRdmaProtocol = $false
    $rdmaProtocol = ""

    ########################################################################
    # Compute Network Construction and RDMA Capability
    ########################################################################

    Write-Host "Beginning Network Construction.`r`n"
    "Beginning Network Construction.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    $MachineCluster | ForEach-Object {
                
        [NodeNetworkData]$newNode = [NodeNetworkData]::new()
        
        $newNode.Name = $_
        $CimSession = New-CimSession -ComputerName $NewNode.Name -Credential $Credentials 
        $newNode.RdmaNetworkAdapters = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { Get-NetAdapterRdma | Select Name, InterfaceDescription, Enabled }

        # $vmTeamMapping = Get-VMNetworkAdapterTeamMapping -ManagementOS

        Write-Host "Machine Name: $($newNode.Name)`r`n"
        "Machine Name: $($newNode.Name)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
        (Get-NetAdapter -CimSession $CimSession | where Status -like "*Up*") | ForEach-Object {

            $newInterface = [InterfaceData]::new()

            $newInterface.Name = $_.Name
            $newInterface.Description = $_.InterfaceDescription
            $newInterface.IfIndex = $_.ifIndex
            $newInterface.IpAddress = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { $interface = $Using:newInterface; $ifIndex = $interface.ifIndex; (Get-NetIpAddress | where InterfaceIndex -eq $ifIndex | where AddressFamily -eq "IPv4" | where SkipAsSource -Like "*False*").IpAddress }
            $newInterface.Status = If ($_.Status -match "Up" -and $newInterface.IpAddress -ne "") {$true} Else {$false}
            $newInterface.SubnetMask = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { $interface = $Using:newInterface; $ifIndex = $interface.ifIndex; (Get-NetIpAddress | where InterfaceIndex -eq $ifIndex | where AddressFamily -eq "IPv4" | where SkipAsSource -Like "*False*").PrefixLength }
            
            $LinkSpeed = $_.LinkSpeed.split(" ")
            Switch($LinkSpeed[1]) {
                
                ("Gbps") {$newInterface.LinkSpeed = [Int]::Parse($LinkSpeed[0]) * [Math]::Pow(10, 9)}

                ("Mbps") {$newInterface.LinkSpeed = [Int]::Parse($LinkSpeed[0]) * [Math]::Pow(10, 6)}

                ("bps") {$newInterface.LinkSpeed = [Int]::Parse($LinkSpeed[0]) * [Math]::Pow(10, 3)}

            }
            Write-Host ".`r`n"

            if ($newInterface.IpAddress -ne "") {
                
                $subnet = [IPAddress] (([IPAddress] $newInterface.IpAddress).Address -band ([IPAddress] (ConvertTo-IPv4MaskString $newInterface.SubnetMask)).Address)
                
                $newInterface.Subnet =  "$($subnet) / $($newInterface.SubnetMask)"
            }
            $newInterface.VLAN = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { $interface = $Using:newInterface; $name = $interface.Name; (Get-VMNetworkAdapterIsolation -ManagementOS | where ParentAdapter -eq "$name").DefaultIsolationID }
            
            if ($newInterface.VLAN -eq "") {
                $newInterface.VLAN = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { $interface = $Using:newInterface; $name = $interface.Name; (Get-NetAdapterAdvancedProperty | where Name -eq "$name" | where DisplayName -like "VLAN ID").DisplayValue }
            }

            if ($newInterface.Description -like "*Mellanox*") {

                $newInterface.RdmaImplementation = "RoCE"
                
            } elseif ($newInterface.Name -in $newNodeRdmaAdapters.Name) { 

                try {

                    $newInterface.RdmaImplementation = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { (Get-NetAdapterAdvancedProperty -Name $Using:newInterface.Name -RegistryKeyword *NetworkDirectTechnology -ErrorAction Stop).RegistryValue }
                    Write-Host $newInterface.RdmaImplementation
                    switch([Int]$rdmaProtocol) {
            
                        0 {$newInterface.RdmaImplementation = "N/A"}
                        
                        1 {$newInterface.RdmaImplementation = "iWARP"}
                        
                        2 {$newInterface.RdmaImplementation = "InfiniBand"}
                        
                        3 {$newInterface.RdmaImplementation = "RoCE"}

                        4 {$newInterface.RdmaImplementation = "RoCEv2"}
                    
                    }

                } catch {

                    $newInterface.RdmaImplementation = "N/A"

                }

            }

            $newInterface.RdmaEnabled = $newInterface.Name -In ($newNode.RdmaNetworkAdapters | where Enabled -Like "True").Name
        
            $newNode.InterfaceListStruct.add($newInterface.Name, $newInterface)
        }
        
        $rdmaEnabledNics = Invoke-Command -ComputerName $newNode.Name -Credential $Credentials -ScriptBlock { (Get-NetAdapterRdma | Where-Object Enabled -eq $true).Name }
        Write-Host "VERBOSE: RDMA Adapters"
        "VERBOSE: RDMA Adapters" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        # Write-Host ($rdmaEnabledNics )
        $rdmaEnabledNics | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        Write-Host "`r`n"
        "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

        # If it's QLogic, iWARP, if it's Mellanox, Roce
        # Chelsio can be either

        ########################################################################
        ## SDDC Machines, checking config for protocol rocki v. iwarp
        ########################################################################
    
        if ($sddcFlag) {    

            Write-Host "VERBOSE: SDDC Machine, checking IpAssignment.json for RDMA Protocol.`r`n"
            "VERBOSE: SDDC Machine, checking IpAssignment.json for RDMA Protocol.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
            
            $sdnNetworkResourceFileRelative = "\IpAssignment.json"
            $sdnNetworkResourceFile = "\\$($newNode.Name)\C$\" + $sdnNetworkResourceFileRelative 

            if([System.IO.File]::Exists($sdnNetworkResourceFile))
            {   
                $payload = get-content -Path $sdnNetworkResourceFile -raw
                $config = convertfrom-json $payload

            } else {
                
                Write-Host "VERBOSE: SDDC Machine does not have access to IpAssignment.json. Exiting.`r`n"
                "VERBOSE: SDDC Machine does not have access to IpAssignment.json. Exiting.`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
                Exit

            }

            if ($newNode.Name -eq $machineName) {

                $equalRdmaProtocol = $true
                $rdmaProtocol = $config.Payload.RdmaMode

            } else {

                $equalRdmaProtocol = $config.Payload.RdmaMode -eq $rdmaProtocol

            }

        } elseif ($newNode.Description -like "*Mellanox*") {

            $newNode.RdmaProtocol = "RoCE"
            
        } 
        
        $newNode.IsRDMACapable = $equalRdmaProtocol
        
        $TestNetwork += $newNode
    }

    Connect-Network -NetworkData $TestNetwork -TestSubNetworks $TestSubNetworks

    Write-Host "####################################`r`n"
    Write-Host "VERBOSE: BEGINNING Test-NetStack CORE STAGES`r`n"
    Write-Host "####################################`r`n"
    "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
    "VERBOSE: BEGINNING Test-NetStack CORE STAGES`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
    "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

    Write-Host "# The Following Subnetworks Will Be Tested"
    Write-Host "# Calculated According To Subnet and VLAN Configurations`r`n"
    "# The Following Subnetworks Will Be Tested" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
    "# Calculated According To Subnet and VLAN Configurations`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

    Write-Host (ConvertTo-Json $TestSubNetworks)
    
    $TestNetworkJson = ConvertTo-Json $TestNetwork -Depth 99

    $TestNetworkJson | Set-Content "C:\Test-NetStack\Test-NetStack-Network-Info.txt"
    
    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\stage-01-ping.psm1')
    # Import-Module ($env:SystemDrive + '\stage-01-ping.psm1')
    # Import-Module ($env:SystemDrive + '\stage-01-ping.psm1')
    # Import-Module ($env:SystemDrive + '\stage-01-ping.psm1')

    ####################################
    # Test Machines for PING Capability
    ####################################
    if ((1 -in $StageNumber) -and (-not $NetworkImage)) {

        Init-StagePing -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -Credentials $Credentials

    }

    # ###################################
    # Test Machines for PING -L -F Capability
    # ###################################
    if ((2 -in $StageNumber) -and (-not $NetworkImage)) {

        stage-02-MTU
        
    }
    
    # ###################################
    # Test Machines for TCP CTS Traffic Capability
    # ###################################
    if ((3 -in $StageNumber) -and (-not $NetworkImage)) {

        stage-03-TCP-Single

    }

    # ###################################
    # Test Machines for NDK Ping Capability
    # ###################################
    if ((4 -in $StageNumber) -and (-not $NetworkImage)) {

        Context "VERBOSE: Testing Connectivity Stage 4: NDK Ping`r`n" {

            Write-Host "####################################`r`n"
            Write-Host "VERBOSE: Testing Connectivity Stage 4: NDK Ping`r`n"
            Write-Host "####################################`r`n"
            "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
            "VERBOSE: Testing Connectivity Stage 4: NDK Ping`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
            "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
            
            $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

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

    ###################################
    # Test Machines for NDK Perf Capability
    ###################################
    if ((5 -in $StageNumber) -and (-not $NetworkImage)) {

        Context "VERBOSE: Testing Connectivity Stage 5: NDK Perf`r`n" {
    
            Write-Host "####################################`r`n"
            Write-Host "VERBOSE: Testing Connectivity Stage 5: NDK Perf`r`n"
            Write-Host "####################################`r`n"
            "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
            "VERBOSE: Testing Connectivity Stage 5: NDK Perf`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
            "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

            $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

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

                                            
                                            if ($ServerIP -eq '192.168.91.1' -and $retries -gt 0) {
                                                Write-Host 'Inconclusive'
                                                Set-ItResult -Inconclusive -Because "Retry"
                                                $Success = $False
                                            }

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

    # # ##################################
    # # Test Machines for NDK Perf (N to 1) Capability
    # # ##################################
    # if ((6 -in $StageNumber) -and (-not $NetworkImage)) {

        # Context "VERBOSE: Testing Connectivity Stage 6: NDK Perf (N : 1)`r`n" {

        #     Write-Host "####################################`r`n"
        #     Write-Host "VERBOSE: Testing Connectivity Stage 6: NDK Perf (N : 1)`r`n"
        #     Write-Host "####################################"
        #     "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        #     "VERBOSE: Testing Connectivity Stage 6: NDK Perf (N : 1)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 
        #     "####################################" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8 

        #     $Results["STAGE 6: NDK Perf (N : 1)"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
        #     $ResultString = ""
        #     $Failures["STAGE 6: NDK Perf (N : 1)"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
        #     $ResultInformationList["STAGE 6: NDK Perf (N : 1)"] = [ResultInformationData[]]@()
        #     $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] = [Boolean[]]@()

    #         $Results["STAGE 6: NDK Perf (N : 1)"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
    #         $ResultString = ""
    #         $Failures["STAGE 6: NDK Perf (N : 1)"] = @("| SERVER MACHINE`t| SERVER NIC`t`t| SERVER BPS`t`t| CLIENT MACHINE`t| CLIENT NIC`t| CLIENT BPS`t`t| THRESHOLD (>80%) |")
    #         $ResultInformationList["STAGE 6: NDK Perf (N : 1)"] = [ResultInformationData[]]@()
    #         $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] = [Boolean[]]@()

    #         $TestNetwork | ForEach-Object {

    #             "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #             $ServerNetworkNode = $_
    #             $ServerName = $_.Name

    #             $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where Status | where RdmaEnabled

    #             $ServerRdmaInterfaceList | ForEach-Object {
                    
    #                 # $ServerStatus = $_.Status
    #                 # if ($ServerStatus) {

    #                 # }
    #                 Write-Host "VERBOSE: Testing NDK Perf N:1 Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
    #                 "VERBOSE: Testing NDK Perf N:1 Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    #                 $ServerIP = $_.IpAddress
    #                 $ServerIF = $_.IfIndex
    #                 $ServerSubnet = $_.Subnet
    #                 $ServerVLAN = $_.VLAN
    #                 $ServerLinkSpeed = $_.LinkSpeed
    #                 $ServerInterfaceDescription = $_.Description
                    
    #                 $ResultString = ""
                    
    #                 $ClientNetwork = $TestNetwork | where Name -ne $ServerName

    #                 for ($i = 1; $i -lt $MachineCluster.Count - 1; $i++) {
                        
    #                     It "(N:1) RDMA Congestion Test (Client $ClientIP to Server $ServerIP)" {

    #                         $RandomClientNodes = If ($ClientNetwork.Count -eq 1) { $ClientNetwork[0] } Else { $ClientNetwork[0..$i] }
    #                         # $RandomClientNodes = $RandomClientNodes | where Status
    #                         $j = 0

    #                         $ServerOutput = @()
    #                         $ClientOutput = @()
    #                         $ServerCounter = @()
    #                         $ClientCounter = @()
    #                         $ServerSuccess = $True
    #                         $MultiClientSuccess = $True
    #                         $ServerCommand = "Server $ServerName CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):900$j  -ServerIf $ServerIF -TestType rping -W 5`r`n"
    #                         $NewResultInformation = [ResultInformationData]::new()
    #                         $NewResultInformation.ReproCommand = "`r`n`t`t$ServerCommand"

    #                         $RandomClientNodes | ForEach-Object {
    #                             Start-Sleep -Seconds 1
                            
    #                             $ClientName = $_.Name
    #                             $ClientInterface = $_.InterfaceListStruct.Values | where Name -In $_.RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
    #                             $ClientIP = $ClientInterface.IpAddress
    #                             $ClientIF = $ClientInterface.IfIndex
    #                             $ClientInterfaceDescription = $ClientInterface.Description  

                                
    #                             $ClientCommand = "Client $($_.Name) CMD: C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
    #                             Write-Host $ServerCommand
    #                             $ServerCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #                             Write-Host $ClientCommand
    #                             $ClientCommand | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    #                             $ServerCounter += Start-Job -ScriptBlock {
    #                                 $ServerName = $Using:ServerName
    #                                 $ServerInterfaceDescription = $Using:ServerInterfaceDescription
    #                                 Get-Counter -ComputerName $ServerName -Counter "\RDMA Activity($ServerInterfaceDescription)\RDMA Inbound Bytes/sec" -MaxSamples 5 #-ErrorAction Ignore
    #                             }

    #                             $ServerOutput += Start-Job -ScriptBlock {
    #                                 $ServerIP = $Using:ServerIP
    #                                 $ServerIF = $Using:ServerIF
    #                                 $j = $Using:j
    #                                 Invoke-Command -ComputerName $Using:ServerName -Credential $Using:Credentials -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -S -ServerAddr $($Using:ServerIP):900$Using:j  -ServerIf $Using:ServerIF -TestType rping -W 5 2>&1" }
    #                             }

    #                             $ClientCounter += Start-Job -ScriptBlock {
    #                                 $ClientName = $Using:ClientName
    #                                 $ClientInterfaceDescription = $Using:ClientInterfaceDescription
    #                                 Get-Counter -ComputerName $ClientName -Counter "\RDMA Activity($ClientInterfaceDescription)\RDMA Outbound Bytes/sec" -MaxSamples 5
    #                             }

    #                             $ClientOutput += Start-Job -ScriptBlock {
    #                                 $ServerIP = $Using:ServerIP
    #                                 $ClientIP = $Using:ClientIP
    #                                 $ClientIF = $Using:ClientIF
    #                                 $j = $Using:j
    #                                 Invoke-Command -Computername $Using:ClientName -ScriptBlock { cmd /c "C:\Test-NetStack\tools\NDK-Perf\NdkPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):900$Using:j -ClientAddr $($Using:ClientIP) -ClientIf $($Using:ClientIF) -TestType rping 2>&1" }
    #                             }
    #                             Start-Sleep -Seconds 1
    #                             $j++
    #                         }
                            
    #                         Start-Sleep -Seconds 10
    #                         Write-Host "##################################################`r`n"
    #                         "##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #                         $ServerBytesPerSecond = 0
    #                         $k = 0
    #                         $ServerCounter | ForEach-Object {
                                
    #                             $read = Receive-Job $_

    #                             $FlatServerOutput = $read.Readings.split(":") | ForEach-Object {
    #                                 try {[uint64]($_) * 8} catch{}
    #                             }
    #                             $ClientInterface = $RandomClientNodes[$k].InterfaceListStruct.Values | where Name -In $RandomClientNodes[$k].RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
    #                             $ClientLinkSpeed = $ClientInterface.LinkSpeed
    #                             $ServerBytesPerSecond = ($FlatServerOutput | Measure-Object -Maximum).Maximum
    #                             $ServerSuccess = $ServerSuccess -and ($ServerBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)
                                
    #                             $k++
    #                         }
    #                         $ResultString += "| ($ServerName)`t`t| ($ServerIP)`t| $ServerBytesPerSecond `t`t|" 

    #                         $ServerOutput | ForEach-Object {
    #                             $job = Receive-Job $_
    #                             Write-Host $job
    #                             $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #                         }
    #                         Write-Host "`r`n##################################################`r`n"
    #                         "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    #                         $k = 0
    #                         $ClientCounter | ForEach-Object {
                                
    #                             $written = Receive-Job $_
    #                             $FlatClientOutput = $written.Readings.split(":") | ForEach-Object {
    #                                 try {[uint64]($_) * 8} catch{}
    #                             }
    #                             $ClientName = $RandomClientNodes[$k].Name
    #                             $ClientInterface = $RandomClientNodes[$k].InterfaceListStruct.Values | where Name -In $RandomClientNodes[$k].RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
    #                             $ClientIP = $ClientInterface.IpAddress
    #                             $ClientIF = $ClientInterface.IfIndex
    #                             $ClientLinkSpeed = $ClientInterface.LinkSpeed
    #                             $ClientBytesPerSecond = ($FlatClientOutput | Measure-Object -Maximum).Maximum
    #                             $IndividualClientSuccess = ($ClientBytesPerSecond -gt ($ServerLinkSpeed, $ClientLinkSpeed | Measure-Object -Minimum).Minimum * .8)
    #                             $MultiClientSuccess = $MultiClientSuccess -and $IndividualClientSuccess
    #                             $NewResultInformation.SourceMachineNameList += $ClientName
    #                             $NewResultInformation.SourceMachineIPList += $ClientIP
    #                             $NewResultInformation.SourceMachineActualBpsList += $ClientBytesPerSecond
    #                             $NewResultInformation.SourceMachineSuccessList += $IndividualClientSuccess
    #                             $NewResultInformation.ReproCommand += "`r`n`t`tClient $($_.ClientName) CMD:  C:\Test-NetStack\tools\NDK-Perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
                                
    #                             $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] = [Boolean[]]@()
                                
    #                             $ResultString +=  "`r|`t`t`t`t`t`t`t`t`t| $($ClientName)`t`t| $($ClientIP)`t|"
    #                             $ResultString += " $ClientBytesPerSecond bps`t| $IndividualClientSuccess`t|"
    #                             $k++
    #                         }

    #                         $k = 0
    #                         $ClientOutput | ForEach-Object {
    #                             $job = Receive-Job $_
    #                             Write-Host $job
    #                             $job | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #                         }
    #                         Write-Host "`r`n##################################################`r`n"
    #                         "`r`n##################################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    #                         $Success = $ServerSuccess -and $MultiClientSuccess
                            
    #                         $Results["STAGE 6: NDK Perf (N : 1)"] += $ResultString
    #                         if (-not $Success) {
    #                             $Failures["STAGE 6: NDK Perf (N : 1)"] += $ResultString
    #                         }

                            
    #                         $NewResultInformation.TargetMachine = $ServerName
    #                         $NewResultInformation.TargetIp = $ServerIP
    #                         $NewResultInformation.NumSources = $MachineCluster.Count - 1
    #                         $NewResultInformation.Success = $Success
    #                         $ResultInformationList["STAGE 6: NDK Perf (N : 1)"] += $NewResultInformation
    #                         $StageSuccessList["STAGE 6: NDK Perf (N : 1)"] += $Success

    #                         $Success | Should Be $True    
    #                     }

    #                 }

    #             }

    #         }
    #     }

    #     Assert-ServerMultiClientInterfaceSuccess -ResultInformationList $ResultInformationList -StageString "STAGE 6: NDK Perf (N : 1)"

    #     Write-Host "RESULTS Stage 6: NDK Perf (N : 1)`r`n"
    #     "RESULTS Stage 6: NDK Perf (N : 1)`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        
    #     $ResultString += "| ($ServerName)`t`t| ($ServerIP)`t|"
    #     ($Results["STAGE 6: NDK Perf (N : 1)"]) | ForEach-Object {

    #         Write-Host $_ 
    #         $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    #     }
    #     if ($StageSuccessList["STAGE 6: NDK Perf (N : 1)"] -contains $false) {
    #         Write-Host "`r`nSTAGE 6: NDK PERF (N:1) FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n"
    #         "`r`nSTAGE 6: NDK PERF (N:1) FAILED. ONE OR MORE TEST INSTANCES FAILED.`r`n" | Out-File 'CTest-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    #         $StageNumber = 0
    #     }
    # }

    Write-Host "`r`nFAILURES STAGES 1-6`r`n"
    "`r`nFAILURES STAGES 1-6`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    ($Failures.Keys | Sort-Object) | ForEach-Object {

        Write-Host $_ 
        $_ | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        Write-Host $Failures[$_] 
        $Failures[$_]  | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8

    }

    $TestNetworkJson = ConvertTo-Json $TestNetwork -Depth 99

    $TestNetworkJson | Set-Content "C:\Test-NetStack\Test-NetStack-Network-Info.txt"

    $endTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Ending Test-NetStack: $endTime`r`n"
    "Ending Test-NetStack: $endTime`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    
    Write-Host "End"
}