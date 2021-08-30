#region Analysis
Class MTU {
    [int] $MSS = '1472'

    MTU () {}
}

Class Reliability {
    # Min # of ICMP packets per path for a reliability test
    [int] $ICMPSent = '2000'

    # Minimum success percentage for a pass
    [int] $ICMPReliability = '99'

    # Minimum success percentage for a pass
    [int] $ICMPPacketLoss = '95'

    # Maximum Milliseconds for a pass
    [int] $ICMPLatency = '1.5'

    # Maximum jitter
    [Double] $ICMPJitter = '.1'

    Reliability () {}
}

Class TCPPerf {
        # Min TPUT by % of link speed
        [int] $TPUT = '85'

    TCPPerf () {}
}

Class NDKPerf {
        # Min TPUT by % of link speed
        [int] $TPUT = '90'

    NDKPerf () {}
}


# Stuff All Analysis Classes in Here
Class Analyzer {
    $MTU         = [MTU]::new()
    $Reliability = [Reliability]::new()
    $TCPPerf     = [TCPPerf]::new()
    $NDKPerf     = [NDKPerf]::new()

    Analyzer () {}
}
#endregion Analysis

#region DataTypes
Class InterfaceDetails {
    [string] $Node
    [string] $InterfaceAlias
    [string] $InterfaceIndex
    [String] $IPAddress
    [String] $PrefixLength
    [String] $AddressState

    [String] $Network
    [String] $Subnet
    [String] $SubnetMask
    [String] $VLAN

    [string] $VMNetworkAdapterName
}
#endregion DataTypes

#region Non-Exported Helpers
Function Convert-CIDRToMask {
    param (
        [Parameter(Mandatory = $true)]
        [int] $PrefixLength
    )

    $bitString = ('1' * $prefixLength).PadRight(32, '0')

    [String] $MaskString = @()

    for($i = 0; $i -lt 32; $i += 8){
        $byteString = $bitString.Substring($i,8)
        $MaskString += "$([Convert]::ToInt32($byteString, 2))."
    }

    Return $MaskString.TrimEnd('.')
}

Function Convert-MaskToCIDR {
    param (
        [Parameter(Mandatory = $true)]
        [IPAddress] $SubnetMask
    )

    [String] $binaryString = @()
    $SubnetMask.GetAddressBytes() | ForEach-Object { $binaryString += [Convert]::ToString($_, 2) }

    Return $binaryString.TrimEnd('0').Length
}

Function Convert-IPv4ToInt {
    Param (
        [Parameter(Mandatory = $true)]
        [IPAddress] $IPv4Address
    )

    $bytes = $IPv4Address.GetAddressBytes()

    Return [System.BitConverter]::ToUInt32($bytes,0)
}

Function Convert-IntToIPv4 {
    Param (
        [Parameter(Mandatory = $true)]
        [uint32]$Integer
    )

    $bytes = [System.BitConverter]::GetBytes($Integer)

    Return ([IPAddress]($bytes)).ToString()
}
#endregion Non-Exported Helpers

