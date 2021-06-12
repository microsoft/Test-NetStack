#region Analysis
Class MTU {
    [int] $MSS = '1472'

    MTU () {}
}

Class Reliability {
    # Min # of ICMP packets per path for a reliability test
    [int] $ICMPSent = '2000'

    # Minimum success percentage for a pass
    [int] $ICMPReliability = '90'

    # Minimum success percentage for a pass
    [int] $ICMPPacketLoss = '95'

    # Maximum Milliseconds for a pass
    [int] $ICMPLatency = '3'

    # Maximum jitter
    [Double] $ICMPJitter = '.1'

    Reliability () {}
}

Class TCPPerf {
        # Min TPUT by % of link speed
        [int] $TPUT = '90'

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
    $localIPs = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast).IPAddress

    foreach ($IP in $IPTarget) {
        $thisNode = (Resolve-DnsName -Name $IP -DnsOnly).NameHost.Split('.')[0]

        if ($thisNode) { # Resolution Available
            if ($thisNode -eq $env:COMPUTERNAME) {
                $AdapterIP = Get-NetIPAddress -IPAddress $IP -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred, Invalid, Duplicate |
                    Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState
                
                $NetAdapter = Get-NetAdapter -InterfaceIndex $AdapterIP.InterfaceIndex -ErrorAction SilentlyContinue

                $VMNetworkAdapter = Get-VMNetworkAdapter -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID

                $RDMAAdapter = Get-NetAdapterRdma -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
            }
            else {
                # Do Not use Invoke-Command here. In the current build nested properties are not preserved and become strings
                $AdapterIP = Get-NetIPAddress -IPAddress $IP -CimSession $thisNode -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred |
                                Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState
                
                $NetAdapter = Get-NetAdapter -CimSession $thisNode -InterfaceIndex $AdapterIP.InterfaceIndex -ErrorAction SilentlyContinue
                $VMNetworkAdapter = Get-VMNetworkAdapter -CimSession $thisNode -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID
                $RDMAAdapter = Get-NetAdapterRdma -CimSession $thisNode -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
            }

            $ClusRes = Get-ClusterResource -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where { $_.OwnerGroup -eq 'Cluster Group' -and $_.ResourceType -eq 'IP Address' }
            $ClusterIPs = ($ClustRes | Get-ClusterParameter -ErrorAction SilentlyContinue -Name Address).Value

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

            $NetAdapter = Get-NetAdapter -InterfaceIndex $AdapterIP.InterfaceIndex -ErrorAction SilentlyContinue

            $VMNetworkAdapter = Get-VMNetworkAdapter -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID

            $RDMAAdapter = Get-NetAdapterRdma -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
        }
        else {
            # Do Not use Invoke-Command here. In the current build nested properties are not preserved and become strings
            $AdapterIP = Get-NetIPAddress -CimSession $thisNode -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred |
                            Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

            $NetAdapter = Get-NetAdapter -CimSession $thisNode -InterfaceIndex $AdapterIP.InterfaceIndex -ErrorAction SilentlyContinue
            $VMNetworkAdapter = Get-VMNetworkAdapter -CimSession $thisNode -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID
            $RDMAAdapter = Get-NetAdapterRdma -CimSession $thisNode -Name "*" | Where-Object -FilterScript { $_.Enabled } | Select-Object -ExpandProperty Name
        }

        $ClusRes = Get-ClusterResource -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Where { $_.OwnerGroup -eq 'Cluster Group' -and $_.ResourceType -eq 'IP Address' }
        $ClusterIPs = ($ClustRes | Get-ClusterParameter -ErrorAction SilentlyContinue -Name Address).Value

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
    $UsableNetworks  = $VLANSupportedNets | Where-Object Count -ne 1

    if ($UsableNetworks) { Return $UsableNetworks }
    else { Return 'None Available' }
}

Function Get-DisqualifiedNetworksFromMapping {
    param ( $Mapping )

    $VLANSupportedNets = $Mapping | Where-Object VLAN -ne 'Unsupported' | Group-Object Subnet, VLAN
    $DisqualifiedByInterfaceCount = $VLANSupportedNets | Where-Object Count -eq 1
    $DisqualifiedByVLANSupport    = $Mapping | Where-Object VLAN -eq 'Unsupported' | Group-Object Subnet, VLAN

    $Disqualified = New-Object -TypeName psobject
    if ($DisqualifiedByVLANSupport) {
        $Disqualified | Add-Member -MemberType NoteProperty -Name VLANNotSupported -Value $DisqualifiedByVLANSupport
    }

    if ($DisqualifiedByInterfaceCount) {
        $Disqualified | Add-Member -MemberType NoteProperty -Name OneInterfaceInSubnet -Value $DisqualifiedByInterfaceCount
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

Function Write-LogFile {
    param ( $NetStackResults )
    $NetStackResults.PSObject.Properties | ForEach-Object {
        $_.Name | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        if ($_.Name -like 'DisqualifiedNetworks') {
            $DisqualifiedNetworks = $_
            $DisqualifiedNetworks.Value.PSObject.Properties | ForEach-Object {
                $DisqualificationCategory = $_
                "`r`nDisqualification Category: $($DisqualificationCategory.Name)" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                $DisqualificationCategory.Value | ForEach-Object {
                    $_.Name | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                    $_.Group | ft * | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                }
            }
            "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        } elseif ($_.Name -like 'TestableNetworks') {
            $TestableNetworks = $_
            $TestableNetworks.Value | ForEach-Object {
                $_.Values | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
                $_.Group | ft * | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
            }
            "`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        } elseif ($_.Name -like 'Stage*') {
            $_.Value | Select-Object -Property * -ExcludeProperty RawData | ft * | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        } elseif ($_.Name -like 'ResultsSummary') {
            $_.Value | ft * | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
        }
        "####################################`r`n" | Out-File 'C:\Test-NetStack\Test-NetStack-Output.txt' -Append -Encoding utf8
    }
}
#endregion Helper Functions
