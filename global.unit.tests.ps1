class InterfaceData {
    [String]$Name
    [String]$SubNet
    [String]$IpAddress
    [String]$IfIndex
    [String]$Description
    [String]$RdmaImplementation
    [String]$vSwitch
    [String]$pSwitch
    [Int]$SubnetMask
    [Int]$Vlan
    [Int]$MTU
    [Long]$LinkSpeed
    [Boolean]$RdmaEnabled = $false
    [Boolean]$Status = $false
    [HashTable]$SubNetMembers = @{}
}

class NodeNetworkData {
    [String]$Name
    [String]$RdmaProtocol
    [boolean]$IsRDMACapable
    [PSobject[]]$RdmaNetworkAdapters = @()
    [HashTable]$InterfaceListStruct = @{}
}

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
      [HashTable] $NetworkConnectivity
    )

    $NetworkConnectivityTemp = @{}

    $SubNetMap = @{}

    $NetworkData | ForEach-Object {
        
        $hostName = $_.Name

        $_.InterfaceListStruct.Values | ForEach-Object {

            if ($_.IpAddress -ne "") {

                $MaskVlanTuple = "$($_.Subnet), $($_.VLAN)"
                $NetworkConnectivityTemp[$MaskVlanTuple] +=  @("$($_.IpAddress)")

            }

        }
        
    }

    $NetworkData | ForEach-Object {
        
        $hostName = $_.Name

        $_.InterfaceListStruct.Values | ForEach-Object {
            
            $MaskVlanTuple = "$($_.Subnet), $($_.VLAN)"

            if ($_.IpAddress -ne "" -and $_.IpAddress -notlike $NetworkConnectivityTemp[$MaskVlanTuple]) {
                
                $MaskVlanTuple = "$($_.Subnet), $($_.VLAN)"

                $_.SubNetMembers[$_.IpAddress] = $NetworkConnectivityTemp[$MaskVlanTuple]
            }

        }
        
    }

}

function Is-Numeric ($Value) {
    return $Value -match "^[\d\.]+$"
}

Clear-Host