#region Helper Functions
Function Get-ConnectivityMapping {
    param (
        [string[]] $Nodes,
        [string[]] $IPTarget
   )

    #TODO: Add IP Target disqualification if the addressState not eq not preferred

    $Mapping = @()
    foreach ($IP in $IPTarget) {
        $thisNode = (Resolve-DnsName -Name $IP -DnsOnly).NameHost.Split('.')[0]

        if ($thisNode) { # Resolution Available
            if ($thisNode -eq $env:COMPUTERNAME) {
                $AdapterIP = Get-NetIPAddress -IPAddress $IP -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred, Invalid, Duplicate |
                    Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

                # Remove APIPA
                $AdapterIP = $AdapterIP | Where IPAddress -NotLike '169.254.*'

                $NetAdapter = Get-NetAdapter -InterfaceIndex $AdapterIP.InterfaceIndex

                $VMNetworkAdapter = Get-VMNetworkAdapter -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID

                $RDMAAdapter = Get-NetAdapterRdma -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
            }
            else {
                # Do Not use Invoke-Command here. In the current build nested properties are not preserved and become strings
                $AdapterIP = Get-NetIPAddress -IPAddress $IP -CimSession $thisNode -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred |
                                Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

                # Remove APIPA
                $AdapterIP = $AdapterIP | Where IPAddress -NotLike '169.254.*'

                $NetAdapter = Get-NetAdapter -CimSession $thisNode -InterfaceIndex $AdapterIP.InterfaceIndex
                $VMNetworkAdapter = Get-VMNetworkAdapter -CimSession $thisNode -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID
                $RDMAAdapter = Get-NetAdapterRdma -CimSession $thisNode -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
            }

            $ClusRes = Get-ClusterResource -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where { $_.OwnerGroup -eq 'Cluster Group' -and $_.ResourceType -eq 'IP Address' }
            $ClusterIPs = ($ClusRes | Get-ClusterParameter -ErrorAction SilentlyContinue -Name Address).Value

            $NodeOutput = @()
            foreach ($thisAdapterIP in ($AdapterIP | Where IPAddress -NotIn $ClusterIPs)) {
                $Result = New-Object -TypeName psobject
                $thisNetAdapter = $NetAdapter | Where InterfaceIndex -eq $thisAdapterIP.InterfaceIndex
                $thisVMNetworkAdapter = $VMNetworkAdapter | Where DeviceID -EQ $thisNetAdapter.DeviceID

                $Result | Add-Member -MemberType NoteProperty -Name NodeName -Value $thisNode
                $Result | Add-Member -MemberType NoteProperty -Name InterfaceAlias -Value $thisAdapterIP.InterfaceAlias
                $Result | Add-Member -MemberType NoteProperty -Name InterfaceIndex -Value $thisAdapterIP.InterfaceIndex
                $Result | Add-Member -MemberType NoteProperty -Name IPAddress -Value $thisAdapterIP.IPAddress
                $Result | Add-Member -MemberType NoteProperty -Name PrefixLength -Value $thisAdapterIP.PrefixLength
                $Result | Add-Member -MemberType NoteProperty -Name AddressState -Value $thisAdapterIP.AddressState
                $Result | Add-Member -MemberType NoteProperty -Name InterfaceDescription -Value $thisNetAdapter.InterfaceDescription
                $Result | Add-Member -MemberType NoteProperty -Name LinkSpeed -Value $thisNetAdapter.LinkSpeed

                if ($thisNetAdapter.Name -in $RDMAAdapter) {
                    $Result | Add-Member -MemberType NoteProperty -Name RDMAEnabled -Value $true
                } else {
                    $Result | Add-Member -MemberType NoteProperty -Name RDMAEnabled -Value $false
                }

                $SubnetMask = Convert-CIDRToMask -PrefixLength $thisAdapterIP.PrefixLength
                $SubNetInInt = Convert-IPv4ToInt -IPv4Address $SubnetMask
                $IPInInt     = Convert-IPv4ToInt -IPv4Address $thisAdapterIP.IPAddress

                $Network    = Convert-IntToIPv4 -Integer ($SubNetInInt -band $IPInInt)
                $Subnet     = "$($Network)/$($thisAdapterIP.PrefixLength)"

                $Result | Add-Member -MemberType NoteProperty -Name SubnetMask -Value $SubnetMask
                $Result | Add-Member -MemberType NoteProperty -Name Network -Value $Network
                $Result | Add-Member -MemberType NoteProperty -Name Subnet -Value $Subnet

                if ($thisVMNetworkAdapter) {
                    $Result | Add-Member -MemberType NoteProperty -Name VMNetworkAdapterName -Value $thisVMNetworkAdapter.Name

                    if ($thisVMNetworkAdapter.IsolationSetting.IsolationMode -eq 'VLAN') {
                        $VLAN = $thisVMNetworkAdapter.IsolationSetting.DefaultIsolationID
                    }
                    elseif ($thisVMNetworkAdapter.VlanSetting.OperationMode -eq 'Access') {
                        $VLAN = $thisVMNetworkAdapter.VlanSetting.AccessVlanId
                    }
                    elseif ($thisVMNetworkAdapter.IsolationSetting.IsolationMode -eq 'None' -and
                            $thisVMNetworkAdapter.VlanSetting.OperationMode -eq 'Untagged') {
                            $VLAN = '0'
                    }
                    else { $thisInterfaceDetails.VLAN = 'Unsupported by Test-NetStack' }
                }
                else {
                    $Result | Add-Member -MemberType NoteProperty -Name VMNetworkAdapterName -Value 'Not Applicable'

                    if ($thisNetAdapter.VlanID -in 0..4095) { $VLAN = $thisNetAdapter.VlanID }
                    else { $VLAN = 'Unsupported' } # In this case, the adapter does not support VLANs
                }

                $Result | Add-Member -MemberType NoteProperty -Name VLAN -Value $VLAN

                $NodeOutput += $Result
            }
        }
        else { # No DNS Available; we should never get here if the prerequisites do their job
            throw 'DNS Not available; required for remoting and to identify realistic system expectations.'
        }

        $Mapping += $NodeOutput
        Remove-Variable AdapterIP -ErrorAction SilentlyContinue
        Remove-Variable RDMAAdapter -ErrorAction SilentlyContinue
    }

    foreach ($thisNode in $Nodes) {
        if ($thisNode -eq $env:COMPUTERNAME) {
            $AdapterIP = Get-NetIPAddress -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred, Invalid, Duplicate |
                Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

            # Remove APIPA
            $AdapterIP = $AdapterIP | Where IPAddress -NotLike '169.254.*'

            $NetAdapter = Get-NetAdapter -InterfaceIndex $AdapterIP.InterfaceIndex

            $VMNetworkAdapter = Get-VMNetworkAdapter -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID

            $RDMAAdapter = Get-NetAdapterRdma -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
        }
        else {
            # Do Not use Invoke-Command here. In the current build nested properties are not preserved and become strings
            $AdapterIP = Get-NetIPAddress -CimSession $thisNode -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred |
                            Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

            # Remove APIPA
            $AdapterIP = $AdapterIP | Where IPAddress -NotLike '169.254.*'

            $NetAdapter = Get-NetAdapter -CimSession $thisNode -InterfaceIndex $AdapterIP.InterfaceIndex
            $VMNetworkAdapter = Get-VMNetworkAdapter -CimSession $thisNode -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID
            $RDMAAdapter = Get-NetAdapterRdma -CimSession $thisNode -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
        }

        $ClusRes = Get-ClusterResource -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where { $_.OwnerGroup -eq 'Cluster Group' -and $_.ResourceType -eq 'IP Address' }
        $ClusterIPs = ($ClusRes | Get-ClusterParameter -ErrorAction SilentlyContinue -Name Address).Value

        $NodeOutput = @()
        foreach ($thisAdapterIP in ($AdapterIP | Where IPAddress -NotIn $ClusterIPs)) {
            $Result = New-Object -TypeName psobject
            $thisNetAdapter = $NetAdapter | Where InterfaceIndex -eq $thisAdapterIP.InterfaceIndex
            $thisVMNetworkAdapter = $VMNetworkAdapter | Where DeviceID -EQ $thisNetAdapter.DeviceID

            $Result | Add-Member -MemberType NoteProperty -Name NodeName -Value $thisNode
            $Result | Add-Member -MemberType NoteProperty -Name InterfaceAlias -Value $thisAdapterIP.InterfaceAlias
            $Result | Add-Member -MemberType NoteProperty -Name InterfaceIndex -Value $thisAdapterIP.InterfaceIndex
            $Result | Add-Member -MemberType NoteProperty -Name IPAddress -Value $thisAdapterIP.IPAddress
            $Result | Add-Member -MemberType NoteProperty -Name PrefixLength -Value $thisAdapterIP.PrefixLength
            $Result | Add-Member -MemberType NoteProperty -Name AddressState -Value $thisAdapterIP.AddressState
            $Result | Add-Member -MemberType NoteProperty -Name InterfaceDescription -Value $thisNetAdapter.InterfaceDescription
            $Result | Add-Member -MemberType NoteProperty -Name LinkSpeed -Value $thisNetAdapter.LinkSpeed

            if ($thisNetAdapter.Name -in $RDMAAdapter) {
                $Result | Add-Member -MemberType NoteProperty -Name RDMAEnabled -Value $true
            } else {
                $Result | Add-Member -MemberType NoteProperty -Name RDMAEnabled -Value $false
            }

            $SubnetMask = Convert-CIDRToMask -PrefixLength $thisAdapterIP.PrefixLength
            $SubNetInInt = Convert-IPv4ToInt -IPv4Address $SubnetMask
            $IPInInt     = Convert-IPv4ToInt -IPv4Address $thisAdapterIP.IPAddress

            $Network    = Convert-IntToIPv4 -Integer ($SubNetInInt -band $IPInInt)
            $Subnet     = "$($Network)/$($thisAdapterIP.PrefixLength)"

            $Result | Add-Member -MemberType NoteProperty -Name SubnetMask -Value $SubnetMask
            $Result | Add-Member -MemberType NoteProperty -Name Network -Value $Network
            $Result | Add-Member -MemberType NoteProperty -Name Subnet -Value $Subnet

            if ($thisVMNetworkAdapter) {
                $Result | Add-Member -MemberType NoteProperty -Name VMNetworkAdapterName -Value $thisVMNetworkAdapter.Name

                if ($thisVMNetworkAdapter.IsolationSetting.IsolationMode -eq 'VLAN') {
                    $VLAN = $thisVMNetworkAdapter.IsolationSetting.DefaultIsolationID
                }
                elseif ($thisVMNetworkAdapter.VlanSetting.OperationMode -eq 'Access') {
                    $VLAN = $thisVMNetworkAdapter.VlanSetting.AccessVlanId
                }
                elseif ($thisVMNetworkAdapter.IsolationSetting.IsolationMode -eq 'None' -and
                        $thisVMNetworkAdapter.VlanSetting.OperationMode -eq 'Untagged') {
                        $VLAN = '0'
                }
                else { $thisInterfaceDetails.VLAN = 'Unsupported by Test-NetStack' }
            }
            else {
                $Result | Add-Member -MemberType NoteProperty -Name VMNetworkAdapterName -Value 'Not Applicable'

                if ($thisNetAdapter.VlanID -in 0..4095) { $VLAN = $thisNetAdapter.VlanID }
                else { $VLAN = 'Unsupported' } # In this case, the adapter does not support VLANs
            }

            $Result | Add-Member -MemberType NoteProperty -Name VLAN -Value $VLAN

            $NodeOutput += $Result
        }

        $Mapping += $NodeOutput
        Remove-Variable AdapterIP -ErrorAction SilentlyContinue
        Remove-Variable RDMAAdapter -ErrorAction SilentlyContinue
    }

   Return $Mapping
}

