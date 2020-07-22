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

    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\test-helper-functions.psm1') -ErrorAction SilentlyContinue

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
    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\stage-02-MTU.psm1')
    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\stage-03-TCP-Single.psm1')
    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\stage-04-NDK-Ping.psm1')
    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\stage-05-NDK-Perf-Single.psm1')
    Import-Module ($env:SystemDrive + '\Test-NetStack\tests\stage-06-NDK-Perf-N-1.psm1')

    ####################################
    # Test Machines for PING Capability
    ####################################
    if ((1 -in $StageNumber) -and (-not $NetworkImage)) {

        Test-StagePing -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -Credentials $Credentials

    }

    # ###################################
    # Test Machines for PING -L -F Capability
    # ###################################
    if ((2 -in $StageNumber) -and (-not $NetworkImage)) {

        Test-StageMTU -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -Credentials $Credentials

    }
    
    # ###################################
    # Test Machines for TCP CTS Traffic Capability
    # ###################################
    if ((3 -in $StageNumber) -and (-not $NetworkImage)) {

        Test-StageTCPSingle -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -RetryStageSuccessList $RetryStageSuccessList -Credentials $Credentials

    }

    # ###################################
    # Test Machines for NDK Ping Capability
    # ###################################
    if ((4 -in $StageNumber) -and (-not $NetworkImage)) {
        Test-StageNDKPing -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -Credentials $Credentials

    }

    ###################################
    # Test Machines for NDK Perf Capability
    ###################################
    if ((5 -in $StageNumber) -and (-not $NetworkImage)) {

        Test-StageNDKPerfSingle -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -RetryStageSuccessList $RetryStageSuccessList -Credentials $Credentials

    }

    # ##################################
    # Test Machines for NDK Perf (N to 1) Capability
    # ##################################
    if ((6 -in $StageNumber) -and (-not $NetworkImage)) {
    
        # TestStageNDKPerfMulti -TestNetwork $TestNetwork -Results $Results -Failures $Failures -ResultInformationList $ResultInformationList -StageSuccessList $StageSuccessList -Credentials $Credentials
    
    }

       

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
    
    Remove-Module 'stage-01-ping'
    Remove-Module 'stage-02-MTU'
    Remove-Module 'stage-03-TCP-Single'
    Remove-Module 'stage-04-NDK-Ping'
    Remove-Module 'stage-05-NDK-Perf-Single'
    Remove-Module 'stage-06-NDK-Perf-N-1'

    Write-Host "End"
}