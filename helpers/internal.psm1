#region Analysis
    Class Reliability {
        [int] $ICMPSent = '2000'
        [int] $ICMPReliability = '90'

        Reliability () {}
    }


    # Stuff All Analysis Classes in Here
    Class Analyzer {
        $Reliability = [Reliability]::new()

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
    Function Get-Connectivity {
        param (
            [string[]] $Nodes
        )

        $Mapper = @()
        $Nodes | ForEach-Object {
            $thisNode = $_

            if ($thisNode -eq $env:COMPUTERNAME) {
                $AdapterIP = Get-NetIPAddress -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred, Invalid, Duplicate |
                    Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

                $NetAdapter = Get-NetAdapter -InterfaceIndex $AdapterIP.InterfaceIndex

                $VMNetworkAdapter = Get-VMNetworkAdapter -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID
            }
            else { 
                # Do Not use Invoke-Command here. In the current build nested properties are not preserved and become strings
                $AdapterIP = Get-NetIPAddress -CimSession $thisNode -AddressFamily IPv4 -SuffixOrigin Dhcp, Manual -AddressState Preferred |
                                Select InterfaceAlias, InterfaceIndex, IPAddress, PrefixLength, AddressState

                $NetAdapter = Get-NetAdapter -CimSession $thisNode -InterfaceIndex $AdapterIP.InterfaceIndex
                $VMNetworkAdapter = Get-VMNetworkAdapter -CimSession $thisNode -ManagementOS | Where DeviceID -in $NetAdapter.DeviceID
            }

            Try {
                $ClusterIPs = (Get-ClusterResource | Where { $_.OwnerGroup -eq 'Cluster Group' -and $_.ResourceType -eq 'IP Address' } | Get-ClusterParameter -Name Address).Value
            } Catch {}

            $NodeOutput = @()
            $AdapterIP | ForEach-Object {
                $thisAdapterIP = $_

                $thisAdapterIP | Where IPAddress -NotIn $ClusterIPs | ForEach-Object {
                    $Result = New-Object -TypeName psobject
                    $thisNetAdapter = $NetAdapter | Where InterfaceIndex -eq $_.InterfaceIndex
                    $thisVMNetworkAdapter = $VMNetworkAdapter | Where DeviceID -EQ $thisNetAdapter.DeviceID

                    $Result | Add-Member -MemberType NoteProperty -Name NodeName -Value $thisNode
                    $Result | Add-Member -MemberType NoteProperty -Name InterfaceAlias -Value $_.InterfaceAlias
                    $Result | Add-Member -MemberType NoteProperty -Name InterfaceIndex -Value $_.InterfaceIndex
                    $Result | Add-Member -MemberType NoteProperty -Name IPAddress -Value $_.IPAddress
                    $Result | Add-Member -MemberType NoteProperty -Name PrefixLength -Value $_.PrefixLength
                    $Result | Add-Member -MemberType NoteProperty -Name AddressState -Value $_.AddressState

                    $SubnetMask = Convert-CIDRToMask -PrefixLength $_.PrefixLength
                    $SubNetInInt = Convert-IPv4ToInt -IPv4Address $SubnetMask
                    $IPInInt     = Convert-IPv4ToInt -IPv4Address $_.IPAddress

                    $Network    = Convert-IntToIPv4 -Integer ($SubNetInInt -band $IPInInt)
                    $Subnet     = "$($Network)/$($_.PrefixLength)"

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
                        $VLAN = $thisNetAdapter.VlanID
                        $Result | Add-Member -MemberType NoteProperty -Name VMNetworkAdapterName -Value 'Not Applicable'

                        if ($thisNetAdapter.VlanID) { $VLAN = $thisNetAdapter.VlanID }
                        else { $VLAN = 'Unsupported' } # In this case, the adapter does not support VLANs
                    }
                    
                    $Result | Add-Member -MemberType NoteProperty -Name VLAN -Value $VLAN

                    $NodeOutput += $Result
                }
            }

            Remove-Variable AdapterIP -ErrorAction SilentlyContinue
            
            $Mapper += $NodeOutput
        }

        Return $Mapper
    }

    Function Connect-NetworkMap {
        param (
            [PSCustomObject] $Mapping
        )


    }
#endregion Helper Functions