Function Get-TestableNetworksFromMapping {
    param ( $Mapping )

    $VLANSupportedNets = $Mapping | Where-Object VLAN -ne 'Unsupported' | Group-Object Subnet, VLAN
    $UsableNetworks    = $VLANSupportedNets | Where-Object {
        $_.Count -ge 1 -and
        (($_.Group.NodeName | Select-Object -Unique).Count) -eq $($Mapping.NodeName | Select-Object -Unique).Count }

    if ($UsableNetworks) { Return $UsableNetworks }
    else { Return 'None Available' }
}

Function Get-DisqualifiedNetworksFromMapping {
    param ( $Mapping )

    $VLANSupportedNets = $Mapping | Where-Object VLAN -ne 'Unsupported' | Group-Object Subnet, VLAN

    $DisqualifiedByInterfaceCount = $VLANSupportedNets | Where-Object Count -eq 1

    $DisqualifiedByNetworkAsymmetry = $VLANSupportedNets | Where-Object { $_.Count -ge 1 -and
        (($_.Group.NodeName | Select -Unique).Count) -ne $($Mapping.NodeName | Select -Unique).Count }

    $DisqualifiedByVLANSupport    = $Mapping | Where-Object VLAN -eq 'Unsupported' | Group-Object Subnet, VLAN

    $Disqualified = New-Object -TypeName psobject
    if ($DisqualifiedByVLANSupport) {
        $Disqualified | Add-Member -MemberType NoteProperty -Name NoVLANOnInterface -Value $DisqualifiedByVLANSupport
    }

    if ($DisqualifiedByInterfaceCount) {
        $Disqualified | Add-Member -MemberType NoteProperty -Name OneInterfaceInSubnet -Value $DisqualifiedByInterfaceCount
    }

    if ($DisqualifiedByNetworkAsymmetry) {
        $Disqualified | Add-Member -MemberType NoteProperty -Name AsymmetricNetwork -Value $DisqualifiedByNetworkAsymmetry
    }

    Return $Disqualified
}