Describe "Test RDMA Congestion`r`n" {

    [NodeNetworkData[]]$TestNetwork = @();
    [String[]]$MachineCluster = @()
    [HashTable]$NetworkConnectivity = @{}

    
    Write-Host "Generating Test-RDMA-Output.txt"
    New-Item C:\cmd\Test-RDMA-Output.txt
    $OutputFile = "Test-RDMA Output File"
    $OutputFile | Set-Content 'C:\cmd\Test-RDMA-Output.txt'

    $startTime = Get-Date -format:'MM-dd-yyyy HH:mm:ss'

    Write-Host "Starting Test-RDMA: $startTime`r`n"
    "Starting Test-RDMA: $startTime`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    $machineName = $env:computername
    $sddcFlag = $true
    $MachineList = "RRN44-14-09 RRN44-14-11 RRN44-14-13 RRN44-14-15"

    if ($MachineList.count -ne 0) {

        $MachineCluster = $MachineList.split(" ")

    } else {

        try {
            
            Write-Host "VERBOSE: No list of machines passed to Test-RDMA. Assuming machine running in cluster.`r`n"
            "VERBOSE: No list of machines passed to Test-RDMA. Assuming machine running in cluster.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

            $MachineCluster = Get-ClusterNode
        
        } catch {
            
            Write-Host "VERBOSE: An error has occurred. Machine $($machineName) is not running the cluster service. Exiting Test-RDMA.`r`n"
            "VERBOSE: An error has occurred. Machine $($machineName) is not running the cluster service. Exiting Test-RDMA.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
            Exit
        
        }

    }

    Write-Host "The Following List of Machines will be tested: $MachineCluster`r`n"
    "The Following List of Machines will be tested: $MachineCluster`r`n"| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8


    $equalRdmaProtocol = $false
    $rdmaProtocol = ""

    ########################################################################
    # Compute Network Construction and RDMA Capability
    ########################################################################

    Write-Host "Identifying Network.`r`n"
    "Beginning Network Construction.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    $MachineCluster | ForEach-Object {
                
        $newNode = [NodeNetworkData]::new()
        
        $newNode.Name = $_

        $newNode.RdmaNetworkAdapters = Get-NetAdapterRdma -CimSession $newNode.Name | Select Name, InterfaceDescription, Enabled

        $vmTeamMapping = Get-VMNetworkAdapterTeamMapping -ManagementOS

        Write-Host "Machine Name: $($newNode.Name)`r`n"
        "Machine Name: $($newNode.Name)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
        
        (Get-NetAdapter -CimSession $_) | ForEach-Object {

            $newInterface = [InterfaceData]::new()

            $newInterface.Name = $_.Name
            $newInterface.Description = $_.InterfaceDescription
            $newInterface.IfIndex = $_.ifIndex
            $newInterface.Status = If ($_.Status -match "Up") {$true} Else {$false}
            $newInterface.IpAddress = (Get-NetIpAddress -CimSession $newNode.Name | where InterfaceIndex -eq $_.ifIndex | where AddressFamily -eq "IPv4" | where SkipAsSource -Like "*False*").IpAddress
            $newInterface.SubnetMask = (Get-NetIpAddress -CimSession $newNode.Name | where InterfaceIndex -eq $_.ifIndex | where AddressFamily -eq "IPv4" | where SkipAsSource -Like "*False*").PrefixLength
            
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
            
            $newInterface.VLAN = (Get-VMNetworkAdapterIsolation -ManagementOS -CimSession $newNode.Name | where ParentAdapter -like "*$($_.Name)*").DefaultIsolationID

            if ($newInterface.VLAN -eq "") {
                
                $newInterface.VLAN = (Get-NetAdapterAdvancedProperty -CimSession $newNode.Name | where Name -like "$($_.Name)" | where DisplayName -like "VLAN ID").DisplayValue

            }

            if ($newInterface.Description -like "*Mellanox*") {

                $newInterface.RdmaImplementation = "RoCE"
                
            } else { 

                try {

                    $newInterface.RdmaImplementation = (Get-NetAdapterAdvancedProperty -CimSession $newNode.Name -Name $_.Name -RegistryKeyword *NetworkDirectTechnology -ErrorAction Stop).RegistryValue
                
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

            if ($vmTeamMapping.NetAdapterName -Contains $newInterface.Name) {

                $newInterface.vSwitch = ($vmTeamMapping | where NetAdapterName -Like "*$($newInterface.Name)*").ParentAdapter.Name 

            } elseif ($vmTeamMapping.ParentAdapter -Like "*$($newInterface.Name)*") {

                $newInterface.pSwitch = ($vmTeamMapping | where ParentAdapter -Like "*$($newInterface.Name)*") | select NetAdapterName

            } else {
                
                $newInterface.vSwitch = "N/A"
                $newInterface.pSwitch = "N/A"
            }

            $newInterface.RdmaEnabled = $newInterface.Name -In ($newNode.RdmaNetworkAdapters | where Enabled -Like "True").Name
        
            $newNode.InterfaceListStruct.add($newInterface.Name, $newInterface)
        }

        if ((Get-NetAdapterRdma).count -ne 0) {

            $newNode.IsRDMACapable = $true

        } else {

            Write-Host "VERBOSE: Machine $($newNode.Name) is not RDMA capable.`r`n"
            "VERBOSE: Machine $($newNode.Name) is not RDMA capable.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

        }
        
        Write-Host "VERBOSE: RDMA Adapters"
        "VERBOSE: RDMA Adapters" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
        Write-Host (Get-NetAdapterRdma -CimSession $newNode.Name).Name
        (Get-NetAdapterRdma -CimSession $newNode.Name).Name | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
        Write-Host "`r`n"
        "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 

        # If it's QLogic, iWARP, if it's Mellanox, Roce
        # Chelsio can be either

        ########################################################################
        ## SDDC Machines, checking config for protocol rocki v. iwarp
        ########################################################################
    
        if ($sddcFlag) {    

            Write-Host "VERBOSE: SDDC Machine, checking IpAssignment.json for RDMA Protocol.`r`n"
            "VERBOSE: SDDC Machine, checking IpAssignment.json for RDMA Protocol.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
            
            $sdnNetworkResourceFileRelative = "\E2EWorkload\IpAssignment.json"
            $sdnNetworkResourceFile = "\\$($newNode.Name)\C$\" + $sdnNetworkResourceFileRelative 

            if([System.IO.File]::Exists($sdnNetworkResourceFile))
            {   
                $payload = get-content -Path $sdnNetworkResourceFile -raw
                $config = convertfrom-json $payload

            } else {
                
                Write-Host "VERBOSE: SDDC Machine does not have access to IpAssignment.json. Exiting.`r`n"
                "VERBOSE: SDDC Machine does not have access to IpAssignment.json. Exiting.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
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


    Connect-Network -NetworkData $TestNetwork -NetworkConnectivity $NetworkConnectivity

    $TestNetworkJson = ConvertTo-Json $TestNetwork -Depth 99

    $TestNetworkJson | Set-Content "C:\cmd\Test-RDMA-Network-Info.txt"

    
    ####################################
    # BEGIN TEST-RDMA CONGESTION
    ####################################

    ####################################
    # Test Machines for PING Capability
    ####################################

    # Context "Basic Connectivity (ping)`r`n" {

    #     Write-Host "####################################`r`n"
    #     Write-Host "VERBOSE: Testing Connectivity Stage 1: PING`r`n"
    #     Write-Host "####################################`r`n"
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "VERBOSE: Testing Connectivity Stage 1: PING`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 

    #     $TestNetwork | ForEach-Object {
            
    #         Write-Host "VERBOSE: Testing Ping Connectivity on Machine: $($_.Name)`r`n"
    #         "VERBOSE: Testing Ping Connectivity on Machine: $($_.Name)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #         $hostName = $_.Name

    #         $ValidInterfaceList = $_.InterfaceListStruct.Values | where IPAddress -ne "" 

    #         $ValidInterfaceList | ForEach-Object {
                
    #             Write-Host "VERBOSE: Testing Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
    #             "VERBOSE: Testing Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #             $SubNetTable = $_.SubNetMembers

    #             $SourceIp = $SubNetTable.Keys[0]

    #             $PeerNetList = $SubNetTable[$SourceIp] | where $_ -notlike $SourceIp
                
    #             $PeerNetList | ForEach-Object {

    #                 $TargetIP = $_

    #                 if ($SourceIp -NotLike $TargetIp -and $TestInterface.Status) {
                        
    #                     It "Basic Connectivity (ping) -- Verify Basic Connectivity: Between $($TargetIP) and $($SourceIP))`r`n" {
                            
    #                         Write-Host "ping $($TargetIP) -S $($SourceIP)`r`n"
    #                         "ping $($TargetIP) -S $($SourceIP)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                
    #                         $Output = Invoke-Command -Computername $hostName -ScriptBlock { cmd /c "ping $Using:TargetIP -S $Using:SourceIP" } | findstr /R "Ping Packets"
    #                         $Success = "$Output" -match "(0% Loss)"
    #                         "PING STATUS SUCCESS: $Success`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                         $Success | Should Be $True
    #                     }
                        
    #                 }

    #             }   

    #         }
        
    #     }

    # }
    


    ####################################
    # Test Machines for PING -L -F Capability
    ####################################

    Context "MTU Connectivity Test (Ping -L -F)`r`n" {
        
        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 2: PING -L -F`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 2: PING -L -F`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 

        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing Ping -L -F Connectivity on Machine: $($_.Name)" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

            $hostName = $_.Name

            $ValidInterfaceList = $_.InterfaceListStruct.Values | where IPAddress -ne "" 

            $ValidInterfaceList | ForEach-Object {
                
                
                Write-Host "VERBOSE: Testing Ping -L -F Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                "VERBOSE: Testing Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

                $TestInterface = $_

                $SubNetTable = $_.SubNetMembers

                $SourceIp = $SubNetTable.Keys[0]

                $PeerNetList = $SubNetTable[$SourceIp] | where $_ -notlike $SourceIp
                
                $PeerNetList | ForEach-Object {

                    $TargetIP = $_

                    if ($SourceIp -NotLike $TargetIp -and $TestInterface.Status) {
                        
                        It "MTU Connectivity -- Verify Connectivity and Discover MTU: Between Target $($TargetIP) and Source $($SourceIP)" {
                            
                            $PacketSize = 1024
                            $Success = $True
                            $Error = $False
                            while($Success) {
                                
                                Write-Host "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f`r`n"
                                "ping $($TargetIP) -S $($SourceIP) -l $PacketSize -f`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

                                $Output = Invoke-Command -Computername $hostName -ScriptBlock { cmd /c "ping $Using:TargetIP -S $Using:SourceIP -l $Using:PacketSize -f" }
                                $Success = ("$Output" -match "Received = 4")
                                $Error = ("$Output" -match "General Failure") -or ("$Output" -match "Destination host unreachable")
                                $Success = $Success -and -not $Error

                                Write-Host "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}) FOR MTU: $PacketSize`r`n"
                                "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}) FOR MTU: $PacketSize`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                
                                if ($Success) {
                                    $PacketSize *= 2
                                } elseif ($Error) {
                                    Write-Host "PING STATUS: General FAILURE - Host May Be Unreachable`r`n"
                                    "PING STATUS: General FAILURE - Host May Be Unreachable`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                } else {
                                    Write-Host "Upper Bound of $PacketSize found. Working to find specific value. Iterating on 20% MTU decreases.`r`n"
                                    "Upper Bound of $PacketSize found. Working to find specific value. Iterating on 20% MTU decreases.`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                }
                            }

                            $Success = $False

                            while((-not $Success) -and (-not $Error)) {

                                Write-Host "ping $($TargetIP) -S $($SourceIP) -L $PacketSize -F`r`n"
                                "ping $($TargetIP) -S $($SourceIP) -L $PacketSize -F`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

                                $Output = Invoke-Command -Computername $hostName -ScriptBlock { cmd /c "ping $Using:TargetIP -S $Using:SourceIP -l $Using:PacketSize -f" }
                                $Success = ("$Output" -match "Received = 4")
                                $Error = ("$Output" -match "General Failure") -or ("$Output" -match "Destination host unreachable")
                                $Success = $Success -and -not $Error

                                if (-not $Success) {
                                    $PacketSize = [math]::Round($PacketSize - ($PacketSize * .2))
                                } elseif ($Error) {
                                    Write-Host "PING STATUS: General FAILURE - Host May Be Unreachable`r`n"
                                    "PING STATUS: General FAILURE - Host May Be Unreachable`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                } else {
                                    Write-Host "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}). Estimated MTU Found: ~$PacketSize`r`n"
                                    "PING STATUS: $(If ($Success) {"SUCCESS"} Else {"FAILURE"}). Estimated MTU Found: ~$PacketSize`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                    $TestInterface.MTU = $PacketSize
                                }
                            }
                            $Success | Should Be $True
                        }

                        Write-Host "####################################`r`n"
                        "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                    }

                }   

            }

        }

    }
    


    ####################################
    # Test Machines for TCP CTS Traffic Capability
    ####################################

    Context "Synthetic Connection Test (TCP)`r`n" {

        Write-Host "####################################`r`n"
        Write-Host "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n"
        Write-Host "####################################`r`n"
        "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
        "VERBOSE: Testing Connectivity Stage 3: TCP CTS Traffic`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
        "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 

        $TestNetwork | ForEach-Object {

            "VERBOSE: Testing CTS Traffic (TCP) Connectivity on Machine: $($_.Name)" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
            $ServerNetworkNode = $_
            $ServerName = $_.Name

            $ServerNetworkNode.InterfaceListStruct.Values | where VLAN -ne 0 | ForEach-Object {
                
                Write-Host "VERBOSE: Testing CTS Traffic (TCP) Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
                "VERBOSE: Testing CTS Traffic (TCP) Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

                $ServerIP = $_.IpAddress
                $ServerSubnet = $_.Subnet
                $ServerVLAN = $_.VLAN
                $ServerLinkSpeed = $_.LinkSpeed

                $TestNetwork | ForEach-Object {

                    $ClientNetworkNode = $_
                    $ClientName = $_.Name

                    $ClientNetworkNode.InterfaceListStruct.Values | where VLAN -ne 0 | ForEach-Object {

                        $ClientIP = $_.IpAddress
                        $ClientSubnet = $_.Subnet
                        $ClientVLAN = $_.VLAN
                        $ClientLinkSpeed = $_.LinkSpeed

                        if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And $TestInterface.Status) {

                            It "Synthetic Connection Test (TCP) -- Verify Throughput is >50% reported: Client $($ClientIP) to Server $($ServerIP)`r`n" {
                                
                                $Success = $False
                                Write-Host "Server $ServerName CMD: C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -listen:$($ServerIP) -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000`r`n"
                                "Server $ServerName CMD: C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -listen:$($ServerIP) -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                Write-Host "Client $ClientName CMD: C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -target:$($ServerIP) -bind:$ClientIP -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed`r`n"
                                "Client $ClientName CMD: C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -target:$($ServerIP) -bind:$ClientIP -consoleverbosity:1 -iterations:2 -RateLimit:$ClientLinkSpeed`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                
                                $ServerOutput = Start-Job -ScriptBlock {
                                    $ServerIP = $Using:ServerIP
                                    $ServerLinkSpeed = $Using:ServerLinkSpeed
                                    Invoke-Command -Computername $Using:ServerName -ScriptBlock { cmd /c "C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -consoleverbosity:1 -ServerExitLimit:32 -TimeLimit:20000 2>&1" }
                                }

                                $ClientOutput = Invoke-Command -Computername $ClientName -ScriptBlock { cmd /c "C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -connections:32 -consoleverbosity:1 -iterations:2 2>&1" }
                            
                                Start-Sleep 1

                                $ServerOutput = Receive-Job $ServerOutput

                                $FlatServerOutput = @()
                                $FlatClientOutput = @()
                                $ServerOutput[20..($ServerOutput.Count-5)] | ForEach-Object {If ($_ -ne "") {$FlatServerOutput += ($_ -split '\D+' | Sort-Object -Unique)}}
                                $ClientOutput[20..($ClientOutput.Count-5)] | ForEach-Object {If ($_ -ne "") {$FlatClientOutput += ($_ -split '\D+' | Sort-Object -Unique)}}
                                $FlatServerOutput = ForEach($num in $FlatServerOutput) {if ($num -ne "") {[Long]::Parse($num)}} 
                                $FlatClientOutput = ForEach($num in $FlatClientOutput) {if ($num -ne "") {[Long]::Parse($num)}}

                                $ServerRecvBps = ($FlatServerOutput | Measure-Object -Maximum).Maximum * 8
                                $ClientRecvBps = ($FlatClientOutput | Measure-Object -Maximum).Maximum * 8
                                $Success = ($ServerRecvBps -gt $ServerLinkSpeed * .5) -and ($ClientRecvBps -gt $ClientLinkSpeed * .5)
                                Write-Host "Server Bps $ServerRecvBps and Client Bps $ClientRecvBps`r`n"
                                "Server Bps $ServerRecvBps and Client Bps $ClientRecvBps`r`n"| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

                                Write-Host "TCP CTS Traffic Server Output: "
                                Write-Host ($ServerOutput -match "SuccessfulConnections")
                                $ServerOutput[($ServerOutput.Count-3)..$ServerOutput.Count] | ForEach-Object {Write-Host $_}
                                Write-Host "`r`n"
                                "TCP CTS Traffic Server Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                ($ServerOutput -match "SuccessfulConnections") | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                $ServerOutput[($ServerOutput.Count-3)..$ServerOutput.Count] | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
                                "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

                                Write-Host "TCP CTS Traffic Client Output: "
                                Write-Host ($ClientOutput -match "SuccessfulConnections")
                                $ClientOutput[($ClientOutput.Count-3)..$ClientOutput.Count] | ForEach-Object {Write-Host $_}
                                Write-Host "`r`n"
                                "TCP CTS Traffic Client Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                ($ClientOutput -match "SuccessfulConnections") | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                                $ClientOutput[($ClientOutput.Count-3)..$ClientOutput.Count] | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
                                "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8


                                $Success | Should Be $True
                            }
                            Write-Host "####################################`r`n"
                            "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                        }
                    }
                }
            }
        }
    }
    

    # ####################################
    # # Test Machines for UDP CTS Traffic Capability
    # ####################################

    # Context "Synthetic Connectivity Test (UDP)`r`n" {
        
    #     Write-Host "####################################`r`n"
    #     Write-Host "VERBOSE: Testing Connectivity Stage 4: UDP CTS Traffic`r`n"
    #     Write-Host "####################################`r`n"
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "VERBOSE: Testing Connectivity Stage 4: UDP CTS Traffic`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    
    #     $TestNetwork | ForEach-Object {
    
    #         "VERBOSE: Testing CTS Traffic (UDP) Connectivity on Machine: $($_.Name)" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #         $ServerNetworkNode = $_
    #         $ServerName = $_.Name
            
    #         $ServerNetworkNode.InterfaceListStruct.Values | where VLAN -ne 0 | ForEach-Object {
    
    #             Write-Host "VERBOSE: Testing CTS Traffic (UDP) Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
    #             "VERBOSE: Testing CTS Traffic (UDP) Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    
    #             $ServerIP = $_.IpAddress
    #             $ServerSubnet = $_.Subnet
    #             $ServerVLAN = $_.VLAN
    #             $ServerLinkSpeed = $_.LinkSpeed

    #             $TestNetwork | ForEach-Object {
    
    #                 $ClientNetworkNode = $_
    #                 $ClientName = $_.Name
    
    #                 $ClientNetworkNode.InterfaceListStruct.Values | where VLAN -ne 0 | ForEach-Object {
    
    #                     $ClientIP = $_.IpAddress
    #                     $ClientSubnet = $_.Subnet
    #                     $ClientVLAN = $_.VLAN
    #                     $ClientLinkSpeed = $_.LinkSpeed

    #                     if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And $TestInterface.Status) {
                            
    #                         It "Synthetic Connection Test (UDP) -- Verify Throughput is >50% reported: Client $($ClientIP) to Server $($ServerIP)`r`n" { 
                                
    #                             $Success = $False
    #                             Write-Host "Server $ServerName CMD: c:\cmd\tools\CTS-Traffic\ctsTraffic.exe -listen:$ServerIP -protocol:udp -bitspersecond:$ServerLinkSpeed -framerate:1000 -streamlength:10 -consoleverbosity:1 -TimeLimit:15000 -Buffer:1000000 `r`n"
    #                             "Server $ServerName CMD: ctsTraffic.exe -listen:$ServerIP -protocol:udp -bitspersecond:$ServerLinkSpeed -framerate:1000 -streamlength:10 -consoleverbosity:1 -TimeLimit:15000 -Buffer:1000000 `r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             Write-Host "Client $ClientName CMD: c:\cmd\tools\CTS-Traffic\ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -protocol:udp -bitspersecond:$ClientLinkSpeed -framerate:1000 -streamlength:10 -consoleverbosity:1 -connections:64 -iterations:1 -Buffer:1000000`r`n"
    #                             "Client $ClientName CMD: ctsTraffic.exe -target:$ServerIP -bind:$ClientIP -protocol:udp -bitspersecond:$ClientLinkSpeed -framerate:1000 -streamlength:10 -consoleverbosity:1 -connections:64 -iterations:1 -Buffer:1000000 `r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
        
    #                             $ServerOutput = Start-Job -ScriptBlock {
    #                                 $ServerIP = $Using:ServerIP
    #                                 $ServerLinkSpeed = $Using:ServerLinkSpeed
    #                                 Invoke-Command -Computername $Using:ServerName -ScriptBlock { cmd /c "C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -listen:$Using:ServerIP -protocol:udp -bitspersecond:40000000 -framerate:100 -streamlength:10 -consoleverbosity:1 -TimeLimit:10000 2>&1 -Buffer:1000000" }
    #                             }
                                
    #                             Start-Sleep 1

    #                             $ClientOutput = Invoke-Command -Computername $ClientName -ScriptBlock { cmd /c "C:\cmd\tools\CTS-Traffic\ctsTraffic.exe -target:$Using:ServerIP -bind:$Using:ClientIP -protocol:udp -bitspersecond:40000000 -framerate:100 -streamlength:10 -consoleverbosity:1 -connections:64 -iterations:1 -Buffer:1000000 2>&1" }
        
    #                             Start-Sleep 3
                                
    #                             $ServerOutput = Receive-Job $ServerOutput
    #                             $FlatServerOutput = @()
    #                             $FlatClientOutput = @()
    #                             $ServerOutput[20..($ServerOutput.Count-2)] | ForEach-Object {If ($_ -ne "") {$FlatServerOutput += ($_ -split '\D+' | Sort-Object -Unique)}}
    #                             $ClientOutput[20..($ClientOutput.Count-10)] | ForEach-Object {If ($_ -ne "") {$FlatClientOutput += ($_ -split '\D+' | Sort-Object -Unique)}}
    #                             $FlatServerOutput = ForEach($num in $FlatServerOutput) {if ($num -ne "") {[Long]::Parse($num)}} 
    #                             $FlatClientOutput = ForEach($num in $FlatClientOutput) {if ($num -ne "") {[Long]::Parse($num)}}

    #                             $ServerRecvBps = ($FlatServerOutput | Measure-Object -Maximum).Maximum
    #                             $ClientRecvBps = ($FlatClientOutput | Measure-Object -Maximum).Maximum
    #                             $Success = ($ServerRecvBps -gt $ServerLinkSpeed * .5) -and ($ClientRecvBps -gt $ClientLinkSpeed * .5)
    #                             Write-Host "Server RevBps: $ServerRecvBps, Client Bps: $ClientRecvBps`r`n"

    #                             Write-Host "UDP CTS Traffic Server Output: "
    #                             Write-Host ($ServerOutput -match "SuccessfulConnections")
    #                             $ServerOutput[($ServerOutput.Count-1)..$ServerOutput.Count] | ForEach-Object {Write-Host $_}
    #                             Write-Host "`r`n"
    #                             "UDP CTS Traffic Server Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             ($ServerOutput -match "SuccessfulConnections") | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             $ServerOutput[($ServerOutput.Count-1)..$ServerOutput.Count] | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
    #                             "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
        
    #                             Write-Host "UDP CTS Traffic Client Output: "
    #                             Write-Host ($ClientOutput -match "SuccessfulConnections")
    #                             $ClientOutput[($ClientOutput.Count-6)..$ClientOutput.Count] | ForEach-Object {Write-Host $_}
    #                             Write-Host "`r`n"
    #                             "UDP CTS Traffic Client Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             ($ClientOutput -match "SuccessfulConnections") | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             $ClientOutput[($ClientOutput.Count-6)..$ClientOutput.Count] | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
    #                             "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                             $Success | Should Be $True
    #                         }
    #                     }
    #                 }
    #             }
    #             Write-Host "####################################`r`n"
    #             "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #         }
    #     }
    # }
    

    # ####################################
    # # Test Machines for NDK Ping Capability
    # ####################################

    # Context "Basic RDMA Connectivity Test (NDK Ping)`r`n" {
    #     Write-Host "####################################`r`n"
    #     Write-Host "VERBOSE: Testing Connectivity Stage 5: NDK Ping`r`n"
    #     Write-Host "####################################`r`n"
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "VERBOSE: Testing Connectivity Stage 5: NDK Ping`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    
    #     $TestNetwork | ForEach-Object {
    
    #         Write-host "VERBOSE: Testing NDK Ping Connectivity on Machine: $($_.Name)"
    #         "VERBOSE: Testing NDK Ping Connectivity on Machine: $($_.Name)" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #         $ServerNetworkNode = $_
    #         $ServerName = $_.Name
    
    #         $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled
    
    #         $ServerRdmaInterfaceList | where VLAN -ne 0 | ForEach-Object {
    
    #             Write-Host "VERBOSE: Testing NDK Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
    #             "VERBOSE: Testing NDK Ping Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                
    #             $ServerIP = $_.IpAddress
    #             $ServerIF = $_.IfIndex
    #             $ServerSubnet = $_.Subnet
    #             $ServerVLAN = $_.VLAN
    
    #             $TestNetwork | ForEach-Object {
    
    #                 $ClientNetworkNode = $_
    #                 $ClientName = $_.Name
    
    #                 $ClientRdmaInterfaceList = $ClientNetworkNode.InterfaceListStruct.Values | where Name -In $ClientNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled
    
    #                 $ClientRdmaInterfaceList | where VLAN -ne 0 | ForEach-Object {
    
    #                     $ClientIP = $_.IpAddress
    #                     $ClientIF = $_.IfIndex
    #                     $ClientSubnet = $_.Subnet
    #                     $ClientVLAN = $_.VLAN
    
    #                     if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And $TestInterface.Status) {
                            
    #                         Write-Host "`r`n##################################################`r`n"
    #                         "`r`n##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
                            
    #                         It "Basic RDMA Connectivity Test -- Verify Basic Rdma Connectivity: Client $ClientIP to Server $ServerIP" {
                                
    #                             $ServerSuccess = $False
    #                             $ClientSuccess = $False
    #                             Write-Host "Server $ServerName CMD: NdkPing -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5`r`n"
    #                             "Server $ServerName CMD: NdkPing -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             Write-Host "Client $ClientName CMD: NdkPing -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
    #                             "Client $ClientName CMD: NdkPing -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
        
    #                             $ServerOutput = Start-Job -ScriptBlock {
    #                                 $ServerIP = $Using:ServerIP
    #                                 $ServerIF = $Using:ServerIF
    #                                 Invoke-Command -Computername $Using:ServerName -ScriptBlock { cmd /c "NdkPing -S -ServerAddr $($Using:ServerIP):9000  -ServerIf $Using:ServerIF -TestType rping -W 5 2>&1" }
    #                             }
    #                             Start-Sleep -Seconds 1
    #                             $ClientOutput = Invoke-Command -Computername $ClientName -ScriptBlock { cmd /c "NdkPing -C -ServerAddr  $($Using:ServerIP):9000 -ClientAddr $Using:ClientIP -ClientIf $Using:ClientIF -TestType rping 2>&1" }
    #                             Start-Sleep -Seconds 5
        
    #                             $ServerOutput = Receive-Job $ServerOutput
                            
    #                             Write-Host "NDK Ping Server Output: "
    #                             $ServerOutput | ForEach-Object {$ServerSuccess = $_ -match 'completes';Write-Host $_}
    #                             Write-Host "`r`n"

    #                             "NDK Ping Server Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             $ServerOutput | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
    #                             "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
        
    #                             Write-Host "NDK Ping Client Output: "
    #                             $ClientOutput[0..($ClientOutput.Count-4)] | ForEach-Object {$ClientSuccess = $_ -match 'completes';Write-Host $_}
    #                             "NDK Ping Client Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             $ClientOutput | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
    #                             Write-Host "`r`n##################################################`r`n"
    #                             "`r`n##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                             $Success = $ServerSuccess -and $ClientSuccess
    #                             $Success | Should Be $True
    #                         }
    #                     }
    #                 }
    #             }
    #         }
    #     }
    # }
    

    # ###################################
    # # Test Machines for NDK Perf Capability
    # ###################################
    
    # Context "1:1 RDMA Congestion Test (NDK Perf)`r`n" {
        
    #     Write-Host "####################################`r`n"
    #     Write-Host "VERBOSE: Testing Connectivity Stage 6: NDK Perf`r`n"
    #     Write-Host "####################################`r`n"
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "VERBOSE: Testing Connectivity Stage 6: NDK Perf`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 


    #     $TestNetwork | ForEach-Object {

    #         Write-Host "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)"
    #         "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #         $ServerNetworkNode = $_
    #         $ServerName = $_.Name

    #         $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled

    #         $ServerRdmaInterfaceList | where VLAN -ne 0 | ForEach-Object {

    #             Write-Host "VERBOSE: Testing NDK Perf Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
    #             "VERBOSE: Testing NDK Perf Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #             $ServerIP = $_.IpAddress
    #             $ServerIF = $_.IfIndex
    #             $ServerSubnet = $_.Subnet
    #             $ServerVLAN = $_.VLAN

    #             $TestNetwork | ForEach-Object {

    #                 $ClientNetworkNode = $_
    #                 $ClientName = $_.Name
                    
    #                 $ClientRdmaInterfaceList = $ClientNetworkNode.InterfaceListStruct.Values | where Name -In $ClientNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled

    #                 $ClientRdmaInterfaceList | where VLAN -ne 0 | ForEach-Object {

    #                     $ClientIP = $_.IpAddress
    #                     $ClientIF = $_.IfIndex
    #                     $ClientSubnet = $_.Subnet
    #                     $ClientVLAN = $_.VLAN

    #                     if (($ServerIP -NotLike $ClientIP) -And ($ServerSubnet -Like $ClientSubnet) -And ($ServerVLAN -Like $ClientVLAN) -And $TestInterface.Status) {

    #                         Write-Host "`r`n##################################################`r`n"
    #                         "`r`n##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                         It "1:1 RDMA Congestion Test -- Stress RDMA Transaction Between Two Singular NICs: Client $ClientIP to Server $ServerIP" {
                                
    #                             $ServerSuccess = $False
    #                             $ClientSuccess = $False
    #                             Start-Sleep -Seconds 1

    #                             Write-Host "Server $ServerName CMD: C:\perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5`r`n"
    #                             "Server $ServerName CMD: C:\perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):9000  -ServerIf $ServerIF -TestType rping -W 5`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             Write-Host "Client $ClientName CMD: C:\perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
    #                             "Client $ClientName CMD: C:\perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):9000 -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                             $ServerOutput = Start-Job -ScriptBlock {
    #                                 $ServerIP = $Using:ServerIP
    #                                 $ServerIF = $Using:ServerIF
    #                                 Invoke-Command -Computername $Using:ServerName -ScriptBlock { cmd /c "C:\perf\NDKPerfCmd.exe -S -ServerAddr $($Using:ServerIP):9000  -ServerIf $Using:ServerIF -TestType rping -W 5 2>&1" }
    #                             }
    #                             Start-Sleep -Seconds 1
                                
    #                             $ClientOutput = Invoke-Command -Computername $ClientName -ScriptBlock { cmd /c "C:\perf\NDKPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):9000 -ClientAddr $Using:ClientIP -ClientIf $Using:ClientIF -TestType rping 2>&1" }
                                
    #                             Start-Sleep -Seconds 5
                                
    #                             $ServerOutput = Receive-Job $ServerOutput
                                
    #                             Write-Host "NDK Perf Server Output: "
    #                             $ServerOutput | ForEach-Object {$ServerSuccess = $_ -match 'completes';Write-Host $_}
    #                             Write-Host "`r`n"
    #                             "NDK Perf Server Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             $ServerOutput | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
    #                             "`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                             Write-Host "NDK Perf Client Output: "
    #                             $ClientOutput[0..($ClientOutput.Count-4)] | ForEach-Object {$ClientSuccess = $_ -match 'completes';Write-Host $_}
    #                             "NDK Perf Client Output: "| Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                             $ClientOutput | ForEach-Object {$_ | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8}
    #                             Write-Host "`r`n##################################################`r`n"
    #                             "`r`n##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                             $Success = $ServerSuccess -and $ClientSuccess
    #                             $Success | Should Be $True
    #                         }
    #                     }
    #                 }
    #             }
    #         }
    #     }
    # }
    

    # ###################################
    # # Test Machines for NDK Perf (N to 1) Capability
    # ###################################

    # Context "(N:1) RDMA Congestion Test (NDK Perf)`r`n" {
    #     Write-Host "####################################`r`n"
    #     Write-Host "VERBOSE: Testing Connectivity Stage 7: NDK Perf (N : 1)`r`n"
    #     Write-Host "####################################"
    #     "####################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "VERBOSE: Testing Connectivity Stage 7: NDK Perf (N : 1)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 
    #     "####################################" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8 

    #     $TestNetwork | ForEach-Object {

    #         "VERBOSE: Testing NDK Perf Connectivity on Machine: $($_.Name)" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #         $ServerNetworkNode = $_
    #         $ServerName = $_.Name

    #         $ServerRdmaInterfaceList = $ServerNetworkNode.InterfaceListStruct.Values | where Name -In $ServerNetworkNode.RdmaNetworkAdapters.Name | where RdmaEnabled

    #         $ServerRdmaInterfaceList | where VLAN -ne 0 | ForEach-Object {
            
    #             Write-Host "VERBOSE: Testing NDK Perf N:1 Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n"
    #             "VERBOSE: Testing NDK Perf N:1 Connectivity for Subnet: $($_.Subnet) and VLAN: $($_.VLAN)`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #             $ServerIP = $_.IpAddress
    #             $ServerIF = $_.IfIndex
    #             $ServerSubnet = $_.Subnet
    #             $ServerVLAN = $_.VLAN

    #             $ClientNetwork = $TestNetwork | where Name -ne $ServerName

    #             for ($i = 0; $i -lt $MachineCluster.Count - 1; $i++) {
                    
    #                 $RandomClientNodes = If ($ClientNetwork.Count -eq 1) { $ClientNetwork[0] } Else { $ClientNetwork[0..$i] }
    #                 $j = 0

    #                 $ServerOutput = @()
    #                 $ClientOutput = @()
                    
    #                 It "(N:1) RDMA Congestion Test (Client $ClientIP to Server $ServerIP)`r`n" {

    #                     $ServerSuccess = $false
    #                     $ClientSuccess = $false
    #                     $RandomClientNodes | ForEach-Object {

    #                         Start-Sleep -Seconds 1
                        
    #                         $ClientName = $_.Name
    #                         $ClientInterface = $_.InterfaceListStruct.Values | where Name -In $_.RdmaNetworkAdapters.Name | where Subnet -Like $ServerSubnet | where VLAN -Like $ServerVLAN
    #                         $ClientIP = $ClientInterface.IpAddress
    #                         $ClientIF = $ClientInterface.IfIndex
                            
    #                         Write-Host "Server $ServerName CMD: C:\perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):900$j  -ServerIf $ServerIF -TestType rping -W 5`r`n"
    #                         "Server $ServerName CMD: C:\perf\NDKPerfCmd.exe -S -ServerAddr $($ServerIP):900$j  -ServerIf $ServerIF -TestType rping -W 5`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                         Write-Host "Client $($_.Name) CMD: C:\perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n"
    #                         "Client $($_.Name) CMD: C:\perf\NDKPerfCmd.exe -C -ServerAddr  $($ServerIP):900$j -ClientAddr $ClientIP -ClientIf $ClientIF -TestType rping`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                         $ServerOutput += Start-Job -ScriptBlock {
    #                             $ServerIP = $Using:ServerIP
    #                             $ServerIF = $Using:ServerIF
    #                             $j = $Using:j
    #                             Invoke-Command -Computername $Using:ServerName -ScriptBlock { cmd /c "C:\perf\NdkPerfCmd.exe -S -ServerAddr $($Using:ServerIP):900$Using:j  -ServerIf $Using:ServerIF -TestType rping -W 5 2>&1" }
    #                         }

    #                         Start-Sleep -Seconds 1

    #                         $ClientOutput += Start-Job -ScriptBlock {
    #                             $ServerIP = $Using:ServerIP
    #                             $ClientIP = $Using:ClientIP
    #                             $ClientIF = $Using:ClientIF
    #                             $j = $Using:j
    #                             Invoke-Command -Computername $Using:ClientName -ScriptBlock { cmd /c "C:\perf\NdkPerfCmd.exe -C -ServerAddr  $($Using:ServerIP):900$Using:j -ClientAddr $($Using:ClientIP) -ClientIf $($Using:ClientIF) -TestType rping 2>&1" }
    #                         }
    #                         Start-Sleep -Seconds 1
    #                         $j++
    #                     }
                        
    #                     Start-Sleep -Seconds 10
    #                     Write-Host "##################################################`r`n"
    #                     "##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                     $ServerOutput | ForEach-Object {
    #                         $job = Receive-Job $_
    #                         Write-Host $job
    #                         Write-Host ($job -match "completes" > 0)
    #                         $job | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                     }
    #                     Write-Host "`r`n##################################################`r`n"
    #                     "`r`n##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                     $ClientOutput | ForEach-Object {
    #                         $job = Receive-Job $_
    #                         Write-Host $job

    #                         Write-Host ($job -match "completes" > 0)
    #                         $job | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8
    #                     }
    #                     Write-Host "`r`n##################################################`r`n"
    #                     "`r`n##################################################`r`n" | Out-File 'C:\cmd\Test-RDMA-Output.txt' -Append -Encoding utf8

    #                     $Success = $ServerSuccess -and $ClientSuccess
    #                     $Success | Should Be $True    
    #                 }

    #             }

    #         }

    #     }

    # }
}