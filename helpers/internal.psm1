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
        # Lowering to 70% while we are still in the tuning phase, return to 90% once we are more confident
        [int] $TPUT = '70'

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
Function Write-LogMessage {
    Param (
        $Message,
        $LogFile
    )
    Write-Host "[$([System.DateTime]::Now)] $Message"
    "[$([System.DateTime]::Now)] $Message" |  Out-File $LogFile -Append -Encoding utf8 -Width 2000
}

# Storage Intent Deployment Status:
#   NotDeployed: Network ATC is not in use - Test-NetStack will test RDMA based on whether RDMA is enabled on a given adapter.
#   DeploymentSuccess: Network ATC has been deployed successfully in a configuration suitable for RDMA testing. Test-NetStack will test RDMA based on whether an adapter belongs to a storage intent.
#   DeploymentFail: Network ATC has been deployed, but was either unsuccessful or the configuration does not support RDMA. Test-NetStack will mark all requested RDMA stages as failures.
enum StorageIntentDeploymentStatus {
    NotDeployed
    DeploymentSuccess
    DeploymentFail
}

# This function will determine:
#   1. Is Network ATC deployed?
#   2. Are all intents successfully deployed?
#   3. Has a storage intent been?
# and return an object containing the cluster name, storage intent, and one of the 3 storage intent deployment statuses to tell the Test-NetStack function how to test RDMA stages.
Function Get-StorageIntentDeploymentStatus {
    param ($LogFile)

    Write-LogMessage -Message "Determining if Network ATC is deployed in a supported configuration" -LogFile $LogFile

    # Create PSObject to store cluster name, storage intent, and deployment status
    $StorageIntentDeployment = New-Object -TypeName psobject
    $StorageIntentDeployment | Add-Member -MemberType NoteProperty -Name ClusterName -Value $null
    $StorageIntentDeployment | Add-Member -MemberType NoteProperty -Name StorageIntent -Value $null
    $StorageIntentDeployment | Add-Member -MemberType NoteProperty -Name DeploymentStatus -Value [StorageIntentDeploymentStatus]::NotDeployed

    # Check for cluster since will need name for Network ATC commands on older builds
    try {
        $ClusterName = Get-Cluster -ErrorAction Stop
        $StorageIntentDeployment.ClusterName = $ClusterName
    }
    catch {
        Write-LogMessage -Message "Warning: Cluster not found. If this is unexpected, please check for errors in cluster deployment. Otherwise, Test-NetStack will continue in standalone mode, and perform a best-effort test of RDMA based on Get-NetAdapterRDMA Enabled property." -LogFile $LogFile
        Return $StorageIntentDeployment
    }

    # If a cluster name was returned, proceed with Network ATC configuration check
    if (-not [String]::IsNullOrEmpty($ClusterName)) {
        try {
            $NetIntentStatusTimeout = 5
            $StartTime = Get-Date
            $EndTime =  (Get-Date).AddMinutes($NetIntentStatusTimeout)
            do {
                # Check for net intent status to determine 1. is Network ATC being used and 2. are all intents successfully deployed
                $NetIntentStatus = Get-NetIntentStatus -ClusterName $ClusterName
                $IntentsContainFailures = ($NetIntentStatus | Where-Object ConfigurationStatus -eq "Failed" | Measure-Object).Count -gt 0
                if ($IntentsContainFailures) {
                    Write-LogMessage -Message "At least one intent failed to be deployed. Please investigate Network ATC configuration. Test-NetStack will mark any requested RDMA stages as failures." -LogFile $LogFile
                    $StorageIntentDeployment.DeploymentStatus = [StorageIntentDeploymentStatus]::DeploymentFail
                    Return $StorageIntentDeployment
                }

                # 'Retrying' status indicates an attempt to recover from a failure, so success is unlikely - bail after only one minute
                $IntentsContainRetrying = ($NetIntentStatus | Where-Object ConfigurationStatus -eq "Retrying" | Measure-Object).Count -gt 0
                if ($IntentsContainRetrying -and ((Get-Date) - $StartTime).TotalSeconds -ge 60) {
                    Write-LogMessage -Message "At least one intent failed to recover from 'Retrying' status after one minute. Please investigate Network ATC configuration. Test-NetStack will mark any requested RDMA stages as failures." -LogFile $LogFile
                    $StorageIntentDeployment.DeploymentStatus = [StorageIntentDeploymentStatus]::DeploymentFail
                    Return $StorageIntentDeployment
                }

                # Statuses such as 'Validating', 'Pending', 'Provisioning', and 'ProvisioningUpdate' have a good chance of resolving on their own - retry status check for up to five minutes
                $AllIntentsSuccessful = ($NetIntentStatus | Where-Object ConfigurationStatus -ne "Success" | Measure-Object).Count -eq 0
                if ($AllIntentsSuccessful -eq $false) {
                    Write-LogMessage -Message "Some intents do not have a successful configuration status. Checking again in 60 seconds to allow temporary statuses to resolve." -LogFile $LogFile
                    $NetIntentStatus | ft * | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                    Sleep 60
                }
            } while ($AllIntentsSuccessful -eq $false -and (Get-Date) -le $EndTime)

            if ($AllIntentsSuccessful -eq $false) {
                Write-LogMessage -Message "Intents not successfully deployed after 5 minutes. Test-NetStack will mark any requested RDMA stages as failures." -LogFile $LogFile
                $StorageIntentDeployment.DeploymentStatus = [StorageIntentDeploymentStatus]::DeploymentFail
                Return $StorageIntentDeployment
            } else {
                Write-LogMessage -Message "All intents deployed successfully." -LogFile $LogFile
            }

        }
        catch {
            # Get-NetIntentStatus will throw an error if Network ATC is not configured, in which case we are here
            Write-LogMessage -Message "Warning: No net intent found. If this is unexpected, please check for errors in Network ATC deployment. Otherwise, Test-NetStack will perform a best-effort test of RDMA based on Get-NetAdapterRDMA Enabled property." -LogFile $LogFile
            Return $StorageIntentDeployment
        }

        # If we've made it to this point, Network ATC is in use and all intents are successfully deployed
        $StorageIntent = Get-NetIntent -ClusterName $ClusterName | Where IsStorageIntentSet -eq $true
        if ($StorageIntent.Count -eq 1) {
            Write-LogMessage -Message "Storage intent set." -LogFile $LogFile
            $StorageIntentDeployment.StorageIntent = $StorageIntent
            $RDMAOverride = (Get-NetIntent -ClusterName $ClusterName).AdapterAdvancedParametersOverride.NetworkDirect
            if ($RDMAOverride -eq $false -or $RDMAOverride -eq 0) {
                Write-LogMessage -Message "RDMA has been disabled with an override. If this is unexpected, please submit an override enabling the Network Direct adapter property. 
                        Otherwise, Test-NetStack will mark any requested RDMA stages as failures.`r
                        To submit override enabling Network Direct:`r
                        `$AdapterOverride = New-NetIntentAdapterPropertyOverrides`r
                        `$AdapterOverride.NetworkDirect = 0`r
                        Set-NetIntent -Name <Intent Name> -AdapterPropertyOverrides `$AdapterOverride -ClusterName <Cluster Name>" -LogFile $LogFile
                $StorageIntentDeployment.DeploymentStatus = [StorageIntentDeploymentStatus]::DeploymentFail
                Return $StorageIntentDeployment
            }
        } else {
            Write-LogMessage -Message "No storage intent set. Test-NetStack will mark any requested RDMA stages as failures." -LogFile $LogFile
            $StorageIntentDeployment.DeploymentStatus = [StorageIntentDeploymentStatus]::DeploymentFail
            Return $StorageIntentDeployment
        }

        # If we've made it to this point, Network ATC is in use, all intents are successfully deployed, and a storage intent is defined
        Write-LogMessage -Message "Network ATC is deployed and successfully configured with a storage intent. Test-NetStack will perform RDMA testing according to net intents." -LogFile $LogFile
        $StorageIntentDeployment.DeploymentStatus = [StorageIntentDeploymentStatus]::DeploymentSuccess
        Return $StorageIntentDeployment
    }
}

Function Get-StorageIntentNICMapping {
    param ($StorageIntentDeployment)

    # Go through output of Get-NetIntentAllGoalStates to determine which adapters are associated with a storage intent, and pNIC/vNIC mapping
    $IntentAllGoalStates = Get-NetIntentAllGoalStates -ClusterName $StorageIntentDeployment.ClusterName
    $NodeNames = (Get-ClusterNode).Name
    $StorageNICMapping = @()
    foreach ($NodeName in $NodeNames) {
        if ($StorageIntentDeployment.StorageIntent.IsOnlyStorage) {
            # If an intent is storage only, no vNICs will be created
            $IntentAllGoalStates.$NodeName.$($StorageIntentDeployment.StorageIntent.IntentName).SwitchConfig.NetAdapters | ForEach-Object {
                $HostNICMapping = New-Object -TypeName psobject
                $HostNICMapping | Add-Member -MemberType NoteProperty -Name NodeName -Value $NodeName
                $HostNICMapping | Add-Member -MemberType NoteProperty -Name pNIC -Value $_.NetAdapterName
                $HostNICMapping | Add-Member -MemberType NoteProperty -Name vNIC -Value $null
                $StorageNICMapping += $HostNICMapping
            }
        } else {
            # If an intent is not storage only, store the pNIC/vNIC mappings
            $IntentAllGoalStates.$NodeName.$($StorageIntentDeployment.StorageIntent.IntentName).SwitchConfig.StorageVirtualNetworkAdapters | ForEach-Object {
                $HostNICMapping = New-Object -TypeName psobject
                $HostNICMapping | Add-Member -MemberType NoteProperty -Name NodeName -Value $NodeName
                $HostNICMapping | Add-Member -MemberType NoteProperty -Name pNIC -Value $_.TeamedPhysicalAdapterName
                $HostNICMapping | Add-Member -MemberType NoteProperty -Name vNIC -Value $_.VmAdapterName
                $StorageNICMapping += $HostNICMapping
            }
        }

    }
    Return $StorageNICMapping
}
Function Get-ConnectivityMapping {
    param (
        [string[]] $Nodes,
        [string[]] $IPTarget,
        $StorageIntentNICMapping
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

            # If we've passed in a storage intent NIC mapping, add a property for StorageIntentSet - this will be how we filter for testing in RDMA stages
            if ($StorageIntentNICMapping.Count -gt 0) {
                if ($thisNetAdapter.Name -in ($StorageIntentNICMapping | Where NodeName -eq $thisNode).pNIC -or $thisNetAdapter.Name -in ($StorageIntentNICMapping | Where NodeName -eq $thisNode).vNIC) {
                    $Result | Add-Member -MemberType NoteProperty -Name StorageIntentSet -Value $true
                } else {
                    $Result | Add-Member -MemberType NoteProperty -Name StorageIntentSet -Value $false
                }
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

Function Get-VDiskStatus {
    param ( $LogFile )

    $UnhealthyDisks = @()
    Write-Host "Getting Virtual Disk Health..."
    "Getting Virtual Disk Health..." | Out-File $LogFile -Append -Encoding utf8 -Width 2000

    Get-VirtualDisk | ForEach-Object {
        if ($_.HealthStatus -eq 'Unhealthy') {
            $UnhealthyDisks += $_.FriendlyName
        } 
    }
    if ($UnhealthyDisks.Length -gt 0) { 
        Write-Host "$($UnhealthyDisks) are unhealthy." 
        "$($UnhealthyDisks) are unhealthy." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        return $true
    }  
    else { 
        Write-Host "All virtual disks are healthy."
        "All virtual disks are healthy." | Out-File $LogFile -Append -Encoding utf8 -Width 2000
        return $false
    }  
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
                        "Receiver Repro Command: $ModuleBase\tools\NTttcp\NTttcp.exe -listen:<ReceivingNicIP> -Protocol:tcp -buffer:262144 -transfer:21474836480 -Pattern:push -TimeLimit:30000" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
                        "Sender Repro Command: $ModuleBase\tools\NTttcp\NTttcp.exe -target:<ReceivingNicIP> -bind:<SenderIP> -Connections:64 -Iterations:1 -Protocol:tcp -buffer:262144 -transfer:21474836480 -Pattern:push" | Out-File $LogFile -Append -Encoding utf8 -Width 2000
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