Function Get-RunspaceGroups {
    param ( $TestableNetworks )
    # create list of all valid source->target pairs
    $allPairs = @()
    $TestableNetworks | ForEach-Object {
        $thisTestableNet = $_
        $thisTestableNet.Group | ForEach-Object {
            $thisSource = $_
            $thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | ForEach-Object {
                $thisTarget = $_
                $thisPair = New-Object -TypeName psobject
                $thisPair | Add-Member -MemberType NoteProperty -Name Source -Value $thisSource
                $thisPair | Add-Member -MemberType NoteProperty -Name Target -Value $thisTarget
                $allPairs += $thisPair
            }
        }
    }

    # build up groups of pairs that can be run simultaneously - no common elements
    $runspaceGroups = @()
    while ($allPairs -ne $null) {
        $allPairs | ForEach-Object {
            $thisPair = $_
            $added = $false
            for ($i = 0; $i -lt $runspaceGroups.Count; $i++) {
                $invalidGroup = $false
                foreach ($pair in $runspaceGroups[$i]) {
                    if (($pair.Source -eq $thisPair.Source) -or ($pair.Target -eq $thisPair.Target) -or ($pair.Source -eq $thisPair.Target) -or ($pair.Target -eq $thisPair.Source)) {
                        $invalidGroup = $true
                    }
                }
                if (!$invalidGroup -and !$added) {
                    $runspaceGroups[$i] += $thisPair
                    $added = $true
                }
            }
            if (!$added) {
                $runspaceGroups += , @($thisPair)
            }
            $allPairs = $allPairs -ne $thisPair
        }
    }

    Return $runspaceGroups
}

