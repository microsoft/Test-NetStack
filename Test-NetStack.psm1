using module .\helpers\prerequisites.psm1
using module .\helpers\internal.psm1
using module .\helpers\icmp.psm1
using module .\helpers\udp.psm1
using module .\helpers\tcp.psm1
using module .\helpers\ndk.psm1

Function Test-NetStack {
    <#
    .SYNOPSIS
        <TODO>

    .DESCRIPTION
        <TODO>

    .PARAMETER Node
        Specifies the machines to test
        - The local machine is the source for non-congestion/stress tests
        - Congestion/stress tests require a failover cluster to ensure common credentials - No credentials are stored/entered into Test-NetStack
        - Minimum of 2 nodes required if specified
        - Optional if a member of a failover cluster; required otherwise

        If part of a failover cluster, and neither the IPTarget or Node parameters are specified, all paths will be tested
        between this node and other nodes in the failover cluster

    .PARAMETER Stage
        List of stages that specifies the tests to be run by Test-NetStack. By default, all stages will be run.

        Tests will always occur in order of lowest stage first and it is highly recommended
        that you run all preceeding tests as they are built upon one another.

        Currently included stages for Test-NetStack:
            Stage 1: Connectivity and PMTUD Verification (ICMP)
            Stage 2: Reliability Calculation (ICMP)
            Stage 3: TPUT Stress (TCP)
            Stage 4: 1:1 RDMA Connectivity (NDK)
            Stage 5: 1:1 RDMA Stress (NDK)
            Stage 6: N:1 RDMA Congestion (NDK)

    .EXAMPLE 4-node test Synthetic and Hardware Data Path
        Test-NetStack -MachineList 'AzStackHCI01', 'AzStackHCI02', 'AzStackHCI03', AzStackHCI04'

    .EXAMPLE Synthetic Tests Only
        Test-NetStack -MachineList 'AzStackHCI01', 'AzStackHCI02' -Stage 4

    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-NetStack

    .LINK
        More projects               : https://github.com/microsoft/sdn
        Windows Networking Blog     : https://blogs.technet.microsoft.com/networking/
        RDMA Configuration Guidance : https://aka.ms/ConvergedNIC
    #>

    [CmdletBinding(DefaultParameterSetName = 'FullNodeMap')]
    param (
        [Parameter(Mandatory=$false, ParameterSetName='FullNodeMap', position = 0)]
        [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'DNS'})]
        [ValidateCount(2, 16)]
        [String[]] $Nodes,

        [Parameter(Mandatory=$false, ParameterSetName='IPAddress', position = 1)]
        [ValidateCount(2, 16)]
        [IPAddress[]] $IPTarget,

        [Parameter(Mandatory=$false)]
        [ValidateSet('1', '2', '3', '4', '5', '6')]
        [Int32[]] $Stage = @('1', '2', '3', '4', '5', '6')
    )

    Clear-Host
    <#
    $here = Split-Path -Parent (Get-Module -Name Test-NetStack | Select-Object -First 1).Path
    $global:Log = New-Item -Name 'Results.log' -Path "$here\Results" -ItemType File -Force
    $startTime = Get-Date -format:'yyyyMMdd-HHmmss' | Out-File $log

    $global:fail = 'FAIL'
    $global:testsFailed = 0
    #>

    # Call Prerequisites

    # Each stages adds their results to this and is eventually returned by this function
    $NetStackResults = New-Object -TypeName psobject

    #region Connectivity Maps
    if ($Nodes) { $Mapping = Get-ConnectivityMapping -Nodes $Nodes }
    else        { $Mapping = Get-ConnectivityMapping -IPTarget $IPTarget }

    $TestableNetworks     = Get-TestableNetworksFromMapping     -Mapping $Mapping
    $DisqualifiedNetworks = Get-DisqualifiedNetworksFromMapping -Mapping $Mapping

    # If at least one note property doesn't exist, then no disqualified networks were identified
    if (($DisqualifiedNetworks | Get-Member -MemberType NoteProperty).Count) {
        $NetStackResults | Add-Member -MemberType NoteProperty -Name DisqualifiedNetworks -Value $DisqualifiedNetworks
    }
    else { Remove-Variable -Name DisqualifiedNetworks -ErrorAction SilentlyContinue }

    if ($TestableNetworks) { $NetStackResults | Add-Member -MemberType NoteProperty -Name TestableNetworks -Value $TestableNetworks }
    else { throw 'No Testable Networks Found' }
    #endregion Connectivity Maps

    # Get the IPs on the local system so you can avoid invoke-command
    #$localIPs = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast).IPAddress

    # Defines the stage requirements - internal.psm1
    $Definitions = [Analyzer]::new()
    Switch ( $Stage | Sort-Object ) {
        '1' { # Connectivity and PMTUD

            Write-Host "Beginning Stage 1 - Connectivity and PMTUD - $([System.DateTime]::Now)"

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PWD -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $Max = [int]$env:NUMBER_OF_PROCESSORS * 2
            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Max, $ISS, $host)
            $RunspacePool.Open()

            $AllJobs = @()
            $StageResults = @()

            if ($IPTarget) {
                foreach ($thisSource in $Mapping) {
                    $targets = $Mapping -ne $thisSource
                    $thisComputerName = (Resolve-DnsName -Name $thisSource -DnsOnly).NameHost.Split('.')[0]

                    $thisSourceResult = @()
                    $targets | ForEach-Object {
                        $thisTarget = $_

                        $PowerShell = [powershell]::Create()
                        $PowerShell.RunspacePool = $RunspacePool

                        [void] $PowerShell.AddScript({
                            param ( $thisComputerName, $thisSource, $thisTarget, $localIPs, $Definitions )

                            if ($thisSource -in $localIPs) {
                                $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource -Destination $thisTarget
                            }
                            else {
                                $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                   -ArgumentList $thisSource, $thisTarget `
                                                                   -ScriptBlock  ${Function:\Invoke-ICMPPMTUD}
                            }

                            $Result = New-Object -TypeName psobject
                            $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisComputerName
                            $Result | Add-Member -MemberType NoteProperty -Name Source         -Value $thisSource
                            $Result | Add-Member -MemberType NoteProperty -Name Destination    -Value $thisTarget
                            $Result | Add-Member -MemberType NoteProperty -Name Connectivity -Value $thisSourceResult.Connectivity
                            $Result | Add-Member -MemberType NoteProperty -Name MTU -Value $thisSourceResult.MTU
                            $Result | Add-Member -MemberType NoteProperty -Name MSS -Value $thisSourceResult.MSS

                            if ($thisSource -in $localIPs) {
                                $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource -Destination $thisTarget -StartBytes $thisSourceMSS -Reliability
                            }
                            else {
                                $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                   -ArgumentList $thisSource, $thisTarget, $thisSourceResult.MSS , $null, $true `
                                                                   -ScriptBlock ${Function:\Invoke-ICMPPMTUD}
                            }

                            $TotalSent   = $thisSourceResult.Count
                            $TotalFailed = ($thisSourceResult -eq '-1').Count
                            $SuccessPercentage = ([Math]::Round((100 - (($TotalFailed / $TotalSent) * 100)), 2))

                            $Result | Add-Member -MemberType NoteProperty -Name TotalSent   -Value $TotalSent
                            $Result | Add-Member -MemberType NoteProperty -Name TotalFailed -Value $TotalFailed
                            $Result | Add-Member -MemberType NoteProperty -Name Reliability -Value $SuccessPercentage

                            # -1 (no response) will be ignored for LAT and JIT
                            $Latency = Get-Latency -RoundTripTime ($thisSourceResult -ne -1)
                            $Jitter  = Get-Jitter  -RoundTripTime ($thisSourceResult -ne -1)

                            $Result | Add-Member -MemberType NoteProperty -Name Latency -Value $Latency
                            $Result | Add-Member -MemberType NoteProperty -Name Jitter -Value $Jitter

                            #TODO: Check if stage value is passed into the runspace; otherwise this section may be broken
                            if ($TotalSent         -ge $Definitions.Reliability.ICMPSent        -and
                                $SuccessPercentage -ge $Definitions.Reliability.ICMPReliability -and
                                $PacketLoss        -le $Definitions.Reliability.ICMPPacketLoss  -and
                                $Latency           -le $Definitions.Reliability.ICMPLatency  -and
                                $Jitter            -le $Definitions.Reliability.ICMPJitter) {
                                $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass'
                            }
                            else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' } #TODO: Update this with specific failure reasons

                            return $Result
                        })

                        $param = @{
                            thisComputerName = $thisComputerName
                            thisSource  = $thisSource
                            thisTarget  = $thisTarget
                            localIPs    = $localIPs
                            Definitions = $Definitions
                        }

                        [void] $PowerShell.AddParameters($param)

                        Write-Host ":: $([System.DateTime]::Now) :: [Started] $thisSource -> $thisTarget"
                        $asyncJobObj = @{ JobHandle   = $PowerShell
                                          AsyncHandle = $PowerShell.BeginInvoke() }

                        $AllJobs += $asyncJobObj
                        #Remove-Variable Result -ErrorAction SilentlyContinue
                    }
                }
            }
            elseif ($Nodes) {
                $TestableNets | ForEach-Object {
                    $thisTestableNet = $_

                    $thisTestableNet.Group | ForEach-Object {
                        $thisSource = $_
                        $thisSourceResult = @()

                        $thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | ForEach-Object {
                            $thisTarget = $_

                            $PowerShell = [powershell]::Create()
                            $PowerShell.RunspacePool = $RunspacePool

                            [void] $PowerShell.AddScript({
                                param ( $thisComputerName, $thisSource, $thisTarget, $localIPs, $Definitions )

                                if ($thisSource -in $localIPs) {
                                    $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource -Destination $thisTarget
                                }
                                else {
                                    $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                       -ArgumentList $thisSource, $thisTarget `
                                                                       -ScriptBlock  ${Function:\Invoke-ICMPPMTUD}
                                }

                                $Result = New-Object -TypeName psobject
                                $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisComputerName
                                $Result | Add-Member -MemberType NoteProperty -Name Source         -Value $thisSource
                                $Result | Add-Member -MemberType NoteProperty -Name Destination    -Value $thisTarget
                                $Result | Add-Member -MemberType NoteProperty -Name Connectivity -Value $thisSourceResult.Connectivity
                                $Result | Add-Member -MemberType NoteProperty -Name MTU -Value $thisSourceResult.MTU
                                $Result | Add-Member -MemberType NoteProperty -Name MSS -Value $thisSourceResult.MSS

                                if ($thisSource -in $localIPs) {
                                    $thisSourceResult = Invoke-ICMPPMTUD -Source $thisSource -Destination $thisTarget -StartBytes $thisSourceMSS -Reliability
                                }
                                else {
                                    $thisSourceResult = Invoke-Command -ComputerName $thisComputerName `
                                                                       -ArgumentList $thisSource, $thisTarget, $thisSourceResult.MSS , $null, $true `
                                                                       -ScriptBlock ${Function:\Invoke-ICMPPMTUD}
                                }

                                $TotalSent   = $thisSourceResult.Count
                                $TotalFailed = ($thisSourceResult -eq '-1').Count
                                $SuccessPercentage = ([Math]::Round((100 - (($TotalFailed / $TotalSent) * 100)), 2))

                                $Result | Add-Member -MemberType NoteProperty -Name TotalSent   -Value $TotalSent
                                $Result | Add-Member -MemberType NoteProperty -Name TotalFailed -Value $TotalFailed
                                $Result | Add-Member -MemberType NoteProperty -Name Reliability -Value $SuccessPercentage

                                # -1 (no response) will be ignored for LAT and JIT
                                $Latency = Get-Latency -RoundTripTime ($thisSourceResult -ne -1)
                                $Jitter  = Get-Jitter  -RoundTripTime ($thisSourceResult -ne -1)

                                $Result | Add-Member -MemberType NoteProperty -Name Latency -Value $Latency
                                $Result | Add-Member -MemberType NoteProperty -Name Jitter -Value $Jitter

                                #TODO: Check if stage value is passed into the runspace; otherwise this section may be broken
                                if ($TotalSent         -ge $Definitions.Reliability.ICMPSent        -and
                                    $SuccessPercentage -ge $Definitions.Reliability.ICMPReliability -and
                                    $PacketLoss        -le $Definitions.Reliability.ICMPPacketLoss  -and
                                    $Latency           -le $Definitions.Reliability.ICMPLatency  -and
                                    $Jitter            -le $Definitions.Reliability.ICMPJitter) {
                                    $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass'
                                }
                                else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' } #TODO: Update this with specific failure reasons


                                return $Result
                            })

                            $param = @{
                                thisComputerName = $thisSource.NodeName
                                thisSource  = $thisSource.IPAddress
                                thisTarget  = $thisTarget.IPaddress
                                localIPs    = $localIPs
                                Definitions = $Definitions
                            }

                            [void] $PowerShell.AddParameters($param)

                            Write-Host ":: $([System.DateTime]::Now) :: [Started] ($($thisSource.NodeName)) $($thisSource.IPAddress) -> $($thisTarget.IPAddress)"
                            $asyncJobObj = @{ JobHandle   = $PowerShell
                                              AsyncHandle = $PowerShell.BeginInvoke() }

                            $AllJobs += $asyncJobObj
                            Remove-Variable Result -ErrorAction SilentlyContinue
                        }
                    }
                }
            }

            While ($AllJobs -ne $null) {
                $AllJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                    $thisJob = $_
                    $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                    $thisSourceHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).SourceHostName
                    $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Source
                    $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Destination

                    $AllJobs = $AllJobs -ne $thisJob

                    Write-Host ":: $([System.DateTime]::Now) :: [Completed] ($thisSourceHostName) $($thisSource) -> $($thisTarget)"
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage1 -Value $StageResults

            Write-Host "Completed Stage 1 - Connectivity and PMTUD - $([System.DateTime]::Now)"
        }

        '2' { # TCP CTS Traffic
            Write-Host "Beginning Stage 2 - TCP - $([System.DateTime]::Now)"
            $StageResults = @()

            if ($IPTarget) {
                $NodeList = @()

                foreach ($IPAddress in $IPTarget) {
                    $NodeList += (Resolve-DnsName -Name $IPAddress -DnsOnly).NameHost.Split('.')[0]
                }
                $Nodes = $NodeList

                $Mapping = Get-Connectivity -Nodes $Nodes

                $VLANSupportedNets = $Mapping | Where-Object VLAN -ne 'Unsupported' | Group-Object Subnet, VLAN
                $TestableNets  = $VLANSupportedNets | Where-Object Count -ne 1

                $DisqualifiedByVLANSupport    = $Mapping | Where-Object VLAN -eq 'Unsupported' | Group-Object Subnet, VLAN
                $DisqualifiedByInterfaceCount = $VLANSupportedNets | Where-Object Count -eq 1

                $Disqualified = New-Object -TypeName psobject
                if ($DisqualifiedByVLANSupport) {
                    $Disqualified | Add-Member -MemberType NoteProperty -Name VLAN         -Value $DisqualifiedByVLANSupport
                }

                if ($DisqualifiedByInterfaceCount) {
                    $Disqualified | Add-Member -MemberType NoteProperty -Name OneIntSubnet -Value $DisqualifiedByInterfaceCount
                }

                # These are the disqualified networks and adapters. Will keep this for reporting.
                if ($Disqualified) {
                    $NetStackResults | Add-Member -MemberType NoteProperty -Name Disqualified -Value $Disqualified
                }

                if ($TestableNets) {
                    $NetStackResults | Add-Member -MemberType NoteProperty -Name Testable -Value $TestableNets
                }
                else {
                    $NetStackResults | Add-Member -MemberType NoteProperty -Name Testable -Value 'None Available'

                    Write-Verbose 'No testable networks found'
                    break
                }

                Remove-Variable -Name VLANSupportedNets, Disqualified, DisqualifiedByVLANSupport, DisqualifiedByInterfaceCount -ErrorAction SilentlyContinue
            }

            $TestableNets | ForEach-Object {
                $thisTestableNet = $_

                $thisTestableNet.Group | ForEach-Object {
                    $thisSource = $_
                    $thisSourceResult = @()

                    $thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | ForEach-Object {
                        $thisTarget = $_

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name SourceHostName -Value $thisSource.NodeName
                        $Result | Add-Member -MemberType NoteProperty -Name Source -Value $thisSource.IPAddress
                        $Result | Add-Member -MemberType NoteProperty -Name Destination -Value $thisTarget.IPaddress

                        $thisSourceResult = Invoke-TCP -Receiver $thisSource -Sender $thisTarget

                        $Result | Add-Member -MemberType NoteProperty -Name ReceiverLinkSpeedGbps -Value $thisSourceResult.ReceiverLinkSpeedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name ReceivedGbps -Value $thisSourceResult.ReceivedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name ReceivedPctgOfLinkSpeed -Value $thisSourceResult.ReceivedPctgOfLinkSpeed
                        $Result | Add-Member -MemberType NoteProperty -Name MinExpectedPctgOfLinkSpeed -Value $Definitions.TCPPerf.TPUT
                        $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData

                        $ThroughputPercentageDec = [Double]$Definitions.TCPPerf.TPUT / 100.0
                        $AcceptableThroughput = $thisSourceResult.RawData.MinLinkSpeedBitsPerSecond * $ThroughputPercentageDec

                        $Success = ($thisSourceResult.RawData.ServerRxbps -gt $AcceptableThroughput) -and `
                                    ($thisSourceResult.RawData.ServerTxbps -gt $AcceptableThroughput) -and `
                                    ($thisSourceResult.RawData.ClientRxbps -gt $AcceptableThroughput) -and `
                                    ($thisSourceResult.RawData.ClientTxbps -gt $AcceptableThroughput)

                        if ($Success) { $Result | Add-Member -MemberType NoteProperty -Name LinkStatus -Value 'Pass' }
                        else { $Result | Add-Member -MemberType NoteProperty -Name LinkStatus -Value 'Fail' }

                        $StageResults += $Result
                        Remove-Variable Result -ErrorAction SilentlyContinue
                    }
                }
            }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage2 -Value $StageResults
            Write-Host "Completed Stage 2 - TCP - $([System.DateTime]::Now)"
        }
        '3' {  }
        '4' {  }
        '5' {  }
        '6' {  }
    }

    Return $NetStackResults
}
