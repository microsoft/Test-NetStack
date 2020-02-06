function Assert-InboundOutboundInterfaceSuccess {

    param(
      [Parameter(Mandatory = $true)]
      [HashTable] $ResultInformationList,
      [Parameter(Mandatory = $true)]
      [String] $StageString
    )
    
    $ResultData = $ResultInformationList[$StageString]
    $InterfaceList = @()
    $MachineList = @()

    $OutlierInboundRecommendations = @{}
    $OutlierOutboundRecommendations = @{}
    $InterfaceInboundRecommendations = ""
    $InterfaceOutboundRecommendations = ""
    $MachineInboundRecommendations = ""
    $MachineOutboundRecommendations = ""
    $InterfaceInboundSuccesses = @{}
    $InterfaceOutboundSuccesses = @{}
    $MachineInboundSuccesses = @{}
    $MachineOutboundSuccesses = @{}

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

        $InterfaceInboundSuccesses[$TargetIp] += @($Success)
        $InterfaceOutboundSuccesses[$SourceIp] += @($Success)
        $MachineInboundSuccesses[$TargetMachine] += @($Success)
        $MachineOutboundSuccesses[$SourceMachine] += @($Success)
        
        $IndividualInboundRecommendation = ""
        $IndividualOutboundRecommendation = ""
        $InterfaceInboundRecommendation = ""
        $InterfaceOutboundRecommendation = ""
        $MachineInboundRecommendation = ""
        $MachineOutboundRecommendation = ""

        switch ($StageString) {
            ("STAGE 1: PING") {
                $IndividualInboundRecommendation = "INDIVIDUAL FAILURE: Ping Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Verify Subnet And VLAN Settings For Relevant NICs.`r`n"
                $IndividualOutboundRecommendation = "INDIVIDUAL FAILURE: Ping Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Verify Subnet And VLAN Settings For Relevant NICs.`r`n"
                $InterfaceInboundRecommendation = "INTERFACE FAILURE: Ping Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify subnet and VLAN settings for relevant NICs. If the problem persists, consider checking NIC cabling.`r`n"
                $InterfaceOutboundRecommendation = "INTERFACE FAILURE: Ping Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify subnet and VLAN settings for relevant NICs. If the problem persists, consider checking NIC cabling.`r`n"
                $MachineInboundRecommendation = "MACHINE FAILURE: Ping Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify firewall settings for the erring machine. If the problem persists, consider checking Machine cabling.`r`n"
                $MachineOutboundRecommendation = "MACHINE FAILURE: Ping Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify firewall settings for the erring machine. If the problem persists, consider checking Machine cabling.`r`n"
            }
            ("STAGE 2: PING -L -F") {
                $IndividualInboundRecommendation = "INDIVIDUAL FAILURE: MTU Check Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine). Reported MTU was ($ReportedMTU), Actual MTU was ($ActualMTU).`r`n`tRECOMMENDATION: Verify MTU Settings.`r`n"
                $IndividualOutboundRecommendation = "INDIVIDUAL FAILURE: MTU Check Failed From Source ($SourceIp) On Machine ($SourceMachine) To Target ($TargetIp) On Machine ($TargetMachine). Reported MTU was ($ReportedMTU), Actual MTU was ($ActualMTU).`r`n`tRECOMMENDATION: Verify MTU Settings.`r`n"
                $InterfaceInboundRecommendation= "INTERFACE FAILURE: MTU Check Failed Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceOutboundRecommendation = "INTERFACE FAILURE: MTU Check Failed Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineInboundRecommendation = "MACHINE FAILURE: MTU Check Failed Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineOutboundRecommendation = "MACHINE FAILURE: MTU Check Failed Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify MTU Settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            }
            ("STAGE 3: TCP CTS Traffic") {
                $IndividualInboundRecommendation = "INDIVIDUAL FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.75) From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine).`r`n`tRECOMMENDATION: Retry TCP transaction with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $IndividualOutboundRecommendation = "INDIVIDUAL FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.75) From Source ($SourceIP) On Machine ($SourceMachine) To Target ($TargetIP) On Machine ($TargetMachine). RECOMMENDATION: Retry TCP transaction with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n`tREPRO COMMANDS: $ReproCommands`r`n"
                $InterfaceInboundRecommendation = "INTERFACE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.75) Across All Source NICs for Target NIC {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $InterfaceOutboundRecommendation = "INTERFACE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.75) Across All Target NICs for Source NIC {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineInboundRecommendation = "MACHINE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.75) Across All Source Machines for Target Machine {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
                $MachineOutboundRecommendation = "MACHINE FAILURE: TCP Traffic Throughput Failed To Meet Threshold (.75) Across All Target Machines for Source Machine {0}.`r`n`tRECOMMENDATION: Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks.`r`n"
            
            }
            
        }
        if (-not $Success) {
            $OutlierInboundRecommendations[$TargetIp] += $IndividualInboundRecommendation
            $OutlierOutboundRecommendations[$SourceIp] += $IndividualOutboundRecommendation
        }
        
    }

    # Write-Host (ConvertTo-Json $InterfaceInboundSuccesses)

    $InterfaceList | ForEach-Object {
        
        $InterfaceInboundSuccess = $InterfaceInboundSuccesses[$_]
        $InterfaceOutboundSuccess = $InterfaceOutboundSuccesses[$_]

        # INBOUND
        if ($InterfaceInboundSuccess -notcontains $true) {
            # Add Interface-Wide Failure Rec
            $InterfaceInboundRecommendations += ($InterfaceInboundRecommendation -f $_)
        } elseif ($InterfaceInboundSuccess -notcontains $false) {
            $InterfaceInboundRecommendations += "INTERFACE Success: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $InterfaceInboundRecommendations += $OutlierInboundRecommendations[$_]
        }
        

        # OUTBOUND
        if ($InterfaceOutboundSuccess -notcontains $true) {
            # Add Interface-Wide Failure Rec
            $InterfaceOutboundRecommendations += ($InterfaceOutboundRecommendation -f $_)
        } elseif ($InterfaceOutboundSuccess -notcontains $false) {
            $InterfaceOutboundRecommendations += "INTERFACE Success: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $InterfaceOutboundRecommendations += $OutlierInboundRecommendations[$_]
        }
        
    }

    $MachineList | ForEach-Object {

        $MachineInboundSuccess = $MachineInboundSuccesses[$_]
        $MachineOutboundSuccess = $MachineOutboundSuccesses[$_]

        # INBOUND
        if ($MachineInboundSuccess -notcontains $true) {
            # Add Machine-Wide Failure Rec
            $MachineInboundRecommendations += ($MachineInboundRecommendation -f $_)
        } elseif ($MachineInboundSuccess -notcontains $false) {
            $MachineInboundRecommendations += "MACHINE SUCCESS: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $MachineInboundRecommendations += ($OutlierInboundRecommendations[$_])
        }
        

        # OUTBOUND
        if ($MachineOutboundSuccess -notcontains $true) {
            # Add Machine-Wide Failure Rec
            $MachineOutboundRecommendations += ($MachineOutboundRecommendation -f $_)
        } elseif ($MachineOutboundSuccess -notcontains $false) {
            $MachineOutboundRecommendations += "MACHINE SUCCESS: ($_).`r`n"
        } else {
            # Add Individual Failure Rec
            $MachineOutboundRecommendations += $OutlierInboundRecommendations[$_]
        }
        
    }
    
    Write-Host $InterfaceInboundRecommendations
    Write-Host $InterfaceOutboundRecommendations
    Write-Host $MachineInboundRecommendations
    Write-Host $MachineOutboundRecommendations

}