Function Get-Jitter {
    <#
    .SYNOPSIS
        This function takes input as a list of roundtriptimes and returns the jitter
    #>

    param (
        [String[]] $RoundTripTime
    )

    0..($RoundTripTime.Count - 1) | ForEach-Object {
        $Iteration = $_

        $Difference = $RoundTripTime[$Iteration] - $RoundTripTime[$Iteration + 1]
        $RTTDif += [Math]::Abs($Difference)
    }

    return ($RTTDif / $RoundTripTime.Count).ToString('.#####')
}

Function Get-Latency {
    <#
    .SYNOPSIS
        This function takes input as a list of roundtriptimes and returns the latency

    .Description
        This function assumes that input is in ms. Since LAT must be > 0 and ICMP only provides ms precision, we normalize 0 to 1s
        This function assumes that all input was successful. Scrub input before sending to this function.
    #>

    param (
        [String[]] $RoundTripTime
    )

    $RTTNormalized = @()
    $RTTNormalized = $RoundTripTime -replace 0, 1
    $RTTNormalized | ForEach-Object { [int] $RTTNumerator = $RTTNumerator + $_ }

    return ($RTTNumerator / $RTTNormalized.Count).ToString('.###')

}


Function Get-Failures {
    param ( $NetStackResults )
    $HostNames = $NetStackResults.TestableNetworks.Group.NodeName | Select-Object -Unique
    $Interfaces = $NetStackResults.TestableNetworks.Group.IPAddress | Select-Object -Unique
    $Failures = New-Object -TypeName psobject
    $NetStackResults.PSObject.Properties | ForEach-Object {
        if ($_.Name -like 'Stage1') {
            $Stage1Results = $_.Value

            $IndividualFailures = @()
            $AllFailures = $Stage1Results | Where-Object PathStatus -eq Fail
            $AllFailures | ForEach-Object {
                $IndividualFailures += "($($_.SourceHostName)) $($_.Source) -> $($_.Destination)"
            }

            $InterfaceFailures = @()
            $Interfaces | ForEach-Object {
                $thisInterface = $_
                $thisInterfaceResults = $Stage1Results | Where-Object Source -eq $thisInterface
                if ($thisInterfaceResults.PathStatus -notcontains "Pass") {
                    $InterfaceFailures += $thisInterface
                }
            }

            $MachineFailures = @()
            $HostNames | ForEach-Object {
                $thisHost = $_
                $thisMachineResults = $Stage1Results | Where-Object SourceHostName -eq $thisHost
                if ($thisMachineResults.PathStatus -notcontains "Pass") {
                    $MachineFailures += $thisHost
                }
            }

            $Stage1Failures = New-Object -TypeName psobject
            $Stage1HadFailures = $false
            if ($IndividualFailures.Count -gt 0) {
                $Stage1Failures | Add-Member -MemberType NoteProperty -Name IndividualFailures -Value $IndividualFailures
                $Stage1HadFailures = $true
            }
            if ($InterfaceFailures.Count -gt 0) {
                $Stage1Failures | Add-Member -MemberType NoteProperty -Name InterfaceFailures -Value $InterfaceFailures
                $Stage1HadFailures = $true
            }
            if ($MachineFailures.Count -gt 0) {
                $Stage1Failures | Add-Member -MemberType NoteProperty -Name MachineFailures -Value $MachineFailures
                $Stage1HadFailures = $true
            }
            if ($Stage1HadFailures) {
                $Failures | Add-Member -MemberType NoteProperty -Name Stage1 -Value $Stage1Failures
            }
        } elseif (($_.Name -like 'Stage2') -or ($_.Name -like 'Stage3') -or ($_.Name -like 'Stage4')) {
            $StageResults = $_.Value
            $IndividualFailures = @()
            $AllFailures = $StageResults | Where-Object PathStatus -eq Fail
            $AllFailures | ForEach-Object {
                $IndividualFailures += "$($_.Sender) -> $($_.Receiver) ($($_.ReceiverHostName))"
            }

            $InterfaceFailures = @()
            $Interfaces | ForEach-Object {
                $thisInterface = $_
                $thisInterfaceResults = $StageResults | Where-Object Receiver -eq $thisInterface
                if ($thisInterfaceResults.PathStatus -notcontains "Pass") {
                    $InterfaceFailures += $thisInterface
                }
            }

            $MachineFailures = @()
            $HostNames | ForEach-Object {
                $thisHost = $_
                $thisMachineResults = $StageResults | Where-Object ReceiverHostName -eq $thisHost
                if ($thisMachineResults.PathStatus -notcontains "Pass") {
                    $MachineFailures += $thisHost
                }
            }

            $StageFailures = New-Object -TypeName psobject
            $StageHadFailures = $false
            if ($IndividualFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name IndividualFailures -Value $IndividualFailures
                $StageHadFailures = $true
            }
            if ($InterfaceFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name InterfaceFailures -Value $InterfaceFailures
                $StageHadFailures = $true
            }
            if ($MachineFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name MachineFailures -Value $MachineFailures
                $StageHadFailures = $true
            }
            if ($StageHadFailures) {
                $Failures | Add-Member -MemberType NoteProperty -Name $_.Name -Value $StageFailures
            }
        } elseif ($_.Name -like 'Stage5') {
            $StageResults = $_.Value

            $InterfaceFailures = @()
            $Interfaces | ForEach-Object {
                $thisInterface = $_
                $thisInterfaceResults = $StageResults | Where-Object Receiver -eq $thisInterface
                if ($thisInterfaceResults.ReceiverStatus -notcontains "Pass") {
                    $InterfaceFailures += $thisInterface
                }
            }

            $MachineFailures = @()
            $HostNames | ForEach-Object {
                $thisHost = $_
                $thisMachineResults = $StageResults | Where-Object ReceiverHostName -eq $thisHost
                if ($thisMachineResults.ReceiverStatus -notcontains "Pass") {
                    $MachineFailures += $thisHost
                }
            }

            $StageFailures = New-Object -TypeName psobject
            $StageHadFailures = $false
            if ($InterfaceFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name InterfaceFailures -Value $InterfaceFailures
                $StageHadFailures = $true
            }
            if ($MachineFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name MachineFailures -Value $MachineFailures
                $StageHadFailures = $true
            }
            if ($StageHadFailures) {
                $Failures | Add-Member -MemberType NoteProperty -Name $_.Name -Value $StageFailures
            }
        } elseif ($_.Name -like 'Stage6') {
            $StageResults = $_.Value

            $NetworkFailures = @()
            $AllFailures = $StageResults | Where-Object NetworkStatus -eq Fail
            $AllFailures | ForEach-Object {
                $NetworkFailures += "Subnet $($_.subnet) VLAN $($_.VLAN)"
            }

            $StageFailures = New-Object -TypeName psobject
            $StageHadFailures = $false
            if ($NetworkFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name NetworkFailures -Value $NetworkFailures
                $StageHadFailures = $true
            }
            if ($StageHadFailures) {
                $Failures | Add-Member -MemberType NoteProperty -Name $_.Name -Value $StageFailures
            }
        } elseif ($_.Name -like 'Stage7') {
            $StageResults = $_.Value

            $InterfaceFailures = @()
            $Interfaces | ForEach-Object {
                $thisInterface = $_
                $thisInterfaceResults = $StageResults | Where-Object Receiver -eq $thisInterface
                if ($thisInterfaceResults.ReceiverStatus -notcontains "Pass") {
                    $InterfaceFailures += $thisInterface
                }
            }

            $MachineFailures = @()
            $HostNames | ForEach-Object {
                $thisHost = $_
                $thisMachineResults = $StageResults | Where-Object ReceiverHostName -eq $thisHost
                if ($thisMachineResults.ReceiverStatus -notcontains "Pass") {
                    $MachineFailures += $thisHost
                }
            }

            $StageFailures = New-Object -TypeName psobject
            $StageHadFailures = $false
            if ($InterfaceFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name InterfaceFailures -Value $InterfaceFailures
                $StageHadFailures = $true
            }
            if ($MachineFailures.Count -gt 0) {
                $StageFailures | Add-Member -MemberType NoteProperty -Name MachineFailures -Value $MachineFailures
                $StageHadFailures = $true
            }
            if ($StageHadFailures) {
                $Failures | Add-Member -MemberType NoteProperty -Name $_.Name -Value $StageFailures
            }
        }
    }
    Return $Failures
}


