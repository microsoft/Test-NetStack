using module .\helpers\prerequisites.psm1
using module .\helpers\internal.psm1
using module .\helpers\icmp.psm1
using module .\helpers\udp.psm1
using module .\helpers\tcp.psm1
using module .\helpers\ndk.psm1

Function Test-NetStack {
    <#
    .SYNOPSIS
        Test-NetStack performs ICMP, TCP, and RDMA traffic testing of networks. Test-NetStack can help you identify misconfigured networks, hotspots, asymmetry across cluster nodes, and more.

    .DESCRIPTION
        Test-NetStack performs ICMP, TCP, and RDMA traffic testing of networks. Test-NetStack can help you identify misconfigured networks, hotspots, asymmetry across cluster nodes, and more.
        Specifically, Test-NetStack:
        - Performs connectivity mapping across a cluster, specific nodes, or IP targets
        - Stage1: ICMP Connectivity, Reliability, and PMTUD
        - Stage2: TCP Stress 1:1
        - Stage3: RDMA Connectivity
        - Stage4: RDMA Stress 1:1
        - Stage5: RDMA Stress N:1
        - Stage6: RDMA Stress N:N

    .PARAMETER Nodes
        - Specifies the machines by DNS Name to test.
        - PowerShell remoting without credentials is required; no credentials are stored or entered into Test-NetStack.
        - Minimum 2 nodes, maximum of 16 nodes.

        If part of a failover cluster, and neither the IPTarget or Node parameters are specified, get-clusternode will be run to attempt to gather nodenames.

    .PARAMETER Stage
        List of stages that specifies the tests to be run by Test-NetStack. By default, all stages will be run.

        Tests will always occur in order of lowest stage first. It is highly recommended that you always run the preceeding tests.

        Currently included stages for Test-NetStack:
        - Stage1: ICMP Connectivity, Reliability, and PMTUD
        - Stage2: TCP Stress 1:1
        - Stage3: RDMA Connectivity
        - Stage4: RDMA Stress 1:1
        - Stage5: RDMA Stress N:1
        - Stage6: RDMA Stress N:N

    .EXAMPLE Run all tests in the local node's failover cluster. Review results from Stage2 and Stage6
        $Results = Test-NetStack

        $Results.Stage2
        $Results.Stage6

    .EXAMPLE 4-domain joined nodes; all tests run
        $Results = Test-NetStack -Nodes 'AzStackHCI01', 'AzStackHCI02', 'AzStackHCI03', AzStackHCI04'

    .EXAMPLE 2-node tests; ICMP and TCP tests only. Review results from Stage1 and Stage2
        $Results = Test-NetStack -MachineList 'AzStackHCI01', 'AzStackHCI02' -Stage 1, 2

        $Results.Stage1
        $Results.Stage2

    .NOTES
        Author: Windows Core Networking team @ Microsoft
        Please file issues on GitHub @ GitHub.com/Microsoft/Test-NetStack

    .LINK
        Networking Blog   : https://aka.ms/MSFTNetworkBlog
        HCI Host Guidance : https://docs.microsoft.com/en-us/azure-stack/hci/deploy/network-atc
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

    $runspaceGroups = Get-RunspaceGroups -TestableNetworks $TestableNetworks

    # Get the IPs on the local system so you can avoid invoke-command
    #$localIPs = (Get-NetIPAddress -AddressFamily IPv4 -Type Unicast).IPAddress

    # Defines the stage requirements - internal.psm1
    $Definitions = [Analyzer]::new()
    
    $ResultsSummary = New-Object -TypeName psobject
    $StageFailures = 0

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
                $TestableNetworks | ForEach-Object {
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

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage1 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage1 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage1 -Value $StageResults

            Write-Host "Completed Stage 1 - Connectivity and PMTUD - $([System.DateTime]::Now)"
        }

        '2' { # TCP CTS Traffic
            Write-Host "Beginning Stage 2 - TCP - $([System.DateTime]::Now)"

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PWD -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $Max = [int]$env:NUMBER_OF_PROCESSORS * 2
            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Max, $ISS, $host)
            $RunspacePool.Open()

            $StageResults = @()
            foreach ($group in $runspaceGroups) {
                $GroupedJobs = @()
                foreach ($pair in $group) {

                    $PowerShell = [powershell]::Create()
                    $PowerShell.RunspacePool = $RunspacePool

                    [void] $PowerShell.AddScript({
                        param ( $thisComputerName, $thisSource, $thisTarget, $localIPs, $Definitions )

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisSource.NodeName
                        $Result | Add-Member -MemberType NoteProperty -Name Sender -Value $thisTarget.IPaddress
                        $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisSource.IPAddress
                        
                        $thisSourceResult = Invoke-TCP -Receiver $thisSource -Sender $thisTarget

                        $Result | Add-Member -MemberType NoteProperty -Name RxLinkSpeedGbps -Value $thisSourceResult.ReceiverLinkSpeedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisSourceResult.ReceivedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxPctgOfLinkSpeed -Value $thisSourceResult.ReceivedPctgOfLinkSpeed
                        $Result | Add-Member -MemberType NoteProperty -Name MinExpectedPctgOfLinkSpeed -Value $Definitions.TCPPerf.TPUT
                        
                        $ThroughputPercentageDec = $Definitions.TCPPerf.TPUT / 100.0
                        $AcceptableThroughput = $thisSourceResult.RawData.MinLinkSpeedbps * $ThroughputPercentageDec

                        if ($thisSourceResult.ReceivedPctgOfLinkSpeed -ge $Definitions.TCPPerf.TPUT) { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass' }
                        else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' }

                        $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData

                        Return $Result
                    })

                    $param = @{
                        thisComputerName = $pair.Source.NodeName
                        thisSource  = $pair.Source
                        thisTarget  = $pair.Target
                        localIPs    = $localIPs
                        Definitions = $Definitions
                    }

                    [void] $PowerShell.AddParameters($param)

                    Write-Host ":: $([System.DateTime]::Now) :: [Started] $($pair.Source.IPAddress) -> ($($pair.Target.NodeName)) $($pair.Target.IPAddress)"
                    $asyncJobObj = @{ JobHandle   = $PowerShell
                                        AsyncHandle = $PowerShell.BeginInvoke() }

                    $GroupedJobs += $asyncJobObj
                }

                While ($GroupedJobs -ne $null) {
                    $GroupedJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                        $thisJob = $_
                        $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                        $thisReceiverHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).ReceiverHostName
                        $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Sender
                        $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Receiver

                        $GroupedJobs = $GroupedJobs -ne $thisJob

                        Write-Host ":: $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)"
                    }
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage2 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage2 -Value 'Pass' }
            
            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage2 -Value $StageResults
            Write-Host "Completed Stage 2 - TCP - $([System.DateTime]::Now)"
        }

        '3' { 
            Write-Host "Beginning Stage 3 - NDK Ping - $([System.DateTime]::Now)"

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PWD -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $Max = [int]$env:NUMBER_OF_PROCESSORS * 2
            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Max, $ISS, $host)
            $RunspacePool.Open()

            $AllJobs = @()
            $StageResults = @()
            $TestableNetworks | ForEach-Object {
                $thisTestableNet = $_

                $thisTestableNet.Group | Where-Object -FilterScript { $_.RDMAEnabled } | ForEach-Object {
                    $thisSource = $_
                    $thisSourceResult = @()
                    
                    $thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | Where-Object -FilterScript { $_.RDMAEnabled } | ForEach-Object {
                        $thisTarget = $_

                        $PowerShell = [powershell]::Create()
                        $PowerShell.RunspacePool = $RunspacePool

                        [void] $PowerShell.AddScript({
                            param ( $thisComputerName, $thisSource, $thisTarget, $localIPs, $Definitions )

                            $Result = New-Object -TypeName psobject
                            $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisSource.NodeName
                            $Result | Add-Member -MemberType NoteProperty -Name Sender -Value $thisTarget.IPaddress
                            $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisSource.IPAddress

                            $thisSourceResult = Invoke-NDKPing -Server $thisSource -Client $thisTarget

                            if ($thisSourceResult.ServerSuccess) { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass' }
                            else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' }

                            Return $Result
                        })

                        $param = @{
                            thisComputerName = $thisSource.NodeName
                            thisSource  = $thisSource
                            thisTarget  = $thisTarget
                            localIPs    = $localIPs
                            Definitions = $Definitions
                        }

                        [void] $PowerShell.AddParameters($param)

                        Write-Host ":: $([System.DateTime]::Now) :: [Started] $($thisSource.IPAddress) -> $($thisTarget.IPAddress)"
                        $asyncJobObj = @{ JobHandle   = $PowerShell
                                          AsyncHandle = $PowerShell.BeginInvoke() }

                        $AllJobs += $asyncJobObj
                    }
                }
            }


            While ($AllJobs -ne $null) {
                $AllJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                    $thisJob = $_
                    $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                    $thisReceiverHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).ReceiverHostName
                    $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Sender
                    $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Receiver

                    $AllJobs = $AllJobs -ne $thisJob

                    Write-Host ":: $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)"
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage3 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage3 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage3 -Value $StageResults
            Write-Host "Completed Stage 3 - NDK Ping - $([System.DateTime]::Now)"
        }

        '4' {  
            Write-Host "Beginning Stage 4 - NDK Perf 1:1 - $([System.DateTime]::Now)"

            $ISS = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $NetStackHelperModules = Get-ChildItem (Join-Path -Path $PWD -ChildPath 'Helpers\*') -Include '*.psm1'
            $NetStackHelperModules | ForEach-Object { $ISS.ImportPSModule($_.FullName) }

            $Max = [int]$env:NUMBER_OF_PROCESSORS * 2
            $RunspacePool = [runspacefactory]::CreateRunspacePool(1, $Max, $ISS, $host)
            $RunspacePool.Open()

            $StageResults = @()
            foreach ($group in $runspaceGroups) {
                $GroupedJobs = @()
                foreach ($pair in $group) {

                    $PowerShell = [powershell]::Create()
                    $PowerShell.RunspacePool = $RunspacePool

                    [void] $PowerShell.AddScript({
                        param ( $thisComputerName, $thisSource, $thisTarget, $localIPs, $Definitions )

                        $Result = New-Object -TypeName psobject
                        $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisSource.NodeName
                        $Result | Add-Member -MemberType NoteProperty -Name Sender -Value $thisTarget.IPaddress
                        $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisSource.IPAddress

                        $thisSourceResult = Invoke-NDKPerf1to1 -Server $thisSource -Client $thisTarget -ExpectedTPUT $Definitions.NDKPerf.TPUT

                        $Result | Add-Member -MemberType NoteProperty -Name RxLinkSpeedGbps -Value $thisSourceResult.ReceiverLinkSpeedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisSourceResult.ReceivedGbps
                        $Result | Add-Member -MemberType NoteProperty -Name RxPctgOfLinkSpeed -Value $thisSourceResult.ReceivedPctgOfLinkSpeed
                        $Result | Add-Member -MemberType NoteProperty -Name MinExpectedPctgOfLinkSpeed -Value $Definitions.NDKPerf.TPUT

                        if ($thisSourceResult.ReceivedPctgOfLinkSpeed -ge $Definitions.NDKPerf.TPUT) { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Pass' }
                        else { $Result | Add-Member -MemberType NoteProperty -Name PathStatus -Value 'Fail' }

                        $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData

                        Return $Result
                    })

                    $param = @{
                        thisComputerName = $pair.Source.NodeName
                        thisSource  = $pair.Source
                        thisTarget  = $pair.Target
                        localIPs    = $localIPs
                        Definitions = $Definitions
                    }

                    [void] $PowerShell.AddParameters($param)

                    Write-Host ":: $([System.DateTime]::Now) :: [Started] $($pair.Source.IPAddress) -> ($($pair.Target.NodeName)) $($pair.Target.IPAddress)"
                    $asyncJobObj = @{ JobHandle   = $PowerShell
                                        AsyncHandle = $PowerShell.BeginInvoke() }

                    $GroupedJobs += $asyncJobObj
                }

                While ($GroupedJobs -ne $null) {
                    $GroupedJobs | Where-Object { $_.AsyncHandle.IsCompleted } | ForEach-Object {
                        $thisJob = $_
                        $StageResults += $thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)
                        $thisReceiverHostName = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).ReceiverHostName
                        $thisSource = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Sender
                        $thisTarget = ($thisJob.JobHandle.EndInvoke($thisJob.AsyncHandle)).Receiver

                        $GroupedJobs = $GroupedJobs -ne $thisJob

                        Write-Host ":: $([System.DateTime]::Now) :: [Completed] $($thisSource) -> ($thisReceiverHostName) $($thisTarget)"
                    }
                }
            }

            $RunspacePool.Close()
            $RunspacePool.Dispose()

            if ('Fail' -in $StageResults.PathStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage4 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage4 -Value 'Pass' }
            
            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage4 -Value $StageResults
            Write-Host "Completed Stage 4 - NDK Perf 1:1 - $([System.DateTime]::Now)"
        }
        '5' { 
            Write-Host "Beginning Stage 5 - NDK Perf N:1 - $([System.DateTime]::Now)"
            $StageResults = @()
            $TestableNetworks | ForEach-Object {
                $thisTestableNet = $_

                $thisTestableNet.Group | Where-Object -FilterScript { $_.RDMAEnabled } | ForEach-Object {
                    $thisSource = $_
                    $ClientNetwork = @($thisTestableNet.Group | Where-Object NodeName -ne $thisSource.NodeName | Where-Object -FilterScript { $_.RDMAEnabled })
                    
                    $thisSourceResult = Invoke-NDKPerfNto1 -Server $thisSource -ClientNetwork $ClientNetwork -ExpectedTPUT $Definitions.NDKPerf.TPUT

                    $Result = New-Object -TypeName psobject
                    $Result | Add-Member -MemberType NoteProperty -Name ReceiverHostName -Value $thisSource.NodeName
                    $Result | Add-Member -MemberType NoteProperty -Name Receiver -Value $thisSource.IPAddress

                    $Result | Add-Member -MemberType NoteProperty -Name RxLinkSpeedGbps -Value $thisSourceResult.ReceiverLinkSpeedGbps
                    $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisSourceResult.RxGbps

                    if ($thisSourceResult.ServerSuccess) { $Result | Add-Member -MemberType NoteProperty -Name ReceiverStatus -Value 'Pass' }
                    else { $Result | Add-Member -MemberType NoteProperty -Name ReceiverStatus -Value 'Fail' }
                    
                    $Result | Add-Member -MemberType NoteProperty -Name ClientNetworkTested -Value $thisSourceResult.ClientNetworkTested
                    $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData

                    $StageResults += $Result
                    Remove-Variable Result -ErrorAction SilentlyContinue
                }
            }

            if ('Fail' -in $StageResults.ReceiverStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage5 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage5 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage5 -Value $StageResults
            Write-Host "Completed Stage 5 - NDK Perf N:1 - $([System.DateTime]::Now)"
        }
        '6' {  
            Write-Host "Beginning Stage 6 - NDK Perf N:N - $([System.DateTime]::Now)"
            $StageResults = @()
            $TestableNetworks | ForEach-Object {
                $thisTestableNet = $_

                $ServerList = $thisTestableNet.Group | Where-Object -FilterScript { $_.RDMAEnabled }

                $thisSourceResult = Invoke-NDKPerfNtoN -ServerList $ServerList -ExpectedTPUT $Definitions.NDKPerf.TPUT

                $Result = New-Object -TypeName psobject
                $thisSubnet = $thisTestableNet.Name.Split(',')[0]
                $thisVLAN = $thisTestableNet.Name.Split(',')[1].Trim()
                $Result | Add-Member -MemberType NoteProperty -Name Subnet -Value $thisSubnet
                $Result | Add-Member -MemberType NoteProperty -Name VLAN -Value $thisVLAN

                $Result | Add-Member -MemberType NoteProperty -Name RxGbps -Value $thisSourceResult.RxGbps

                if ($thisSourceResult.ServerSuccess) { $Result | Add-Member -MemberType NoteProperty -Name NetworkStatus -Value 'Pass' }
                else { $Result | Add-Member -MemberType NoteProperty -Name NetworkStatus -Value 'Fail' }
                    
                $Result | Add-Member -MemberType NoteProperty -Name RawData -Value $thisSourceResult.RawData

                $StageResults += $Result
                Remove-Variable Result -ErrorAction SilentlyContinue
            }

            if ('Fail' -in $StageResults.NetworkStatus) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage6 -Value 'Fail'; $StageFailures++ }
            else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name Stage6 -Value 'Pass' }

            $NetStackResults | Add-Member -MemberType NoteProperty -Name Stage6 -Value $StageResults
            Write-Host "Completed Stage 6 - NDK Perf N:N - $([System.DateTime]::Now)"
        }
    }
    
    if ($StageFailures -gt 0) { $ResultsSummary | Add-Member -MemberType NoteProperty -Name NetStack -Value 'Fail' }
    else { $ResultsSummary | Add-Member -MemberType NoteProperty -Name NetStack -Value 'Pass' }

    $NetStackResults | Add-Member -MemberType NoteProperty -Name ResultsSummary -Value $ResultsSummary

    $Failures = Get-Failures -NetStackResults $NetStackResults
    $NetStackResults | Add-Member -MemberType NoteProperty -Name Failures -Value $Failures
    Write-LogFile -NetStackResults $NetStackResults
    Return $NetStackResults
}