Function Write-RecommendationsToLogFile {
    param (
        $NetStackResults,
        $LogFile
    )

    "Failure Recommendations`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    $ModuleBase = (Get-Module Test-NetStack -ListAvailable | Select-Object -First 1).ModuleBase

    $NetStackResults.PSObject.Properties | Where-Object { $_.Name -like 'Stage*' } | ForEach-Object {
        if ($NetStackResults.Failures.PSObject.Properties.Name -contains $_.Name) {
                "$($_.Name) Failure Recommendations`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                switch ($_.Name) {
                'Stage1' {
                    if ($NetStackResults.Failures.Stage1.PSObject.Properties.Name -contains "IndividualFailures") {
                        "Individual Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Connectivity and PMTUD failed across the following connections:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage1.IndividualFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify subnet, VLAN, and MTU settings for relevant NICs." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage1.PSObject.Properties.Name -contains "InterfaceFailures") {
                        "`nInterface Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Connectivity and PMTUD failed across all target NICs for the following source NICs:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage1.InterfaceFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify subnet, VLAN, and MTU settings for relevant NICs. If the problem persists, consider checking NIC cabling or physical interlinks."  | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage1.PSObject.Properties.Name -contains "MachineFailures") {
                        "`nMachine Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Connectivity and PMTUD failed across all target machines for the following source machines:"  | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage1.MachineFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify firewall and MTU settings for the erring machines. If the problem persists, consider checking the machine cabling, NIC cabling, or physical interlinks."  | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
                'Stage2' {
                    if ($NetStackResults.Failures.Stage2.PSObject.Properties.Name -contains "IndividualFailures") {
                        "Individual Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "TCP throughput failed to meet threshold across the following connections:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage2.IndividualFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Retry TCP transaction with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Receiver Repro Command: $ModuleBase\tools\CTS-Traffic\ctsTraffic.exe -listen:<ReceivingNicIP> -Protocol:tcp -buffer:262144 -transfer:21474836480 -Pattern:push -TimeLimit:30000" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Sender Repro Command: $ModuleBase\tools\CTS-Traffic\ctsTraffic.exe -target:<ReceivingNicIP> -bind:<SenderIP> -Connections:64 -Iterations:1 -Protocol:tcp -buffer:262144 -transfer:21474836480 -Pattern:push" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage2.PSObject.Properties.Name -contains "InterfaceFailures") {
                        "`nInterface Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "TCP throughput failed to meet threshold across all source NICs for the following target NICs:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage2.InterfaceFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. Verify firewall settings for the erring machine. If the problem persists, consider checking NIC cabling or physical interlinks."  | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage2.PSObject.Properties.Name -contains "MachineFailures") {
                        "`nMachine Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "TCP throughput failed to meet threshold across all source machines for the following target machines:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage2.MachineFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC provisioning. Inspect VMQ, VMMQ, and RSS settings. If the problem persists, consider checking NIC cabling or physical interlinks."  | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
                'Stage3' {
                    if ($NetStackResults.Failures.Stage3.PSObject.Properties.Name -contains "IndividualFailures") {
                        "Individual Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Ping failed across the following connections:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage3.IndividualFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Retry NDK Ping with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Receiver Repro Command: NdkPerfCmd.exe -S -ServerAddr <ReceivingNicIP>:9000  -ServerIf <ReceivingNicInterfaceIndex> -TestType rping -W 15 2>&1" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Sender Repro Command: NdkPerfCmd.exe -C -ServerAddr  <ReceivingNicIP>:9000 -ClientAddr <SendingNicIP> -ClientIf <SendingNicInterfaceIndex> -TestType rping 2>&1" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage3.PSObject.Properties.Name -contains "InterfaceFailures") {
                        "`nInterface Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Ping failed across all source NICs for the following target NICs:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage3.InterfaceFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC provisioning. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage3.PSObject.Properties.Name -contains "MachineFailures") {
                        "`nMachine Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Ping failed across all source machines for the following target machines:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage3.MachineFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC provisioning. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
                'Stage4' {
                    if ($NetStackResults.Failures.Stage4.PSObject.Properties.Name -contains "IndividualFailures") {
                        "Individual Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Perf (1:1) failed across the following connections:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage4.IndividualFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Retry NDK Perf (1:1) with repro commands. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Receiver Repro Command: NDKPerfCmd.exe -S -ServerAddr <ReceivingNicIP>:9000  -ServerIf <ReceivingNicInterfaceIndex> -TestType rperf -W 20 2>&1" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Sender Repro Command: NDKPerfCmd.exe -C -ServerAddr <ReceivingNicIP>:9000 -ClientAddr <SendingNicIP> -ClientIf <SendingNicInterfaceIndex> -TestType rperf 2>&1" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage4.PSObject.Properties.Name -contains "InterfaceFailures") {
                        "`nInterface Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Perf (1:1) failed across all source NICs for the following target NICs:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage4.InterfaceFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage4.PSObject.Properties.Name -contains "MachineFailures") {
                        "`nMachine Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Perf (1:1) failed across all source machines for the following target machines:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage4.MachineFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
                'Stage5' {
                    if ($NetStackResults.Failures.Stage5.PSObject.Properties.Name -contains "InterfaceFailures") {
                        "Interface Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Perf (N:1) failed for the following target NICs:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage5.InterfaceFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage5.PSObject.Properties.Name -contains "MachineFailures") {
                        "`nMachine Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Perf (N:1) failed across all source machines for the following target machines:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage5.MachineFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC RDMA provisioning and traffic class settings. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
                'Stage6' {
                    if ($NetStackResults.Failures.Stage6.PSObject.Properties.Name -contains "NetworkFailures") {
                        "Network Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "NDK Perf (N:N) failed for networks with the following subnet/VLAN:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage6.NetworkFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC RDMA provisioning and traffic class settings. Consider confirming NIC firmware and drivers, as well. If the problem persists, consider checking NIC cabling or physical interlinks." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
                'Stage7' {
                    if ($NetStackResults.Failures.Stage7.PSObject.Properties.Name -contains "InterfaceFailures") {
                        "Interface Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "RDMA Perf VMSwitch Stress failed for the following target NICs:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage7.InterfaceFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Verify NIC RDMA provisioning and traffic class settings. Confirm NIC firmware, drivers, and check NIC cabling or physical interlinks as well." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                    if ($NetStackResults.Failures.Stage7.PSObject.Properties.Name -contains "MachineFailures") {
                        "`nMachine Failure Recommendations" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "RDMA Perf VMSwitch Stress failed across all source machines for the following target machines:" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        $NetStackResults.Failures.Stage7.MachineFailures | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Check your VMSwitch configuration and verify NIC RDMA provisioning and traffic class settings." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    }
                }
            }
            "`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        }
        "####################################`r`n" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
    }
}
#endregion Helper Functions
